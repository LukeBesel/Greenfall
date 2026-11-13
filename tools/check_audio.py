#!/usr/bin/env python3
"""[v8snd] Checks the game's synthesized sounds and recorded mixes for the defects that make
laptop speakers rattle or crackle.

  # every built-in sound (written by tools/dump_audio.gd first)
  godot --headless --path . -s tools/dump_audio.gd
  python3 tools/check_audio.py                       # reads screenshots/audio_dump/manifest.json
  # a recording of the real mix (--audio-capture on a run, see docs/ADJUSTING.md)
  python3 tools/check_audio.py --wav screenshots/audio_capture/master.wav [--seg 10]
  # retriggers: a --sound-log run's summary (no sound machine-guns or stacks)
  python3 tools/check_audio.py --sound-log screenshots/sound_log_summary.json

Per sound: peak (dBFS), samples at full scale, DC offset, share of energy below 80 Hz and
80-200 Hz, clicks per second (single-sample steps far above the local signal), loop seam step
(for loops: the jump from the last sample back to the first), and the depth of a steady 15-80 Hz
tremolo (a purr or buzz there reads as a helicopter / rattle on laptop speakers). Exit 1 if any limit is broken.
Needs numpy (scipy optional, used for nicer spectra when present).
"""
import argparse
import json
import re
import os
import sys
import wave

import numpy as np

# Limits. "bed": loops that play for minutes (ambience beds, beam hum); "note": score instruments
# (short, transposed); "shot": one-shot SFX.
LIMITS = {
    "bed": {"peak": 0.99, "dc": 0.01, "sub80": 0.25, "clicks_s": 2.0, "seam": 0.05, "flutter": 0.3},
    "note": {"peak": 0.99, "dc": 0.02, "sub80": 0.6, "clicks_s": 4.0, "seam": 0.08, "flutter": 1.5},
    "shot": {"peak": 0.99, "dc": 0.03, "sub80": 0.7, "clicks_s": 40.0, "seam": 1.0, "flutter": 1.0},
    "animal": {"peak": 0.99, "dc": 0.02, "sub80": 0.15, "clicks_s": 10.0, "seam": 1.0, "flutter": 0.45, "b80_200": 0.45},
    "mix": {"peak": 0.995, "dc": 0.01, "sub80": 0.30, "clicks_s": 2.0, "seam": 1.0, "flutter": 0.5},
}
# Instruments that are meant to be deep (a kick, a sub bass): only clipping / DC / clicks apply.
# The Master bus high-pass (data/sound.json master_highpass_hz) trims what is under it.
DEEP = {"music_kick", "music_sub", "music_bass", "music_bass_short", "music_conga_lo",
        "sfx_crunch", "sfx_thunk", "sfx_clunk", "sfx_hydraulic", "sfx_groan", "sfx_thud", "sfx_boom", "sfx_rumble"}


