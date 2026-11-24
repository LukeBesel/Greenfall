#!/usr/bin/env bash
# [orbB] Globe save -> load across two processes: Lumi's position (direction + height) and the
# currencies must come back from disk. Both processes must finish successfully.
cd "$(dirname "$0")/.." || exit 1
DIR="orbit_reload_$$"
log=$(mktemp "${TMPDIR:-/tmp}/orbit_reload.XXXXXX") || exit 1
trap 'rm -f "$log"' EXIT

run_reload() {
	local phase="$1" marker="$2"; shift 2
	local code=0
	timeout -k 30 "${CHECK_EXIT_TIMEOUT:-1800}" godot --headless --path . -- \
		"$@" --orbit --save-dir="$DIR" --orbit-reload="$phase" >"$log" 2>&1 || code=$?
	grep -aE '^\[reload\]|SCRIPT ERROR' "$log"
	if [ "$code" -ne 0 ] || grep -aqE 'SCRIPT ERROR|^\[reload\].*FAIL' "$log" || ! grep -aqE "$marker" "$log"; then
		echo "[orbit_reload] FAIL $phase (Godot exit $code; successful completion marker required)"
		tail -n 15 "$log"
		return 1
	fi
}

# Match the actual lines in OrbitDev._reload_check, not an unrelated PASS in engine output.
run_reload write '^\[reload\] wrote .*saved=true$' --fresh || exit 1
run_reload read '^\[reload\] read .* PASS$' || exit 1
