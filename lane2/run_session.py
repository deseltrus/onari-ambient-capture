"""Non-destructive replacement for run_demo.py: accumulate instead of wipe.

Same steps, minus the `graph.delete()` that opens run_demo. Every invocation
opens a new Session; earlier ones survive as history.

    python3 lane2/run_session.py                          # full demo fixtures
    python3 lane2/run_session.py --label "rehearsal 2"
    python3 lane2/run_session.py fixtures/events-sample.jsonl
    python3 lane2/run_session.py --list                   # what is in the graph

Use this for rehearsals on the shared instance. `run_demo.py` still exists and
still wipes — keep it for the one clean run before the live demo.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

if sys.stdout.encoding and sys.stdout.encoding.lower() != "utf-8":
    sys.stdout.reconfigure(encoding="utf-8")

from common import REPO_ROOT, get_graph  # noqa: E402
from consolidate_session import consolidate_session, render  # noqa: E402
from ingest import ingest_fixtures  # noqa: E402
from link import link_all  # noqa: E402
from seed import seed  # noqa: E402
from sessions import dedupe, list_sessions, new_session, tag_session  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("fixtures", nargs="?",
                        default=str(REPO_ROOT / "fixtures" / "events-demo-full.jsonl"))
    parser.add_argument("--label", help="human name for this session")
    parser.add_argument("--list", action="store_true", help="list sessions and exit")
    parser.add_argument("--no-fixtures", action="store_true",
                        help="open a session and tag whatever is already there "
                             "(use after a live capture run)")
    args = parser.parse_args()

    graph = get_graph()

    if args.list:
        sessions = list_sessions(graph)
        if not sessions:
            print("no sessions yet")
            return 0
        print(f"{len(sessions)} session(s), newest first:\n")
        for index, s in enumerate(sessions):
            marker = "  ← current" if index == 0 else ""
            print(f"  [{s['ordinal']:>3}] {s['id']}  {s['started_at']}  "
                  f"{s['boards']} boards, {s['notes']} notes{marker}")
        return 0

    # Seeding is MERGE-based, so running it every session is free and keeps a
    # fresh graph correct without a wipe.
    seed(graph)

    session_id = new_session(graph, args.label)
    print(f"session {session_id}" + (f"  ({args.label})" if args.label else ""))

    if not args.no_fixtures:
        ingest_fixtures(graph, Path(args.fixtures))
        removed = dedupe(graph)
        if removed:
            print(f"deduped {removed} repeated node(s) — ingest.py CREATEs rather "
                  f"than MERGEs, so a re-run would otherwise double them")

    counts = tag_session(graph, session_id)
    print(f"tagged {counts.get('boards', 0)} boards, {counts.get('notes', 0)} notes, "
          f"{counts.get('deltas', 0)} deltas into this session")

    link_all(graph)
    print()
    print(render(consolidate_session(graph, session_id)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
