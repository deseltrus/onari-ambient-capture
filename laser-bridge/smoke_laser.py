#!/usr/bin/env python3
"""The LaserData smoke test the base README asks for: publish and read back one
record, on the topics this project actually uses.

Green here means the transport half of lane 1 is done and the graph lane has
somewhere real to read from.

    export LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'
    python3 smoke_laser.py
"""

from __future__ import annotations

import asyncio
import sys
import time

import laser_common as common


async def main() -> int:
    print(f"connecting to {common.connection_string()}")
    laser = await common.connect()

    try:
        caps = await laser.capabilities()
        print(f"connected · managed={caps.managed} query={caps.query} watch={caps.watch}")

        await common.ensure_topics(laser)
        print(f"topics ready · {common.TOPIC_IN} · {common.TOPIC_OUT}")

        # A contract-shaped switch event, so this exercises the real payload
        # rather than a toy {"hello": 1}.
        marker = f"smoke-{int(time.time() * 1000)}"
        event = {
            "type": "switch",
            "v": 1,
            "t": "2026-08-03T18:00:01Z",
            "seq": 1,
            "from": {"app": None, "title": None, "board_id": None},
            "to": {"app": "SmokeTest", "title": marker, "board_id": marker},
            "dwell_ms_from": None,
        }
        problems = common.contract_errors(event)
        if problems:
            print(f"FAIL: the smoke event itself does not conform: {problems}")
            return 1

        await laser.topic(common.TOPIC_IN).publish().json(event).send()
        print(f"published one switch event ({marker})")

        cursor = laser.topic(common.TOPIC_IN).replay()
        deadline = time.monotonic() + 15.0
        while time.monotonic() < deadline:
            messages = await cursor.poll()
            for message in messages:
                try:
                    payload = message.json()
                except Exception:  # noqa: BLE001
                    continue
                if (payload.get("to") or {}).get("title") == marker:
                    print("read the same record back off the topic")
                    print("LASERDATA_SMOKE_GREEN")
                    return 0
            await asyncio.sleep(0.2)

        print("FAIL: published, but the record did not come back within 15s")
        return 1
    finally:
        await laser.close()


if __name__ == "__main__":
    try:
        sys.exit(asyncio.run(main()))
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {type(exc).__name__}: {exc}")
        print("\nchecks:")
        print("  • is Laser Stack up?   cd laser-stack && ./scripts/up")
        print("  • is the connection string exported? echo $LASER_CONNECTION_STRING")
        print("  • is the SDK installed?  pip install laser-sdk")
        sys.exit(1)
