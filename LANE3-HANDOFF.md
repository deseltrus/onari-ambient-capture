# Lane 3 handoff — Guild + RocketRide

**For: Chao.** Blocks E and F. Everything upstream of you is built and running;
this is what it produces, what you produce, and what is still undecided.

---

## Where you plug in

```
Swift capture ──▶ laser-bridge ──▶ LaserData ──▶ FalkorDB ──▶ intent-frame.json
     (done)          (done)         (done)        (done)             │
                                                                     ▼
                                                        ┌────────────────────────┐
                                                        │  E: Guild              │
                                                        │  consolidation agent   │
                                                        │  + policy agent        │
                                                        │  + human approval      │
                                                        └───────────┬────────────┘
                                                                    ▼
                                                        ┌────────────────────────┐
                                                        │  F: RocketRide         │
                                                        │  context-to-artifact   │
                                                        └───────────┬────────────┘
                                                                    ▼
                                                     result event ──▶ dispatch surface
```

**You do not need to wait for anything.** `intent-frame.json` is committed at
the repo root with real data. Build against that file today.

## Your input: `intent-frame.json`

Regenerate any time with `python3 lane2/emit_frame.py --pretty`.

```json
{
  "session":  {"id": "s0002-…", "ordinal": 2, "started_at": "…", "label": "…"},
  "mission":  "signal-pipeline",
  "boards": [
    {
      "board_id": "uuid",
      "app": "Safari",
      "title": "LinkedIn - ML engineer profile",
      "last_seen": "2026-08-03T18:03:00Z",
      "notes":  [{"text": "...", "t": "...", "mode": "note|passthrough"}],
      "deltas": [{"kind": "assistant_answer", "preview": "..."}],
      "topics": [{"topic": "talk-contact", "score": 0.50}],
      "unspoken": true
    }
  ],
  "history_joins": [
    {"topic": "talk-contact",
     "episode": "seed_talk_contact",
     "body": "Met an ML engineer at a talk two weeks ago, working on context
              systems. Wanted to follow up about the signal pipeline but never did.",
     "t": "2026-07-21T19:00:00Z"}
  ],
  "prior_sessions": [
    {"session_id": "s0001-…", "weight": 0.01, "topics": [...], "notes": [...]}
  ]
}
```

`session` and `prior_sessions` were added later and are additive — if you ignore
them nothing breaks. `mission`, `boards`, `history_joins` are the contract.

### The one thing that decides whether the demo lands

**Build the prompt around `unspoken: true` boards and `history_joins`. Not the
notes.**

An outreach draft that quotes the user's own typed notes proves nothing — they
typed them. The entire payoff is citing the LinkedIn profile they *looked at and
never wrote down*, connected to a seeded memory from two weeks ago. In the
current frame that board has **no notes and the highest topic score (0.50)**.
That is the signal. If the generated artifact does not visibly draw on it, we
have built a very elaborate note-taking app.

## Your output: a `result` event

Per `event-contract.json`, on the `dispatch-results` topic:

```json
{"type": "result", "v": 1, "t": "ISO-8601",
 "dispatch_id": "uuid", "status": "running|done|failed",
 "artifact": "the produced draft, when done"}
```

`lane2/ingest.py` already writes `Result` nodes for these, so the graph side is
done. Watch the topic with `python3 laser-bridge/watch_results.py`, and
`--emit-test` publishes a synthetic result so you can prove the path before your
pipeline exists.

## Running the upstream

```bash
cp .env.example .env          # fill in — see credentials below
pip3 install falkordb python-dotenv laser-sdk

python3 lane2/check_falkor.py            # DNS → TCP → plain → TLS, with timeouts
python3 lane2/run_session.py             # seed + ingest fixtures + link (never wipes)
python3 lane2/emit_frame.py --pretty     # -> intent-frame.json
```

That is enough for your whole lane. The Swift capture app only matters if you
want live events instead of fixtures; `LANE1.md` and `HANDOFF.md` cover it.

## Credentials

**Create your own** — both are free and per-person, and separate keys mean one
revocation does not take out the team:

- RocketRide Cloud — cloud.rocketride.ai, plus the promo code in the hackathon Discord
- Guild — guild.ai workspace + API access

**Shared, sent to you privately — never in the repo or a group chat:**

- `FALKOR_HOST` / `PORT` / `USER` / `PASSWORD` — Niv's cloud instance. **`FALKOR_SSL=false`**;
  it speaks plain RESP with auth, and connecting with TLS *hangs on the
  handshake* rather than erroring, which costs ten confusing minutes.
- `LASER_CONNECTION_STRING` — only if you want the live stream. Local Laser
  Stack is `iggy:laser@127.0.0.1:8090` on your own machine.

`.env` is gitignored. Keep it that way. Rotate the FalkorDB password after the event.

## Gotchas that already cost us time

| Thing | What happens |
|---|---|
| `run_demo.py` opens with `graph.delete()` | It **wipes the shared graph**. Use `run_session.py` instead — same steps, accumulates. Keep `run_demo.py` for the one clean run before the live demo. |
| `FALKOR_SSL=true` on this instance | Hangs forever, no error. It is `false`. |
| Re-running `ingest.py` | `ingest.py` uses `CREATE`, not `MERGE`, so notes double. `run_session.py` dedupes automatically. |
| No Swift SDK for LaserData | Capture posts NDJSON to `laser-bridge` on loopback, which publishes with the real SDK. Not a workaround you need to care about — just do not go looking for a Swift client. |

## Open decisions — the first one is yours to force

1. **The return path does not work yet.** LaserData runs locally on
   `127.0.0.1`, so cloud RocketRide and Guild **cannot publish** `result` events
   onto `dispatch-results`. Two options: a LaserData Cloud free-tier account
   used only for that topic, or the dispatch surface reads `Result` nodes out of
   FalkorDB instead — `ingest.py` already writes them, so that path is nearly
   free. **This blocks the demo's closing beat. Decide it first.**

2. **Guild reaching FalkorDB is fine** — the graph is cloud-hosted, so a
   cloud agent can query it directly. That was an open risk and it is closed.

3. **Load-bearing use of all four sponsor tools is judged**, and RocketRide has
   its own $1000 prize for building on RocketRide Cloud. Block F is where that
   is won or lost — traces visible on screen during the run is an explicit demo
   requirement.

## Where things live

| Path | What |
|---|---|
| `intent-frame.json` | **your input**, real data, regenerate with `emit_frame.py` |
| `lane2/INTENT_FRAME.md` | Niv's notes on the frame |
| `lane2/consolidate_session.py` | builds the frame (session-scoped) |
| `laser-bridge/watch_results.py` | **your output path** — subscribe `dispatch-results` |
| `event-contract.json` | the four event types, v1 |
| `HANDOFF.md` | lane 1 status, architecture, failure modes |
| `seed/demo-scenario.md` | the demo script the artifact has to serve |
