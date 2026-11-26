#!/usr/bin/env bash
# [v13goals] Planting is gone (owner, 26 Nov: the player only cleans): a save from the planting game
# loads clean and plays on. Makes a save by playing, writes the old planting state into it
# (tools/planting_old_save.gd: seeds, the seed step on the card, a planting Request, a thirsty
# planted cell, a Drip and a Seedling), plays on from it and checks: no script error, the seeds became
# cubes, the robots clean, the old plants grow by themselves, the card moved on. Exit 1 on a failure.
cd "$(dirname "$0")/.."
mkdir -p screenshots
DIR="old_plant_$$"
LOG=screenshots/check_old_planting_save.log
godot --headless --path . -- --fresh --orbit --no-intro --autoplay --time-scale=8 --quit-after=60 --save-dir="$DIR" >"$LOG.make" 2>&1
godot --headless --path . -s tools/planting_old_save.gd -- --save-dir="$DIR" 2>&1 | grep "^\[old-planting\]" | tee "$LOG"
godot --headless --path . -- --orbit --no-intro --autoplay --time-scale=8 --clarity-log --quit-after=90 --save-dir="$DIR" >"$LOG.load" 2>&1
code=0
ASKS='\bplant (a|the|it|some|seeds?)\b|planting|watering|water (it|them|the (plants?|seeds?|garden))|seed tin|out of seeds|no seeds'
if grep -q "SCRIPT ERROR" "$LOG.load"; then echo "[old-planting] FAIL script error on load"; grep -m3 -A2 "SCRIPT ERROR" "$LOG.load"; code=1; fi
if grep -E "^\[clarity\]" "$LOG.load" | grep -qiE "$ASKS"; then echo "[old-planting] FAIL the player is told to plant or water:"; grep -E "^\[clarity\]" "$LOG.load" | grep -iE "$ASKS" | head -5; code=1; fi
godot --headless --path . -s tools/planting_old_save.gd -- --save-dir="$DIR" --verify 2>&1 | grep "^\[old-planting\]" | tee -a "$LOG"
grep -q "^\[old-planting\] PASS" "$LOG" && [ "$(grep -c '^\[old-planting\] PASS' "$LOG")" -ge 2 ] || code=1
exit $code
