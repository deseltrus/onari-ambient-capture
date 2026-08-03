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
import sys
import urllib.error
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import executors  # noqa: E402  (sibling module; needs the path insert above)


def resolve_frame_path() -> pathlib.Path:
    """Explicit ONARI_INTENT_FRAME wins. Otherwise pick the scenario frame under
    scenarios/ (default: the three-docs -> WhatsApp demo). Fall back to the
    legacy intent-frame.json so the older LinkedIn scenario still runs."""
    explicit = os.getenv("ONARI_INTENT_FRAME")
    if explicit:
        return pathlib.Path(explicit)
    scenario = os.getenv("ONARI_SCENARIO", "three-docs-whatsapp")
    candidate = ROOT / "scenarios" / f"{scenario}.json"
    if candidate.exists():
        return candidate
    return ROOT / "intent-frame.json"


FRAME_PATH = resolve_frame_path()
SESSIONS: dict[str, list[dict[str, str]]] = {}
RESPONSES: dict[str, dict[str, Any]] = {}


def is_whatsapp_scenario(frame: dict[str, Any]) -> bool:
    return (
        frame.get("scenario") == "three-docs-whatsapp"
        or frame.get("target", {}).get("channel") == "whatsapp"
    )


def whatsapp_group(frame: dict[str, Any]) -> str:
    return frame.get("target", {}).get("group", "Hackathon 08/03 - TEAM O")


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


def whatsapp_fixture_response(session_id: str, frame: dict[str, Any]) -> dict[str, Any]:
    """Consolidation for the three-documents demo. The insight is the synthesis
    ACROSS the documents the user read, each joined to an open TEAM O thread, and
    the payoff action is a WhatsApp update to the team group."""
    group = whatsapp_group(frame)
    docs = sorted(
        executors._document_boards(frame),
        key=lambda b: max((t.get("score", 0) for t in b.get("topics", [])), default=0),
        reverse=True,
    )

    evidence: list[dict[str, Any]] = []
    for board in docs:
        topic = max(board.get("topics", []), key=lambda t: t.get("score", 0), default={}).get("topic", "")
        answer = executors._answer_for_topic(frame, topic)
        note = (board.get("notes") or [{}])[0].get("text")
        evidence.append({
            "id": board["board_id"],
            "kind": "unspoken_board" if board.get("unspoken") else "note",
            "label": board["title"],
            "detail": answer or note or "Read this session; you never wrote down what it settled.",
            "observedAt": board.get("last_seen"),
        })
    # The single strongest open thread, as the concrete history join.
    top_topic = max(
        (t for board in docs for t in board.get("topics", [])),
        key=lambda t: t.get("score", 0),
        default={},
    ).get("topic")
    history = executors._history_for_topic(frame, top_topic) if top_topic else None
    if history:
        episode = next((j for j in frame.get("history_joins", []) if j.get("topic") == top_topic), {})
        evidence.append({
            "id": episode.get("episode", "seed_team_thread"),
            "kind": "history_join",
            "label": "Open TEAM O thread",
            "detail": history,
            "observedAt": episode.get("t"),
        })

    doc_count = len(docs)
    open_threads = len({j.get("topic") for j in frame.get("history_joins", [])})
    summary = (
        f"You read {doc_count} documents and answered {open_threads} open TEAM O "
        f"questions in your tabs — but none of those answers reached the team. "
        f"Onari can post the synthesis to “{group}” for you."
    )

    response = {
        "id": f"response_{uuid.uuid4()}",
        "sessionId": session_id,
        "createdAt": now(),
        "summary": summary,
        "evidence": evidence,
        "suggestedActions": [{
            "id": f"action_{uuid.uuid4()}",
            "type": "send_whatsapp",
            "label": f"Send update to {group}",
            "requiresApproval": True,
            "target": group,
        }],
    }
    RESPONSES[response["id"]] = response
    return response


def consolidate(session_id: str) -> dict[str, Any]:
    provider = os.getenv("ONARI_AI_PROVIDER", "fixture").lower()
    if provider == "fixture":
        frame = load_frame()
        if is_whatsapp_scenario(frame):
            return whatsapp_fixture_response(session_id, frame)
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

    frame = load_frame()
    response = RESPONSES.get(payload.get("responseId", ""))
    if not response:
        response = (
            whatsapp_fixture_response(payload["sessionId"], frame)
            if is_whatsapp_scenario(frame)
            else fixture_response(payload["sessionId"])
        )

    dispatch_id = f"dispatch_{uuid.uuid4()}"

    # WhatsApp scenario: draft the team update from the three documents and run
    # it through the selected execution pipeline (rehearsal by default).
    if is_whatsapp_scenario(frame):
        group = whatsapp_group(frame)
        message = executors.draft_whatsapp_message(frame, group)
        intent = {
            "dispatchId": dispatch_id,
            "sessionId": payload["sessionId"],
            "action": "send_whatsapp",
            "objective": response["summary"],
            "evidence": response["evidence"],
            "constraints": {"artifactOnly": True, "doNotSend": os.getenv("ONARI_EXECUTOR", "rehearsal") != "whatsapp_mac"},
            "approval": {"approvedBy": "user", "approvedAt": now()},
        }
        result = executors.execute(intent, message, group)
        return {
            "dispatchId": result["dispatchId"],
            "status": result["status"],
            "artifact": result.get("artifact"),
            "traceURL": result.get("traceURL"),
            "steps": result.get("steps", []),
        }

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
    print(
        f"lane3: http://127.0.0.1:{port} · provider={os.getenv('ONARI_AI_PROVIDER', 'fixture')}"
        f" · scenario={os.getenv('ONARI_SCENARIO', 'three-docs-whatsapp')}"
        f" · executor={os.getenv('ONARI_EXECUTOR', 'rehearsal')}"
        f" · frame={FRAME_PATH.name}"
    )
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
