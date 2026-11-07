#!/usr/bin/env bash
# Runs all GUT unit tests headless, then the save/load round trip. Exit code is non-zero on failure.
# [health] The round trip must also exit cleanly: a crash at quit (e.g. SIGABRT, code 134) fails the run.
# Set SKIP_ROUNDTRIP=1 for a quick unit-test-only run; extra args are passed to GUT.
set -e
cd "$(dirname "$0")/.."
godot --headless --import --path . >/dev/null 2>&1 || true
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -glog=1 "$@"
if [ "${SKIP_ROUNDTRIP:-0}" != "1" ]; then
	tools/check_exit.sh
fi
