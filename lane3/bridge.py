#!/usr/bin/env python3
"""Local boundary between the Mac UI and cloud coordination/execution.

The Mac app contains no service credentials. During development this server
uses deterministic fixtures. Set ONARI_AI_PROVIDER=openai or anthropic for a
real model; Guild remains the production coordinator and can replace the
provider without changing the Swift contract. RocketRide is called only by the
explicit /dispatch endpoint after the Mac confirmation dialog.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import pathlib
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
FRAME_PATH = pathlib.Path(os.getenv("ONARI_INTENT_FRAME", ROOT / "intent-frame.json"))
SESSIONS: dict[str, list[dict[str, str]]] = {}
RESPONSES: dict[str, dict[str, Any]] = {}


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def load_frame() -> dict[str, Any]:
    return json.loads(FRAME_PATH.read_text(encoding="utf-8"))


def strongest_unspoken(frame: dict[str, Any]) -> dict[str, Any] | None:
    boards = [board for board in frame.get("boards", []) if board.get("unspoken")]
    return max(
        boards,
        key=lambda board: max((topic.get("score", 0) for topic in board.get("topics", [])), default=0),
        default=None,
    )


def fixture_response(session_id: str) -> dict[str, Any]:
    frame = load_frame()
    board = strongest_unspoken(frame)
    top_topic = None
    if board:
        top_topic = max(board.get("topics", []), key=lambda item: item.get("score", 0), default={}).get("topic")
    history = next(
        (item for item in frame.get("history_joins", []) if item.get("topic") == top_topic),
        (frame.get("history_joins") or [None])[0],
    )

    evidence: list[dict[str, Any]] = []
    if board:
        evidence.append({
            "id": board["board_id"],
            "kind": "unspoken_board",
            "label": board["title"],
            "detail": f"Seen in {board['app']}, never written down, and ranked as a strong topic signal.",
            "observedAt": board.get("last_seen"),
        })
    if history:
        evidence.append({
            "id": history["episode"],
            "kind": "history_join",
            "label": f"Earlier {history['topic']} thread",
            "detail": history["body"],
            "observedAt": history.get("t"),
        })

    response = {
        "id": f"response_{uuid.uuid4()}",
        "sessionId": session_id,
        "createdAt": now(),
        "summary": (
            f"{board['title'] if board else 'An unspoken surface'} appears relevant to your "
            f"{frame.get('mission', 'current')} mission and reconnects with an unfinished historical thread."
        ),
        "evidence": evidence,
        "suggestedActions": [{
            "id": f"action_{uuid.uuid4()}",
            "type": "draft_outreach",
            "label": "Create outreach draft",
            "requiresApproval": True,
        }],
    }
    RESPONSES[response["id"]] = response
    return response


def consolidate(session_id: str) -> dict[str, Any]:
    provider = os.getenv("ONARI_AI_PROVIDER", "fixture").lower()
    if provider == "fixture":
        return fixture_response(session_id)

    frame = load_frame()
    prompt = f"""
You are Onari's Guild consolidation agent. Convert the intent frame into one
short, evidence-grounded insight and zero or more action candidates.

Rules:
- The payoff is what the user did NOT type. Prioritize boards where unspoken=true.
- Connect those boards to history_joins using shared topics.
- Do not invent people, facts, contact details, or actions.
- Return JSON only, with exactly this shape:
{{
  "summary": "one short paragraph",
  "evidence": [
    {{"id":"source id","kind":"unspoken_board|history_join","label":"short label","detail":"why it matters","observedAt":"ISO timestamp or null"}}
  ],
  "suggestedActions": [
    {{"type":"draft_outreach|create_brief","label":"button label","requiresApproval":true}}
  ]
}}

