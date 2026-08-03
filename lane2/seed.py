"""Seed the historical layer: episodes + topics from seed/seed-episodes.json.

Topics are the join surface (schema.cypher): boards and notes get
RELATES_TO edges pointing at them; episodes carry the narrative history.
Keywords per topic drive the lexical linker in link.py.
"""
import json

from common import REPO_ROOT, get_graph

# topic -> keywords the linker matches against board titles / note text.
TOPIC_KEYWORDS = {
    "signal-pipeline": ["signal", "pipeline", "capture", "latency"],
    "residency": ["residency", "application", "builder"],
    "agent-workflows": ["agent", "dispatch", "workflow", "assemble", "codex", "claude"],
    "talk-contact": ["linkedin", "profile", "contact", "ml engineer", "talk", "follow up"],
}

EPISODE_TOPIC = {
    "seed_signal_pipeline": "signal-pipeline",
    "seed_residency": "residency",
    "seed_agent_workflows": "agent-workflows",
    "seed_talk_contact": "talk-contact",
}


def seed(graph):
    data = json.loads((REPO_ROOT / "seed" / "seed-episodes.json").read_text())
    for name, keywords in TOPIC_KEYWORDS.items():
        graph.query(
            "MERGE (t:Topic {name: $name}) SET t.keywords = $kw",
            {"name": name, "kw": keywords},
        )
    for ep in data["episodes"]:
        graph.query(
            """
            MERGE (e:Episode {name: $name})
            SET e.body = $body, e.t = $t
            WITH e
            MATCH (t:Topic {name: $topic})
            MERGE (e)-[:RELATES_TO {score: 1.0}]->(t)
            """,
            {
                "name": ep["name"],
                "body": ep["body"],
                "t": ep["reference_time"],
                "topic": EPISODE_TOPIC[ep["name"]],
            },
        )
    print(f"seeded {len(data['episodes'])} episodes, {len(TOPIC_KEYWORDS)} topics")


if __name__ == "__main__":
    seed(get_graph())
