"""Shared LaserData wiring for the capture lane.

STREAM / TOPIC MODEL — the one thing every lane must agree on
`event-contract.json` says `stream_in: ambient-events` and
`stream_out: dispatch-results`. Laser's own model is stream -> topic, so we
map the contract's two "streams" onto two TOPICS inside one Laser stream:

    stream  onari                (LASER_STREAM)
      topic ambient-events       capture -> graph
      topic dispatch-results     RocketRide -> dispatch surface

Every tool in this repo resolves them through the constants below. If the team
decides differently in the contract sync, change it HERE and nowhere else.
"""

from __future__ import annotations

import os
import re
import uuid

DEFAULT_STREAM = os.environ.get("LASER_STREAM", "onari")
TOPIC_IN = os.environ.get("LASER_TOPIC_IN", "ambient-events")
TOPIC_OUT = os.environ.get("LASER_TOPIC_OUT", "dispatch-results")
PARTITIONS = int(os.environ.get("LASER_PARTITIONS", "4"))

LOCAL_CONNECTION_STRING = "iggy:laser@127.0.0.1:8090"


def connection_string() -> str:
    """`LASER_CONNECTION_STRING` if set, otherwise the Laser Stack default.

    `./scripts/up` in laser-stack prints the exact value to export. The SDK
    adds the `iggy+tcp://` scheme and the default port itself, so a bare
    `user:password@host` is fine.
    """
    return os.environ.get("LASER_CONNECTION_STRING", "").strip() or LOCAL_CONNECTION_STRING


async def connect(stream: str | None = None):
    """Connect, pinned to our stream. Import is lazy so `--stdout` mode runs
    with no SDK installed at all."""
    import laser_sdk as ls

    return await ls.Laser.connect(connection_string(), stream=stream or DEFAULT_STREAM)


async def ensure_topics(laser) -> None:
    """Idempotent. Safe to call from every tool on every start."""
    await laser.topic(TOPIC_IN).ensure(partitions=PARTITIONS)
    await laser.topic(TOPIC_OUT).ensure(partitions=PARTITIONS)


# -------------------------------------------------------------- board identity

# Must match `capture-mac/Sources/AmbientMac/Contract/BoardIdentity.swift`.
# Cross-language test vectors live in `BoardIdentityTests.swift`.
BOARD_NAMESPACE = uuid.UUID("6f1c9a2e-3b7d-4c58-9f10-2d4a8e5b7c31")


def normalize_title(title: str) -> str:
    """Strip the parts of a window title that change while the surface does
    not: unread counts, editor dirty markers, whitespace runs."""
    s = title.strip()
    s = re.sub(r"^\(\d+\)\s*", "", s)
    while s[:1] in ("•", "*"):
        s = s[1:].strip()
    return re.sub(r"\s+", " ", s).strip()


def board_id(app: str, title: str) -> str:
    """The same UUIDv5 the Mac app derives. Lets the graph lane compute a
    board_id for a surface it only knows by name — no lookup table, no
    coordination call."""
    return str(uuid.uuid5(BOARD_NAMESPACE, f"{app}|{normalize_title(title)}"))


# ---------------------------------------------------------------- validation

VALID_TYPES = {"switch", "note", "delta", "result"}

REQUIRED_FIELDS = {
    "switch": ["type", "v", "t", "seq", "from", "to", "dwell_ms_from"],
    "note": ["type", "v", "t", "board_id", "app", "title", "text", "mode", "field"],
    "delta": ["type", "v", "t", "board_id", "kind", "source", "preview"],
    "result": ["type", "v", "t", "dispatch_id", "status", "artifact"],
}


def contract_errors(event: dict) -> list[str]:
    """Check one event against the contract. Returns [] when it conforms.

    The bridge REJECTS non-conforming events instead of forwarding them. A bad
    event that reaches the graph lane costs them a debugging round-trip they
    cannot spare; a rejected one costs us a log line.
    """
    problems: list[str] = []

    kind = event.get("type")
    if kind not in VALID_TYPES:
        return [f"unknown type {kind!r} (contract allows {sorted(VALID_TYPES)})"]

    if event.get("v") != 1:
        problems.append(f"version {event.get('v')!r}, contract is v1")

    for field in REQUIRED_FIELDS[kind]:
        if field not in event:
            problems.append(f"missing required field {field!r}")

    if kind == "switch":
        for side in ("from", "to"):
            ref = event.get(side)
            if not isinstance(ref, dict):
                problems.append(f"{side!r} must be an object")
                continue
            for key in ("app", "title", "board_id"):
                if key not in ref:
                    problems.append(f"{side}.{key} missing")
        if not isinstance(event.get("seq"), int):
            problems.append("seq must be an integer")

    if kind == "note":
        if event.get("mode") not in ("note", "passthrough"):
            problems.append(f"mode {event.get('mode')!r} must be 'note' or 'passthrough'")
        if event.get("mode") == "passthrough" and not event.get("field"):
            problems.append("passthrough notes must name the field that received the text")

    return problems
