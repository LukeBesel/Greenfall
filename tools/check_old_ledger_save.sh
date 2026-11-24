#!/usr/bin/env bash
# Owner item 105: a save from a build that still had the Ledger, taken in the middle of its arc,
# loads clean and plays on. Makes a save by playing, writes the old Ledger state into it
# (tools/ledger_old_save.gd), plays on from it and checks: no script error, nothing says "Ledger",
# the save comes out without a Ledger key and with more play time. Exit 1 on a failure.
cd "$(dirname "$0")/.." || exit 1
mkdir -p screenshots
DIR="old_arc_$$"  # (no "ledger" in the name: the run's log is searched for the word)
LOG=screenshots/check_old_ledger_save.log

# Keep each phase's status and complete log. A PASS printed before a crash is not a pass,
# and the fixture writer's PASS cannot stand in for the final verifier's PASS.
run_phase() {
	local phase="$1" marker="$2"; shift 2
	local log="$LOG.$phase" code=0
	timeout -k 30 "${CHECK_EXIT_TIMEOUT:-1800}" godot --headless --path . "$@" >"$log" 2>&1 || code=$?
	grep -a '^\[old-ledger\]' "$log"
	if [ "$code" -ne 0 ] || grep -aqE 'SCRIPT ERROR|^\[old-ledger\].*FAIL' "$log" || { [ -n "$marker" ] && ! grep -aqE "$marker" "$log"; }; then
		echo "[old-ledger] FAIL $phase: exit $code, script error, failure or missing completion marker (see $log)"
		tail -n 15 "$log"
		return 1
	fi
}

run_phase fresh '' -- --fresh --orbit --no-intro --autoplay --time-scale=8 --quit-after=60 --save-dir="$DIR" || exit 1
run_phase fixture '^\[old-ledger\] PASS$' -s tools/ledger_old_save.gd -- --save-dir="$DIR" || exit 1
run_phase load '' -- --orbit --no-intro --autoplay --time-scale=8 --clarity-log --quit-after=90 --save-dir="$DIR" || exit 1
if grep -aqi ledger "$LOG.load"; then
	echo '[old-ledger] FAIL the run still says Ledger:'
	grep -am5 -i ledger "$LOG.load"
	exit 1
fi
run_phase verify '^\[old-ledger\] PASS$' -s tools/ledger_old_save.gd -- --save-dir="$DIR" --verify || exit 1
