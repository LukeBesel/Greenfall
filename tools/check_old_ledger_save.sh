#!/usr/bin/env bash
# Owner item 105: a save from a build that still had the Ledger, taken in the middle of its arc,
# loads clean and plays on. Makes a save by playing, writes the old Ledger state into it
# (tools/ledger_old_save.gd), plays on from it and checks: no script error, nothing says "Ledger",
# the save comes out without a Ledger key and with more play time. Exit 1 on a failure.
cd "$(dirname "$0")/.."
mkdir -p screenshots
DIR="old_arc_$$"  # (no "ledger" in the name: the run's log is searched for the word)
LOG=screenshots/check_old_ledger_save.log
godot --headless --path . -- --fresh --orbit --no-intro --autoplay --time-scale=8 --quit-after=60 --save-dir="$DIR" >"$LOG" 2>&1
godot --headless --path . -s tools/ledger_old_save.gd -- --save-dir="$DIR" 2>&1 | grep "^\[old-ledger\]" | tee -a "$LOG"
godot --headless --path . -- --orbit --no-intro --autoplay --time-scale=8 --clarity-log --quit-after=90 --save-dir="$DIR" >"$LOG.load" 2>&1
code=0
if grep -q "SCRIPT ERROR" "$LOG.load"; then echo "[old-ledger] FAIL script error on load"; grep -m3 -A2 "SCRIPT ERROR" "$LOG.load"; code=1; fi
if grep -qi "ledger" "$LOG.load"; then echo "[old-ledger] FAIL the run still says Ledger:"; grep -m5 -i "ledger" "$LOG.load"; code=1; fi
godot --headless --path . -s tools/ledger_old_save.gd -- --save-dir="$DIR" --verify 2>&1 | grep "^\[old-ledger\]" | tee -a "$LOG"
grep -q "^\[old-ledger\] PASS" "$LOG" && [ "$(grep -c '^\[old-ledger\] PASS' "$LOG")" -ge 2 ] || code=1
exit $code
