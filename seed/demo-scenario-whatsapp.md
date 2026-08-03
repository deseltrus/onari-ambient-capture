# Demo scenario — three documents → WhatsApp team update (prepared)

This is the scenario the current demo runs. It is **pre-loaded and played back
as if live** — nothing is recorded on stage. The intent frame lives at
`scenarios/three-docs-whatsapp.json` and the bridge loads it by default
(`ONARI_SCENARIO=three-docs-whatsapp`).

## The demo user

A builder on **TEAM O** at the 08/03 hackathon. Before the team's build call
they are reading three sponsor/background documents in Safari at the same time
and asking questions about each one in separate tabs. They never stop to write
a summary — that is the gap Onari fills.

## The live wander sequence (the script)

Three documents, three question tabs, all in Safari:

1. **RocketRide Cloud — Execution Pipelines (docs)** — read, no note. *Unspoken,
   highest topic score.* This is the one that matters.
2. **FalkorDB — Graph + Vector memory (docs)** — read, no note. Unspoken.
3. **Ambient Agents: capturing work context (arXiv)** — one note:
   "section four privacy model is close to what we said we'd do".
4. Tab: **ChatGPT** — "does RocketRide run pipelines async or block?"
5. Tab: **Claude** — "can FalkorDB do vector similarity for recall?"
6. Tab: **Perplexity** — "ambient capture privacy patterns".

Each question tab carries an `assistant_answer` delta — the answer the user got
but never relayed to the team.

## What consolidation must show

Not one board — the **synthesis across all three documents**, joined to three
open TEAM O threads:

- RocketRide docs → "you agreed to own the execution layer and report back
  whether RocketRide is the right thing to build on." (unanswered)
- FalkorDB docs → "do we keep a separate vector store, or can the graph hold
  embeddings?" (undecided in the channel)
- Ambient-agents paper → "our differentiator is on-device capture with a visible
  recording state — that promise needs a source before the demo."

The payoff is that all three answers exist in the user's tabs and none of them
reached the team.

## The dispatch (the execution pipeline)

The suggested action is **send a WhatsApp update to the group
"Hackathon 08/03 - TEAM O"** summarizing what the three documents settle.

Intent frame → policy check → approval → **RocketRide execution pipeline** →
WhatsApp message drafted from the three-document synthesis → sent to the group →
delivery confirmation streams back onto the dispatch surface.

For the demo the pipeline runs in **rehearsal mode**: every step is shown live
(assemble context → draft → policy check → open WhatsApp → send → confirm) but
the message is *not* actually delivered. The real executor
(`ONARI_EXECUTOR=whatsapp_mac`) sends through the WhatsApp desktop app and is
opt-in only, so a rehearsal never posts to a real group. See `lane3/README.md`.
