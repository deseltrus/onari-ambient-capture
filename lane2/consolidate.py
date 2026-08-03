"""Consolidation: the session in relation to history -> the intent frame.

Output contract (artifact, tab 3): extremely short, clear, detail-rich.
Emits JSON (for Guild, lane 3) and a readable text block (for the stage).
"""
import json

from common import get_graph


def consolidate(graph):
    boards = graph.query(
        """
        MATCH (b:Board)
        OPTIONAL MATCH (n:Note)-[:ON]->(b)
        OPTIONAL MATCH (d:Delta)-[:AT]->(b)
        OPTIONAL MATCH (b)-[r:RELATES_TO]->(t:Topic)
        RETURN b.id, b.app, b.title, b.last_seen,
               collect(DISTINCT {text: n.text, t: n.t, mode: n.mode}),
               collect(DISTINCT {kind: d.kind, preview: d.preview}),
               collect(DISTINCT {topic: t.name, score: r.score})
        ORDER BY b.last_seen
        """
    ).result_set

    history = graph.query(
        """
        MATCH (x)-[:RELATES_TO]->(t:Topic)<-[:RELATES_TO]-(e:Episode)
        WHERE x:Board OR x:Note
        RETURN DISTINCT t.name, e.name, e.body, e.t
        """
    ).result_set

    frame = {"mission": None, "boards": [], "history_joins": []}
    for bid, app, title, last_seen, notes, deltas, topics in boards:
        frame["boards"].append(
            {
                "board_id": bid,
                "app": app,
                "title": title,
                "last_seen": last_seen,
                "notes": [n for n in notes if n.get("text")],
                "deltas": [d for d in deltas if d.get("kind")],
                "topics": [t for t in topics if t.get("topic")],
                "unspoken": not any(n.get("text") for n in notes),
            }
        )
    for tname, ename, body, t in history:
        frame["history_joins"].append(
            {"topic": tname, "episode": ename, "body": body, "t": t}
        )

    # Mission: the dominant topic across the session's boards and notes.
    tally = {}
    for b in frame["boards"]:
        for t in b["topics"]:
            tally[t["topic"]] = tally.get(t["topic"], 0) + (t["score"] or 0)
    frame["mission"] = max(tally, key=tally.get) if tally else None
    return frame


def render(frame):
    lines = [f"MISSION: {frame['mission']}", ""]
    for b in frame["boards"]:
        tag = " [no note — seen in context]" if b["unspoken"] else ""
        lines.append(f"• {b['app']} — {b['title']}{tag}")
        for n in b["notes"]:
            lines.append(f'    "{n["text"]}"')
        for d in b["deltas"]:
            lines.append(f"    Δ {d['kind']}: {d['preview']}")
        for t in b["topics"]:
            lines.append(f"    ↳ {t['topic']} ({t['score']:.2f})")
    lines.append("")
    lines.append("HISTORY JOINS:")
    for h in frame["history_joins"]:
        lines.append(f"• [{h['topic']}] {h['body']}")
    return "\n".join(lines)


if __name__ == "__main__":
    frame = consolidate(get_graph())
    print(render(frame))
    print("\n--- intent frame (JSON, for lane 3) ---")
    print(json.dumps(frame, indent=2))
