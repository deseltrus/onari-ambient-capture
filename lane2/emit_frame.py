#!/usr/bin/env python3
"""Write the intent frame to a file — the handoff artifact for lane 3.

Guild consumes this and RocketRide's `context-to-artifact` pipeline runs on it.

Session-aware: if the graph has sessions, the frame is about the NEWEST one and
earlier sessions ride along as `prior_sessions` at 1% weight. If it has none
(a plain `run_demo.py` graph), it falls back to the flat consolidation, so this
never breaks on a graph someone else built.

    python3 lane2/emit_frame.py                    # -> intent-frame.json
    python3 lane2/emit_frame.py --session s0002-…  # a specific session
    python3 lane2/emit_frame.py --flat             # ignore sessions entirely
    python3 lane2/emit_frame.py --pretty
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import REPO_ROOT, get_graph  # noqa: E402
from consolidate import consolidate as consolidate_flat  # noqa: E402
from consolidate import render as render_flat  # noqa: E402
from consolidate_session import consolidate_session  # noqa: E402
from consolidate_session import render as render_session  # noqa: E402
from sessions import current_session  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", default=str(REPO_ROOT / "intent-frame.json"))
    parser.add_argument("--session", help="consolidate a specific session id")
    parser.add_argument("--flat", action="store_true",
                        help="ignore sessions — every board in the graph")
    parser.add_argument("--pretty", action="store_true", help="also print the readable view")
    args = parser.parse_args()

    graph = get_graph()

    use_sessions = not args.flat and (args.session or current_session(graph))
    if use_sessions:
        frame = consolidate_session(graph, args.session)
        render = render_session
    else:
        frame = consolidate_flat(graph)
        render = render_flat

    if not frame["boards"]:
        session_note = ""
        if use_sessions:
            session_note = (" This session has no boards — if you just ran a live "
                            "capture, tag it with: python3 lane2/run_session.py --no-fixtures")
        print("the graph is empty — run an ingest first "
              "(lane2/run_session.py for fixtures, lane2/ingest_stream.py for live)."
              + session_note, file=sys.stderr)
        return 1

    Path(args.out).write_text(json.dumps(frame, indent=2), encoding="utf-8")

    unspoken = [b for b in frame["boards"] if b["unspoken"]]
    print(f"wrote {args.out}")
    if frame.get("session"):
        print(f"  session        : {frame['session']['label']} ({frame['session']['id']})")
    print(f"  mission        : {frame['mission']}")
    print(f"  boards         : {len(frame['boards'])}")
    print(f"  history joins  : {len(frame['history_joins'])}")
    if frame.get("prior_sessions"):
        print(f"  prior sessions : {len(frame['prior_sessions'])} (weight 0.01)")
    print(f"  unspoken boards: {len(unspoken)}"
          + (f"  ({', '.join(b['title'][:40] for b in unspoken)})" if unspoken else ""))

    if not unspoken:
        print("\n  ⚠ no unspoken board in this frame. The demo's payoff is a surface that"
              "\n    contributed WITHOUT a note — check the wander included a dwell with"
              "\n    no note spoken on it.")

    if args.pretty:
        print()
        print(render(frame))
    return 0


if __name__ == "__main__":
    sys.exit(main())
