# Onari — Ambient Context Capture

**Memory Meets Motion · Aug 3 · Frontier Tower SF**

A VoiceOS with the emphasis on the **memory layer**. Voice products execute
what you *say*. Onari executes from **intention** — formed by what you took in,
what you saw, and what historically matters to you — and closes the loop by
dispatching real work and streaming the result back onto the same surface.

Onari watches along while you work, captures raw thoughts the moment they appear
(a hotkey, no formulating), binds each to its exact window and moment, and lets
context accumulate. When you step back, it brings the whole session together
against long-term memory — **including what you never wrote down** — proposes a
move, and on your approval sends a real workflow off to execute.

---

## The loop, in six lines

1. Work normally; a hotkey captures raw voice notes, transcribed locally, bound to window + moment.
2. Switches, notes and agent answers stream as events in the background — no overlay while working.
3. Events aggregate into a **memory graph**, joined with seeded history.
4. Step back: the **session-intelligence view** shows the session as one mission, including what you never noted.
5. Correct by voice, approve → a **real workflow dispatches** in the background.
6. The result streams back onto the same surface. **Loop closed.**

> The bet: raw, unpolished expression is the highest-bandwidth signal a person
> has. Structure is a tax today's tools demand. Whoever builds the clearest
> translation from inner expression to outer action wins — and that needs both
> halves in one system: **memory** that holds what you meant, and **motion**
> that acts on it.

---

## System architecture

Everything below is built and running. The four sponsor systems are each
**load-bearing** — remove any one and the loop breaks.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  macOS menu-bar app        Swift · capture-mac/                            │
│  • active-window switch chain (NSWorkspace + Accessibility)               │
│  • hotkey voice notes, transcribed locally (Parakeet / on-device speech)  │
│  • pass-through dictation + agent-answer deltas                           │
│  • Session-Intelligence window: insight · chat · approval · result        │
└───────────────┬──────────────────────────────────────────────────────────┘
                │ NDJSON on loopback
                ▼
        laser-bridge/  ───publish──►  ◆ LASERDATA  ambient-events stream
        (thin Swift→SDK publisher)          │   signal transport, both directions
                                            ▼
                                    lane2/  stream consumer
                                            │   writes boards · notes · switch edges · deltas
                                            ▼
                                    ◆ FALKORDB   the memory graph
                                    boards + notes + history, multi-hop queries
                                            │   consolidate_session → emit_frame
                                            ▼
                                    intent-frame.json   (the context edge)
                                            │
                                            ▼
        ◆ GUILD  coordinator   ◄────  lane3/bridge.py   local adapter boundary
        consolidation agent +          /consolidate   /chat   /dispatch
        policy + human approval             │   approved intent (policy-gated)
        + scoped credentials                ▼
                                    lane3/executors.py   execution pipeline
                                            ▼
                                    ◆ ROCKETRIDE   context → artifact → action
                                    server-side pipeline, live trace URL
                                            │   result event
                                            ▼
                                    back via LASERDATA / FALKORDB Result node
                                            ▼
                                    Mac Session-Intelligence window (loop closed)
```

### The sponsor stack — load-bearing use of all four

| Tool | Role | Concretely in this repo |
|---|---|---|
| **LaserData** | Signal transport, both directions | Every capture event is published to the `ambient-events` stream by `laser-bridge/`; the result streams back on `dispatch-results`. `laser-bridge/watch_results.py` subscribes to the return path. |
| **FalkorDB** | The state everything reads and writes | `lane2/ingest*.py` writes boards / notes / switch edges / deltas; `lane2/consolidate_session.py` runs multi-hop queries joining the session to seeded history; results write back as `Result` nodes. |
| **Guild.ai** | Coordinator | `lane3/bridge.py` is the local Guild-adapter boundary: it owns consolidation, session chat, the allow-listed action policy, human approval, and scoped credentials — and calls RocketRide as an integrated endpoint. Swift never holds a credential. |
| **RocketRide** | Executor | `lane3/executors.py` sends the approved intent frame to a RocketRide pipeline that produces the artifact and returns a live trace URL. `context → reason → artifact → send`. |

### The end-to-end dispatch

```
Capture (switches · Parakeet notes · dictation · deltas)
      │  publish
      ▼  LaserData ─ ambient-events
Consumer  →  FalkorDB  (board graph + seeded history)
      │  multi-hop query
      ▼  Guild  ─ consolidation → intent frame → policy → approval
      │  integrated endpoint call
      ▼  RocketRide ─ pipeline executes, live trace
      │  result event
      ▼  back through LaserData / FalkorDB Result node
      ▼  the same Session-Intelligence surface  ·  memory gains the new facts
