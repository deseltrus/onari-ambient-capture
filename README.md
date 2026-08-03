# Ambient Context Capture — Memory Meets Motion (Aug 3)

A VoiceOS with the emphasis on the memory layer. Voice products execute
what you say; we execute from intention, formed by what you took in and
what historically matters. Full doc (four tabs: project, vision, stack,
demo) is linked in the group.

This repo starts from our openly declared base: event contract, fixtures,
graph schema, smoke tests, and a tested macOS window scaffold. Everything
here is setup material; the product gets built today.

## North star: the moment we build toward

We are not building note-taking. We are building the proof that a system
which watched you work can act on your behalf better than anything you
could have typed.

The three minutes at the end: the user floats through his windows,
speaking half-thoughts, touching one page he never comments on. He steps
back. The screen shows his session as one mission, with a suggested action
that includes the thing he never said, and its reason. He approves with a
word; a real workflow fires; the result comes back.

If the room goes quiet at "the thing he never said", we won. Measure every
cut you make today against that one moment. Everything else is decoration.

## The layers (this README is the single source, no second doc needed)

### 1. What this is

A VoiceOS with the emphasis on the memory layer. Voice products execute
what you say. We execute from **intention**: formed by what you took in,
what you saw, and what historically matters to you.

The bet: raw, unpolished expression is the highest-bandwidth signal a
person has. Structure is a tax today's tools demand. Whoever builds the
clearest translation from inner expression to outer action wins, and that
needs both halves in one system: memory that holds what you meant, and
motion that acts on it.

### 2. The frame: simultaneous chess

Kasparov played thirty boards at once. Every move aims to be **one step
ahead on that board**, while all boards hold their state. Two things carry
it: per-board state that persists while he stands elsewhere, and a target
function that never changes.

- Kasparov's target is winning the game. **Our target is the user's win.**
- The boards are your surfaces: windows, sessions, pages. Walking away
  freezes nothing; new behavior **attaches to previous and historical
  states**.
- So this is not "notes plus task execution". It is capturing the **signal
  level between surfaces**, persisting those signal surfaces, and forming
  **intent mapping** from them.
- The teacher is the user: **approvals and corrections are the learning
  signal**. Early supervision is how the system earns autonomy.

### 3. Value hierarchy (highest first)

1. **Understanding over time** — aggregated signal against history becomes
   prediction of the next action level. Everything serves this.
2. **Signal between surfaces** — the switch, the dwell, the unspoken
   glance; passively captured, in context, with the moment's stamp.
3. **Persistent states** — re-entry continues instead of restarting.
4. **Governed motion** — understanding becomes action through approval,
   policy, correction; the result feeds back.

### 4. Cases (agent orchestration is one case, not the product)

| Case | What gets grasped | Demonstrable moment |
|---|---|---|
| Working with agents | session windows, arriving outputs, thoughts between the lines | an answer lands on its board while you're elsewhere |
| Reading | which text, which position in time, raw reactions | half-thoughts return joined to related history |
| Watching / listening | title + moment, snips at the timestamp | "that point at minute 12" exists as a bound note |
| Browsing people | profiles seen, dwell, what you didn't write down | the unspoken profile resurfaces as relevant |

### 5. Input surfaces

| Surface | Access | Depth |
|---|---|---|
| Active window | NSWorkspace + Accessibility: app, title, focus | always on: the switch chain |
| Voice | hotkey mic capture, bound to (app, window, time) | always on: the note channel |
| Agent sessions | Claude Code / Codex session files, file watchers; only assistant-output events count as deltas | deep, zero integration |
| Web / foreign apps | metadata always; content only per explicit arming | shallow in v1, by design |

**Capture UI: none.** Mouse + focus is the display. Only pixels: a
recording indicator at the cursor while the hotkey is held, and a state dot
in the menu bar. The consolidation view is a normal window, opened
deliberately.

**Two input modes, one awareness:** note hotkey (records a raw thought,
types nowhere) and pass-through dictation (speech becomes text in the
focused field). Both bind to window + moment; pass-through also records
which field received the input. **Transcription: Parakeet, local.**

### 6. What executes, what aggregates

- Every captured signal **aggregates into memory, always**.
- A signal that implies an action (person, event, deadline, ask) becomes an
  **action candidate** in the consolidation view.
- Candidates pass a **policy check** (allow-listed action types) and
  **user approval or correction**, then dispatch.
- Today dispatch produces **artifacts** (outreach draft, brief, package).
  Screen-level action, logins, standing background chains: the named later
  stage, behind the same gate.

### 7. Why not just write into Claude?

1. **We are the instance above.** A chat holds one thread; we hold your
   movement across everything, including what you never sent.
2. **Friction.** Formulating is a tax. We capture at the moment of thought;
   formulation happens at dispatch time, grounded in memory.
3. **The unspoken.** A chat only knows what you typed.
4. **Continuity.** Chats forget; states persist and attach to history.
5. **And when you do want to talk to an agent directly,** pass-through
   dictation gives you exactly that, with the system still aware.

### 8. The context edge

The dispatched package is the **intent frame**, never a transcript dump:
mission, boards touched, notes in order, the history joins that matter.
Query results only. Context caching keeps repeated structure cheap. The
result feeds back so the next frame starts sharper.

## T0 — first 30 minutes

1. Clone. Copy `.env.example` to `.env`, fill in your own keys from last
   night's setup. `.env` is gitignored, never commit it, never post keys
   in the chat.
