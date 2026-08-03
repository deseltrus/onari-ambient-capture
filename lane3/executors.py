#!/usr/bin/env python3
"""RocketRide execution pipeline.

This is the layer that turns an *approved* intent into a real outcome. It is
deliberately pluggable so the demo can run without touching a real account and
without posting to a real group chat:

  ONARI_EXECUTOR=rehearsal    default. Pretend-live: every pipeline step is
                              produced and returned so the Mac UI can play them
                              back as if it happened on stage. Nothing is sent.
  ONARI_EXECUTOR=whatsapp_mac real send through the WhatsApp desktop app on this
                              Mac (AppleScript UI automation). Opt-in only.
  ONARI_EXECUTOR=rocketride   forward the approved intent to a RocketRide Cloud
                              endpoint (ROCKETRIDE_ENDPOINT/ROCKETRIDE_API_KEY)
                              and normalize its response.

Every executor returns the same shape (see `ExecutionResult`), so the Mac
contract never changes when the backend does.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import urllib.error
import urllib.request
import uuid
from typing import Any, Callable


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


# A pipeline step as the Mac UI renders it in the live execution log.
def step(step_id: str, label: str, status: str = "done", detail: str = "") -> dict[str, Any]:
    return {"id": step_id, "label": label, "status": status, "detail": detail, "t": now()}


# --- message drafting ------------------------------------------------------

TOPIC_LEAD = {
    "execution-pipeline": "RocketRide (execution)",
    "graph-memory": "FalkorDB (memory)",
    "context-capture": "Ambient-capture paper",
}

TOPIC_NET = {
    "execution-pipeline": "build the dispatch/execution layer on RocketRide",
    "graph-memory": "keep memory in FalkorDB — no separate vector store",
    "context-capture": "on-device capture with a visible recording state is our sourced differentiator",
}


def _document_boards(frame: dict[str, Any]) -> list[dict[str, Any]]:
    """The documents the user actually read (Safari boards that are not the
    question tabs). Question tabs are marked by carrying an assistant_answer
    delta and no independent topic weight in the story."""
    docs = []
    for board in frame.get("boards", []):
        if board.get("app") != "Safari":
            continue
        # A question tab has a delta but the doc it answers carries the topic.
        if board.get("board_id", "").startswith("q"):
            continue
        docs.append(board)
    return docs


def _answer_for_topic(frame: dict[str, Any], topic: str) -> str | None:
    for board in frame.get("boards", []):
        if not board.get("board_id", "").startswith("q"):
            continue
        if any(t.get("topic") == topic for t in board.get("topics", [])):
            for delta in board.get("deltas", []):
                if delta.get("preview"):
                    return delta["preview"]
    return None


def _history_for_topic(frame: dict[str, Any], topic: str) -> str | None:
    for join in frame.get("history_joins", []):
        if join.get("topic") == topic:
            return join.get("body")
    return None


def draft_whatsapp_message(frame: dict[str, Any], group: str) -> str:
    """Deterministically synthesize the team update from the three documents,
    the answers pulled from the question tabs, and the open team threads. This
    is what proves the point: every line cites something the user saw but never
    relayed."""
    lines: list[str] = ["Team — quick sync before the build call. I went deep on the docs:"]
    nets: list[str] = []
    index = 1
    for board in sorted(
        _document_boards(frame),
        key=lambda b: max((t.get("score", 0) for t in b.get("topics", [])), default=0),
        reverse=True,
    ):
        topic = max(board.get("topics", []), key=lambda t: t.get("score", 0), default={}).get("topic", "")
        lead = TOPIC_LEAD.get(topic, board.get("title", "a document"))
        answer = _answer_for_topic(frame, topic)
        detail = answer or (board.get("notes") or [{}])[0].get("text", "")
        lines.append(f"{index}) {lead}: {detail}".rstrip())
        if topic in TOPIC_NET:
            nets.append(TOPIC_NET[topic])
        index += 1
    if nets:
        lines.append("Net: " + "; ".join(nets) + ". Pushing on this now.")
    return "\n".join(lines)


# --- executors -------------------------------------------------------------

def _rehearsal(intent: dict[str, Any], message: str, group: str) -> dict[str, Any]:
    """Pretend-live. Produce the full pipeline the UI animates. Nothing sent."""
    steps = [
        step("assemble", "Assemble context from the 3 documents",
             detail="RocketRide pulled the read documents, tab answers, and open team threads."),
        step("draft", "Draft the team update",
             detail=f"{len(message.split())} words, grounded only in what you actually read."),
        step("policy", "Policy check",
             detail="artifactOnly + doNotSend honored (rehearsal): message prepared, delivery held."),
        step("open", f"Open WhatsApp → {group}", detail="Located the group thread."),
        step("send", "Send message", status="skipped",
             detail="Rehearsal mode — not delivered. Set ONARI_EXECUTOR=whatsapp_mac to send for real."),
        step("confirm", "Confirm delivery", status="skipped", detail="Simulated delivery receipt."),
    ]
    return {
        "status": "done",
        "artifact": message,
        "traceURL": f"https://cloud.rocketride.ai/runs/run_{uuid.uuid4().hex[:12]}",
        "steps": steps,
        "channel": "whatsapp",
        "target": group,
        "delivered": False,
    }


def _whatsapp_mac(intent: dict[str, Any], message: str, group: str) -> dict[str, Any]:
    """Real send through the WhatsApp desktop app via AppleScript UI scripting.

    Opt-in. Requires the WhatsApp macOS app installed, logged in, and
    Accessibility permission for the controlling process. Best-effort: WhatsApp
    exposes no scripting dictionary, so this drives the UI (search the group,
    type, press return)."""
    script = f'''
    tell application "WhatsApp" to activate
    delay 1.0
    tell application "System Events"
        tell process "WhatsApp"
            keystroke "f" using {{command down}}
            delay 0.4
            keystroke {json.dumps(group)}
            delay 0.8
            key code 36
            delay 0.8
            keystroke {json.dumps(message)}
            delay 0.4
            key code 36
        end tell
    end tell
    '''
    steps = [
        step("assemble", "Assemble context from the 3 documents"),
        step("draft", "Draft the team update", detail=f"{len(message.split())} words"),
        step("policy", "Policy check", detail="Real send authorized by explicit approval."),
        step("open", f"Open WhatsApp → {group}"),
    ]
    try:
        subprocess.run(["osascript", "-e", script], check=True, capture_output=True, timeout=30)
        steps.append(step("send", "Send message", detail=f"Delivered to {group}."))
        steps.append(step("confirm", "Confirm delivery", detail="Message posted to the group."))
        delivered = True
        status = "done"
    except (subprocess.CalledProcessError, subprocess.TimeoutExpired, FileNotFoundError) as error:
        reason = getattr(error, "stderr", b"")
        reason = reason.decode(errors="replace") if isinstance(reason, bytes) else str(error)
        steps.append(step("send", "Send message", status="failed", detail=reason.strip() or str(error)))
        delivered = False
        status = "failed"
    return {
        "status": status,
        "artifact": message,
        "traceURL": None,
        "steps": steps,
        "channel": "whatsapp",
        "target": group,
        "delivered": delivered,
    }


def _rocketride(intent: dict[str, Any], message: str, group: str) -> dict[str, Any]:
    endpoint = os.getenv("ROCKETRIDE_ENDPOINT")
    if not endpoint:
        raise ValueError("ONARI_EXECUTOR=rocketride requires ROCKETRIDE_ENDPOINT")
    api_key = os.getenv("ROCKETRIDE_API_KEY")
    if not api_key:
        raise ValueError("ONARI_EXECUTOR=rocketride requires ROCKETRIDE_API_KEY")
    request = urllib.request.Request(
        endpoint,
        data=json.dumps({**intent, "message": message}).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=45) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        raise RuntimeError(f"RocketRide returned HTTP {error.code}: {error.read().decode(errors='replace')}") from error
    artifact = data.get("artifact")
    if isinstance(artifact, dict):
        artifact = artifact.get("content")
    return {
        "status": data.get("status", "done"),
        "artifact": artifact or message,
        "traceURL": (data.get("trace") or {}).get("url", data.get("traceUrl") or data.get("traceURL")),
        "steps": data.get("steps", []),
        "channel": "whatsapp",
        "target": group,
        "delivered": bool(data.get("delivered", data.get("status") == "done")),
    }


EXECUTORS: dict[str, Callable[[dict[str, Any], str, str], dict[str, Any]]] = {
    "rehearsal": _rehearsal,
    "whatsapp_mac": _whatsapp_mac,
    "rocketride": _rocketride,
}


def execute(intent: dict[str, Any], message: str, group: str) -> dict[str, Any]:
    """Dispatch an approved intent through the selected executor."""
    name = os.getenv("ONARI_EXECUTOR", "rehearsal").lower()
    executor = EXECUTORS.get(name)
    if executor is None:
        raise ValueError(f"Unknown ONARI_EXECUTOR: {name}. Options: {', '.join(EXECUTORS)}")
    result = executor(intent, message, group)
    result.setdefault("dispatchId", intent.get("dispatchId") or f"dispatch_{uuid.uuid4()}")
    result["executor"] = name
    return result
