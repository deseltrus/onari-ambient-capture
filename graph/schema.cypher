// Board/note/switch model for the hackathon build (block D).
// Boards are surfaces (windows/sessions); switches carry the wander chain;
// notes bind raw thoughts to the exact moment; topics are the historical
// layer that assembly joins against (Graphiti episodes land there).

CREATE (:Board {id: 'demo', app: 'Codex', title: 'signal pipeline', feldklasse: 'A'});

// Switch chain: every focus change is an edge with time + dwell.
// (:Board)-[:SWITCHED_TO {t, dwell_ms, seq}]->(:Board)

// Notes: raw spoken fragments, bound to board + moment.
// (:Note {id, text_ref, t})-[:ON]->(:Board)

// Deltas: what changed on an unfocused board (agent answer arrived).
// (:Delta {kind: 'assistant_answer', t, ref})-[:AT]->(:Board)

// History join (the unspoken-becomes-relevant edge, via Graphiti episodes):
// (:Board|:Note)-[:RELATES_TO {score}]->(:Topic {name})

// Assembly query sketch — the session in relation to history:
// MATCH (b:Board)<-[:ON]-(n:Note)
// OPTIONAL MATCH (b)-[:RELATES_TO]->(t:Topic)<-[:RELATES_TO]-(other)
// RETURN b, collect(n), collect(DISTINCT t), collect(DISTINCT other)
// ORDER BY b.last_seen;
