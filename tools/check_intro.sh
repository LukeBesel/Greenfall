#!/usr/bin/env bash
# [v9intro] The opening film must leave the same world however it ends: watched to the end, or
# skipped at the start, in the middle of the fall, just before the crash, and after it (hatch).
# Each case is a headless run of the real game; the film prints its end state and they must match.
#   tools/check_intro.sh           all five cases (about 8 minutes)
#   tools/check_intro.sh --quick   watched + skipped just before the crash
# Logs: screenshots/check_intro_*.log. Exit 1 on a difference, a script error or a crash.
cd "$(dirname "$0")/.."
mkdir -p screenshots
GD=${GODOT_WRAPPER:-godot}
cases="watch:-1 start:0.3 fall:68 pre_impact:IMPACT hatch:HATCH"
[ "$1" = "--quick" ] && cases="watch:-1 pre_impact:IMPACT"
fail=0
ref=""
for c in $cases; do
	name=${c%%:*}; at=${c##*:}
	log="screenshots/check_intro_${name}.log"
	args="--fresh --orbit --intro --intro-quit --quit-after=900 --save-dir=check_intro_$$"
	if [ "$at" = "IMPACT" ] || [ "$at" = "HATCH" ]; then
		# Times come from the table: 0.1 s before the hit, and 2 s into the hatch shot.
		at=$(python3 - "$at" "$ref_log" <<'PY'
import re, sys
want, log = sys.argv[1], sys.argv[2]
t = {}
for line in open(log, errors="replace"):
    m = re.match(r"\[intro\] shot (\S+)\s+([\d.]+) -\s+([\d.]+) s", line)
    if m:
        t[m.group(1)] = float(m.group(2))
import json
p = {s["id"]: s for s in json.load(open("data/intro_shots.json"))["shots"]}
print("%.2f" % (t["impact"] + p["impact"]["p"]["hit_at"] - 0.1 if want == "IMPACT" else t["hatch"] + 2.0))
PY
)
	fi
	[ "$at" != "-1" ] && args="$args --intro-skip-at=$at"
	$GD --headless --path . --fixed-fps 10 -- $args >"$log" 2>&1
	code=$?
	[ -z "$ref_log" ] && ref_log="$log"
	state=$(grep -a "^\[intro\] end state:" "$log" | tail -1 | sed 's/^\[intro\] end state: //')
	if [ "$code" -ne 0 ] || grep -aq "SCRIPT ERROR" "$log" || [ -z "$state" ]; then
		echo "[check_intro] FAIL $name: exit $code, script error or no end state (see $log)"
		grep -a -m5 -A2 "SCRIPT ERROR" "$log"
		fail=1
		continue
	fi
	if [ -z "$ref" ]; then
		ref="$state"
		python3 - "$state" <<'PY' || fail=1
import json, sys
s = json.loads(sys.argv[1])
want = {"lumi_visible": True, "eyes_open": True, "pod_placed": True, "hatch_open": True, "hud": True,
        "game_camera": True, "intro_done": True, "tunes": "play", "busy": False}
bad = {k: s.get(k) for k, v in want.items() if s.get(k) != v}
if bad:
    print("[check_intro] FAIL watch: wrong end state %s" % bad)
    sys.exit(1)
PY
		echo "[check_intro] PASS $name: $state"
	elif [ "$state" != "$ref" ]; then
		echo "[check_intro] FAIL $name (skip at $at s): the world differs from the watched film"
		echo "  watched: $ref"
		echo "  skipped: $state"
		fail=1
	else
		echo "[check_intro] PASS $name (skip at $at s): same world as the watched film"
	fi
done
exit $fail