2. Confirm `event-contract.json` together (pre-drafted: four event types,
   stream in `ambient-events`, stream out `dispatch-results`). After
   confirmation it only changes by team agreement — every lane codes
   against it.
3. Smoke tests:
   - FalkorDB: `pip install falkordb && python3 smoke/falkordb-smoke.py`
     (local fallback: `docker run -p 6379:6379 -p 3000:3000 -it --rm falkordb/falkordb:latest`)
   - LaserData: publish + read one record per their Quickstart (docs.laserdata.com)
   - RocketRide: hello pipeline per docs.rocketride.org/quickstart
   - Guild: quickstart agent per docs.guild.ai

## Lanes

| Lane | Needs Mac? | Starts with |
|---|---|---|
| 1 — capture (Swift) | yes | `capture-mac/` scaffold: menu-bar shell → switch events → Parakeet notes → publish to LaserData |
| 2 — memory | no | consumer against `fixtures/events-sample.jsonl` → FalkorDB writes per `graph/schema.cypher` → seed history from `seed/seed-episodes.json` |
| 3 — coordination + motion | no | Guild agents (consolidation + policy, agent-assisted via CLI) → RocketRide pipeline `context-to-artifact` → result subscription |

Lanes 2 and 3 never wait on lane 1: fixtures carry them until integration.



## How context binds (read this first, it is the core)

Nothing floats free. Every captured thing carries its surface and its moment:

1. **Note → surface.** A note event carries `board_id + app + title + t`
   (see `event-contract.json`). The graph writer stores it as
   `(:Note)-[:ON]->(:Board)` with the timestamp. A note is never loose
   text; it is text AT a surface AT a moment.
2. **Surface → session.** The switch chain
   `(:Board)-[:SWITCHED_TO {t, seq}]->(:Board)` gives every board its
   position in the wander order. That is how "what I saw in that moment"
   stays in context.
3. **Deltas** (an agent answer arriving) bind the same way:
   `(:Delta)-[:AT]->(:Board)`.
4. **History join.** Boards and notes link to seeded/accumulated topics:
   `(:Note|:Board)-[:RELATES_TO]->(:Topic)`. This is where the never-noted
   surface becomes relevant.
5. **Consolidation = ONE model call** (the Guild consolidation agent).
   INPUT: graph query results only — boards in wander order with their
   notes, deltas, and topic joins. Never raw transcripts.
   OUTPUT: an intent frame:
   ```json
   { "mission": "one sentence",
     "boards": ["wander order"],
     "candidates": [ { "action": "...", "why": {
         "source": "note or glance on board X at t",
         "history": "topic thread it joins" } } ] }
   ```
   A candidate without a `why` (source + history) is invalid. This frame
   is what gets approved and dispatched; the result event closes the loop.

## Already prepared before today (declared base)

- `event-contract.json` — four event types (switch, note, delta, result), two streams. Drafted, waiting for team confirmation
- `fixtures/events-sample.jsonl` — contract-conform sample session, so the memory lane builds from minute one
- `graph/schema.cypher` — board/note/switch/topic model + the consolidation query sketch
- `seed/seed-episodes.json` + `seed/demo-scenario.md` — synthetic history and the demo script (wander sequence, note texts, the unspoken-contact beat)
- `smoke/` — FalkorDB connection test + Graphiti driver check
- `capture-mac/` — Swift scaffold, builds green, window-contract tests pass (borderless, click-through, never steals focus)

Changelog today: repo renamed to onari-ambient-capture · scenario contact neutralized (name it on the day) · this section added.


## Interaction states

| State | Trigger | On screen |
|---|---|---|
| Idle | capture off | dim state dot only |
| Capturing | capture on | active dot; events flow; nothing else |
| Note recording | hotkey held | indicator follows cursor; release → transcribed, bound, gone |
| Pass-through | second hotkey | same indicator; text lands in the focused field |
| Paused | global pause | dot shows paused; zero events |
| Consolidation | user opens view | normal window: mission + action candidates |
| Dispatch running | approval given | workflow trace visible |
| Result | result event | lands on dispatch surface; graph updated |

## The consolidation screen

| Zone | Content | Source |
|---|---|---|
| Top line | the session mission, one sentence | consolidation agent over session graph |
| Left rail | boards in wander order, dwell + note count | switch chain (FalkorDB) |
| Center | action candidates, each with WHY: source note/glance + joined history thread | multi-hop queries + seeded history |
| Center, marked | unspoken entries (seen, never noted), visually distinct | boards without notes |
| Bottom bar | approve · correct by voice · dismiss | Guild approval |
| Side panel | dispatch trace, then result | RocketRide trace + result events |

Contract: extremely short, clear, detail-rich. Every candidate names its why.

## Goal outcomes today (acceptance at 15:00)

1. Switch chain + notes land in FalkorDB from real capture events (fixtures as fallback)
2. Note hotkey → local Parakeet transcript, bound to window + moment, visible in graph
3. Consolidation view renders the mission from graph queries, incl. one never-noted board
4. One approved dispatch runs a real RocketRide workflow; result streams back
5. The 3-minute demo runs end to end, pre-warmed, per `seed/demo-scenario.md`

Stretch: pass-through dictation live · agent-session delta on its board.

## Checkpoints

13:00 integration 1 (real events replace fixtures; if Swift lags, fixtures
stay in) · 14:30 integration 2 + demo rehearsal · 15:00 freeze · 15:30
submit via Discord `/submit`.
