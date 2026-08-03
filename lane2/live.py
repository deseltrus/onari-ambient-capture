"""Live consumer: tail a growing JSONL file, ingest each new event, keep
the consolidation fresh.

Transport-agnostic on purpose: lane 1 can append to a file over SSH/rsync,
pipe through netcat, or we swap in a LaserData watch subscription later —
write_event() doesn't care where events come from.

Usage: python live.py <events.jsonl> [--interval 1.0]
"""
import json
import sys
import time
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)

from common import get_graph
from consolidate import consolidate, render
from ingest import write_event
from link import link_all


def follow(path, interval=1.0):
    """Yield new lines as the file grows (works even if it doesn't exist yet)."""
    pos = 0
    while True:
        p = Path(path)
        if p.exists():
            with p.open() as f:
                f.seek(pos)
                for line in f:
                    if line.strip():
                        yield line
                pos = f.tell()
        time.sleep(interval)


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    source = sys.argv[1]
    interval = float(sys.argv[2].split("=", 1)[1]) if len(sys.argv) > 2 else 1.0
    graph = get_graph()
    count = 0
    print(f"following {source} (ctrl-c to stop)")
    for line in follow(source, interval):
        try:
            ev = json.loads(line)
        except json.JSONDecodeError as e:
            print(f"skipped bad line: {e}")
            continue
        write_event(graph, ev)
        link_all(graph)
        count += 1
        print(f"\n=== event {count}: {ev['type']} @ {ev.get('t', '?')} ===")
        print(render(consolidate(graph)))


if __name__ == "__main__":
    main()
