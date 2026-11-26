#!/usr/bin/env bash
# Render turnaround screenshots of a robot design script.
# Usage: tools/turnaround.sh res://player/designs/patch_a.gd screenshots/turn_a [extra args]
# Lumi designs and Locker looks: tools/turnaround.sh res://player/patch_model.gd OUT --design=sprout [--style=side:ff3d8a,head:halo]
set -e
cd "$(dirname "$0")/.."
flock -o /tmp/gf-render.lock timeout "${TIMEOUT:-240}" xvfb-run -a -s "-screen 0 960x720x24" \
  godot --path . --rendering-driver opengl3 --resolution 960x720 res://scenes/turnaround.tscn -- --fresh --model="$1" --out="$2" "${@:3}" 2>&1 \
  | grep -vE "ALSA|alsa|audio_driver|All audio drivers|at: (init_output_device|initialize)|status < 0" || true
