"""Shared FalkorDB connection for lane 2. Reads .env at repo root."""
import os
from pathlib import Path

from dotenv import load_dotenv
from falkordb import FalkorDB

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

GRAPH_NAME = os.environ.get("ONARI_GRAPH", "onari")


def get_graph():
    db = FalkorDB(
        host=os.environ.get("FALKOR_HOST", "localhost"),
        port=int(os.environ.get("FALKOR_PORT", "6379")),
        username=os.environ.get("FALKOR_USER") or None,
        password=os.environ.get("FALKOR_PASSWORD") or None,
    )
    return db.select_graph(GRAPH_NAME)
