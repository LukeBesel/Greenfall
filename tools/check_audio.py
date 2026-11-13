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


VERBOSE = False

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="screenshots/audio_dump")
    ap.add_argument("--wav", action="append", default=[])
    ap.add_argument("--sound-log", default="", help="a --sound-log summary json: retrigger caps")
    ap.add_argument("--seg", type=float, default=10.0)
    ap.add_argument("-v", action="store_true")
    a = ap.parse_args()
    VERBOSE = a.v
    bad = 0
    if a.sound_log:
        bad += check_log(a.sound_log)
    elif a.wav:
        for p in a.wav:
            bad += check_mix(p, a.seg)
    else:
        bad += check_dump(a.dir)
    sys.exit(1 if bad else 0)
