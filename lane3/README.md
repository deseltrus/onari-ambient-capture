# Lane 3 — session intelligence and approved motion

The Mac app owns the visible session surface. This local bridge keeps service
credentials out of Swift and provides one stable API for Guild/model
coordination and RocketRide execution.

## The demo: three documents → WhatsApp team update

One command from the repository root:

```bash
./lane3/run_demo.sh
```

It starts the bridge on the `three-docs-whatsapp` scenario and launches the
menu-bar app pointed at it. Open the window with **⌘I**. Onari shows that you
read three documents (RocketRide docs, FalkorDB docs, an ambient-agents paper)
and answered three open TEAM O questions in your tabs — then offers to **post
the synthesis to the group "Hackathon 08/03 - TEAM O."** Approving runs the
RocketRide execution pipeline, whose steps play back live.

Scenario source: `scenarios/three-docs-whatsapp.json`. Presenter script:
`seed/demo-scenario-whatsapp.md`.

### Execution pipeline modes (`ONARI_EXECUTOR`)

| Value | What happens |
|---|---|
| `rehearsal` *(default)* | Pretend-live: every pipeline step is shown, the WhatsApp message is drafted, but **nothing is sent**. This is the demo mode. |
| `whatsapp_mac` | **Real** send through the WhatsApp desktop app via AppleScript UI scripting. Opt-in. Requires WhatsApp installed + logged in and Accessibility permission. |
| `rocketride` | Forward the approved intent to a RocketRide Cloud endpoint (`ROCKETRIDE_ENDPOINT` / `ROCKETRIDE_API_KEY`) and normalize its response. |

```bash
# Real send (will actually post to the group):
ONARI_EXECUTOR=whatsapp_mac ./lane3/run_demo.sh
```

### Run the pieces by hand

```bash
python3 lane3/bridge.py
ONARI_LANE3_URL=http://127.0.0.1:8765 swift run --package-path capture-mac
```

Without `ONARI_LANE3_URL`, the Mac app reads the scenario frame itself and uses
the same deterministic fixture response (including the WhatsApp pipeline). No
cloud account is required to rehearse the UI.

## Legacy scenario

The original LinkedIn outreach story still works: set
`ONARI_SCENARIO=` to a name that resolves to `intent-frame.json`, or point
`ONARI_INTENT_FRAME` at it directly.

## Connect an AI provider during Guild setup

The long-term coordinator is a Guild auto-managed agent. The bridge deliberately
keeps the Mac contract independent of the provider, so a direct provider can be
used while the custom Guild integration is being published:

```bash
ONARI_AI_PROVIDER=openai OPENAI_API_KEY=... python3 lane3/bridge.py
# or
ONARI_AI_PROVIDER=anthropic ANTHROPIC_API_KEY=... python3 lane3/bridge.py
```

Never commit API keys. Guild should ultimately own the model session and expose
the same `/consolidate`, `/chat`, and `/dispatch` semantics through its typed
agent/integration surface.

## RocketRide

RocketRide is never called by `/consolidate` or `/chat`. It is called only by
`/dispatch`, which rejects requests without `approved: true`.

```bash
ROCKETRIDE_ENDPOINT=https://... \
ROCKETRIDE_API_KEY=... \
python3 lane3/bridge.py
```

Until the team confirms the exact RocketRide Cloud endpoint and response
schema, leaving `ROCKETRIDE_ENDPOINT` unset produces a deterministic draft.

## Return path

For the demo, the Mac app saves the artifact into its append-only session
folder. The next integration step should write the normalized result into
FalkorDB as a `Result` node. This avoids depending on a cloud service reaching
the local-only LaserData topic.
