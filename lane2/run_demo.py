"""Lane 2 end to end against fixtures: wipe -> seed -> ingest -> link -> consolidate.

Usage: python run_demo.py [fixtures.jsonl]  (default: the full demo sequence)
"""
import sys
from pathlib import Path

from common import REPO_ROOT, get_graph
from consolidate import consolidate, render
from ingest import ingest_fixtures
from link import link_all
from seed import seed

graph = get_graph()
try:
    graph.delete()
except Exception:
    pass  # graph may not exist yet
graph = get_graph()

fixtures = (
    Path(sys.argv[1])
    if len(sys.argv) > 1
    else REPO_ROOT / "fixtures" / "events-demo-full.jsonl"
)
seed(graph)
ingest_fixtures(graph, fixtures)
link_all(graph)
print()
print(render(consolidate(graph)))
