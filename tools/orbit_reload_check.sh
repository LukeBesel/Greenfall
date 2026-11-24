#!/usr/bin/env bash
# [orbB] Globe save -> load across two processes: Lumi's position (direction + height) and the
# currencies must come back from disk. Prints the [reload] lines and fails if either run fails.
cd "$(dirname "$0")/.." || exit 1
DIR="orbit_reload_$$"
log=$(mktemp "${TMPDIR:-/tmp}/orbit_reload.XXXXXX") || exit 1
trap 'rm -f "$log"' EXIT

run_reload() {
	local phase="$1"; shift
	local code=0
	timeout -k 30 "${CHECK_EXIT_TIMEOUT:-1800}" godot --headless --path . -- \
		"$@" --orbit --save-dir="$DIR" --orbit-reload="$phase" >"$log" 2>&1 || code=$?
	grep -aE "^\[reload\]|SCRIPT ERROR" "$log"
	if [ "$code" -ne 0 ] || grep -aqE "SCRIPT ERROR|^\[reload\] FAIL" "$log"; then
		echo "[orbit_reload] FAIL $phase (Godot exit $code)"
		tail -n 15 "$log"
		return 1
	fi
}

run_reload write --fresh || exit 1
run_reload read || exit 1
if ! grep -aqE '^\[reload\] PASS([[:space:]:]|$)' "$log"; then
	echo "[orbit_reload] FAIL read (missing PASS marker)"
	tail -n 15 "$log"
	exit 1
fi
