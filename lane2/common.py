"""Shared FalkorDB connection for lane 2. Reads .env at repo root.

Works against a local Docker instance AND FalkorDB Cloud from the same file.

`FALKOR_SSL` selects TLS and DEFAULTS TO OFF. Do not make it clever: guessing
TLS from "a password is set" is wrong for FalkorDB Cloud instances that speak
plain RESP with auth, and the failure mode is the worst kind — connecting with
TLS to a non-TLS port hangs on the handshake instead of erroring. Run
`lane2/check_falkor.py`; it tries both with timeouts and tells you which.

The socket timeouts below exist for the same reason: no operation against the
graph should ever be able to hang the demo.
"""
import os
from pathlib import Path

from dotenv import load_dotenv
from falkordb import FalkorDB

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

GRAPH_NAME = os.environ.get("ONARI_GRAPH", "onari")


def _env_bool(name: str, default: bool) -> bool:
    raw = os.environ.get(name, "").strip().lower()
    if not raw:
        return default
    return raw in ("1", "true", "yes", "on")


SOCKET_TIMEOUT = int(os.environ.get("FALKOR_TIMEOUT", "10"))


def connection_info() -> dict:
    """The resolved target, for diagnostics. Never includes the password."""
    return {
        "host": os.environ.get("FALKOR_HOST", "localhost"),
        "port": int(os.environ.get("FALKOR_PORT", "6379")),
        "username": os.environ.get("FALKOR_USER") or None,
        "ssl": _env_bool("FALKOR_SSL", False),
        "graph": GRAPH_NAME,
        "password_set": bool(os.environ.get("FALKOR_PASSWORD")),
    }


def get_graph():
    db = FalkorDB(
        host=os.environ.get("FALKOR_HOST", "localhost"),
        port=int(os.environ.get("FALKOR_PORT", "6379")),
        username=os.environ.get("FALKOR_USER") or None,
        password=os.environ.get("FALKOR_PASSWORD") or None,
        ssl=_env_bool("FALKOR_SSL", False),
        socket_timeout=SOCKET_TIMEOUT,
        socket_connect_timeout=SOCKET_TIMEOUT,
    )
    return db.select_graph(GRAPH_NAME)
