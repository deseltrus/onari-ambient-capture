"""Live ingest: LaserData `ambient-events` -> FalkorDB, via lane 2's own writer.

This is the 13:00 integration, in one file. `ingest.py` already knows how to
turn a contract event into graph writes; the only thing it lacked was a source
other than a fixtures file. So this does not reimplement anything — it consumes
the stream and calls lane 2's `write_event` per event.

    fixtures  ─┐
               ├─▶  write_event(graph, ev)  ─▶  FalkorDB
    LaserData ─┘        (lane2/ingest.py)

Run it:
    export LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'
    python3 lane2/ingest_stream.py                # catch up, then follow
    python3 lane2/ingest_stream.py --from-now     # only new events
    python3 lane2/ingest_stream.py --link-every 5 # re-link topics as it goes

Fixtures still work exactly as before; nothing here replaces them. If the Swift
lane stalls, `python3 lane2/run_demo.py` is untouched and the demo path stands.
"""

from __future__ import annotations

import argparse
import asyncio
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "lane2"))
sys.path.insert(0, str(REPO_ROOT / "laser-bridge"))

# Two modules named for "common" would be a trap, so neither gets aliased:
#   laser_common  -> laser-bridge/laser_common.py  (stream + contract)
#   lane2_common  -> lane2/common.py               (FalkorDB connection)
import laser_common  # noqa: E402  (path set above)
import common as lane2_common  # noqa: E402
from ingest import write_event  # noqa: E402  lane2/ingest.py
from link import link_all  # noqa: E402

POLL_INTERVAL = 0.2


def describe(ev: dict) -> str:
    kind = ev.get("type")
    if kind == "switch":
        to = ev.get("to") or {}
        frm = ev.get("from") or {}
        return f"switch #{ev.get('seq')}  {frm.get('app') or '∅'} → {to.get('app')} · {to.get('title')}"
    if kind == "note":
        return f"note   [{ev.get('app')}] \"{ev.get('text')}\""
    if kind == "delta":
        return f"delta  [{ev.get('source')}] {ev.get('preview', '')[:60]}"
    if kind == "result":
        return f"result {ev.get('status')} {ev.get('dispatch_id')}"
    return str(kind)


async def run(from_now: bool, link_every: int) -> None:
    graph = lane2_common.get_graph()
    laser = await laser_common.connect()

    try:
        await laser_common.ensure_topics(laser)
        topic = laser.topic(laser_common.TOPIC_IN)

        # `replay()` starts at offset 0 so a restart rebuilds the whole session
        # — the graph writes are MERGE-based and idempotent, so re-reading is
        # safe and is the cheapest possible recovery story.
        cursor = topic.replay()
        if from_now:
            # Drain what is already there without writing it.
            while await cursor.poll():
                pass
            print("skipped existing events, following from now")

        print(f"ingesting {laser_common.DEFAULT_STREAM}/{laser_common.TOPIC_IN} "
              f"-> FalkorDB graph '{lane2_common.GRAPH_NAME}'", flush=True)

        written = 0
        since_link = 0
        while True:
            messages = await cursor.poll()
            if not messages:
                await asyncio.sleep(POLL_INTERVAL)
                continue

            for message in messages:
                try:
                    event = message.json()
                except Exception as exc:  # noqa: BLE001
                    print(f"  skipped undecodable record: {exc}", file=sys.stderr, flush=True)
                    continue

                problems = laser_common.contract_errors(event)
                if problems:
                    # Loud, and skipped. A malformed event that reaches the
                    # graph is far more expensive to debug than one refused here.
                    print(f"  REJECTED {event.get('type')}: {'; '.join(problems)}",
                          file=sys.stderr, flush=True)
                    continue

                try:
                    write_event(graph, event)
                except Exception as exc:  # noqa: BLE001
                    print(f"  graph write failed for {event.get('type')}: {exc}",
                          file=sys.stderr, flush=True)
                    continue

                written += 1
                since_link += 1
                print(f"  {written:>3}  {describe(event)}", flush=True)

            if link_every and since_link >= link_every:
                since_link = 0
                link_all(graph)
    finally:
        await laser.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--from-now", action="store_true",
                        help="ignore events already on the topic")
    parser.add_argument("--link-every", type=int, default=0, metavar="N",
                        help="re-run the relevance linker every N events (0 = never)")
    args = parser.parse_args()

    try:
        asyncio.run(run(args.from_now, args.link_every))
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    main()
