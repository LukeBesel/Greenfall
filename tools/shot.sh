#!/usr/bin/env bash
# Rendered screenshot(s) of the game (the round world). Usage: tools/shot.sh NAME [extra devhook args...]
# [v6flat] Compatibility renderer (opengl3, Mesa llvmpipe) under Xvfb, inside the shared render
# lock (/tmp/gf-render.lock: one render at a time on the box). Low preset at 960x540 and a long
# settle time by default. Output: screenshots/NAME.png. Log: screenshots/NAME.log
set -e
cd "$(dirname "$0")/.."
NAME="${1:-shot}"; shift || true
RES="${RES:-960x540}"
DELAY="${DELAY:-40}"
stdbuf -oL flock -o /tmp/gf-render.lock timeout "${TIMEOUT:-900}" xvfb-run -a -s "-screen 0 1280x720x24" stdbuf -oL \
  godot --path . --rendering-driver opengl3 --resolution "$RES" -- --fresh --quality="${QUALITY:-0}" --perf \
  --shot="screenshots/${NAME}.png" --shot-delay="$DELAY" --quit-after="$((DELAY + 5))" "$@" > "screenshots/${NAME}.log" 2>&1 || true
grep -aE "screenshot|perf\]|SCRIPT ERROR|ERROR: (?!Condition \"status)" "screenshots/${NAME}.log" | tail -4 || true
