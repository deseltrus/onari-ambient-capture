#!/bin/bash
cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
pkill -f "bridge.py" 2>/dev/null
python3 laser-bridge/bridge.py --stdout > "$ROOT/lane1-events.log" 2>&1 &
BRIDGE=$!
sleep 1
echo "bridge up (pid $BRIDGE) -> lane1-events.log"
echo "watch THIS terminal — every switch and note prints here live."
cd capture-mac || exit 1
# stderr is unbuffered, so the app's log lands immediately even through tee.
swift run AmbientMac 2>&1 | tee "$ROOT/lane1-app.log"
kill $BRIDGE 2>/dev/null
