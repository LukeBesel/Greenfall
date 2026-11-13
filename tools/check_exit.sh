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
		grep -m20 -E "FAIL|SCRIPT ERROR|pause-watch\]" "$log"  # [main] show the failing checks in CI logs
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
# [orbB] the globe's save -> load across two processes (Lumi's position, currencies)
if tools/orbit_reload_check.sh >screenshots/check_exit_orbit_reload.log 2>&1; then
	echo "[check_exit] PASS orbit_reload (two processes)"
else
	echo "[check_exit] FAIL orbit_reload: see screenshots/check_exit_orbit_reload.log"
	fail=1
fi
# [v6qa] Quitting or freeing while a hub town builds, and quitting during a rocket hop, corrupted
# the heap at exit (exit 134, "corrupted size vs. prev_size in fastbins"; QA_VERDANCE Q7/Q16).
run quit_mid_build -- --fresh --orbit --no-intro --orbit-walk-in=1,380 --quit-mid-build=30
run free_mid_build -- --fresh --orbit --no-intro --orbit-walk-in=1,380 --quit-mid-build=30 --quit-mode=free
run quit_on_hop -- --fresh --orbit --no-intro --orbit-hop=4 --quit-on-hop=4
# [v8hex] Owner (Nov 13): every start-area hex clears with the starter tools, and no big item
# stands round base 1 (exit 1 lists the stuck hexes and the big things).
run hex_audit -- --fresh --orbit --no-intro --hex-audit --hex-audit-quit
# [v8seed] "Plant the first seed" played with real key and mouse events (tools/seed_walk.gd): the
# bot's own path hid that a player could not plant (owner, 2026-11-13).
run seed_walk -- --fresh --orbit --no-intro --seed-walk --save-dir=check_exit_seed_$$
if [ "$1" = "--quick" ]; then
	run quit15 -- --fresh --quit-after=15
fi
exit $fail
