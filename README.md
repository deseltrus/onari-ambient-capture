# Ambient Context Capture — Memory Meets Motion (Aug 3)

A VoiceOS with the emphasis on the memory layer. Voice products execute
what you say; we execute from intention, formed by what you took in and
what historically matters. Full doc (four tabs: project, vision, stack,
demo) is linked in the group.

This repo starts from our openly declared base: event contract, fixtures,
graph schema, smoke tests, and a tested macOS window scaffold. Everything
here is setup material; the product gets built today.

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


## Already prepared before today (declared base)

- `event-contract.json` — four event types (switch, note, delta, result), two streams. Drafted, waiting for team confirmation
- `fixtures/events-sample.jsonl` — contract-conform sample session, so the memory lane builds from minute one
- `graph/schema.cypher` — board/note/switch/topic model + the consolidation query sketch
- `seed/seed-episodes.json` + `seed/demo-scenario.md` — synthetic history and the demo script (wander sequence, note texts, the unspoken-contact beat)
- `smoke/` — FalkorDB connection test + Graphiti driver check
- `capture-mac/` — Swift scaffold, builds green, window-contract tests pass (borderless, click-through, never steals focus)

Changelog today: repo renamed to onari-ambient-capture · scenario contact neutralized (name it on the day) · this section added.

## Checkpoints

13:00 integration 1 (real events replace fixtures; if Swift lags, fixtures
stay in) · 14:30 integration 2 + demo rehearsal · 15:00 freeze · 15:30
submit via Discord `/submit`.
