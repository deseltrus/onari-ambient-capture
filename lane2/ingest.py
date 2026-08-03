"""Event consumer: contract events -> graph writes per graph/schema.cypher.

Source is pluggable: fixtures JSONL now, LaserData stream at integration.
Handles the four contract types: switch, note, delta, result.
"""
import hashlib
import json

from common import REPO_ROOT, get_graph


def _note_id(ev):
    raw = f"{ev['board_id']}|{ev['t']}|{ev['text']}"
    return hashlib.sha1(raw.encode()).hexdigest()[:12]


def write_event(graph, ev):
    kind = ev["type"]
    if kind == "switch":
        to = ev["to"]
        graph.query(
            """
            MERGE (b:Board {id: $id})
            SET b.app = $app, b.title = $title, b.last_seen = $t
            """,
            {"id": to["board_id"], "app": to["app"], "title": to["title"], "t": ev["t"]},
        )
        if ev["from"]["board_id"]:
            graph.query(
                """
                MATCH (a:Board {id: $from_id}), (b:Board {id: $to_id})
                CREATE (a)-[:SWITCHED_TO {t: $t, dwell_ms: $dwell, seq: $seq}]->(b)
                """,
                {
                    "from_id": ev["from"]["board_id"],
                    "to_id": to["board_id"],
                    "t": ev["t"],
                    "dwell": ev.get("dwell_ms_from") or 0,
                    "seq": ev["seq"],
                },
            )
    elif kind == "note":
        graph.query(
            """
            MERGE (b:Board {id: $bid})
            ON CREATE SET b.app = $app, b.title = $title, b.last_seen = $t
            CREATE (n:Note {id: $nid, text: $text, t: $t, mode: $mode, field: $field})
            CREATE (n)-[:ON]->(b)
            """,
            {
                "bid": ev["board_id"],
                "app": ev["app"],
                "title": ev["title"],
                "nid": _note_id(ev),
                "text": ev["text"],
                "t": ev["t"],
                "mode": ev.get("mode", "note"),
                "field": ev.get("field"),
            },
        )
    elif kind == "delta":
        graph.query(
            """
            MERGE (b:Board {id: $bid})
            CREATE (d:Delta {kind: $kind, t: $t, preview: $preview, source: $source})
            CREATE (d)-[:AT]->(b)
            """,
            {
                "bid": ev["board_id"],
                "kind": ev["kind"],
                "t": ev["t"],
                "preview": ev.get("preview", ""),
                "source": ev.get("source", ""),
            },
        )
    elif kind == "result":
        graph.query(
            """
            MERGE (r:Result {dispatch_id: $did})
            SET r.status = $status, r.t = $t, r.artifact = $artifact
            """,
            {
                "did": ev["dispatch_id"],
                "status": ev["status"],
                "t": ev["t"],
                "artifact": ev.get("artifact"),
            },
        )


def ingest_fixtures(graph, path=None):
    path = path or REPO_ROOT / "fixtures" / "events-sample.jsonl"
    count = 0
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        write_event(graph, json.loads(line))
        count += 1
    print(f"ingested {count} events from {path.name}")


if __name__ == "__main__":
    ingest_fixtures(get_graph())
