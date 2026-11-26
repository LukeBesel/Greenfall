#!/usr/bin/env python3
"""Level / cleanliness report for WAVs rendered by tools/render_music.gd.

Usage: python3 tools/check_music_wav.py screenshots/music_*.wav
Prints peak and RMS (dBFS), loudest 3 s window, share of energy above 6 kHz, and a click score
(largest second-difference spike relative to the local RMS). Exit code 1 if anything clips.
"""
import math
import struct
import sys
import wave


def analyse(path):
    with wave.open(path, "rb") as w:
        n, rate, ch, width = w.getnframes(), w.getframerate(), w.getnchannels(), w.getsampwidth()
        raw = w.readframes(n)
    assert width == 2, "expected 16-bit"
    x = [s / 32768.0 for s in struct.unpack("<%dh" % (n * ch), raw)][::ch]
    peak = max(abs(s) for s in x)
    rms = math.sqrt(sum(s * s for s in x) / len(x))
    win = rate * 3
    loud = max(
        math.sqrt(sum(s * s for s in x[i:i + win]) / win) for i in range(0, max(1, len(x) - win), win // 2)
    )
    # High band energy: difference of a heavy one-pole low-pass (~6 kHz at 22.05 kHz).
    a = 1.0 - math.exp(-2 * math.pi * 6000.0 / rate)
    lp, hi_e, tot_e = 0.0, 0.0, 0.0
    for s in x:
        lp += (s - lp) * a
        hi_e += (s - lp) ** 2
        tot_e += s * s
    # Click score: |second difference| vs. RMS of the surrounding 50 ms.
    blk = rate // 20
    click = 0.0
    for b in range(0, len(x) - blk, blk):
        seg = x[b:b + blk]
        r = math.sqrt(sum(s * s for s in seg) / blk) + 1e-4
        d2 = max(abs(seg[i + 1] - 2 * seg[i] + seg[i - 1]) for i in range(1, blk - 1))
        click = max(click, d2 / r)
    db = lambda v: 20 * math.log10(max(v, 1e-9))
    return peak, db(peak), db(rms), db(loud), 100.0 * hi_e / max(tot_e, 1e-12), click, len(x) / rate


def main():
    bad = False
    for p in sys.argv[1:]:
        peak, pk, rms, loud, hi, click, dur = analyse(p)
        bad |= peak >= 0.99
        print(f"{p:38s} {dur:5.1f}s peak {pk:6.1f} dBFS  rms {rms:6.1f} dBFS  loudest3s {loud:6.1f} dBFS"
              f"  >6kHz {hi:5.2f}%  click {click:5.2f}")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
