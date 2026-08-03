#!/usr/bin/env python3
"""Does the FalkorDB connection actually work? Run this before anything else.

Checks DNS, then TCP, then tries plain and TLS with HARD TIMEOUTS. Without a
socket timeout, connecting with ssl=True to a non-TLS port hangs forever — the
client sits waiting for a server hello that never comes, and you get "tcp:
connected" followed by silence.

    python3 lane2/check_falkor.py
"""

from __future__ import annotations

import os
import socket
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from dotenv import load_dotenv  # noqa: E402
from falkordb import FalkorDB  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")

HOST = os.environ.get("FALKOR_HOST", "localhost")
PORT = int(os.environ.get("FALKOR_PORT", "6379"))
USER = os.environ.get("FALKOR_USER") or None
PASSWORD = os.environ.get("FALKOR_PASSWORD") or None
GRAPH = os.environ.get("ONARI_GRAPH", "onari")

TIMEOUT = 6


def try_connect(ssl_on: bool):
    """Returns (graph, None) on success, (None, error) on failure. Never hangs."""
    try:
        db = FalkorDB(
            host=HOST, port=PORT, username=USER, password=PASSWORD, ssl=ssl_on,
            socket_timeout=TIMEOUT, socket_connect_timeout=TIMEOUT,
        )
        graph = db.select_graph(GRAPH)
        graph.query("RETURN 1")
        return graph, None
    except Exception as exc:  # noqa: BLE001
        return None, exc


def main() -> int:
    print(f"target : {HOST}:{PORT}")
    print(f"user   : {USER or '(none)'}   password: {'set' if PASSWORD else 'NOT SET'}")
    print(f"graph  : {GRAPH}")

    try:
        ip = socket.gethostbyname(HOST)
        print(f"dns    : {HOST} -> {ip}")
    except Exception as exc:  # noqa: BLE001
        print(f"\nFAIL: DNS did not resolve: {exc}")
        return 1

    sock = socket.socket()
    sock.settimeout(TIMEOUT)
    try:
        sock.connect((ip, PORT))
        print("tcp    : connected")
    except Exception as exc:  # noqa: BLE001
        print(f"\nFAIL: cannot reach {HOST}:{PORT} — {type(exc).__name__}: {exc}")
        print("  • wrong port, instance asleep, or the venue network blocks it")
        return 1
    finally:
        sock.close()

    # Plain first: FalkorDB Cloud free-tier instances commonly speak plain RESP
    # with auth, and TLS-to-a-non-TLS-port is the failure that hangs.
    errors = {}
    for ssl_on in (False, True):
        label = "tls " if ssl_on else "plain"
        graph, error = try_connect(ssl_on)
        if graph is None:
            errors[ssl_on] = error
            print(f"{label}  : failed — {type(error).__name__}: {str(error)[:90]}")
            continue

        print(f"{label}  : OK")
        counts = graph.query(
            "MATCH (n) RETURN labels(n)[0] AS label, count(*) AS n ORDER BY label"
        ).result_set
        if counts:
            print("\ngraph contents:")
            for label_name, number in counts:
                print(f"  {label_name or '(unlabelled)':<12} {number}")
        else:
            print("\ngraph is empty (expected before the first ingest)")

        want = "true" if ssl_on else "false"
        current = os.environ.get("FALKOR_SSL", "")
        print(f"\nFALKOR_CHECK_GREEN")
        print(f"set FALKOR_SSL={want} in .env"
              + ("  (already correct)" if current.lower() == want else f"  (currently {current or 'unset'})"))
        return 0

    print("\nFAIL: reachable, but neither plain nor TLS authenticated.")
    for ssl_on, error in errors.items():
        print(f"  ssl={ssl_on}: {type(error).__name__}: {str(error)[:160]}")
    print("  • check FALKOR_USER / FALKOR_PASSWORD against the FalkorDB console")
    print("  • the password has a lowercase L and a capital I that look identical"
          " in most fonts — compare character by character")
    return 1


if __name__ == "__main__":
    sys.exit(main())
