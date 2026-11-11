#!/usr/bin/env bash
# One render of a wreck, a tease or a buried find (systems/find_sites_dev.gd), on software GL.
# Usage: tools/find_shot.sh NAME ID[:STATE] [extra dev flags...]   -> screenshots/finds/NAME.png
# A city away from the start takes about two minutes to build: DELAY (default 150 s) covers it.
set -e
cd "$(dirname "$0")/.."
NAME="$1"; SHOT="$2"; shift 2
DELAY="${DELAY:-150}"
mkdir -p screenshots/finds
timeout "${TIMEOUT:-580}" xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
  --resolution "${RES:-960x540}" -- --fresh --quality="${QUALITY:-0}" --detector-on --find-shot="$SHOT" \
  --shot="screenshots/finds/${NAME}.png" --shot-delay="$DELAY" --quit-after="$((DELAY + 5))" "$@" \
  > "screenshots/finds/${NAME}.log" 2>&1 || true
grep -aE "SCRIPT ERROR|\[finds\]|screenshot" "screenshots/finds/${NAME}.log" | tail -4 || true
