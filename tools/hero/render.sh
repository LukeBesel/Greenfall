#!/bin/bash
# hero_render.sh RES args... : gated single render of scenes/hero_preview.tscn in the hero worktree
cd "$(dirname "$0")/../.."
RES=$1; shift
for i in $(seq 1 ${GATE_TRIES:-120}); do
  if ! pgrep -f '^godot .*rendering-driver vulkan' >/dev/null && [ "$(free -g | awk '/Mem:/{print $7}')" -ge 6 ]; then break; fi
  sleep 10
done
W=${RES%x*}; H=${RES#*x}
timeout 900 xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path . --rendering-driver vulkan --resolution $RES res://scenes/hero_preview.tscn -- --fresh --quality=2 "$@" > screenshots/hero/render.log 2>&1
grep -aE "screenshot|SCRIPT ERROR|ERROR" screenshots/hero/render.log | grep -v ALSA | head -10
