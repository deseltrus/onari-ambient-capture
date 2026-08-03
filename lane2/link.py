"""Relevance linker: attach boards and notes to historical topics.

Lexical for now (keyword overlap against Topic.keywords). This is what
makes the un-noted LinkedIn glance surface in consolidation: the board
title alone carries enough signal to join the talk-contact topic.
"""


def _score(text, keywords):
    text = text.lower()
    hits = [k for k in keywords if k in text]
    return len(hits) / len(keywords) if keywords else 0.0, hits


def link_all(graph):
    topics = graph.query("MATCH (t:Topic) RETURN t.name, t.keywords").result_set
    boards = graph.query("MATCH (b:Board) RETURN b.id, b.app, b.title").result_set
    notes = graph.query("MATCH (n:Note) RETURN n.id, n.text").result_set

    edges = 0
    for tname, kws in topics:
        for bid, app, title in boards:
            score, hits = _score(f"{app} {title}", kws or [])
            if score > 0:
                graph.query(
                    """
                    MATCH (b:Board {id: $bid}), (t:Topic {name: $t})
                    MERGE (b)-[r:RELATES_TO]->(t) SET r.score = $s, r.hits = $h
                    """,
                    {"bid": bid, "t": tname, "s": score, "h": hits},
                )
                edges += 1
        for nid, text in notes:
            score, hits = _score(text or "", kws or [])
            if score > 0:
                graph.query(
                    """
                    MATCH (n:Note {id: $nid}), (t:Topic {name: $t})
                    MERGE (n)-[r:RELATES_TO]->(t) SET r.score = $s, r.hits = $h
                    """,
                    {"nid": nid, "t": tname, "s": score, "h": hits},
                )
                edges += 1
    print(f"linked {edges} RELATES_TO edges")


if __name__ == "__main__":
    from common import get_graph

    link_all(get_graph())
