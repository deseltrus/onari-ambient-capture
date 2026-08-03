# Lane 3 — session intelligence and approved motion

The Mac app owns the visible session surface. This local bridge keeps service
credentials out of Swift and provides one stable API for Guild/model
coordination and RocketRide execution.

## Run the demo path

From the repository root:

```bash
python3 lane3/bridge.py
ONARI_LANE3_URL=http://127.0.0.1:8765 swift run --package-path capture-mac
```

Without `ONARI_LANE3_URL`, the Mac app reads `intent-frame.json` itself and
uses the same deterministic fixture response. No cloud account is required to
rehearse the UI.

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
