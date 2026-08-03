#!/bin/bash
# ./lane1-run.sh          bridge prints events, no LaserData needed (dry run)
# ./lane1-run.sh --live   bridge PUBLISHES to LaserData (needs laser-stack up)
cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
MODE="--stdout"; LABEL="DRY RUN (printing only, not publishing)"
[ "$1" = "--live" ] && { MODE=""; LABEL="LIVE (publishing to LaserData)"; }
pkill -f "bridge.py" 2>/dev/null
python3 laser-bridge/bridge.py $MODE > "$ROOT/lane1-events.log" 2>&1 &
BRIDGE=$!
sleep 1
echo "bridge up (pid $BRIDGE) — $LABEL  -> lane1-events.log"
echo "watch THIS terminal: every switch and note prints live."
cd capture-mac || exit 1
swift run AmbientMac 2>&1 | tee "$ROOT/lane1-app.log"
kill $BRIDGE 2>/dev/null