INTENT FRAME:
{json.dumps(frame, ensure_ascii=False)}
"""
    parsed = parse_json_object(call_model(provider, prompt))
    response = {
        "id": f"response_{uuid.uuid4()}",
        "sessionId": session_id,
        "createdAt": now(),
        "summary": str(parsed["summary"]),
        "evidence": parsed.get("evidence", []),
        "suggestedActions": [
            {"id": f"action_{uuid.uuid4()}", **action}
            for action in parsed.get("suggestedActions", [])
        ],
    }
    if not any(item.get("kind") == "unspoken_board" for item in response["evidence"]):
        raise ValueError("AI consolidation omitted the required unspoken-board evidence")
    RESPONSES[response["id"]] = response
    return response


def model_chat(session_id: str, message: str, response_id: str | None) -> str:
    provider = os.getenv("ONARI_AI_PROVIDER", "fixture").lower()
    response = RESPONSES.get(response_id or "")
    context = json.dumps({"intentFrame": load_frame(), "activeResponse": response}, ensure_ascii=False)
    history = SESSIONS.setdefault(session_id, [])

    if provider == "fixture":
        labels = " and ".join(item["label"] for item in (response or {}).get("evidence", []))
        answer = f"The session evidence is {labels or 'not loaded yet'}. In connected Guild mode I will preserve this context across turns."
    else:
        prompt = (
            "You are Onari's Guild coordination layer. Answer concisely using only the supplied session context. "
            "Prioritize unspoken boards and history joins over typed notes. Never claim an action was executed.\n\n"
            f"SESSION CONTEXT:\n{context}\n\nCONVERSATION:\n{json.dumps(history)}\n\nUSER:\n{message}"
        )
        answer = call_model(provider, prompt)

    history.extend([{"role": "user", "text": message}, {"role": "assistant", "text": answer}])
    return answer


def call_model(provider: str, prompt: str) -> str:
    if provider == "openai":
        payload = {
            "model": os.getenv("OPENAI_MODEL", "gpt-5-mini"),
            "input": prompt,
        }
        data = request_json(
            "https://api.openai.com/v1/responses",
            payload,
            {"Authorization": f"Bearer {required('OPENAI_API_KEY')}"},
        )
        if data.get("output_text"):
            return data["output_text"]
        return "".join(
            part.get("text", "")
            for item in data.get("output", [])
            for part in item.get("content", [])
            if part.get("type") in ("output_text", "text")
        )

    if provider == "anthropic":
        payload = {
            "model": os.getenv("ANTHROPIC_MODEL", "claude-sonnet-4-5"),
            "max_tokens": 600,
            "messages": [{"role": "user", "content": prompt}],
        }
        data = request_json(
            "https://api.anthropic.com/v1/messages",
            payload,
            {
                "x-api-key": required("ANTHROPIC_API_KEY"),
                "anthropic-version": "2023-06-01",
            },
        )
        return "".join(item.get("text", "") for item in data.get("content", []) if item.get("type") == "text")

    raise ValueError(f"Unsupported ONARI_AI_PROVIDER: {provider}")


def parse_json_object(text: str) -> dict[str, Any]:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        cleaned = cleaned.split("\n", 1)[1].rsplit("```", 1)[0]
    value = json.loads(cleaned)
    if not isinstance(value, dict):
        raise ValueError("AI response must be a JSON object")
    return value


def dispatch(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("approved") not in (True, "true"):
        raise ValueError("RocketRide dispatch requires explicit approval")

    response = RESPONSES.get(payload.get("responseId", ""))
    if not response:
        response = fixture_response(payload["sessionId"])

    dispatch_id = f"dispatch_{uuid.uuid4()}"
    endpoint = os.getenv("ROCKETRIDE_ENDPOINT")
    if endpoint:
        result = request_json(
            endpoint,
            {
                "dispatchId": dispatch_id,
                "sessionId": payload["sessionId"],
                "action": "draft_outreach",
                "objective": response["summary"],
                "evidence": response["evidence"],
                "constraints": {"artifactOnly": True, "doNotSend": True, "maxWords": 120},
                "approval": {"approvedBy": "user", "approvedAt": now()},
            },
            {"Authorization": f"Bearer {required('ROCKETRIDE_API_KEY')}"},
        )
        return {
            "dispatchId": result.get("dispatchId", dispatch_id),
            "status": result.get("status", "done"),
            "artifact": (result.get("artifact") or {}).get("content", result.get("artifact")),
            "traceURL": (result.get("trace") or {}).get("url", result.get("traceUrl")),
        }

    return {
        "dispatchId": dispatch_id,
        "status": "done",
        "artifact": (
            "Hey — I was revisiting our signal-pipeline work and came across the context-systems thread. "
            "It connected back to our earlier conversation, and I’d love to compare notes and show you what we’re building."
        ),
        "traceURL": None,
    }


def required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise ValueError(f"Missing required environment variable: {name}")
    return value


def request_json(url: str, payload: dict[str, Any], headers: dict[str, str]) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", **headers},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"Service returned HTTP {error.code}: {error.read().decode(errors='replace')}") from error


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self.send_json(200, {"ok": True, "mode": os.getenv("ONARI_AI_PROVIDER", "fixture")})
        else:
            self.send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        try:
            length = int(self.headers.get("Content-Length", "0"))
            payload = json.loads(self.rfile.read(length) or b"{}")
            if self.path == "/consolidate":
                result = consolidate(payload["sessionId"])
            elif self.path == "/chat":
                result = {"text": model_chat(payload["sessionId"], payload["message"], payload.get("responseId"))}
            elif self.path == "/dispatch":
                result = dispatch(payload)
            else:
                return self.send_json(404, {"error": "not found"})
            self.send_json(200, result)
        except Exception as error:  # keep the UI error structured during demo failures
            self.send_json(400, {"error": str(error)})

    def log_message(self, format: str, *args: Any) -> None:
        print(f"lane3: {format % args}")

    def send_json(self, status: int, value: dict[str, Any]) -> None:
        data = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)


if __name__ == "__main__":
    port = int(os.getenv("ONARI_LANE3_PORT", "8765"))
    print(f"lane3: http://127.0.0.1:{port} · provider={os.getenv('ONARI_AI_PROVIDER', 'fixture')}")
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
