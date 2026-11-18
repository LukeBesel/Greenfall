#!/usr/bin/env bash
# [health] Lists GDScript warnings for every project script (addons/ skipped).
#   tools/warnings_audit.sh                 the project's enabled warnings
#   EXTRA=unsafe_property_access,unsafe_method_access tools/warnings_audit.sh   also normally-off ones
# Prints "path:line: message" sorted, then a count per file. Exit code 0 always.
cd "$(dirname "$0")/.."
if [ -e override.cfg ]; then echo "override.cfg already exists; refusing to overwrite it" >&2; exit 2; fi
trap 'rm -f override.cfg' EXIT
godot --headless --path . -s res://tools/warnings_audit.gd -- --list-levels --extra="${EXTRA:-}" 2>/dev/null | grep -E '^\[debug\]|=2$' > override.cfg
timeout 600 godot --headless --path . -s res://tools/warnings_audit.gd 2>&1 | python3 -c '
import sys, re
lines = sys.stdin.read().split("\n")
seen = set()
for i, l in enumerate(lines):
    if "(Warning treated as error.)" not in l:
        continue
    msg = l.split("Parse Error: ", 1)[-1].replace(" (Warning treated as error.)", "")
    loc = lines[i + 1].strip() if i + 1 < len(lines) else ""
    m = re.search(r"\((res://[^)]+)\)", loc)
    key = (m.group(1) if m else loc, msg)
    if key in seen:
        continue
    seen.add(key)
items = sorted(seen, key=lambda k: (k[0].rsplit(":", 1)[0], int(k[0].rsplit(":", 1)[1]) if k[0].rsplit(":", 1)[-1].isdigit() else 0))
for loc, msg in items:
    print("%s: %s" % (loc.replace("res://", ""), msg))
per = {}
for loc, _ in items:
    f = loc.rsplit(":", 1)[0]
    per[f] = per.get(f, 0) + 1
print("\n[warnings_audit] %d warnings in %d files" % (len(items), len(per)))
'
