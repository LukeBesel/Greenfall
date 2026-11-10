#!/bin/bash
# render.sh RES args... : gated single render of scenes/hero_preview.tscn in the hero worktree.
# DRIVER=opengl3 renders with the Compatibility renderer (much faster on software GL; no SSAO or
# volumetric extras, so use it for iteration and Vulkan for finals). GATE_TRIES=1 skips the wait.
cd "$(dirname "$0")/../.."
RES=$1; shift
DRIVER=${DRIVER:-vulkan}
for i in $(seq 1 ${GATE_TRIES:-120}); do
  if ! pgrep -f '^godot .*rendering-driver vulkan' >/dev/null && [ "$(free -g | awk '/Mem:/{print $7}')" -ge 6 ]; then break; fi
  sleep 10
done
W=${RES%x*}; H=${RES#*x}
LOG=screenshots/hero/render.log
timeout 900 xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path . --rendering-driver $DRIVER --resolution $RES res://scenes/hero_preview.tscn -- --fresh --quality=2 "$@" > $LOG 2>&1
grep -aE "screenshot|SCRIPT ERROR|ERROR" $LOG | grep -v ALSA | head -10
