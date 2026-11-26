#!/usr/bin/env bash
# [orbB] Globe save -> load across two processes: Lumi's position (direction + height) and the
# currencies must come back from disk. Prints the two [reload] lines; exit 1 on FAIL.
cd "$(dirname "$0")/.."
DIR="orbit_reload_$$"
godot --headless --path . -- --fresh --orbit --save-dir="$DIR" --orbit-reload=write 2>&1 | grep -E "^\[reload\]|SCRIPT ERROR"
godot --headless --path . -- --orbit --save-dir="$DIR" --orbit-reload=read 2>&1 | grep -E "^\[reload\]|SCRIPT ERROR" | tee /tmp/orbit_reload_$$.log
grep -q "PASS" /tmp/orbit_reload_$$.log; code=$?
rm -f /tmp/orbit_reload_$$.log
exit $code
