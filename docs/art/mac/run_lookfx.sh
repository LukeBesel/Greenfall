#!/bin/bash
# Captures and times the --look-fx review on a Mac's real GPU (Forward+ on Metal).
# Run from the repository root on macOS:   bash docs/art/mac/run_lookfx.sh
# Optional: GODOT=/path/to/Godot  PARTS="frames perf"  (default both; frames ~35 min, perf ~25 min)
# Writes JPEG frames to docs/art/mac/lookfx/, logs to docs/art/mac/lookfx/logs/,
# and the frame-rate table to docs/art/mac/lookfx/perf.tsv. Changes no game code.
# Works with the stock macOS bash 3.2.
set -u

if [ "$(uname -s)" != "Darwin" ]; then
	echo "STOP: this is $(uname -s), not macOS. The review needs the Mac's GPU; no frames were made." >&2
	exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

GODOT="${GODOT:-}"
if [ -z "$GODOT" ]; then
	if command -v godot >/dev/null 2>&1; then GODOT="$(command -v godot)"
	elif [ -x /Applications/Godot.app/Contents/MacOS/Godot ]; then GODOT=/Applications/Godot.app/Contents/MacOS/Godot
	else echo "STOP: Godot not found. Install 4.7.2-stable or set GODOT=." >&2; exit 2
	fi
fi
VER="$("$GODOT" --version 2>/dev/null | head -1)"
case "$VER" in
	4.7.2.stable*) ;;
	*) echo "STOP: need Godot 4.7.2-stable, found '$VER'." >&2; exit 2 ;;
esac

OUT=docs/art/mac/lookfx
LOGS=$OUT/logs
mkdir -p "$LOGS"
PARTS="${PARTS:-frames perf}"

{
	echo "commit: $(git rev-parse HEAD)"
	echo "branch: $(git rev-parse --abbrev-ref HEAD)"
	echo "godot: $VER"
	echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	sysctl -n hw.model machdep.cpu.brand_string 2>/dev/null
	system_profiler SPHardwareDataType SPDisplaysDataType 2>/dev/null |
		grep -E "Model Name|Model Identifier|Chip|Memory|Chipset Model|Resolution|Refresh|Metal" | sed 's/^ *//'
} > "$OUT/hardware.txt"
cat "$OUT/hardware.txt"

if [ ! -d .godot/imported ]; then
	echo "== importing assets (once)"
	"$GODOT" --headless --import --path . > "$LOGS/import.txt" 2>&1
fi

BASE="--fresh --quality=2 --orbit --no-intro --no-hud"

# fx_args VARIANT -> the look-fx flag for that variant (base has none)
fx_args() {
	case "$1" in
		base) echo "" ;;
		fx1) echo "--look-fx" ;;
		fx2) echo "--look-fx=2" ;;
	esac
}

# shot NAME ARGS...  one frame, PNG -> JPEG q88; reports missing or black frames
shot() {
	local name="$1"; shift
	local png="$OUT/$name.png" jpg="$OUT/$name.jpg" log="$LOGS/$name.txt"
	rm -f "$png"
	# shellcheck disable=SC2086
	"$GODOT" --path . --resolution 1920x1080 -- $BASE "$@" \
		--shot="$png" --shot-delay=35 --quit-after=40 > "$log" 2>&1
	local rc=$?
	if [ ! -s "$png" ]; then
		echo "FAIL  $name: no frame written (exit $rc), see $log"
		echo "$name	no-frame	exit=$rc" >> "$OUT/failures.tsv"
		return
	fi
	sips -s format jpeg -s formatOptions 88 "$png" --out "$jpg" >/dev/null 2>&1 && rm -f "$png"
	if ! grep -q "Forward+" "$log"; then
		echo "WARN  $name: log does not mention Forward+ (check the renderer line in $log)"
		echo "$name	renderer?	" >> "$OUT/failures.tsv"
	fi
	if grep -qiE "unrecognized|unknown (option|argument)" "$log"; then
		echo "WARN  $name: an option was not recognised, see $log"
		echo "$name	flag?	" >> "$OUT/failures.tsv"
	fi
	echo "ok    $name (exit $rc)"
}

