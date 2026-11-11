#!/usr/bin/env python3
"""[v6pace] Pacing report from an autoplay run (docs/BALANCE.md, "Measuring a planet's arc").

    python3 tools/cadence.py screenshots/autoplay_report.json [run.log]

run.log is the run's stdout (the `[card]` and `[arc]` lines; `--clarity-log` not needed).
Prints:
  - the arc: when each hub is woken, each rocket tier, the drive, the exit (bot minutes);
  - cubes per minute between those points (lifetime earned / time), and the factor from one to the next;
  - reward cadence: gaps between "something new" moments (an upgrade level, a robot, research done,
    a station or machine, a base level, a hub, a rocket tier, a story step), the longest gaps, and how
    many break the targets (3-6 min in the first hour, 6-10 later, never over MAX_GAP);
  - card waits: how long each card step stayed up, the priced ones flagged (saving for a buy).
"""
import json
import re
import sys

MAX_GAP = 12.0       # minutes without anything new
FIRST_HOUR_GAP = 6.0
LATER_GAP = 10.0
MAX_GRIND = 15.0     # one priced card up longer than this is a wall

NEW_KINDS = {"robot", "research", "station", "tank", "tier", "base", "bench_tier", "build", "signal_tower",
             "scrubber", "composter", "builder", "glim_light", "glim_scan"}


def main() -> None:
    rep = json.load(open(sys.argv[1]))
    log_path = sys.argv[2] if len(sys.argv) > 2 else None
    end = float(rep.get("game_time_s", 0.0)) / 60.0
    moments: list[tuple[float, str]] = []
    for e in rep.get("log", []):
        if e.get("event") == "upgrade":
            moments.append((float(e["t"]) / 60.0, "upgrade %s %s" % (e.get("id"), e.get("level"))))
    for e in rep.get("timeline", []):
        k = str(e.get("kind", ""))
        if k in NEW_KINDS or k.startswith("glim_"):
            moments.append((float(e["t"]) / 60.0, "%s %s" % (k, e.get("id", e.get("type", e.get("tier", ""))))))
    arc: list[tuple[float, str]] = []
    cards: list[tuple[float, str, bool]] = []
    if log_path:
        for line in open(log_path, errors="replace"):
            m = re.match(r"\[card\] ([\d.]+) min  (\S+)  \"([^\"]*)\"(  price)?", line)
            if m:
                t = float(m.group(1))
                cards.append((t, "%s (%s)" % (m.group(2), m.group(3)), m.group(4) is not None))
                moments.append((t, "card %s" % m.group(2)))
            m = re.match(r"\[arc\] ([\d.]+) min  (hub \d+ restored|rocket Mk \d+|built the Mk V drive|PLANET EXIT)", line)
            if m:
                arc.append((float(m.group(1)), m.group(2)))
                moments.append((float(m.group(1)), m.group(2)))
                end = max(end, float(m.group(1)))
    else:
        for k, v in rep.items():
            if re.match(r"(hub_\d+|rocket_tier_\d+|drive_\d+|planet_exit)_s$", k):
                arc.append((float(v) / 60.0, k[:-2]))
    arc.sort()
    moments.sort()
    print("== Arc (bot minutes) ==")
    for t, what in arc:
        print("  %6.1f  %s" % (t, what))
    # Cubes per minute between arc points, from the per-minute log's lifetime earned.
    pts = [(float(e["t"]) / 60.0, float(e["earned"])) for e in rep.get("log", []) if "earned" in e]
    pts.sort()

    def earned_at(t: float) -> float:
        best = 0.0
        for pt, ev in pts:
            if pt <= t:
                best = ev
        return best

    print("== Cubes per minute (lifetime earned / time) ==")
    marks = [(0.0, "start")] + [a for a in arc if a[1].startswith("hub") or a[1].startswith("PLANET")]
    if pts:
        marks.append((pts[-1][0], "end of log"))
    last_rate = 0.0
    for (t0, a), (t1, b) in zip(marks, marks[1:]):
        if t1 - t0 < 0.5:
            continue
        rate = (earned_at(t1) - earned_at(t0)) / (t1 - t0)
        f = (" x%.1f" % (rate / last_rate)) if last_rate > 0 else ""
        print("  %6.1f-%6.1f  %-24s %10.0f /min%s" % (t0, t1, "%s -> %s" % (a, b), rate, f))
        last_rate = rate
    print("== Reward cadence (gaps between new things) ==")
    ts = sorted({round(t, 1) for t, _ in moments})
    gaps = [(b - a, a, b) for a, b in zip([0.0] + ts, ts + [end]) if b > a]
    bad = [(g, a, b) for g, a, b in gaps if g > (FIRST_HOUR_GAP if a < 60.0 else LATER_GAP)]
    print("  %d new moments over %.0f min; mean gap %.1f min" % (len(ts), end, end / max(len(ts), 1)))
    for lo, hi in [(0, 60), (60, 120), (120, 180), (180, 240), (240, 300)]:
        g = [x for x, a, _ in gaps if lo <= a < hi]
        if g:
            print("  %3d-%3d min: %3d gaps, longest %.1f" % (lo, hi, len(g), max(g)))
    print("  over target (%.0f min in the first hour, %.0f later): %d; over %.0f min: %d" % (
        FIRST_HOUR_GAP, LATER_GAP, len(bad), MAX_GAP, len([1 for g, _, _ in gaps if g > MAX_GAP])))
    for g, a, b in sorted(bad, reverse=True)[:10]:
        print("    %5.1f min  %6.1f -> %6.1f" % (g, a, b))
    if cards:
        print("== Card waits (longest; * = a price on the card) ==")
        waits = [(b[0] - a[0], a[0], a[1], a[2]) for a, b in zip(cards, cards[1:] + [(end, "", False)])]
        for w, t, name, priced in sorted(waits, reverse=True)[:10]:
            flag = "*" if priced else " "
            wall = "  WALL" if priced and w > MAX_GRIND else ""
            print("  %5.1f min %s at %6.1f  %s%s" % (w, flag, t, name, wall))


if __name__ == "__main__":
    main()
