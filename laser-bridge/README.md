# laser-bridge — lane 1's transport

The Laser SDK ships for Rust, Python and TypeScript. **There is no Swift SDK.**
So the Mac app does not talk to Iggy; it POSTs newline-delimited JSON to this
process on loopback, and this process publishes with the real SDK.

```
AmbientMac  ──POST ndjson──▶  bridge.py  ──laser-sdk──▶  ambient-events  ──▶  graph lane
                                  │
                                  └── rejects anything that violates event-contract.json
```

One boring hop, and the entire "how does Swift reach LaserData" risk disappears.
Replace it with a native client after the hackathon; nothing above it changes.

## Stream / topic model — everyone must match this

The contract names two streams. Laser's model is stream → topic, so:

| Contract | Laser stream | Laser topic |
|---|---|---|
| `stream_in: ambient-events` | `onari` | `ambient-events` |
| `stream_out: dispatch-results` | `onari` | `dispatch-results` |

Override with `LASER_STREAM`, `LASER_TOPIC_IN`, `LASER_TOPIC_OUT`. All of it is
resolved in `laser_common.py` and nowhere else.

## Run it

```bash
# 0. No LaserData needed. Prints what it WOULD publish, validates every event.
#    Use this to get the Mac app verified before Docker is even up.
python3 bridge.py --stdout

# 1. The real thing.
pip install laser-sdk
export LASER_CONNECTION_STRING='iggy:laser@127.0.0.1:8090'   # printed by laser-stack ./scripts/up
python3 bridge.py
```

## The four tools

| Command | What it does |
|---|---|
| `python3 bridge.py` | HTTP ingest on `127.0.0.1:8077` → publishes to `ambient-events` |
| `python3 bridge.py --stdout` | Same, but prints instead of publishing. Zero dependencies |
| `python3 bridge.py --replay FILE` | Publish a JSONL file and exit — spool catch-up, or the repo fixtures |
| `python3 tail.py --follow` | Read `ambient-events` back. **This is the graph lane's starting point** |
| `python3 watch_results.py` | Subscribe `dispatch-results` — the return path, for lane 3 |
| `python3 smoke_laser.py` | The README's LaserData smoke test, on our real topics |

## Endpoints

```
POST /events    one JSON object, a JSON array, or NDJSON
GET  /health    {"ok": true, "received": N, "published": N, "rejected": N}
```

## Two properties the demo leans on

**Nothing is lost.** The Mac app appends every event to a durable JSONL spool
*before* it attempts the POST. If the bridge is down, the venue wifi dies, or
Docker gets restarted, the spool is the record:

```bash
python3 bridge.py --replay ~/Library/Application\ Support/Onari/ambient-events.jsonl
```

**Nothing bad gets through.** Every event is checked against
`event-contract.json` before publishing. A malformed event is rejected with a
loud log line instead of reaching the graph lane and costing them a debugging
round-trip. Try it:

```bash
curl -X POST http://127.0.0.1:8077/events -d '{"type":"telepathy","v":1}'
# {"accepted": 0, "rejected": 1, "parse_errors": []}
```

## For the graph lane

Two things here are yours to take:

1. **`tail.py`** — the consume loop is exactly the shape your FalkorDB writer
   needs. Swap the `print` for the Cypher write and you are consuming live
   instead of reading fixtures off disk. It works against the fixtures today:

   ```bash
   python3 bridge.py --replay ../fixtures/events-sample.jsonl   # seed the topic
   python3 tail.py                                              # read it back
   ```

2. **`laser_common.board_id(app, title)`** — derives the same UUIDv5 the Mac app
   does, so you can compute a board's id from its name with no lookup table and
   no coordination call. Cross-language test vectors are pinned in
   `capture-mac/Tests/AmbientMacTests/BoardIdentityTests.swift`.
