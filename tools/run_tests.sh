#!/usr/bin/env bash
# Runs all GUT unit tests headless. Exit code is non-zero on failure.
set -e
cd "$(dirname "$0")/.."
godot --headless --import --path . >/dev/null 2>&1 || true
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -glog=1 "$@"
