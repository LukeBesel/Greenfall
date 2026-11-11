#!/bin/bash
# M3-18c render helper: one view per run, opengl3 under xvfb, Medium, with --perf.
#   tools/world_audit/city_shot.sh OUT.png HUBSPEC STAGE SOURCE DISTRICT [extra flags...]
# HUBSPEC is --shot-hub's value (N[,x,z,yaw]); STAGE -1, SOURCE - and DISTRICT - leave that flag out.
# DELAY=S sets the shot delay (default 70). The log is OUT.log beside the picture.
OUT=$1; HUB=$2; STAGE=$3; SRC=$4; DIST=$5; shift 5
D=${DELAY:-70}
ARGS="--fresh --no-intro --quality=1 --no-hud --perf --shot-hub=$HUB --shot=$OUT --shot-delay=$D --quit-after=$((D + 4))"
[ "$STAGE" != "-1" ] && ARGS="$ARGS --town-stage=$STAGE"
[ "$SRC" != "-" ] && ARGS="$ARGS --town-source=$SRC"
[ "$DIST" != "-" ] && ARGS="$ARGS --district-stage=$DIST"
mkdir -p "$(dirname "$OUT")"
xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 --resolution 1280x720 \
	res://tools/world_audit/world_shot.tscn -- $ARGS "$@" > "${OUT%.png}.log" 2>&1
grep "\[perf\]" "${OUT%.png}.log" | tail -2
ls -la "$OUT" 2>&1 | tail -1
