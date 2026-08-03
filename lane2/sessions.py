"""Sessions: accumulate instead of wipe.

`run_demo.py` opens with `graph.delete()`. That is fine for a single-user
fixture rehearsal and wrong for everything else — on a shared instance it
destroys other lanes' data, and it throws away exactly the thing the product
claims to have: "the tenth session knows the first nine."

So: every run is a Session. Nothing is deleted. The newest session is what the
consolidation is ABOUT; older sessions decay into the historical layer, which
is the same place the seeded episodes live. That is the Kasparov frame made
literal — per-surface state that persists while you are elsewhere.

    (:Session {id, ordinal, started_at, label})
        ▲                    ▲
        │ :IN_SESSION        │ :SEEN_IN
    (:Note) (:Delta)      (:Board)

Boards are shared across sessions on purpose: the same window seen on Monday
and Friday is one board with two SEEN_IN edges, so revisits are visible rather
than duplicated. Notes and deltas belong to exactly one session.
"""

from __future__ import annotations

import datetime as _dt

from common import get_graph

# The current session outweighs everything before it. 0.01 is the "99%+"
# ratio: prior sessions inform, they do not compete.
PRIOR_SESSION_WEIGHT = 0.01


def _now_iso() -> str:
    return _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def new_session(graph, label: str | None = None) -> str:
    """Open a session and return its id. Ordinal is monotonic, so 'latest'
    never depends on clock skew between machines."""
    rows = graph.query("MATCH (s:Session) RETURN max(s.ordinal)").result_set
    highest = (rows[0][0] if rows and rows[0][0] is not None else 0)
    ordinal = int(highest) + 1

    started = _now_iso()
    session_id = f"s{ordinal:04d}-{started.replace(':', '').replace('-', '')}"
    graph.query(
        """
        MERGE (s:Session {id: $id})
        SET s.ordinal = $ordinal, s.started_at = $started, s.label = $label
        """,
        {"id": session_id, "ordinal": ordinal, "started": started,
         "label": label or f"session {ordinal}"},
    )
    return session_id


def current_session(graph) -> str | None:
    rows = graph.query(
        "MATCH (s:Session) RETURN s.id ORDER BY s.ordinal DESC LIMIT 1"
    ).result_set
    return rows[0][0] if rows else None


def list_sessions(graph) -> list[dict]:
    rows = graph.query(
        """
        MATCH (s:Session)
        OPTIONAL MATCH (n:Note)-[:IN_SESSION]->(s)
        OPTIONAL MATCH (b:Board)-[:SEEN_IN]->(s)
        RETURN s.id, s.ordinal, s.started_at, s.label,
               count(DISTINCT n), count(DISTINCT b)
        ORDER BY s.ordinal DESC
        """
    ).result_set
    return [
        {"id": r[0], "ordinal": r[1], "started_at": r[2], "label": r[3],
         "notes": r[4], "boards": r[5]}
        for r in rows
    ]


def dedupe(graph) -> int:
    """Remove duplicate notes and deltas.

    `ingest.py` uses CREATE, not MERGE, so re-ingesting the same fixtures twice
    doubles every note. That is precisely why run_demo had to wipe. Deduping
    here removes the reason: `Note.id` is already a deterministic hash of
    (board, time, text), so a repeat is exactly identifiable.
    """
    removed = 0

    duplicates = graph.query(
        """
        MATCH (n:Note)
        WITH n.id AS nid, collect(n) AS group
        WHERE size(group) > 1
        RETURN nid, size(group)
        """
    ).result_set
    for nid, count in duplicates:
        # Keep one, drop the rest. Done one id at a time so a partial failure
        # cannot cascade into deleting a whole label.
        graph.query(
            """
            MATCH (n:Note {id: $nid})
            WITH collect(n) AS group
            FOREACH (extra IN tail(group) | DETACH DELETE extra)
            """,
            {"nid": nid},
        )
        removed += int(count) - 1

    delta_duplicates = graph.query(
        """
        MATCH (d:Delta)
        WITH d.t AS t, d.preview AS preview, collect(d) AS group
        WHERE size(group) > 1
        RETURN t, preview, size(group)
        """
    ).result_set
    for t, preview, count in delta_duplicates:
        graph.query(
            """
            MATCH (d:Delta {t: $t, preview: $preview})
            WITH collect(d) AS group
            FOREACH (extra IN tail(group) | DETACH DELETE extra)
            """,
            {"t": t, "preview": preview},
        )
        removed += int(count) - 1

    return removed


def tag_session(graph, session_id: str) -> dict:
    """Attach everything written since the last tag to this session.

    Works without touching `ingest.py`: anything lacking a session_id was
    written by the run in progress, so it belongs to the session in progress.
    """
    counts = {}

    for label in ("Note", "Delta"):
        graph.query(
            f"MATCH (n:{label}) WHERE n.session_id IS NULL SET n.session_id = $sid",
            {"sid": session_id},
        )
        rows = graph.query(
            f"""
            MATCH (n:{label} {{session_id: $sid}}), (s:Session {{id: $sid}})
            MERGE (n)-[:IN_SESSION]->(s)
            RETURN count(n)
            """,
            {"sid": session_id},
        ).result_set
        counts[label.lower() + "s"] = rows[0][0] if rows else 0

    # Boards touched this session: any board carrying one of this session's
    # notes or deltas, plus any board that has never been seen in a session at
    # all — that second clause is what catches the un-noted glance, which is
    # the one board the demo cannot afford to lose.
    graph.query(
        """
        MATCH (s:Session {id: $sid})
        MATCH (n:Note {session_id: $sid})-[:ON]->(b:Board)
        MERGE (b)-[:SEEN_IN]->(s)
        """,
        {"sid": session_id},
    )
    graph.query(
        """
        MATCH (s:Session {id: $sid})
        MATCH (d:Delta {session_id: $sid})-[:AT]->(b:Board)
        MERGE (b)-[:SEEN_IN]->(s)
        """,
        {"sid": session_id},
    )
    graph.query(
        """
        MATCH (s:Session {id: $sid})
        MATCH (b:Board) WHERE NOT (b)-[:SEEN_IN]->(:Session)
        MERGE (b)-[:SEEN_IN]->(s)
        """,
        {"sid": session_id},
    )

    rows = graph.query(
        "MATCH (b:Board)-[:SEEN_IN]->(:Session {id: $sid}) RETURN count(b)",
        {"sid": session_id},
    ).result_set
    counts["boards"] = rows[0][0] if rows else 0

    graph.query(
        "MATCH (b:Board)-[:SEEN_IN]->(:Session {id: $sid}) SET b.last_session = $sid",
        {"sid": session_id},
    )
    return counts


if __name__ == "__main__":
    graph = get_graph()
    sessions = list_sessions(graph)
    if not sessions:
        print("no sessions yet — run lane2/run_session.py")
    else:
        print(f"{len(sessions)} session(s), newest first:\n")
        for index, s in enumerate(sessions):
            marker = "→ current" if index == 0 else f"  weight {PRIOR_SESSION_WEIGHT}"
            print(f"  [{s['ordinal']:>3}] {s['id']}  {s['started_at']}  "
                  f"{s['boards']} boards, {s['notes']} notes   {marker}")
