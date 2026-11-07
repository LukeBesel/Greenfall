#!/usr/bin/env python3
"""Writes docs/steam/achievements.csv and docs/steam/stats.csv from data/achievements.json and
data/steam.json, in the order and with the fields Steamworks asks for (App Admin > Stats &
Achievements). Run from the repo root after changing achievements:  python3 tools/steam/export_steam_csv.py
"""
import csv
import json
import os

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
ach = json.load(open(os.path.join(ROOT, "data/achievements.json")))["achievements"]
cfg = json.load(open(os.path.join(ROOT, "data/steam.json")))
stats = {s["key"]: s for s in cfg["stats"]}
out_dir = os.path.join(ROOT, "docs/steam")
os.makedirs(out_dir, exist_ok=True)

with open(os.path.join(out_dir, "achievements.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["api_name", "display_name", "description", "hidden", "set_by", "progress_stat", "progress_min", "progress_max", "game_id", "icon_hint"])
    for a in ach:
        c = a.get("cond", {})
        hidden = bool(a.get("hidden")) or str(c.get("key", "")).startswith("egg_")
        prog, pmin, pmax = "", "", ""
        if c.get("type") == "stat" and c.get("key") in stats:
            s = stats[c["key"]]
            prog, pmin = s["api"], 0
            pmax = int(round(float(c.get("target", 1)) * float(s.get("scale", 1.0))))
            if pmax <= 1:
                prog, pmin, pmax = "", "", ""
        w.writerow([a["id"].upper(), a["name"], a["desc"], "yes" if hidden else "no", "Client", prog, pmin, pmax, a["id"], a.get("icon", "")])

with open(os.path.join(out_dir, "stats.csv"), "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["api_name", "type", "display_name", "set_by", "increment_only", "default", "game_key"])
    for s in cfg["stats"]:
        w.writerow([s["api"], s["type"], s["name"], "Client", "yes", 0, s["key"]])

print("wrote %d achievements, %d stats to %s" % (len(ach), len(cfg["stats"]), out_dir))
