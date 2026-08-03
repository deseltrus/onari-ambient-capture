#!/bin/bash
cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"; LOG="$ROOT/lane1-build.log"
cd capture-mac || exit 1
{ echo "### swift build"; swift build 2>&1; echo "### EXIT_BUILD:$?"
  echo "### swift test";  swift test  2>&1; echo "### EXIT_TEST:$?"; } > "$LOG" 2>&1
echo "errors: $(grep -c 'error:' "$LOG")"; grep -E "^### EXIT_" "$LOG"
echo "full output -> lane1-build.log"
