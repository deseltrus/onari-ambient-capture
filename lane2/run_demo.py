"""Lane 2 end to end against fixtures: wipe -> seed -> ingest -> link -> consolidate."""
from common import get_graph
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

seed(graph)
ingest_fixtures(graph)
link_all(graph)
print()
print(render(consolidate(graph)))