if echo "$PARTS" | grep -q frames; then
	rm -f "$OUT/failures.tsv"
	for tn in "afternoon 0.68" "dusk 0.735" "morning 0.3" "noon 0.5" "night 0.0"; do
		set -- $tn; tname=$1; t=$2
		for v in base fx1 fx2; do
			# shellcheck disable=SC2046
			shot "pad_${tname}_${v}" --orbit-time="$t" $(fx_args $v)
			# shellcheck disable=SC2046
			shot "lake_${tname}_${v}" --orbit-time="$t" --lake-view $(fx_args $v)
		done
	done
	# Looking toward the low sun at dusk: all three yaws, keep the one that faces the sun.
	for yaw in 90 180 270; do
		for v in base fx1 fx2; do
			# shellcheck disable=SC2046
			shot "sunward_dusk_yaw${yaw}_${v}" --orbit-time=0.735 --orbit-spawn=0,0,$yaw $(fx_args $v)
		done
	done
fi

# median of numbers on stdin
median() {
	sort -n | awk '{a[NR]=$1} END{if(NR==0){print "NA"}else if(NR%2){print a[(NR+1)/2]}else{printf "%.2f\n",(a[NR/2]+a[NR/2+1])/2}}'
}

# perf_run NAME VSYNCFLAG ARGS... -> prints the run's median game_fps over samples from t>=20 s
perf_run() {
	local name="$1" vs="$2"; shift 2
	local log="$LOGS/$name.txt"
	# shellcheck disable=SC2086
	"$GODOT" --path . --resolution 1920x1080 $vs -- $BASE --perf --orbit-time=0.735 "$@" > "$log" 2>&1
	grep "^\[perf\]" "$log" | sed -E 's/.*t=([0-9]+)s.*game_fps=([0-9.]+).*/\1 \2/' |
		awk '$1>=20{print $2}' | median
}

if echo "$PARTS" | grep -q perf; then
	TSV=$OUT/perf.tsv
	printf "scenario\tvsync\tvariant\trun1\trun2\trun3\tmedian_fps\tframe_ms\n" > "$TSV"
	for vsmode in default off; do
		vs=""; [ "$vsmode" = off ] && vs="--disable-vsync"
		for sc in stand walk; do
			for v in base fx1 fx2; do
				runs=""
				for i in 1 2 3; do
					if [ "$sc" = stand ]; then
						# shellcheck disable=SC2046
						r=$(perf_run "perf_${sc}_${vsmode}_${v}_$i" "$vs" --quit-after=40 $(fx_args $v))
					else
						# shellcheck disable=SC2046
						r=$(perf_run "perf_${sc}_${vsmode}_${v}_$i" "$vs" --orbit-spawn=0,-260 --orbit-walk=boost --quit-after=75 $(fx_args $v))
					fi
					runs="$runs $r"
					echo "perf  $sc vsync=$vsmode $v run $i: $r fps"
				done
				med=$(echo $runs | tr ' ' '\n' | grep -v NA | median)
				ms=$(echo "$med" | awk '$1>0{printf "%.2f", 1000/$1} $1<=0||$1=="NA"{print "NA"}')
				# shellcheck disable=SC2086
				printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "$sc" "$vsmode" "$v" $runs "$med" "$ms" >> "$TSV"
			done
		done
	done
	echo
	cat "$TSV"
	echo
	echo "If the 'off' rows sit at the display's refresh rate (see hardware.txt), V-Sync still capped"
	echo "them: Settings.apply_display() sets the V-Sync mode from the saved setting after the engine"
	echo "flag is read. Turn V-Sync off in the game's settings menu once, then rerun PARTS=perf."
fi

echo
echo "Frames: $OUT/*.jpg   Logs: $LOGS/   Hardware: $OUT/hardware.txt"
[ -s "$OUT/failures.tsv" ] && { echo "Problems:"; cat "$OUT/failures.tsv"; }
exit 0
