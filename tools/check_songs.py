#!/usr/bin/env python3
"""[v6sound] Song check for the owner: run it after adding songs.

    python3 tools/check_songs.py            # the short report
    python3 tools/check_songs.py --all      # also list every song still waiting for a file
    python3 tools/check_songs.py --planet=verdance   # only that planet's playlist

Lists every entry of data/songs.json and whether its audio file is in audio/songs/ (or a planet
folder below it), the files that have no entry (they play with the defaults), and each planet's
playlist. Mistakes (unknown planet, unknown moment, two files for one song) are marked "!!".
Exit code 1 only when there is a mistake; songs still waiting for a file are fine.
The rules are the same as systems/tunes.gd (scan_files, default_entry, moments, on_planet).
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data", "songs.json")
SONG_DIR = os.path.join(ROOT, "audio", "songs")
EXTS = ("mp3", "ogg", "wav")
MOMENTS = ["title", "intro", "explore", "night", "restored", "base_restored", "launch", "ending"]


def slug(name):
    base = name.rsplit(".", 1)[0].lower()
    return re.sub(r"_+", "_", re.sub(r"[^a-z0-9]", "_", base)).strip("_")


def scan(song_dir):
    """{id: (relative path, folder, base name)}, plus [(id, kept, extra)] for doubles."""
    out, doubles = {}, []
    folders = [""] + sorted(f for f in os.listdir(song_dir) if os.path.isdir(os.path.join(song_dir, f)))
    for folder in folders:
        base = os.path.join(song_dir, folder)
        for f in sorted(os.listdir(base)):
            if f.rsplit(".", 1)[-1].lower() not in EXTS or not os.path.isfile(os.path.join(base, f)):
                continue
            sid = slug(f)
            rel = os.path.join(folder, f) if folder else f
            if not sid:
                continue
            if sid in out:
                doubles.append((sid, out[sid][0], rel))
                continue
            out[sid] = (rel, folder, f.rsplit(".", 1)[0])
    return out, doubles


def moments_of(s):
    m = s.get("moments")
    if isinstance(m, str):
        return [m]
    if isinstance(m, list):
        return m
    if not s.get("shuffle", True):
        return ["title"]
    return {"night": ["title", "night"], "restored": ["title", "restored"]}.get(s.get("kind", "playlist"), ["title", "explore", "night"])


def planets_of(s):
    p = s.get("planets")
    if isinstance(p, str):
        return [p]
    return p if isinstance(p, list) else []


def where(s, planet_ids, cfg):
    """Planets a song plays on in the background, as text."""
    ps = planets_of(s)
    listed = [p for p in planet_ids if s["id"] in cfg.get("planets", {}).get(p, {}).get("songs", [])]
    if ps:
        return "everywhere" if "all" in ps else ", ".join(ps + [p for p in listed if p not in ps])
    g = s.get("group", "")
    if g in planet_ids:
        if s.get("kind") in ("night", "restored"):
            return ", ".join([g] + [p for p in listed if p != g])
        return g + " (rarely elsewhere)"
    return "everywhere"


def on_planet(s, planet, cfg):
    ps = planets_of(s)
    if ps:
        return "all" in ps or planet in ps
    return s.get("group") == planet or s["id"] in cfg.get("planets", {}).get(planet, {}).get("songs", [])


def main():
    show_all = "--all" in sys.argv
    only = next((a.split("=", 1)[1] for a in sys.argv if a.startswith("--planet=")), "")
    cfg = json.load(open(DATA, encoding="utf-8"))
    planet_ids = [k for k in cfg.get("planets", {}) if not k.startswith("_")] or ["verdance", "ochre", "tidewell", "rime", "anvil"]
    files, doubles = scan(SONG_DIR)
    songs = cfg.get("songs", [])
    by_file = {slug(os.path.basename(s["file"])): s["id"] for s in songs if "file" in s}
    file_of = {by_file.get(fid, fid): v for fid, v in files.items()}
    ids = [s["id"] for s in songs]
    problems = []

    for sid in sorted(set(i for i in ids if ids.count(i) > 1)):
        problems.append("song id listed twice in data/songs.json: %s" % sid)
    for sid, kept, extra in doubles:
        problems.append("two files for one song (%s): using %s, ignoring %s" % (sid, kept, extra))
    for s in songs:
        for m in moments_of(s):
            if m not in MOMENTS:
                problems.append("%s: unknown moment \"%s\" (use: %s)" % (s["id"], m, ", ".join(MOMENTS)))
        for p in planets_of(s):
            if p != "all" and p not in planet_ids:
                problems.append("%s: unknown planet \"%s\" (use: all, %s)" % (s["id"], p, ", ".join(planet_ids)))
        if s.get("unlock", "cd") not in ("start", "cd"):
            problems.append("%s: unlock must be start or cd" % s["id"])
        if s.get("unlock", "cd") == "cd" and s["id"] in file_of and not s.get("found_on"):
            problems.append("%s: a CD needs \"found_on\": the planet it is found on" % s["id"])
        if s.get("artist") and s["artist"] not in [a["id"] for a in cfg.get("artists", [])]:
            problems.append("%s: unknown artist \"%s\"" % (s["id"], s["artist"]))
    for p in planet_ids:
        for sid in cfg["planets"].get(p, {}).get("songs", []) if "planets" in cfg else []:
            if sid not in ids and sid not in file_of:
                problems.append("planets.%s.songs lists \"%s\", which is not a song" % (p, sid))
    main_theme = cfg.get("main_theme", "greenfall_main")
    if main_theme not in file_of:
        problems.append("the main theme (%s) has no file" % main_theme)

    have = [s for s in songs if s["id"] in file_of]
    waiting = [s for s in songs if s["id"] not in file_of]
    autos = [fid for fid in file_of if fid not in ids]

    def row(s, mark):
        f = file_of.get(s["id"])
        trim = s.get("volume_db", 0)
        return "  %s %-24s %-30s %-28s %-26s %s%s%s" % (
            mark, s["id"], s.get("title", "")[:30], (f[0] if f else "(no file yet)")[:28], where(s, planet_ids, cfg)[:26],
            "+".join(moments_of(s)), "  from the start" if s.get("unlock", "cd") == "start" else "  CD on %s" % s.get("found_on", "?"),
            ("  x%g" % s["weight"] if s.get("weight", 1) != 1 else "") + ("  %+g dB" % trim if trim else ""))

    if not only:
        print("Songs with a file (%d of %d listed):" % (len(have), len(songs)))
        print("     %-24s %-30s %-28s %-26s %s" % ("id", "title", "file", "plays on", "moments, unlock"))
        for s in have:
            print(row(s, "ok"))
        print()
        print("Files with no entry (%d): they play with the defaults (owned from the start)." % len(autos))
        for fid in autos:
            rel, folder, name = file_of[fid]
            print("  ++ %-24s %-30s %-28s %s" % (fid, name[:30], rel[:28], folder if folder in planet_ids else "everywhere"))
        print()
        print("Listed songs still waiting for a file: %d%s" % (len(waiting), "" if show_all else "  (--all lists them)"))
        if show_all:
            for s in waiting:
                print(row(s, "--"))
        print()

    print("Playlists (songs that have a file; * = owned from the start, others are CDs to find):")
    for p in planet_ids:
        if only and p != only:
            continue
        names = []
        for s in have:
            ms = moments_of(s)
            if on_planet(s, p, cfg) and any(m in ms for m in ("explore", "night", "restored")) and s.get("weight", 1) > 0:
                names.append(s["id"] + ("*" if s.get("unlock", "cd") == "start" else ""))
        for fid in autos:
            folder = file_of[fid][1]
            if folder == p or folder not in planet_ids:
                names.append(fid + "*")
        everywhere = [s["id"] for s in have if not planets_of(s) and s.get("group") not in planet_ids and s.get("shuffle", True)
                      and any(m in moments_of(s) for m in ("explore", "night"))]
        rules = {k: v for k, v in cfg.get("planets", {}).get(p, {}).items() if k != "songs"}
        print("  %-9s %2d: %s" % (p, len(names), ", ".join(names) if names else "(none yet: the built-in score plays)"))
        if everywhere:
            print("            plus, from everywhere: %s" % ", ".join(everywhere))
        if rules:
            print("            its own rules: %s" % json.dumps(rules))
    for m in ("title", "intro", "base_restored", "launch", "ending"):
        got = [s["id"] for s in have if m in moments_of(s)]
        if m == "title":
            print("  title screen: %d songs (the ones you own), %s first" % (len(got) + len(autos), main_theme))
        else:
            print("  %-13s %s" % (m + ":", ", ".join(got) if got else "(no song marked: the built-in score plays)"))
    print()
    print("Rules: gaps %s s, after a load %s s, after landing %s s, main theme share %s, song level %s dB" % (
        cfg.get("gap_s"), cfg.get("first_gap_s"), cfg.get("landing_gap_s"), cfg.get("main_share"), cfg.get("song_db", -7.0)))
    if problems:
        print()
        print("Mistakes to fix (%d):" % len(problems))
        for pr in problems:
            print("  !! " + pr)
        return 1
    print("No mistakes found.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
