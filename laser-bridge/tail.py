#!/usr/bin/env python3
"""tail — read `ambient-events` back off the stream.

Two jobs:
  1. Proof for the capture lane that events really landed (not just that the
     POST returned 202).
  2. The graph lane's starting point. The consume loop below is exactly the
     shape the FalkorDB writer needs — swap the `print` for the Cypher write
     and lane 2 is consuming live instead of reading fixtures off disk.

    python3 tail.py                 # everything on the topic, then exit
    python3 tail.py --follow        # stay attached
    python3 tail.py --jsonl out.jsonl
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys

import laser_common as common
from bridge import describe

POLL_INTERVAL = 0.2


async def run(follow: bool, jsonl_path: str | None, quiet: bool) -> None:
    laser = await common.connect()
    sink = open(jsonl_path, "a", encoding="utf-8") if jsonl_path else None

    try:
        await common.ensure_topics(laser)
        # A replay cursor starts at offset 0: a fresh reader sees the whole
        # session, which is what makes this safe to run mid-demo.
        cursor = laser.topic(common.TOPIC_IN).replay()
        print(f"tailing {common.DEFAULT_STREAM}/{common.TOPIC_IN}"
              + (" (following)" if follow else ""), flush=True)

        seen = 0
        idle = 0.0
        while True:
            messages = await cursor.poll()
            if not messages:
                if not follow and idle >= 1.0:
                    break
                idle += POLL_INTERVAL
                await asyncio.sleep(POLL_INTERVAL)
                continue

            idle = 0.0
            for message in messages:
                try:
                    event = message.json()
                except Exception:  # noqa: BLE001
                    print("  (undecodable record)", file=sys.stderr, flush=True)
                    continue

                seen += 1
                if not quiet:
                    print(f"  {seen:>3}  " + describe(event), flush=True)
                if sink:
                    sink.write(json.dumps(event, sort_keys=True) + "\n")
                    sink.flush()

        print(f"{seen} event(s)", flush=True)
    finally:
        if sink:
            sink.close()
        await laser.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--follow", "-f", action="store_true", help="stay attached")
    parser.add_argument("--jsonl", metavar="FILE", help="also append each event to a JSONL file")
    parser.add_argument("--quiet", "-q", action="store_true", help="count only, no per-event line")
    args = parser.parse_args()

    try:
        asyncio.run(run(args.follow, args.jsonl, args.quiet))
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
