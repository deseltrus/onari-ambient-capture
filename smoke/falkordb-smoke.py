#!/usr/bin/env python3
"""Tonight's checklist item, for real: confirm the FalkorDB connection.

Local:  docker run -p 6379:6379 -p 3000:3000 -it --rm falkordb/falkordb:latest
Cloud:  FALKOR_HOST / FALKOR_PORT / FALKOR_USER / FALKOR_PASSWORD env vars
"""
import os
from falkordb import FalkorDB

db = FalkorDB(
    host=os.environ.get("FALKOR_HOST", "localhost"),
    port=int(os.environ.get("FALKOR_PORT", "6379")),
    username=os.environ.get("FALKOR_USER"),
    password=os.environ.get("FALKOR_PASSWORD"),
)
g = db.select_graph("smoke")
g.query("CREATE (:Board {name:'codex'})-[:SWITCHED_TO]->(:Board {name:'claude'})")
res = g.query("MATCH (a:Board)-[:SWITCHED_TO]->(b:Board) RETURN a.name, b.name")
assert res.result_set == [["codex", "claude"]], res.result_set
g.delete()
print("FALKORDB_SMOKE_GREEN")
