#!/usr/bin/env bash
# [health] CI check: headless runs must finish with exit code 0 (no crash at quit) and no SCRIPT ERROR.
#   tools/check_exit.sh          save/load round trip (all systems)
#   tools/check_exit.sh --quick  also a 15 s plain run (catches shutdown crashes outside the round trip)
# Logs go to screenshots/check_exit_*.log.
cd "$(dirname "$0")/.."
mkdir -p screenshots
fail=0

run() {
	local name="$1"; shift
	local log="screenshots/check_exit_${name}.log"
	godot --headless --path . "$@" >"$log" 2>&1
	local code=$?
	if [ "$code" -ne 0 ]; then
		echo "[check_exit] FAIL $name: exit code $code (134 = crash at quit; see $log)"
		grep -m10 -E "FAIL|SCRIPT ERROR" "$log"  # [main] show the failing checks in CI logs
		fail=1
	elif grep -q "SCRIPT ERROR" "$log"; then
		echo "[check_exit] FAIL $name: SCRIPT ERROR in $log"
		grep -m5 -A2 "SCRIPT ERROR" "$log"
		fail=1
	else
		echo "[check_exit] PASS $name (exit 0)"
	fi
	if grep -q "leaked at exit\|still in use at exit" "$log"; then
		echo "[check_exit] note $name: leaks at exit (run with --verbose for details):"
		grep "leaked at exit\|still in use at exit" "$log" | head -5
	fi
}

run roundtrip res://tools/save_roundtrip.tscn -- --fresh --save-dir=check_exit_$$  # own save folder: parallel runs cannot clobber it
# [v1menu] The round world is the default, so the plain round trip is the globe's; the dormant flat
# game keeps its own until it is removed.
run roundtrip_flat res://tools/save_roundtrip.tscn -- --fresh --flat --save-dir=check_exit_flat_$$
# [orbB] the globe's save -> load across two processes (Lumi's position, currencies)
if tools/orbit_reload_check.sh >screenshots/check_exit_orbit_reload.log 2>&1; then
	echo "[check_exit] PASS orbit_reload (two processes)"
else
	echo "[check_exit] FAIL orbit_reload: see screenshots/check_exit_orbit_reload.log"
	fail=1
fi
if [ "$1" = "--quick" ]; then
	run quit15 -- --fresh --quit-after=15
fi
exit $fail