```

---

## The demo: three documents → WhatsApp team update

The prepared, pre-warmed scenario (`scenarios/three-docs-whatsapp.json`, presenter
script `seed/demo-scenario-whatsapp.md`):

You are on **TEAM O** at the hackathon. Before the build call you read three
documents in Safari at once — the **RocketRide Cloud docs**, the **FalkorDB
docs**, and an **ambient-agents paper** — and ask questions about each in
separate tabs. You never stop to summarize. Onari does.

Step back and open the window (**⌘I**). Onari shows:

- **What it noticed** — the synthesis across all three documents, in big type.
- **Why it surfaced** — two of the documents are *unspoken* (read, never noted),
  each joined to an open TEAM O thread you agreed to answer and never did.
- **A suggested action**, reasoned out after the session and revealed with
  animation: **Send an update to the WhatsApp group "Hackathon 08/03 - TEAM O."**

Accept it by voice/hotkey (**⌃⌥⌘↩**) or click. The **RocketRide execution
pipeline plays back live** (assemble context → draft → policy check → open
WhatsApp → send → confirm) and the message lands in a WhatsApp bubble with a
RocketRide trace link.

**The wow beat:** every line of the message cites something you *saw but never
typed*. That view exists nowhere else — not in any chat.

### Execution modes (`ONARI_EXECUTOR`)

| Value | What happens |
|---|---|
| `rehearsal` *(default)* | Pretend-live: every pipeline step is shown, the message is drafted, **nothing is sent**. The demo mode — a rehearsal never posts to a real group. |
| `whatsapp_mac` | **Real** send through the WhatsApp desktop app (AppleScript UI scripting). Opt-in. |
| `rocketride` | Forward the approved intent to a RocketRide Cloud endpoint and normalize its response. |

---

## Run it

```bash
cp .env.example .env          # your own keys; .env is gitignored, never commit it
./lane3/run_demo.sh           # starts the bridge (rehearsal) + launches the app
```

Then look for **◉ onari** in the menu bar and press **⌘I** to open the
Session-Intelligence window. The app also runs without the bridge — it reads the
scenario frame directly and uses the same deterministic fixture pipeline, so the
UI always has data.

Real send (actually posts to the group):

```bash
ONARI_EXECUTOR=whatsapp_mac ./lane3/run_demo.sh
```

Build / run the pieces individually:

```bash
swift build --package-path capture-mac        # menu-bar app
python3 lane3/bridge.py                        # coordination + execution bridge
ONARI_LANE3_URL=http://127.0.0.1:8765 swift run --package-path capture-mac
```

### Upstream (live capture → memory), optional

```bash
pip3 install falkordb python-dotenv laser-sdk
python3 lane2/check_falkor.py       # DNS → TCP → plain → TLS, with timeouts
python3 lane2/run_session.py        # seed + ingest fixtures + link (never wipes)
python3 lane2/emit_frame.py --pretty  # → intent-frame.json
```

> **`FALKOR_SSL=false`** for the shared instance — TLS *hangs on the handshake*
> rather than erroring. Use `lane2/run_session.py`, **never** `lane2/run_demo.py`
> (it calls `graph.delete()` and wipes the shared graph).

---

## Repository layout

| Path | What |
|---|---|
| `capture-mac/` | Swift menu-bar app: capture (Lane 1) + the Session-Intelligence window (Lane 3 UI) |
| `laser-bridge/` | Thin publisher/consumer bridge to **LaserData** (loopback NDJSON → SDK) |
| `lane2/` | **FalkorDB** memory: stream consumer, graph writer, history seed, consolidation queries, `emit_frame` |
| `lane3/` | **Guild** adapter (`bridge.py`) + **RocketRide** execution pipeline (`executors.py`) + `run_demo.sh` |
| `scenarios/` | Prepared intent frames (default: `three-docs-whatsapp.json`) |
| `seed/` | Synthetic history + presenter scripts (`demo-scenario-whatsapp.md`) |
| `event-contract.json` | The four event types (switch · note · delta · result), v1, both streams |
| `intent-frame.json` | Legacy scenario frame; the context edge shape |

### Lanes (how it was built, three engineers, never blocking)

| Lane | Needs Mac? | Owns |
|---|---|---|
| 1 — capture | yes | `capture-mac/`: menu-bar shell → switch events → Parakeet notes → publish to LaserData |
| 2 — memory | no | LaserData consumer → FalkorDB graph → seeded history → consolidation queries |
| 3 — coordination + motion | no | Guild agents (consolidation + policy + approval) → RocketRide pipeline → result subscription |

The **event contract and fixtures decouple all three lanes** — any lane that
stalls is bypassed, the demo path always has data.

---

## The frame: simultaneous chess

Kasparov played thirty boards at once. Every move aims to be **one step ahead on
that board**, while all boards hold their state. Two things carry it: per-board
state that persists while he stands elsewhere, and a target function that never
changes.

- Kasparov's target is winning the game. **Onari's target is the user's win.**
- The boards are your surfaces: windows, sessions, pages. Walking away freezes
  nothing; new behavior **attaches to previous and historical states**.
- So this is not "notes plus task execution." It is capturing the **signal level
  between surfaces**, persisting those surfaces, and forming **intent mapping**.
- The teacher is the user: **approvals and corrections are the learning signal.**

### Value hierarchy (highest first)

1. **Understanding over time** — aggregated signal against history becomes prediction of the next action. Everything serves this.
2. **Signal between surfaces** — the switch, the dwell, the unspoken glance; passively captured, in context, with the moment's stamp.
3. **Persistent states** — re-entry continues instead of restarting.
4. **Governed motion** — understanding becomes action through approval, policy, correction; the result feeds back.

### Why not just write into Claude?

- **We are the instance above.** A chat holds one thread; Onari holds your movement across everything, including what you never sent.
- **Friction.** Formulating is a tax. Onari captures at the moment of thought; formulation happens at dispatch time, grounded in memory.
- **The unspoken.** A chat only knows what you typed. Onari surfaces what you never noted, because it was seen in context.
- **Continuity.** Chats forget; states persist and attach to history. The tenth session knows the first nine.

---

## The context edge

The dispatched package is the **intent frame** — never a transcript dump:
mission, boards touched, notes in order, the history joins that matter. Query
results only; the receiving model's context window is bounded and stuffing it
lowers quality. Context caching keeps repeated structure cheap and pre-warms the
demo. The result feeds back into the same view and into memory, so the next
package starts sharper.

> The closing line to the room: the goal of every move is to be one step ahead.
> Kasparov played it on thirty boards for the win of the game. We build it across
> all your surfaces, for the win of the user.
