#!/usr/bin/env bash
# Owner item 110 ("not when i log off"): a save loads as exactly the world that was saved,
# whatever the clock says. Plays a short game with robots out, plants in the ground, a research
# running and the rocket's cells refilling, saves, then loads that save five times with its time
# stamp moved (tools/clock_save.gd): 2 hours and 30 days ago (the game was closed that long),
# 2 hours and 400 days in the future (the computer's clock was set back), and once as an old
# save (version 5) that still carries the away-earnings keys, a day old. Each load compares
# cubes, parts, seeds, clean hexes, junk left, bales, plants, every robot and both timers with
# what was saved, plays 8 s and fails on any "while you were away" message
# (tools/clock_check.gd, "[clock]" lines). Exit 1 on a failure.
cd "$(dirname "$0")/.."
mkdir -p screenshots
DIR="clock_$$"
LOG=screenshots/check_clock_save.log
: >"$LOG"
code=0
godot --headless --path . -- --fresh --orbit --no-intro --robots=scoopie:2,haulbug:1 --clock-check=save --time-scale=4 --quit-after=600 --save-dir="$DIR" >"${LOG%.log}_save.log" 2>&1
grep "^\[clock\]" "${LOG%.log}_save.log" | tee -a "$LOG"
if ! grep -q "^\[clock\] PASS save" "${LOG%.log}_save.log"; then echo "[clock] FAIL the save run did not finish (see ${LOG%.log}_save.log)"; tail -n 8 "${LOG%.log}_save.log"; exit 1; fi
n=0
for spec in "7200" "2592000" "-7200" "-34560000" "86400 --old"; do
	n=$((n + 1))
	# shellcheck disable=SC2086
	godot --headless --path . -s tools/clock_save.gd -- --save-dir="$DIR" --shift=$spec 2>&1 | grep "^\[clock\]" | tee -a "$LOG"
	godot --headless --path . -- --orbit --no-intro --clock-check=load --quit-after=600 --save-dir="$DIR" >"${LOG%.log}_load$n.log" 2>&1
	grep "^\[clock\]" "${LOG%.log}_load$n.log" | tee -a "$LOG"
	if grep -q "SCRIPT ERROR" "${LOG%.log}_load$n.log"; then echo "[clock] FAIL script error on load $n"; grep -m3 -A2 "SCRIPT ERROR" "${LOG%.log}_load$n.log"; code=1; fi
	grep -q "^\[clock\] PASS the world is the saved one" "${LOG%.log}_load$n.log" || { echo "[clock] FAIL load $n (shift $spec): see ${LOG%.log}_load$n.log"; code=1; }
done
[ "$code" -eq 0 ] && echo "[clock] PASS all 5 loads: 2 h and 30 days closed, clock set back 2 h and 400 days, old save"
exit $code
