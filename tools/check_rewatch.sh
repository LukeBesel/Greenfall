#!/usr/bin/env bash
# [v11film] Watching the opening film again must never change the save or the world
# (tools/rewatch_check.gd): seven rewatches in the real game (watched, skipped at five moments,
# paused and resumed), each compared before and after, then the pause menu's entry.
#   tools/check_rewatch.sh      about 5 minutes headless
# Log: screenshots/check_rewatch.log. Exit 1 on a failure, a script error or a crash.
cd "$(dirname "$0")/.."
mkdir -p screenshots
log=screenshots/check_rewatch.log
timeout -k 30 "${CHECK_EXIT_TIMEOUT:-1800}" ${GODOT_WRAPPER:-godot} --headless --path . --fixed-fps 10 -- --fresh --orbit --no-intro --rewatch-check --save-dir=check_rewatch_$$ >"$log" 2>&1
code=$?
grep -a "^\[rewatch\]" "$log"
if [ "$code" -ne 0 ] || grep -aq "SCRIPT ERROR" "$log" || ! grep -aq "^\[rewatch\] PASS" "$log"; then
	echo "[check_rewatch] FAIL (exit $code; see $log)"
	grep -a -m5 -A2 "SCRIPT ERROR" "$log"
	exit 1
fi
echo "[check_rewatch] PASS"
