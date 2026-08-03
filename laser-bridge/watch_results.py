#!/usr/bin/env python3
"""watch-results — the return path.

RocketRide's artifact comes back as a `result` event on `dispatch-results`.
This is the subscription the dispatch surface sits on; running it in a visible
terminal during the demo is what makes "motion is real" something the room
sees rather than something we claim.

    python3 watch_results.py

Lane 3 can also use this to prove their pipeline emitted anything at all,
before any UI exists.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import laser_common as common

POLL_INTERVAL = 0.25


def render(event: dict) -> str:
    status = event.get("status")
    marker = {"running": "…", "done": "✓", "failed": "✗"}.get(status, "?")
    head = f"{marker} {status}  dispatch={event.get('dispatch_id')}  t={event.get('t')}"
    artifact = event.get("artifact")
    if status == "done" and artifact:
        body = "\n".join("      " + line for line in str(artifact).splitlines())
        return f"{head}\n{body}"
    return head


async def run(emit_test: bool) -> None:
    laser = await common.connect()
    try:
        await common.ensure_topics(laser)

        if emit_test:
            event = {
                "type": "result",
                "v": 1,
                "t": "2026-08-03T18:10:00Z",
                "dispatch_id": "00000000-0000-0000-0000-0000000000ff",
                "status": "done",
                "artifact": "Test artifact: the return path is wired.",
            }
            await laser.topic(common.TOPIC_OUT).publish().json(event).send()
            print(f"published a test result to {common.TOPIC_OUT}", flush=True)

        cursor = laser.topic(common.TOPIC_OUT).replay()
        print(f"watching {common.DEFAULT_STREAM}/{common.TOPIC_OUT} — Ctrl-C to stop", flush=True)

        while True:
            messages = await cursor.poll()
            if not messages:
                await asyncio.sleep(POLL_INTERVAL)
                continue
            for message in messages:
                try:
                    event = message.json()
                except Exception:  # noqa: BLE001
                    print("  (undecodable record)", file=sys.stderr, flush=True)
                    continue
                problems = common.contract_errors(event)
                if problems:
                    print(f"  non-conforming result: {'; '.join(problems)}\n"
                          f"  {json.dumps(event)}", file=sys.stderr, flush=True)
                    continue
                print(render(event), flush=True)
    finally:
        await laser.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--emit-test", action="store_true",
                        help="publish one synthetic result first, to prove the path both ways")
    args = parser.parse_args()
    try:
        asyncio.run(run(args.emit_test))
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
