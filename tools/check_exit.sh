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
	timeout -k 30 "${CHECK_EXIT_TIMEOUT:-1800}" godot --headless --path . "$@" >"$log" 2>&1  # [v10quit] a hang fails, not blocks CI
	local code=$?
	if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
		echo "[check_exit] FAIL $name: hang at exit (killed after ${CHECK_EXIT_TIMEOUT:-1800} s; see $log). Log tail:"
		tail -n 15 "$log"
		fail=1
	elif [ "$code" -ne 0 ]; then
		echo "[check_exit] FAIL $name: exit code $code (134 = crash at quit; see $log)"
		grep -m60 -E "FAIL|SCRIPT ERROR|pause-watch\]|walk-opening\] stuck|walk-home\] debug" "$log"  # [main] show the failing checks in CI logs ([v9a] and what held Lumi)
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
# [v9intro] The opening film leaves the same world watched or skipped (just before the crash).
if tools/check_intro.sh --quick >screenshots/check_exit_intro.log 2>&1; then
	echo "[check_exit] PASS intro (watched = skipped)"
else
	echo "[check_exit] FAIL intro: see screenshots/check_exit_intro.log"
	fail=1
fi
# [v11film] Watching the film again (pause menu, Codex) changes nothing: the save and the world
# are compared before and after seven rewatches, skipped at different moments.
if tools/check_rewatch.sh >screenshots/check_exit_rewatch.log 2>&1; then
	echo "[check_exit] PASS rewatch (the world is the same after watching the film again)"
else
	echo "[check_exit] FAIL rewatch: see screenshots/check_exit_rewatch.log"
	tail -n 20 screenshots/check_exit_rewatch.log
	fail=1
fi
# [v9a] Goal audit: New Game to the first robot with real keys, mouse aim and bench clicks
# (tools/walk_opening.gd): intro skip, checklist, bin, bench buys, bales, tower, Glim, hex, Bot Bay.
run walk_opening -- --fresh --orbit --intro --walk-opening --save-dir=check_exit_open_$$
# [v9a] Two spots where the opening walk stopped, played alone with real keys: pressed against the
# lake's edge by the bin in every key direction Lumi moves or the way is all lake (he froze there),
# and with a bale pressed over a buried part E picks the bale up, as the prompt says (it dug);
# and from behind the Shack's back wall (a CI run paced there) the walker gets to the Bot Bay.
# [v14qa] the lean-to built: W into its side and back walls never takes Lumi through (before it is built no wall stops him);
# bales left 150-600 m from Lumi stay where they lie (they fell into the planet and dropped onto Lumi).
run walk_opening_spots -- --fresh --orbit --no-intro --detector-on --walk-opening --walk-opening-spot="-7.4,-6.7;-7.0,-3.0;-10.5,7.7@pt:6.0:7.6;-7.4,-6.7@shackwall+farbale" --walk-opening-spot-goals=shore,digbale --save-dir=check_exit_spots_$$
# [v9c] The travel steps (rocket, stations 2 and 6, the drive, the end card) played with real
# input (tools/walk_travel.gd), and a save in the middle of station 2's chain loaded back.
run walk_travel -- --fresh --orbit --no-intro --walk-travel --quit-after=4000 --save-dir=check_exit_travel_$$
# [v10base] Owner playtest 3 #103/#100: fly to station 2 and back with a Continue at each end; the
# workbench, bin and the rest of the yard still stand and answer E; the ship flies nose first.
run walk_travel_back -- --fresh --orbit --no-intro --walk-travel --walk-travel-back --quit-after=1500 --save-dir=check_exit_travelb_$$
run walk_travel_end -- --orbit --no-intro --walk-travel --walk-travel-end --quit-after=600 --save-dir=check_exit_travel_$$
run walk_travel_save -- --fresh --orbit --no-intro --walk-travel --walk-travel-save --quit-after=2000 --save-dir=check_exit_travelr_$$
run walk_travel_resume -- --orbit --no-intro --walk-travel --walk-travel-resume --quit-after=1500 --save-dir=check_exit_travelr_$$
# [v9c] Every far station has its count of hexes finishable with the starting Lift (0)
# within 100 m of its pad (exit 1 lists the short ones).
run hex_audit_hubs -- --fresh --orbit --no-intro --hex-audit --hex-audit-hubs --hex-audit-lift=0 --hex-audit-quit
# [v9d] Every goal and achievement left on Verdance can complete (tools/goal_audit.gd on the globe),
# and one goal of each kind a player does by hand moves when played with real input (tools/walk_goals.gd).
run walk_goals -- --fresh --orbit --no-intro --walk-goals --save-dir=check_exit_goals_$$
# [v9b] The home steps after the first robot (hex2 .. base3, the garden, the Requests board) played
# with real keys and mouse clicks on the workbench (tools/walk_home.gd).
run walk_home -- --fresh --orbit --no-intro --walk-home --save-dir=check_exit_home_$$
if tools/check_old_ledger_save.sh >screenshots/check_exit_old_ledger.log 2>&1; then  # owner item 105
	echo "[check_exit] PASS old_ledger_save (a save from mid Ledger arc loads clean and plays on)"
else
	echo "[check_exit] FAIL old_ledger_save: see screenshots/check_exit_old_ledger.log"
	fail=1
fi
# [v10snd] Owner (Nov 15): the first song plays when the CD by the start pad is found, and the radio
# (N) plays a found song at will: a new game with real keys and clicks, two reloads (tools/walk_radio.gd).
run walk_radio -- --fresh --orbit --no-intro --walk-radio --save-dir=check_exit_radio_$$
run walk_radio_clean -- --fresh --orbit --no-intro --walk-radio --walk-radio-clean --save-dir=check_exit_radioc_$$
# [v9s] Owner (Nov 13): "super annoying to hear the same bird chirp so many times over and over".
# Two and a half minutes standing on green ground by the start (birds, frogs, the life bed), every
# sound logged; tools/check_audio.py --repeat fails on a sound that repeats more than its category
# allows (plays a minute, the same take back to back, metronome spacing; docs/ADJUSTING.md).
run sound_repeat -- --fresh --orbit --no-intro --life-sound --life-clean=6,5 --life-grown --sound-log=res://screenshots/check_exit_sound.txt --quit-after=150
if python3 tools/check_audio.py --repeat screenshots/check_exit_sound.txt --skip 30 >screenshots/check_exit_sound_repeat.log 2>&1; then
	echo "[check_exit] PASS sound_repeat ($(grep -c . screenshots/check_exit_sound.txt) plays)"
else
	echo "[check_exit] FAIL sound_repeat: see screenshots/check_exit_sound_repeat.log"
	grep FAIL screenshots/check_exit_sound_repeat.log | head -8
	fail=1
fi
rm -f screenshots/check_exit_sound.txt
if [ "$1" = "--quick" ]; then
	run quit15 -- --fresh --quit-after=15
fi
exit $fail
