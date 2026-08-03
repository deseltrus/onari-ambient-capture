# Lane 1 → handoff

Status, how to run it, and the contract lane 3 codes against.

---

## What lane 1 delivers

Blocks A, B and C, proven on real hardware — not against fixtures.

| Block | What | State |
|---|---|---|
| A | Menu-bar shell, state dot, no standing overlay | done |
| B | Window/title tracking → `switch` events with `seq` + `dwell_ms_from` | done, verified live |
| C | Hotkey voice note → transcript bound to (app, window, time) | done, verified live |
| — | Publish to LaserData via `laser-bridge` | done |
| — | Live ingest into FalkorDB via lane 2's writer | done |
| G | Agent-session log reader (`delta` events) | **not built** — fixtures cover it |
| — | Pass-through dictation (types into the focused field) | **not built** — ~30 min with `CGEvent` |

Verified end to end: a spoken note produced
`🎙 note on [Terminal · …]: "What what have I been working on"`,
published as a contract-conforming `note` event.

## Run it

```bash
# 1. transport
cd ../laser-stack && ./scripts/up        # prints LASER_CONNECTION_STRING

# 2. capture  (--live publishes; without it the bridge only prints)
./lane1-run.sh --live

# 3. memory
python3 lane2/ingest_stream.py --link-every 3 --show-frame

# 4. the handoff artifact
python3 lane2/emit_frame.py --pretty     # -> intent-frame.json
```

Checks, when something is off:

```bash
python3 lane2/check_falkor.py            # DNS → TCP → plain → TLS, with timeouts
python3 laser-bridge/smoke_laser.py      # publish + read back one record
cd capture-mac && swift test             # 27 tests
```

## Architecture as built

```
AmbientMac (Swift, local)
    │  POST ndjson  →  127.0.0.1:8077
laser-bridge (Python, local)            ← no Swift SDK exists; this is why
    │  laser-sdk
LaserData / Iggy  (local, 127.0.0.1:8090)
    │  topic: ambient-events
lane2/ingest_stream.py (local)
    │  write_event()   ← lane 2's own code, unchanged
FalkorDB Cloud
    │  consolidate() + link_all()
intent-frame.json  ─────────────────────→  GUILD → ROCKETRIDE
                                                      │
                                            dispatch-results ← ⚠ see open questions
```

## The contract lane 3 codes against

`lane2/emit_frame.py` writes `intent-frame.json`:

```json
{
  "mission": "seed_signal_pipeline",
  "boards": [
    {
      "board_id": "uuid",
      "app": "Safari",
      "title": "LinkedIn - ML engineer profile",
      "last_seen": "2026-08-03T18:03:00Z",
      "notes":  [{"text": "...", "t": "...", "mode": "note|passthrough"}],
      "deltas": [{"kind": "assistant_answer", "preview": "..."}],
      "topics": [{"topic": "seed_talk_contact", "score": 0.5}],
      "unspoken": true
    }
  ],
  "history_joins": [
    {"topic": "seed_talk_contact", "episode": "...", "body": "...", "t": "..."}
  ]
}
```

**`unspoken: true` is the demo.** It marks a board that contributed with no note
attached — the LinkedIn profile that was seen and never typed. The RocketRide
prompt should lean on `history_joins` and the unspoken board, not on the notes;
citing the notes proves nothing, since the user typed those.

The return path is a `result` event on `dispatch-results`, per
`event-contract.json`. `lane2/ingest.py` already writes `Result` nodes for it.

## board_id is derived, not random

UUIDv5 over `app|normalized-title`, identical in Swift and Python:

```python
from laser_bridge.laser_common import board_id
board_id("Safari", "LinkedIn - profile")   # -> 1775bd62-4c99-536f-a59a-e89d4a259c44
```

Title normalization strips unread counts (`(3) LinkedIn`) and editor dirty
markers (`• file.swift`) so a notification does not fork a board. Cross-language
vectors are pinned in `capture-mac/Tests/AmbientMacTests/BoardIdentityTests.swift`.

## Failure modes, and what they cost

| If this breaks | What happens | Cost to the demo |
|---|---|---|
| LaserData down | Swift spools every event to `~/Library/Application Support/Onari/ambient-events.jsonl`; `bridge.py --replay <file>` catches up | none, if replayed |
| Swift capture down | `lane2/run_demo.py` runs the full fixture sequence | none — fixtures are the rehearsed path |
| FalkorDB unreachable | `check_falkor.py` says which layer; 10s timeouts, never hangs | blocks lane 2 and 3 |
| Mic fails on stage | menu → "Inject scripted note" fires the wander script's texts | none |
| Hotkey taken | `ONARI_HOTKEY=ctrl+opt+cmd+j`, or click the menu item | none |

## Open questions for the team

1. **The return path is the one hop still broken.** LaserData is local
   (`127.0.0.1`), so cloud RocketRide and Guild cannot publish `result` events
   onto `dispatch-results`. Either a LaserData Cloud account for that one topic,
   or the dispatch surface reads `Result` nodes out of FalkorDB — `ingest.py`
   already writes them, so that path is nearly free. **Decide before 14:30.**

2. **FalkorDB Cloud is plain RESP, not TLS.** `FALKOR_SSL=false`. Connecting
   with TLS to that port hangs on the handshake rather than erroring, which
   costs ten confusing minutes if someone assumes otherwise.

3. **Stream/topic mapping.** The contract says "streams"; Laser's model is
   stream → topic. Both contract streams are topics inside one Laser stream
   named `onari`. Resolved in `laser-bridge/laser_common.py`, nowhere else.

4. **`run_demo.py` wipes the graph, and the graph is shared.** Its first act is
   `graph.delete()`. On one shared FalkorDB Cloud instance that means any
   teammate rehearsing the fixture demo silently destroys everyone else's data
   mid-integration. Two options: give each lane its own graph via `ONARI_GRAPH`
   (done for lane 1 — `onari_nikhil`), and reserve `onari` for the rehearsed
   demo run only; or add a `--keep` flag to `run_demo.py`. **Agree this before
   the 14:30 rehearsal**, or the rehearsal itself will wipe the live data.

5. **Rotate the FalkorDB password after the event.** It is in a shared `.env`
   and has been pasted in chat.
