#!/usr/bin/env bash
# Rendered screenshot(s) of the game. Usage: tools/shot.sh NAME [extra devhook args...]
# Forward+ on software Vulkan (lavapipe) under Xvfb is slow: defaults to the Low preset at
# 960x540 and a long settle time. Output: screenshots/NAME.png. Log: screenshots/NAME.log
set -e
cd "$(dirname "$0")/.."
NAME="${1:-shot}"; shift || true
RES="${RES:-960x540}"
DELAY="${DELAY:-40}"
stdbuf -oL timeout "${TIMEOUT:-900}" xvfb-run -a -s "-screen 0 1280x720x24" stdbuf -oL \
  godot --path . --rendering-driver vulkan --resolution "$RES" -- --fresh --quality="${QUALITY:-0}" --perf \
  --shot="screenshots/${NAME}.png" --shot-delay="$DELAY" --quit-after="$((DELAY + 5))" "$@" > "screenshots/${NAME}.log" 2>&1 || true
grep -aE "screenshot|perf\]|SCRIPT ERROR|ERROR: (?!Condition \"status)" "screenshots/${NAME}.log" | tail -4 || true
