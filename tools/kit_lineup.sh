#!/usr/bin/env bash
# [kit] Render the art kit lineup (art/kit/kit_lineup.gd), gated: waits until no other vulkan
# render runs and >= 6 GB RAM is free. Usage: tools/kit_lineup.sh OUT_PREFIX [--only=a,b] [--day-only]
set -e
cd "$(dirname "$0")/.."
OUT=${1:-screenshots/kit/lineup}; shift || true
for i in $(seq 1 120); do
  if ! pgrep -f '^godot .*rendering-driver vulkan' >/dev/null && [ "$(free -g | awk '/Mem:/{print $7}')" -ge 6 ]; then break; fi
  sleep 10
done
mkdir -p "$(dirname "$OUT")"
timeout "${TIMEOUT:-5400}" xvfb-run -a -s "-screen 0 960x540x24" \
  godot --path . --rendering-driver vulkan --resolution 960x540 res://art/kit/kit_lineup.tscn -- --fresh --out="$OUT" "$@" 2>&1 \
  | grep -vE "ALSA|alsa|audio_driver|All audio drivers|at: (init_output_device|initialize)|status < 0" || true
