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

## On-stage flow (what the presenter does)

1. Menu bar shows **◉ onari** — capture is live. Open the window with **⌘I**.
2. Top-left, the green **Onari · live** dot pulses the whole time — the honesty
   indicator that Onari is running.
3. The window does a short **staged "thinking"** pass (Reviewing this session →
   Reconnecting to memory → Finding what you never wrote down → Assembling), so
   nothing snaps in instantly.
4. **What Onari noticed** appears in large type, with the three documents and the
   open TEAM O thread as evidence. Events are *not* on this surface — they live
   behind the **Activity** button (top-right).
5. *(Optional)* Tap the **mic** and ask a question by voice — on-device speech
   fills the chat and Onari answers in the same session.
6. After a beat — "Onari is deciding what would help…" — the **suggested action
   animates in**: *Send update to Hackathon 08/03 - TEAM O.*
7. **Accept it by voice/hotkey (⌃⌥⌘↩)** or click it. The RocketRide execution
   pipeline plays back live and the WhatsApp message lands in a green bubble,
   "Sent to Hackathon 08/03 - TEAM O", with a RocketRide trace link.

## The dispatch (the execution pipeline)

The message is a **hardcoded, polished team update** (`hardcoded_message` in the
scenario) so the send is deterministic on stage: it summarizes reading the
RocketRide Cloud docs and the FalkorDB docs on Safari and what they mean for the
build.

Intent frame → policy check → approval (hotkey **⌃⌥⌘↩** or click) → **RocketRide
execution pipeline** → WhatsApp message → group → delivery confirmation.

For the demo the pipeline runs in **rehearsal mode**: every step is shown live
(assemble context → draft → policy check → open WhatsApp → send → confirm) but
the message is *not* actually delivered. The real executor
(`ONARI_EXECUTOR=whatsapp_mac`) sends through the WhatsApp desktop app and is
opt-in only, so a rehearsal never posts to a real group. See `lane3/README.md`.
