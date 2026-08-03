"""Session-scoped consolidation.

Same output contract as `consolidate.py` — `mission`, `boards`,
`history_joins` — so lane 3 does not have to change anything. Two fields are
ADDED, never substituted:

    "session":        which session this frame is about
    "prior_sessions": what came before, at PRIOR_SESSION_WEIGHT

The newest session is the frame. Older sessions are history, sitting next to
the seeded episodes, and are weighted so they inform the mission without ever
outvoting what the user is doing right now.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from common import get_graph  # noqa: E402
from sessions import PRIOR_SESSION_WEIGHT, current_session  # noqa: E402


def consolidate_session(graph, session_id: str | None = None) -> dict:
    session_id = session_id or current_session(graph)
    if session_id is None:
        return {"session": None, "mission": None, "boards": [],
                "history_joins": [], "prior_sessions": []}

    boards = graph.query(
        """
        MATCH (b:Board)-[:SEEN_IN]->(:Session {id: $sid})
        OPTIONAL MATCH (n:Note)-[:ON]->(b) WHERE n.session_id = $sid
        OPTIONAL MATCH (d:Delta)-[:AT]->(b) WHERE d.session_id = $sid
        OPTIONAL MATCH (b)-[r:RELATES_TO]->(t:Topic)
        RETURN b.id, b.app, b.title, b.last_seen,
               collect(DISTINCT {text: n.text, t: n.t, mode: n.mode}),
               collect(DISTINCT {kind: d.kind, preview: d.preview}),
               collect(DISTINCT {topic: t.name, score: r.score})
        ORDER BY b.last_seen
        """,
        {"sid": session_id},
    ).result_set

    history = graph.query(
        """
        MATCH (x)-[:RELATES_TO]->(t:Topic)<-[:RELATES_TO]-(e:Episode)
        WHERE x:Board OR x:Note
        RETURN DISTINCT t.name, e.name, e.body, e.t
        """
    ).result_set

    prior = graph.query(
        """
        MATCH (s:Session) WHERE s.id <> $sid
        OPTIONAL MATCH (n:Note)-[:IN_SESSION]->(s)
        OPTIONAL MATCH (b:Board)-[:SEEN_IN]->(s)
        OPTIONAL MATCH (b)-[:RELATES_TO]->(t:Topic)
        RETURN s.id, s.ordinal, s.started_at, s.label,
               collect(DISTINCT n.text), collect(DISTINCT t.name)
        ORDER BY s.ordinal DESC
        """,
        {"sid": session_id},
    ).result_set

    meta = graph.query(
        "MATCH (s:Session {id: $sid}) RETURN s.ordinal, s.started_at, s.label",
        {"sid": session_id},
    ).result_set
    ordinal, started_at, label = (meta[0] if meta else (None, None, None))

    frame = {
        "session": {"id": session_id, "ordinal": ordinal,
                    "started_at": started_at, "label": label},
        "mission": None,
        "boards": [],
        "history_joins": [],
        "prior_sessions": [],
    }

    for bid, app, title, last_seen, notes, deltas, topics in boards:
        frame["boards"].append({
            "board_id": bid,
            "app": app,
            "title": title,
            "last_seen": last_seen,
            "notes": [n for n in notes if n.get("text")],
            "deltas": [d for d in deltas if d.get("kind")],
            "topics": [t for t in topics if t.get("topic")],
            "unspoken": not any(n.get("text") for n in notes),
        })

    for tname, ename, body, t in history:
        frame["history_joins"].append(
            {"topic": tname, "episode": ename, "body": body, "t": t}
        )

    for sid, ordinal_, started, label_, texts, topic_names in prior:
        texts = [x for x in texts if x]
        topic_names = [x for x in topic_names if x]
        if not texts and not topic_names:
            continue
        frame["prior_sessions"].append({
            "session_id": sid,
            "ordinal": ordinal_,
            "started_at": started,
            "label": label_,
            "weight": PRIOR_SESSION_WEIGHT,
            "topics": topic_names,
            "notes": texts[:5],
            "note_count": len(texts),
        })

    # Mission: this session's topics at full weight, prior sessions at 1%.
    # Without the weighting a long history would drown out the last ten
    # minutes, which is the opposite of what the consolidation is for.
    tally: dict[str, float] = {}
    for board in frame["boards"]:
        for topic in board["topics"]:
            tally[topic["topic"]] = tally.get(topic["topic"], 0) + (topic["score"] or 0)
    for prior_session in frame["prior_sessions"]:
        for name in prior_session["topics"]:
            tally[name] = tally.get(name, 0) + PRIOR_SESSION_WEIGHT

    frame["mission"] = max(tally, key=tally.get) if tally else None
    return frame


def render(frame: dict) -> str:
    session = frame.get("session") or {}
    lines = [
        f"SESSION: {session.get('label')} ({session.get('id')})",
        f"MISSION: {frame['mission']}",
        "",
    ]
    for board in frame["boards"]:
        tag = " [no note — seen in context]" if board["unspoken"] else ""
        lines.append(f"• {board['app']} — {board['title']}{tag}")
        for note in board["notes"]:
            lines.append(f'    "{note["text"]}"')
        for delta in board["deltas"]:
            lines.append(f"    Δ {delta['kind']}: {delta['preview']}")
        for topic in board["topics"]:
            lines.append(f"    ↳ {topic['topic']} ({topic['score']:.2f})")

    lines.append("")
    lines.append("HISTORY JOINS:")
    for join in frame["history_joins"]:
        lines.append(f"• [{join['topic']}] {join['body']}")

    if frame["prior_sessions"]:
        lines.append("")
        lines.append(f"EARLIER SESSIONS (weight {PRIOR_SESSION_WEIGHT}):")
        for prior in frame["prior_sessions"]:
            topics = ", ".join(prior["topics"]) or "—"
            lines.append(
                f"• [{prior['label']}] {prior['note_count']} note(s) · {topics}"
            )
    return "\n".join(lines)


if __name__ == "__main__":
    graph = get_graph()
    frame = consolidate_session(graph, sys.argv[1] if len(sys.argv) > 1 else None)
    print(render(frame))
    print("\n--- intent frame (JSON, for lane 3) ---")
    print(json.dumps(frame, indent=2))
