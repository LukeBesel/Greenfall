#!/usr/bin/env bash
# [artguard] Did new art break the game? Headless, a few minutes (docs/ART_BASELINE.md).
#   tools/art_guard.sh                  run every check, compare with docs/art_baseline.json; exit 1 on a FAIL
#   tools/art_guard.sh --write-baseline run them and store the numbers as the new baseline (on main only)
#   tools/art_guard.sh --fault=NAME     plant one world fault (walkthrough, invisible, white, rig, locker,
#                                       film, tris) and run only the world check: it must FAIL
#   tools/art_guard.sh --quick          the file census and the world check only (no walks, no perf run)
#   ART_GUARD_RENDER=1                  also rendered runs: draw calls, primitives and texture memory at four
#                                       fixed views by day and three at dusk and night, and their frames
#                                       (screenshots/art_guard/view_*.png; one render at a time, ~20 min)
# Logs and numbers: screenshots/art_guard/ (static.json, world.log, city_walk.log, site_reach.log,
# target_reach.log, perf.log, render.log).
cd "$(dirname "$0")/.."
OUT="${ART_GUARD_OUT:-screenshots/art_guard}"
mkdir -p "$OUT"
write=""; fault=""; quick=""
for a in "$@"; do
	case "$a" in
		--write-baseline) write="--write-baseline" ;;
		--fault=*) fault="${a#--fault=}"; quick=1 ;;
		--quick) quick=1 ;;
	esac
done
rm -f "$OUT"/*.log "$OUT"/static.json
T="${ART_GUARD_TIMEOUT:-7200}"  # includes the wait for a run slot on a busy box
SD="artguard_$$"

python3 tools/art_guard.py self-test >"$OUT/selftest.log" 2>&1 || { echo "[artguard] FAIL selftest: the file checks' own test failed:"; cat "$OUT/selftest.log"; exit 1; }
python3 tools/art_guard.py static "$OUT/static.json" || exit 1

g() {  # name, args...: one headless globe run, its log in $OUT/name.log
	local name="$1"; shift
	timeout -k 30 "$T" godot --headless --path . -- "$@" >"$OUT/$name.log" 2>&1
	echo "$?" >"$OUT/$name.code"
}
FA=""; [ -n "$fault" ] && FA="--art-guard-fault=$fault"
g world --fresh --orbit --no-intro --art-guard $FA --save-dir=${SD}_w --quit-after=1200 &
if [ -z "$quick" ]; then
	g city_walk --fresh --orbit --no-intro --city-walk --save-dir=${SD}_c &
	g site_reach --fresh --orbit --no-intro --site-reach --save-dir=${SD}_s &
	g target_reach --fresh --orbit --no-intro --target-reach --target-reach-hubs="${ART_GUARD_HUBS:-3}" --save-dir=${SD}_t &
	g perf --fresh --orbit --no-intro --load-report --orbit-spawn=0,-260 --orbit-walk=boost --hitch --quit-after=75 --save-dir=${SD}_p &
fi
wait
if [ -n "$ART_GUARD_RENDER" ] && [ -z "$fault" ]; then
	# Day (the new game's morning), dusk (0.77) and night (0.95): one load, one render at a time.
	touch /tmp/gf-render.want
	flock -o /tmp/gf-render.lock timeout -k 30 3000 xvfb-run -a -s "-screen 0 1280x720x24" \
		godot --path . --rendering-driver opengl3 --resolution 960x540 -- --fresh --orbit --no-intro --quality=0 \
		--art-guard-views="$OUT" --save-dir=${SD}_r --quit-after=100000 >"$OUT/render.log" 2>&1
	# Brightness of each frame (the art branch's tools/frame_stats.py, once merged).
	[ -f tools/frame_stats.py ] && python3 tools/frame_stats.py "$OUT"/view_*.png >"$OUT/frame_stats.txt" 2>&1
fi
for f in "$OUT"/*.code; do
	n=$(basename "$f" .code); c=$(cat "$f")
	if [ "$c" = "124" ] || [ "$c" = "137" ]; then echo "[artguard] note: the $n run was killed ($c: timeout or memory); its check reads as not finished"; fi
done
rm -f "$OUT"/*.code
python3 tools/art_guard.py compare "$OUT" $write
code=$?
if [ -n "$fault" ]; then
	if [ "$code" -ne 0 ]; then echo "[artguard] fault '$fault' planted: caught (exit $code)"; else echo "[artguard] fault '$fault' planted: NOT caught"; fi
fi
exit $code
