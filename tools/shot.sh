#!/usr/bin/env bash
# Rendered screenshot(s) of the game. Usage: tools/shot.sh NAME [extra devhook args...]
# Example: tools/shot.sh slice --cam=wide --shot-delay=3
# Uses Forward+ on software Vulkan (lavapipe) under Xvfb. Output: screenshots/NAME.png
set -e
cd "$(dirname "$0")/.."
NAME="${1:-shot}"; shift || true
RES="${RES:-1280x720}"
timeout "${TIMEOUT:-120}" xvfb-run -a -s "-screen 0 ${RES}x24" \
  godot --path . --rendering-driver vulkan --resolution "$RES" -- --fresh --shot="screenshots/${NAME}.png" --quit-after="${QUIT:-6}" "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_driver|All audio drivers|at: (init_output_device|initialize)" || true
