#!/usr/bin/env python3
"""Contact sheets from an intro frame folder (tools/intro_capture.gd).

  python3 tools/intro_sheet.py FRAMES_DIR OUT_PREFIX [--cols 6] [--rows 5] [--from S] [--to S] [--step N] [--w 320]

Each tile carries its film time in seconds. Writes OUT_PREFIX_01.jpg, _02.jpg, ...
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("frames")
    ap.add_argument("out")
    ap.add_argument("--cols", type=int, default=6)
    ap.add_argument("--rows", type=int, default=5)
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=1e9)
    ap.add_argument("--step", type=int, default=1)
    ap.add_argument("--w", type=int, default=320)
    a = ap.parse_args()
    files = []
    for f in sorted(glob.glob(os.path.join(a.frames, "f_*.jpg"))):
        t = int(os.path.basename(f)[2:8]) / 100.0
        if a.t0 <= t <= a.t1:
            files.append((t, f))
    files = files[:: a.step]
    per = a.cols * a.rows
    h = a.w * 9 // 16
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    for page in range(0, len(files), per):
        chunk = files[page : page + per]
        rows = (len(chunk) + a.cols - 1) // a.cols
        sheet = Image.new("RGB", (a.cols * a.w, rows * h), (20, 20, 24))
        d = ImageDraw.Draw(sheet)
        for i, (t, f) in enumerate(chunk):
            im = Image.open(f).convert("RGB").resize((a.w, h), Image.LANCZOS)
            x, y = (i % a.cols) * a.w, (i // a.cols) * h
            sheet.paste(im, (x, y))
            d.rectangle([x, y, x + 46, y + 13], fill=(0, 0, 0))
            d.text((x + 3, y + 1), "%.1f" % t, fill=(255, 230, 90))
        path = "%s_%02d.jpg" % (a.out, page // per + 1)
        sheet.save(path, quality=88)
        print(path, len(chunk), "frames %.1f-%.1f s" % (chunk[0][0], chunk[-1][0]))


if __name__ == "__main__":
    main()