def read_wav(path):
    with wave.open(path, "rb") as w:
        rate = w.getframerate()
        ch = w.getnchannels()
        width = w.getsampwidth()
        raw = w.readframes(w.getnframes())
    if width == 2:
        x = np.frombuffer(raw, dtype="<i2").astype(np.float64) / 32768.0
    elif width == 1:
        x = (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    else:
        x = np.frombuffer(raw, dtype="<i4").astype(np.float64) / 2147483648.0
    if ch > 1:
        x = x.reshape(-1, ch).mean(axis=1)
    return rate, x


def band_shares(x, rate):
    if len(x) < 64:
        return 0.0, 0.0
    n = 1 << int(np.ceil(np.log2(min(len(x), rate * 4))))
    seg = x[: (len(x) // n) * n].reshape(-1, n) if len(x) >= n else np.pad(x, (0, n - len(x)))[None, :]
    win = np.hanning(n)
    p = np.zeros(n // 2 + 1)
    for s in seg:
        p += np.abs(np.fft.rfft((s - s.mean()) * win)) ** 2
    f = np.fft.rfftfreq(n, 1.0 / rate)
    tot = p[f >= 10].sum() + 1e-30
    return p[(f >= 10) & (f < 80)].sum() / tot, p[(f >= 80) & (f < 200)].sum() / tot


def clicks_per_s(x, rate):
    """Single-sample steps far above what the signal around them does (impulses, crackle)."""
    if len(x) < 256:
        return 0.0
    d = np.abs(np.diff(x))
    k = max(int(rate * 0.01), 8)  # 10 ms local level
    loc = np.convolve(d, np.ones(k) / k, mode="same")
    hits = (d > 6.0 * loc) & (d > 0.002)  # relative, so it works on quiet mix recordings too
    # count each burst once
    idx = np.flatnonzero(hits)
    if idx.size == 0:
        return 0.0
    n = 1 + int((np.diff(idx) > int(rate * 0.002)).sum())
    return n / (len(x) / rate)


def flutter(x, rate):
    """Depth of a steady 15-80 Hz tremolo (a purr, a buzz, a helicopter chop): the amplitude of
    the strongest sinusoid in that band of the envelope, relative to the mean envelope (0..1+).
    Only counted when it stands well clear of the envelope's random wobble (noise beds)."""
    if len(x) < rate // 4:
        return 0.0
    hop = max(rate // 400, 1)  # ~400 Hz envelope rate
    m = len(x) // hop
    env = np.sqrt((x[: m * hop].reshape(m, hop) ** 2).mean(axis=1))
    mean = env.mean()
    if mean < 1e-6:
        return 0.0
    e = (env - mean) / mean
    X = np.abs(np.fft.rfft(e * np.hanning(len(e)))) * 2.0 / (0.5 * len(e))
    f = np.fft.rfftfreq(len(e), hop / rate)
    band = (f >= 15) & (f < 80)
    if not band.any():
        return 0.0
    peak = X[band].max()
    if peak * peak < 12.0 * np.median(X[band] ** 2):
        return 0.0  # no steady tremolo, just noise
    return float(peak)


def seam_step(x, loop_begin, loop_end):
    if loop_end <= loop_begin + 2 or loop_end > len(x):
        return 0.0
    # jump at the wrap vs. the typical step there
    jump = abs(x[loop_end - 1] - x[loop_begin])
    typ = np.abs(np.diff(x[max(loop_begin, loop_end - 64): loop_end])).mean() if loop_end > 64 else 0.0
    return max(0.0, jump - 2.0 * typ)


def measure(x, rate, loop=False, lb=0, le=0):
    pk = float(np.abs(x).max()) if len(x) else 0.0
    sub, low = band_shares(x, rate)
    return {
        "peak": pk,
        "peak_db": 20 * np.log10(pk + 1e-12),
        "rms_db": 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-12) if len(x) else -240.0,
        "fs": int((np.abs(x) >= 0.985).sum()),
        "dc": float(x.mean()) if len(x) else 0.0,
        "sub80": sub,
        "b80_200": low,
        "clicks_s": clicks_per_s(x, rate),
        "seam": seam_step(x, lb, le if le > 0 else len(x)) if loop else 0.0,
        "flutter": flutter(x, rate),
    }


def judge(name, kind, m):
    lim = LIMITS[kind]
    bad = []
    if m["peak"] > lim["peak"]:
        bad.append("peak %.3f" % m["peak"])
    if abs(m["dc"]) > lim["dc"]:
        bad.append("dc %+.4f" % m["dc"])
    if kind in ("bed", "mix") and m["clicks_s"] > lim["clicks_s"]:  # tonal shots step on purpose
        bad.append("clicks %.1f/s" % m["clicks_s"])
    if re.sub(r"_\d+$", "", name) not in DEEP:
        if m["sub80"] > lim["sub80"]:
            bad.append("sub-80 Hz %.0f%%" % (m["sub80"] * 100))
        # a steady 15-80 Hz chop matters when the sound is bass-heavy (a helicopter / rattle)
        if m["flutter"] > lim["flutter"] and m["sub80"] + m["b80_200"] > 0.35:
            bad.append("15-80 Hz tremolo depth %.2f" % m["flutter"])
    if "b80_200" in lim and m["b80_200"] > lim["b80_200"]:
        bad.append("80-200 Hz %.0f%%" % (m["b80_200"] * 100))
    if m["seam"] > lim["seam"]:
        bad.append("loop seam step %.3f" % m["seam"])
    return bad


def row(name, kind, m, bad):
    return "%-26s %-4s pk %6.1f rms %6.1f fs %4d dc %+.4f <80 %3.0f%% 80-200 %3.0f%% clk %5.1f/s seam %.3f trem %4.2f  %s" % (
        name, kind, m["peak_db"], m["rms_db"], m["fs"], m["dc"], m["sub80"] * 100, m["b80_200"] * 100,
        m["clicks_s"], m["seam"], m["flutter"], ("FAIL " + ", ".join(bad)) if bad else "ok")


def check_dump(d):
    with open(os.path.join(d, "manifest.json")) as f:
        items = json.load(f)
    fails = 0
    for it in items:
        rate, x = read_wav(os.path.join(d, it["file"]))
        kind = it["kind"]
        m = measure(x, rate, it["loop"], int(it.get("loop_begin", 0)), int(it.get("loop_end", 0)))
        bad = judge(it["name"], kind, m)
        fails += bool(bad)
        if bad or kind in ("bed", "animal") or VERBOSE:
            print(row(it["name"], kind, m, bad))
    print("[check_audio] %d sounds, %d failing" % (len(items), fails))
    return fails


def check_mix(path, seg):
    rate, x = read_wav(path)
    print("== %s: %.1f s" % (path, len(x) / rate))
    fails = 0
    n = int(seg * rate)
    for s in range(0, len(x), n):
        c = x[s: s + n]
        if len(c) < rate:
            break
        if np.sqrt((c ** 2).mean()) < 1e-4:
            print("%5.0fs  quiet" % (s / rate))
            continue
        m = measure(c, rate)
        bad = judge("mix", "mix", m)
        fails += bool(bad)
        print(row("%5.0fs" % (s / rate), "mix", m, bad))
    m = measure(x, rate)
    print(row("whole", "mix", m, judge("mix", "mix", m)))
    return fails


# Retrigger caps for a --sound-log summary (screenshots/sound_log_summary.json): no sound may
# start more than this many times a game minute on average, or stack more copies than this.
MAX_PER_MIN = 90.0
MAX_STACK = 4


def check_log(path):
    with open(path) as f:
        log = json.load(f)
    fails = 0
    for nm, r in sorted(log.get("sounds", {}).items(), key=lambda kv: -kv[1].get("per_min", 0)):
        bad = []
        if r.get("per_min", 0) > MAX_PER_MIN:
            bad.append("%.0f plays a minute" % r["per_min"])
        if r.get("stack", 0) > MAX_STACK:
            bad.append("%d at once" % r["stack"])
        fails += bool(bad)
        if bad or VERBOSE:
            print("%-30s %-9s %6.1f/min stack %d  %s" % (nm, r.get("bus", ""), r.get("per_min", 0), r.get("stack", 0), ("FAIL " + ", ".join(bad)) if bad else "ok"))
    print("[check_audio] sound log %s: %.1f min, %d sounds, %d failing" % (path, log.get("minutes", 0), len(log.get("sounds", {})), fails))
    return fails


# [v9s] Repetition rules for a --sound-log log file (screenshots/sound_log.txt, one row per play with
# its variant and pitch). Owner, 2026-11-13: "its super annoying to hear the same bird chirp so many
# times over and over ... lively but just peaceful". Per sound: plays a minute, gaps, how many takes
# it has, the longest run of the same take, how regular its spacing is, and an annoyance score.
# Category of a sound (first regex that matches its name; tags like "scoop:clink" included).
CATS = [
    ("bird", r"^(song|chirp|coo|gull|quack|bird|heron)$"),
    ("animal", r"^(frog|meow|seal|purr|flutter|ice_creak)$"),
    ("ambience", r"^(amb_|life_|LifeAmbience)"),
    ("robot", r"^(robot:|bot:)"),
]
# Caps per category: max plays a minute of one sound; max same take back to back (any pitch) for
# sounds with more than one take; min gap regularity (coefficient of variation of the gaps under
# 60 s; a metronome is 0) once a sound has 8 such gaps, or None to skip; category total a minute.
REPEAT_RULES = {
    "bird":     {"per_min": 3.0, "streak": 1, "cv": 0.25, "total": 4.0},
    "animal":   {"per_min": 4.0, "streak": 1, "cv": 0.25, "total": 8.0},
    "ambience": {"per_min": 2.0, "streak": 2, "cv": 0.2, "total": 4.0},
    "robot":    {"per_min": 30.0, "streak": 3, "cv": 0.15, "total": 60.0},
    "ui":       {"per_min": 90.0, "streak": None, "cv": None, "total": None},
    "action":   {"per_min": 90.0, "streak": None, "cv": None, "total": None},
}
# A sound played more often than this a minute must have this many takes, or this pitch spread
# (p90 / p10 of its pitch scale - 1): the same exact sound over and over is what a player notices.
BUSY_PER_MIN = 10.0
MIN_TAKES = 3
MIN_PITCH_SPREAD = 0.06
# Same take at the same pitch (within 1%) back to back, within 10 s: at most this many in a row.
MAX_SAME_RUN = 4
# Loops and beds (a restart is not a repeat a player hears as one).
LOOPS = r"(/Loop_|/Life_|^song:|^sting:)"
# Sounds the player starts one by one with a key (story, menus) are not judged for spacing.


def category(name, bus):
    for cat, rx in CATS:
        if re.search(rx, name):
            return cat
    if bus == "UI":
        return "ui"
    return "action"


def load_log(path):
    rows = []
    with open(path) as f:
        head = f.readline().rstrip("\n").split("\t")
        for line in f:
            c = line.rstrip("\n").split("\t")
            if len(c) < 5:
                continue
            r = dict(zip(head, c))
            try:
                rows.append((float(r["game_s"]), r["sound"], r.get("bus", ""), float(r.get("db", -99)),
                             r.get("variant", ""), float(r.get("pitch", 1.0) or 1.0), r.get("from", "")))
            except ValueError:
                continue
    return rows


def repeat_stats(rows, skip_s=0.0):
    rows = [r for r in rows if r[0] >= skip_s]
    if not rows:
        return 0.0, {}
    t0 = rows[0][0]
    minutes = max((rows[-1][0] - t0) / 60.0, 0.5)
    by = {}
    for r in rows:
        by.setdefault(r[1], []).append(r)
    out = {}
    for nm, rs in by.items():
        ts = [r[0] for r in rs]
        gaps = [b - a for a, b in zip(ts, ts[1:])]
        short = [g for g in gaps if g < 60.0]
        cv = None
        if len(short) >= 8:
            m = float(np.mean(short))
            cv = float(np.std(short) / m) if m > 0 else 0.0
        vars_ = [r[4] for r in rs]
        pitches = np.array([r[5] for r in rs])
        takes = len(set(v for v in vars_ if v)) or 1
        spread = float(np.percentile(pitches, 90) / max(np.percentile(pitches, 10), 1e-3) - 1.0) if len(rs) > 2 else 0.0
        streak = run = 1
        same = srun = 1
        for a, b in zip(rs, rs[1:]):
            run = run + 1 if (a[4] == b[4] and a[4] != "") else 1
            streak = max(streak, run)
            srun = srun + 1 if (a[4] == b[4] and abs(b[5] / max(a[5], 1e-3) - 1.0) < 0.01 and b[0] - a[0] < 10.0) else 1
            same = max(same, srun)
        bus = rs[0][2]
        db = float(np.mean([r[3] for r in rs]))
        per_min = len(rs) / minutes
        cat = category(nm, bus)
        # Annoyance: how often x how loud x how alike x how regular x how long the same take runs.
        level = 10 ** (max(min(db, 0.0), -40.0) / 20.0) * (0.5 if bus == "UI" else 1.0)
        alike = 1.0 / np.sqrt(takes * (1.0 + spread / 0.03))
        regular = 1.0 + (max(0.0, 0.4 - cv) * 2.5 if cv is not None else 0.0)
        score = per_min * level * alike * regular * (1.0 + (streak - 1) / 4.0) * 10.0
        out[nm] = {"cat": cat, "bus": bus, "n": len(rs), "per_min": per_min, "min_gap": min(gaps) if gaps else -1.0,
                   "med_gap": float(np.median(gaps)) if gaps else -1.0, "cv": cv, "takes": takes, "spread": spread,
                   "streak": streak, "same_run": same, "db": db, "score": score}
    return minutes, out


def check_repeat(path, skip_s, out_json=""):
    minutes, st = repeat_stats(load_log(path), skip_s)
    fails = 0
    totals = {}
    print("== %s: %.1f game minutes" % (path, minutes))
    print("%-24s %-8s %5s %6s %7s %7s %5s %6s %6s %4s %6s %7s  %s" % ("sound", "cat", "plays", "/min", "mingap", "medgap", "cv",
          "takes", "pitch%", "run", "avg dB", "annoy", "verdict"))
    for nm, r in sorted(st.items(), key=lambda kv: -kv[1]["score"]):
        rule = REPEAT_RULES[r["cat"]]
        totals[r["cat"]] = totals.get(r["cat"], 0.0) + r["per_min"]
        bad = []
        if r["per_min"] > rule["per_min"] and r["n"] >= 4:
            bad.append("%.1f/min > %.0f" % (r["per_min"], rule["per_min"]))
        if rule["streak"] is not None and r["takes"] > 1 and r["streak"] > rule["streak"]:
            bad.append("same take %dx running" % r["streak"])
        if rule["cv"] is not None and r["cv"] is not None and r["cv"] < rule["cv"]:
            bad.append("metronome (cv %.2f)" % r["cv"])
        if r["per_min"] > BUSY_PER_MIN and r["takes"] < MIN_TAKES and r["spread"] < MIN_PITCH_SPREAD:
            bad.append("busy with %d take(s), pitch spread %.0f%%" % (r["takes"], r["spread"] * 100))
        if r["same_run"] > MAX_SAME_RUN and not re.search(LOOPS, nm):
            bad.append("identical %dx in a row" % r["same_run"])
        fails += bool(bad)
        print("%-24s %-8s %5d %6.2f %7.2f %7.2f %5s %6d %6.0f %4d %6.1f %7.2f  %s" % (nm[:24], r["cat"], r["n"], r["per_min"], r["min_gap"],
              r["med_gap"], ("%.2f" % r["cv"]) if r["cv"] is not None else "-", r["takes"], r["spread"] * 100, r["streak"], r["db"], r["score"],
              ("FAIL " + "; ".join(bad)) if bad else "ok"))
    for cat, tot in sorted(totals.items()):
        cap = REPEAT_RULES[cat]["total"]
        bad = cap is not None and tot > cap
        fails += bad
        print("[check_audio] %-8s all sounds %.2f a minute%s" % (cat, tot, ("  FAIL > %.0f" % cap) if bad else ""))
    if out_json:
        with open(out_json, "w") as f:
            json.dump({"minutes": minutes, "sounds": st, "totals": totals}, f, indent=1)
    print("[check_audio] repetition %s: %d failing" % (path, fails))
    return fails


VERBOSE = False

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="screenshots/audio_dump")
    ap.add_argument("--wav", action="append", default=[])
    ap.add_argument("--sound-log", default="", help="a --sound-log summary json: retrigger caps")
    ap.add_argument("--seg", type=float, default=10.0)
    ap.add_argument("--repeat", default="", help="[v9s] a --sound-log log file (sound_log.txt): repetition rules")
    ap.add_argument("--skip", type=float, default=20.0, help="--repeat: ignore the first S game seconds (loading, intro)")
    ap.add_argument("--json", default="", help="--repeat: also write the table as json")
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    VERBOSE = a.v
    bad = 0
    if a.repeat:
        bad += check_repeat(a.repeat, a.skip, a.json)
    elif a.sound_log:
        bad += check_log(a.sound_log)
    elif a.wav:
        for p in a.wav:
            bad += check_mix(p, a.seg)
    else:
        bad += check_dump(a.dir)
    sys.exit(1 if bad else 0)
