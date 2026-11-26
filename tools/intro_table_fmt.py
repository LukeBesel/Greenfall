#!/usr/bin/env python3
"""Rewrites data/intro_shots.json in its house layout (one line per camera / cue list)."""
import json
import sys

P = sys.argv[1] if len(sys.argv) > 1 else "data/intro_shots.json"
d = json.load(open(P))
out = ["{"]
for k in d:
    if k != "shots":
        out.append("  %s: %s," % (json.dumps(k), json.dumps(d[k])))
out.append('  "shots": [')
rows = []
for s in d["shots"]:
    head = {k: s[k] for k in s if k not in ("cam", "lines", "sfx", "cues", "p")}
    items = ["      " + ", ".join("%s: %s" % (json.dumps(k), json.dumps(v)) for k, v in head.items())]
    for k in ("cam", "lines", "sfx", "cues", "p"):
        if k in s:
            items.append("      %s: %s" % (json.dumps(k), json.dumps(s[k])))
    rows.append("    {\n" + ",\n".join(items) + "\n    }")
out.append(",\n".join(rows))
out.append("  ]")
out.append("}")
text = "\n".join(out) + "\n"
json.loads(text)
open(P, "w").write(text)
