#!/usr/bin/env python3
"""[art2] Lumi against the owner's turnaround, by measurement. Usage: tools/hero/overlay.py OUT.png
Cuts the five figures out of art/concept/aurora_turnaround.png and out of the renders
screenshots/hero/turn_v2_0..4.png (scenes/hero_preview.tscn --view=turn --no-floor --out=screenshots/hero/turn_nf), scales each to the same
height, and compares their outlines: the width of the figure at 40 heights from top (0) to bottom
(1). Prints, per view, where the render is wider (+) or narrower (-) than the concept as a share of
the figure's height, and the outline overlap (IoU). Writes a sheet: concept, render, overlay
(concept red, render cyan, overlap white)."""
import sys
import numpy as np
from PIL import Image

H = 360


def mask_of(im):
    a = np.asarray(im.convert("RGB"), dtype=np.float32)
    bg = np.median(np.concatenate([a[:6].reshape(-1, 3), a[-6:].reshape(-1, 3), a[:, :6].reshape(-1, 3), a[:, -6:].reshape(-1, 3)]), axis=0)
    d = np.abs(a - bg).sum(axis=2)
    return d > 60


def fit(im):
    m = mask_of(im)
    ys, xs = np.where(m)
    if len(ys) == 0:
        return None, None
    y0, y1 = np.percentile(ys, 0.5), np.percentile(ys, 99.5)
    x0, x1 = np.percentile(xs, 0.5), np.percentile(xs, 99.5)
    box = (int(x0), int(y0), int(x1) + 1, int(y1) + 1)
    c = im.crop(box)
    w = max(1, int(c.width * H / c.height))
    c = c.resize((w, H), Image.LANCZOS)
    mm = Image.fromarray((m[box[1]:box[3], box[0]:box[2]] * 255).astype(np.uint8)).resize((w, H), Image.NEAREST)
    return c, np.asarray(mm) > 127


def centre(m, W):
    out = np.zeros((H, W), bool)
    if m.shape[1] > W:
        o = (m.shape[1] - W) // 2
        m = m[:, o:o + W]
    x = (W - m.shape[1]) // 2
    out[:, x:x + m.shape[1]] = m
    return out


concept = Image.open("art/concept/aurora_turnaround.png").convert("RGB")
cw = concept.width / 5.0
top = int(concept.height * 0.08)  # below the title strip
bottom = int(concept.height * 0.72)  # above the floor reflection
names = ["front", "front 3/4", "side", "back 3/4", "back"]
W = 420
sheet = Image.new("RGB", (W * 5, H * 3 + 8), (10, 10, 12))
for i in range(5):
    c_im, c_m = fit(concept.crop((int(i * cw), top, int((i + 1) * cw), bottom)))
    r_im, r_m = fit(Image.open("screenshots/hero/turn_nf_%d.png" % i).convert("RGB"))
    if c_m is None or r_m is None:
        print(names[i], "no figure found")
        continue
    cm, rm = centre(c_m, W), centre(r_m, W)
    iou = (cm & rm).sum() / max(1, (cm | rm).sum())
    wc = cm.sum(axis=1) / H
    wr = rm.sum(axis=1) / H
    bands = [("head top", 0.05, 0.2), ("head mid", 0.2, 0.42), ("head low", 0.42, 0.55), ("torso", 0.55, 0.78), ("pod", 0.78, 0.98)]
    parts = " ".join("%s %+.2f" % (n, (wr[int(a * H):int(b * H)].mean() - wc[int(a * H):int(b * H)].mean())) for n, a, b in bands)
    print("%-10s IoU %.2f  aspect concept %.2f render %.2f  width diff: %s" % (names[i], iou, c_m.shape[1] / H, r_m.shape[1] / H, parts))
    sheet.paste(c_im, (i * W + (W - c_im.width) // 2, 0))
    sheet.paste(r_im, (i * W + (W - r_im.width) // 2, H + 4))
    ov = np.zeros((H, W, 3), np.uint8)
    ov[cm] = (220, 60, 60)
    ov[rm] = (40, 200, 220)
    ov[cm & rm] = (235, 235, 235)
    sheet.paste(Image.fromarray(ov), (i * W, H * 2 + 8))
sheet.save(sys.argv[1])
