# Intent frame — lane 2 → lane 3 contract

`consolidate.py` emits this JSON. Guild's consolidation agent consumes it
(or re-runs the same Cypher itself — the graph is the source of truth).

```json
{
  "mission": "signal-pipeline",
  "boards": [
    {
      "board_id": "uuid",
      "app": "Safari",
      "title": "LinkedIn - ML engineer profile",
      "last_seen": "2026-08-03T18:03:00Z",
      "notes": [{"text": "...", "t": "...", "mode": "note|passthrough"}],
      "deltas": [{"kind": "assistant_answer", "preview": "..."}],
      "topics": [{"topic": "talk-contact", "score": 0.5}],
      "unspoken": true
    }
  ],
  "history_joins": [
    {
      "topic": "talk-contact",
      "episode": "seed_talk_contact",
      "body": "Met an ML engineer at a talk two weeks ago...",
      "t": "2026-07-21T19:00:00Z"
    }
  ]
}
```

Semantics:
- `mission` — dominant topic across the session (RELATES_TO score sum).
- `boards` — wander order (by last_seen). `unspoken: true` = seen in
  context, zero notes taken. The demo's wow beat; do not drop these.
- `topics` — why each board/note is in the mission (the relevance
  reasoning judges want to see).
- `history_joins` — seeded/accumulated episodes reachable via a shared
  Topic from anything in this session. This is "it still knows from
  two weeks ago".

Graph access for lane 3 (read-only is fine):
- Boards + notes: `MATCH (n:Note)-[:ON]->(b:Board) RETURN b, n`
- History: `MATCH (x)-[:RELATES_TO]->(t:Topic)<-[:RELATES_TO]-(e:Episode) RETURN t, e`
- Connection: same .env vars as smoke test (FALKOR_HOST/PORT/USER/PASSWORD).
