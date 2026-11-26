#!/bin/bash
# [art2] One gated render of scenes/hero_preview.tscn on software GL (the cloud box has no Vulkan GPU).
# Usage: tools/hero/render_gl.sh 1280x800 --view=turn --out=screenshots/hero/turn_v2
cd "$(dirname "$0")/../.."
RES=$1; shift
W=${RES%x*}; H=${RES#*x}
flock -o /tmp/gf-render.lock timeout 600 xvfb-run -a -s "-screen 0 ${W}x${H}x24" godot --path . --rendering-driver opengl3 --resolution $RES res://scenes/hero_preview.tscn -- --fresh --quality=2 "$@" > screenshots/hero/render.log 2>&1
grep -aE "screenshot|SCRIPT ERROR|SHADER ERROR" screenshots/hero/render.log | head -10
