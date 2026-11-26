#!/usr/bin/env bash
# [v7planet] Planet smoke (docs/NEW_PLANET.md): boots a planet of data/planets.json on its globe,
# walks Lumi, hops to hub 1, wakes it and saves (process 1), then loads the save in a new process
# and checks it came back (process 2). Prints the [smoke] lines; exit 1 on any FAIL or SCRIPT ERROR.
# Usage: tools/planet_smoke.sh testworld [more ids...]   (one godot at a time; about 1-3 min each)
cd "$(dirname "$0")/.."
code=0
for id in "${@:-testworld}"; do
	DIR="planet_smoke_${id}_$$"
	LOG="/tmp/planet_smoke_${id}_$$.log"
	godot --headless --path . -- --fresh --orbit-planet="$id" --no-intro --hop-skip --save-dir="$DIR" --planet-smoke=write > "$LOG" 2>&1
	w=$?
	godot --headless --path . -- --save-dir="$DIR" --no-intro --planet-smoke=read --planet-smoke-want="$id" >> "$LOG" 2>&1
	r=$?
	grep -E "^\[smoke\]|SCRIPT ERROR|^ERROR" "$LOG" | head -60
	if [ $w -ne 0 ] || [ $r -ne 0 ] || grep -q "SCRIPT ERROR" "$LOG" || [ "$(grep -c 'PASS$' "$LOG")" -lt 2 ]; then
		echo "[smoke] $id: FAIL (write exit $w, read exit $r)"
		code=1
	else
		echo "[smoke] $id: PASS"
	fi
	rm -f "$LOG"
	rm -rf "$HOME/.local/share/godot/app_userdata/Greenfall/saves_$DIR" 2>/dev/null
done
exit $code
