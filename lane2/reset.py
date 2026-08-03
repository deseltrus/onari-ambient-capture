"""Reset for a live run: wipe the graph, seed history only.

Use before an integration or demo take: the graph starts clean with the
synthetic episodes/topics, then live.py fills it from real capture events.
"""
from common import get_graph
from seed import seed

graph = get_graph()
try:
    graph.delete()
except Exception:
    pass  # graph may not exist yet
graph = get_graph()
seed(graph)
print("graph reset: history seeded, ready for live events")
