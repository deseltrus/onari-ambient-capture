#!/usr/bin/env bash
# One command for the three-documents -> WhatsApp demo.
#
#   ./lane3/run_demo.sh              rehearsal (default) — pretend-live, nothing sent
#   ONARI_EXECUTOR=whatsapp_mac ./lane3/run_demo.sh   real send via WhatsApp desktop
#
# Starts the local bridge on the WhatsApp scenario, waits for it to be healthy,
# then launches the menu-bar app pointed at it. Ctrl-C tears both down.
set -euo pipefail

cd "$(dirname "$0")/.."   # repo root

PORT="${ONARI_LANE3_PORT:-8765}"
export ONARI_LANE3_PORT="$PORT"
export ONARI_LANE3_URL="http://127.0.0.1:${PORT}"
export ONARI_SCENARIO="${ONARI_SCENARIO:-three-docs-whatsapp}"
export ONARI_EXECUTOR="${ONARI_EXECUTOR:-rehearsal}"
export ONARI_AI_PROVIDER="${ONARI_AI_PROVIDER:-fixture}"

echo "onari demo · scenario=${ONARI_SCENARIO} · executor=${ONARI_EXECUTOR} · provider=${ONARI_AI_PROVIDER}"
if [ "$ONARI_EXECUTOR" = "whatsapp_mac" ]; then
  echo "⚠️  whatsapp_mac executor is REAL — approving the action will post to the group."
else
  echo "rehearsal mode: the send pipeline is played back live but nothing is delivered."
fi

# Free the port if a previous run left the bridge behind.
lsof -ti tcp:"$PORT" | xargs kill 2>/dev/null || true

python3 lane3/bridge.py &
BRIDGE_PID=$!
trap 'kill "$BRIDGE_PID" 2>/dev/null || true' EXIT INT TERM

# Wait for health before launching the UI.
for _ in $(seq 1 30); do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then break; fi
  sleep 0.2
done
echo "bridge healthy → launching menu-bar app (look for “◎ onari” in the menu bar; open with ⌘I)"

swift run --package-path capture-mac
