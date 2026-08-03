#!/usr/bin/env python3
"""laser-bridge — the Swift capture app's way onto LaserData.

WHY THIS EXISTS
The Laser SDK ships for Rust, Python and TypeScript. There is no Swift SDK, and
writing an Iggy TCP client in Swift is not a 4.5-hour task. So the Mac app POSTs
newline-delimited JSON to this process on loopback, and this process publishes
with the real SDK. One small, boring hop that removes the entire risk.

    AmbientMac  --POST ndjson-->  bridge.py  --laser-sdk-->  ambient-events

RUN IT

    # No LaserData needed — prints what it would publish. Use this to get the
    # Swift app verified in the first ten minutes.
    python3 bridge.py --stdout

    # The real thing, against local Laser Stack.
    export LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'
    python3 bridge.py

    # Catch the stream up from the Mac app's durable spool after an outage.
    python3 bridge.py --replay ~/Library/Application\\ Support/Onari/ambient-events.jsonl

ENDPOINTS
    POST /events    body is one JSON object, or NDJSON for a batch
    GET  /health    {"ok": true, "published": N, "rejected": N}
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import laser_common as common

DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8077

# Bounded so a wedged publisher applies backpressure instead of eating RAM.
QUEUE_MAX = 10_000


class Stats:
    def __init__(self) -> None:
        self.published = 0
        self.rejected = 0
        self.received = 0


STATS = Stats()


def parse_body(raw: bytes) -> tuple[list[dict], list[str]]:
    """Accept a single JSON object, a JSON array, or NDJSON. Being liberal here
    costs nothing and means a curl one-liner works for debugging."""
    text = raw.decode("utf-8", errors="replace").strip()
    if not text:
        return [], ["empty body"]

    # Whole-body JSON first (object or array).
    try:
        parsed = json.loads(text)
        if isinstance(parsed, dict):
            return [parsed], []
        if isinstance(parsed, list):
            return [e for e in parsed if isinstance(e, dict)], []
    except json.JSONDecodeError:
        pass

    events: list[dict] = []
    errors: list[str] = []
    for number, line in enumerate(text.splitlines(), start=1):
        line = line.strip()
        if not line:
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError as exc:
            errors.append(f"line {number}: {exc.msg}")
            continue
        if isinstance(event, dict):
            events.append(event)
        else:
            errors.append(f"line {number}: not a JSON object")
    return events, errors


def make_handler(submit):
    class Handler(BaseHTTPRequestHandler):
        # The default logger prints a line per request; at 400ms polling that
        # buries the output we actually want.
        def log_message(self, format, *args):  # noqa: A002
            pass

        def _respond(self, code: int, payload: dict) -> None:
            body = json.dumps(payload).encode()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):  # noqa: N802
            if self.path.startswith("/health"):
                self._respond(200, {
                    "ok": True,
                    "received": STATS.received,
                    "published": STATS.published,
                    "rejected": STATS.rejected,
                })
            else:
                self._respond(404, {"error": "not found"})

        def do_POST(self):  # noqa: N802
            if not self.path.startswith("/events"):
                self._respond(404, {"error": "not found"})
                return

            length = int(self.headers.get("Content-Length", "0") or 0)
            raw = self.rfile.read(length) if length else b""
            events, parse_errors = parse_body(raw)

            accepted, rejected = [], []
            for event in events:
                problems = common.contract_errors(event)
                if problems:
                    rejected.append({"event": event.get("type"), "problems": problems})
                else:
                    accepted.append(event)

            for entry in rejected:
                STATS.rejected += 1
                print(
                    f"  REJECTED {entry['event']}: {'; '.join(entry['problems'])}",
                    file=sys.stderr, flush=True,
                )

            STATS.received += len(accepted)
            for event in accepted:
                submit(event)

            self._respond(202 if accepted else 400, {
                "accepted": len(accepted),
                "rejected": len(rejected),
                "parse_errors": parse_errors,
            })

    return Handler


def describe(event: dict) -> str:
    """One readable line per event, so the terminal doubles as the side-screen
    'events are streaming' feed during the demo."""
    kind = event.get("type")
    if kind == "switch":
        to = event.get("to") or {}
        frm = event.get("from") or {}
        dwell = event.get("dwell_ms_from")
        origin = f"{frm.get('app')} " if frm.get("app") else "∅ "
        held = f"  (held {dwell / 1000:.1f}s)" if isinstance(dwell, (int, float)) else ""
        return f"switch #{event.get('seq')}  {origin}→ {to.get('app')} · {to.get('title')}{held}"
    if kind == "note":
        mode = event.get("mode")
        marker = "🎙" if mode == "note" else "⌨"
        return f"note   {marker} [{event.get('app')}] \"{event.get('text')}\""
    if kind == "delta":
        return f"delta  [{event.get('source')}] {event.get('preview')!r}"
    if kind == "result":
        return f"result {event.get('status')} dispatch={event.get('dispatch_id')}"
    return json.dumps(event)


async def publisher_loop(queue: asyncio.Queue, stdout_only: bool) -> None:
    """Drain the queue onto the topic. Batches whatever has piled up, so a
    burst of switches is one publish, not twenty."""
    laser = None
    topic = None

    if not stdout_only:
        laser = await common.connect()
        await common.ensure_topics(laser)
        caps = await laser.capabilities()
        print(
            f"connected · stream={common.DEFAULT_STREAM} topic={common.TOPIC_IN} "
            f"managed={caps.managed}",
            flush=True,
        )
        topic = laser.topic(common.TOPIC_IN)
    else:
        print("--stdout: events are printed, not published", flush=True)

    try:
        while True:
            event = await queue.get()
            batch = [event]
            # Opportunistically drain whatever else is already waiting.
            while not queue.empty() and len(batch) < 64:
                batch.append(queue.get_nowait())

            for item in batch:
                print("  " + describe(item), flush=True)

            if topic is not None:
                try:
                    request = topic.publish_batch().inline_payload()
                    for item in batch:
                        request = request.add_json(item)
                    await request.send()
                    STATS.published += len(batch)
                except Exception as exc:  # noqa: BLE001
                    # Never die on a publish error: the Mac app's spool is the
                    # durable record and can be replayed.
                    print(f"  publish failed ({exc}); {len(batch)} event(s) dropped "
                          f"from the stream, still in the Mac spool", file=sys.stderr, flush=True)

            for _ in batch:
                queue.task_done()
    finally:
        if laser is not None:
            await laser.close()


async def replay_file(path: str, stdout_only: bool) -> None:
    """Publish a JSONL file (the Mac spool, or the repo fixtures) and exit."""
    with open(path, encoding="utf-8") as handle:
        events = [json.loads(line) for line in handle if line.strip()]

    good = [e for e in events if not common.contract_errors(e)]
    bad = len(events) - len(good)
    print(f"replaying {len(good)} event(s) from {path}" + (f" ({bad} rejected)" if bad else ""),
          flush=True)

    if stdout_only:
        for event in good:
            print("  " + describe(event), flush=True)
        return

    laser = await common.connect()
    try:
        await common.ensure_topics(laser)
        request = laser.topic(common.TOPIC_IN).publish_batch().inline_payload()
        for event in good:
            request = request.add_json(event)
            print("  " + describe(event), flush=True)
        await request.send()
        print(f"published {len(good)} event(s) to {common.TOPIC_IN}", flush=True)
    finally:
        await laser.close()


async def serve(host: str, port: int, stdout_only: bool) -> None:
    loop = asyncio.get_running_loop()
    queue: asyncio.Queue = asyncio.Queue(maxsize=QUEUE_MAX)

    def submit(event: dict) -> None:
        # Called from an HTTP worker thread; hop to the event loop safely.
        # put_nowait so a full queue drops loudly rather than blocking the POST
        # and stalling the capture app.
        def _put() -> None:
            try:
                queue.put_nowait(event)
            except asyncio.QueueFull:
                print("  queue full, dropped one event", file=sys.stderr, flush=True)

        loop.call_soon_threadsafe(_put)

    server = ThreadingHTTPServer((host, port), make_handler(submit))
    server.daemon_threads = True
    threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"laser-bridge listening on http://{host}:{port}/events", flush=True)

    try:
        await publisher_loop(queue, stdout_only)
    finally:
        server.shutdown()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--host", default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--stdout", action="store_true",
                        help="print events instead of publishing (no LaserData needed)")
    parser.add_argument("--replay", metavar="FILE",
                        help="publish a JSONL file and exit (spool catch-up, fixtures)")
    args = parser.parse_args()

    try:
        if args.replay:
            asyncio.run(replay_file(args.replay, args.stdout))
        else:
            asyncio.run(serve(args.host, args.port, args.stdout))
    except KeyboardInterrupt:
        print(f"\nstopped · received {STATS.received} · published {STATS.published} "
              f"· rejected {STATS.rejected}")


if __name__ == "__main__":
    main()
