#!/bin/bash
# Captures and timings for the --look-fx review (docs/art/mac/LOOKFX.md).
# Run on the Mac, from the repository root:   bash docs/art/mac/run_lookfx.sh
# Needs macOS with a real GPU (Metal) and Godot 4.7.2-stable. Takes about 75 minutes.
#   SHOTS=0 skips the frames, PERF=0 skips the timings, VSYNC=1 times with V-Sync left on.
set -u
[ "$(uname -s)" = "Darwin" ] || { echo "Not macOS ($(uname -s)): stop. This review needs the Mac's GPU."; exit 1; }
GODOT="${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}"
[ -x "$GODOT" ] || { echo "Godot not found: install 4.7.2-stable or set GODOT=/path/to/Godot"; exit 1; }
case "$("$GODOT" --version)" in 4.7.2.stable*) ;; *) echo "Need Godot 4.7.2-stable, found $("$GODOT" --version)"; exit 1;; esac
[ -f project.godot ] || { echo "Run from the repository root"; exit 1; }

OUT=docs/art/mac/lookfx
mkdir -p "$OUT/logs"
{ git rev-parse HEAD; "$GODOT" --version; system_profiler SPHardwareDataType SPDisplaysDataType; } > "$OUT/hardware.txt" 2>&1
"$GODOT" --headless --import --path . > "$OUT/logs/import.log" 2>&1

BASE="--fresh --quality=2 --orbit --no-intro --no-hud"
fx_flag() { case "$1" in off) echo "";; k1) echo "--look-fx";; k2) echo "--look-fx=2";; esac; }

shot() {  # shot NAME ORBIT_TIME FX [extra game flags]
	local name=$1 t=$2 fx=$3; shift 3
	"$GODOT" --path . --resolution 1920x1080 -- $BASE --orbit-time="$t" $(fx_flag "$fx") "$@" \
		--shot="$OUT/$name.png" --shot-delay=35 --quit-after=40 > "$OUT/logs/$name.log" 2>&1
	if [ -f "$OUT/$name.png" ]; then
		sips -s format jpeg -s formatOptions 88 "$OUT/$name.png" --out "$OUT/$name.jpg" > /dev/null && rm "$OUT/$name.png"
		echo "ok   $name.jpg"
	else
		echo "FAIL $name (see $OUT/logs/$name.log)"
	fi
}

if [ "${SHOTS:-1}" = "1" ]; then
	for tod in afternoon:0.68 dusk:0.735 morning:0.3 noon:0.5 night:0.0; do
		n=${tod%%:*}; t=${tod##*:}
		for fx in off k1 k2; do
			shot "pad_${n}_${fx}" "$t" "$fx"
			shot "lake_${n}_${fx}" "$t" "$fx" --lake-view
		done
	done
	# Toward the low sun: keep the yaw that faces it at dusk, delete the other two sets.
	for yaw in 90 180 270; do
		for fx in off k1 k2; do
			shot "sun_yaw${yaw}_dusk_${fx}" 0.735 "$fx" "--orbit-spawn=0,0,$yaw"
		done
	done
fi

if [ "${PERF:-1}" = "1" ]; then
	VS="--disable-vsync"; [ "${VSYNC:-0}" = "1" ] && VS=""
	TSV="$OUT/perf.tsv"
	printf "scenario\tfx\trun\tmedian_game_fps\tsamples\n" > "$TSV"
	perf() {  # perf SCENARIO FX RUN SETTLE_SECONDS [game flags]
		local sc=$1 fx=$2 run=$3 settle=$4; shift 4
		local log="$OUT/logs/perf_${sc}_${fx}_${run}.log"
		"$GODOT" --path . --resolution 1920x1080 $VS -- $BASE --orbit-time=0.735 $(fx_flag "$fx") --perf "$@" > "$log" 2>&1
		# Median of the 3-second game_fps samples taken after the world has built.
		grep '^\[perf\]' "$log" | sed -E 's/.*t=([0-9]+)s.*game_fps=([0-9.]+).*/\1 \2/' | awk -v s="$settle" '$1 >= s {print $2}' | sort -n \
			| awk -v sc="$sc" -v fx="$fx" -v run="$run" '{a[NR]=$1} END {if (NR == 0) {printf "%s\t%s\t%s\tFAILED\t0\n", sc, fx, run} else {m = (NR % 2) ? a[(NR+1)/2] : (a[NR/2] + a[NR/2+1]) / 2; printf "%s\t%s\t%s\t%.1f\t%d\n", sc, fx, run, m, NR}}' >> "$TSV"
		tail -1 "$TSV"
	}
	for run in 1 2 3; do
		for fx in off k1 k2; do
			perf pad "$fx" "$run" 20 --quit-after=40
			perf walk "$fx" "$run" 20 --orbit-spawn=0,-260 --orbit-walk=boost --quit-after=75
		done
	done
	echo "V-Sync: $([ -z "$VS" ] && echo on || echo "disabled (--disable-vsync)")" >> "$OUT/hardware.txt"
fi
echo "Done. Frames and perf.tsv are in $OUT; look at every frame before writing LOOKFX.md."
