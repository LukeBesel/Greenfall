#!/usr/bin/env python3
"""[art7] The flora kit's one texture, painted in code: python3 art/models/flora/build_atlas.py

flora_atlas.png, 1024x1024 RGBA, a 4x4 grid of 256 px tiles (painted at 2x and scaled down).
build_flora.py maps its cards onto these tiles; plants/flora.gdshader draws them alpha-scissored.

 0 oak spray      1 birch spray     2 pine bough      3 bush spray
 4 fern frond     5 grass blades    6 bark (3 strips) 7 solid ramps (blade, dry, stem, seed)
 8 daisy          9 poppy          10 umbel          11 lupin spike
12 rosette       13 moss cushion   14 blossom spray  15 seed-head grass

Petals are painted near white (the shader tints unsaturated petal pixels with the instance's
colour); flower centres are saturated and keep their own colour. Transparent pixels carry the
tile's mean colour so mipmaps do not pull a dark fringe in.
"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

T = 512  # tile size while painting (2x)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "flora_atlas.png")


def rgb(c, k=1.0):
    return tuple(int(max(0, min(255, v * k))) for v in c) + (255,)


def leaf_poly(cx, cy, ang, ln, wd, lobes=0, rnd=None):
    """A pointed leaf from its base, as a polygon."""
    pts = []
    n = 9
    for side in (1, -1):
        rng = range(n + 1) if side == 1 else range(n - 1, 0, -1)
        for i in rng:
            t = i / n
            w = wd * math.sin(math.pi * t ** 0.75) * (1.0 + (0.22 * math.sin(t * math.pi * lobes) if lobes else 0.0))
            x = t * ln
            y = side * w * 0.5
            pts.append((cx + x * math.cos(ang) - y * math.sin(ang), cy + x * math.sin(ang) + y * math.cos(ang)))
    return pts


def draw_leaf(d, cx, cy, ang, ln, wd, col, lobes=0, rib=True):
    d.polygon(leaf_poly(cx, cy, ang, ln, wd, lobes), fill=rgb(col))
    # the half away from the light a little darker, a pale midrib
    half = leaf_poly(cx, cy, ang, ln, wd, lobes)
    n = len(half) // 2
    d.polygon(half[: n + 1] + [(cx, cy)], fill=rgb(col, 0.84))
    if rib:
        d.line([(cx, cy), (cx + ln * 0.92 * math.cos(ang), cy + ln * 0.92 * math.sin(ang))], fill=rgb(col, 1.28), width=max(1, int(wd * 0.07)))


def jitter(col, r, dv=0.16, dh=0.08):
    v = 1.0 + r.uniform(-dv, dv)
    h = r.uniform(-dh, dh)
    return (col[0] * v * (1.0 + h), col[1] * v, col[2] * v * (1.0 - h))


def spray(seed, base, tip, n_twigs, leaves_per, ln, wd, lobes=0, radial=True, droop=0.0, blossom=None):
    """A branch-end mass of leaves: twigs fan out from the tile's lower middle (or its centre),
    leaves along them, dark inner ones first and light outer ones on top."""
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    ox, oy = (T * 0.5, T * 0.5) if radial else (T * 0.5, T * 0.96)
    twigs = []
    for k in range(n_twigs):
        a = (r.uniform(0, math.tau) if radial else -math.pi / 2 + r.uniform(-1.15, 1.15))
        L = T * (r.uniform(0.27, 0.44) if radial else r.uniform(0.55, 0.88))
        twigs.append((a, L))
    items = []
    for a, L in twigs:
        px, py = ox, oy
        segs = 7
        ca = a
        pts = [(px, py)]
        for s in range(segs):
            ca += r.uniform(-0.22, 0.22) + droop * 0.12 * (1 if math.cos(ca) > 0 else -1)
            px += math.cos(ca) * L / segs
            py += math.sin(ca) * L / segs
            pts.append((px, py))
            t = (s + 1) / segs
            for j in range(leaves_per):
                la = ca + r.choice((-1, 1)) * r.uniform(0.5, 1.25)
                depth = r.random() * 0.55 + t * 0.45
                items.append((depth, px + r.uniform(-6, 6), py + r.uniform(-6, 6), la, ln * r.uniform(0.7, 1.2) * T / 256, wd * r.uniform(0.75, 1.15) * T / 256))
        d.line(pts, fill=(58, 44, 30, 255), width=max(2, int(T * 0.012)))
    items.sort(key=lambda it: it[0])
    for depth, x, y, la, l2, w2 in items:
        col = tuple(base[i] + (tip[i] - base[i]) * depth for i in range(3))
        draw_leaf(d, x, y, la, l2, w2, jitter(col, r), lobes)
    if blossom:
        for k in range(int(len(items) * 0.45)):
            _, x, y, _, _, _ = r.choice(items)
            rr = r.uniform(5, 9) * T / 256
            for p in range(5):
                pa = p * math.tau / 5 + r.random()
                d.ellipse([x + math.cos(pa) * rr - rr * 0.7, y + math.sin(pa) * rr - rr * 0.7, x + math.cos(pa) * rr + rr * 0.7, y + math.sin(pa) * rr + rr * 0.7], fill=rgb(jitter(blossom, r, 0.06, 0.02)))
            d.ellipse([x - rr * 0.35, y - rr * 0.35, x + rr * 0.35, y + rr * 0.35], fill=(236, 190, 70, 255))
    return im


def pine(seed):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    # a bough seen from above/side: a main twig left to right, side twigs, needles on all
    def needles(x0, y0, x1, y1, ln, dens, shade):
        L = math.hypot(x1 - x0, y1 - y0)
        a = math.atan2(y1 - y0, x1 - x0)
        for i in range(int(L / dens)):
            t = i / max(1, int(L / dens))
            x = x0 + (x1 - x0) * t
            y = y0 + (y1 - y0) * t
            for s in (-1, 1):
                na = a + s * r.uniform(0.6, 1.1)
                l2 = ln * r.uniform(0.7, 1.15) * (1.0 - 0.35 * t)
                c = jitter((38 * shade, 84 * shade, 52 * shade), r, 0.22, 0.06)
                d.line([(x, y), (x + math.cos(na) * l2, y + math.sin(na) * l2)], fill=rgb(c), width=max(2, int(T * 0.008)))
        d.line([(x0, y0), (x1, y1)], fill=(64, 46, 30, 255), width=max(2, int(T * 0.012)))
    x0, y0, x1, y1 = T * 0.04, T * 0.5, T * 0.97, T * 0.5
    for k in range(9):
        t = 0.08 + 0.86 * k / 8
        for s in (-1, 1):
            bx = x0 + (x1 - x0) * t
            L = T * 0.34 * (1.0 - 0.75 * t) + T * 0.05
            a = s * (0.75 + 0.15 * r.random())
            ex, ey = bx + math.cos(a) * L, y0 + math.sin(a) * L
            needles(bx, y0, ex, ey, T * 0.05, 3.2, 0.82 + 0.3 * r.random())
            # tertiary
            for q in (0.45, 0.75):
                mx, my = bx + (ex - bx) * q, y0 + (ey - y0) * q
                a2 = a + s * 0.6
                needles(mx, my, mx + math.cos(a2) * L * 0.35, my + math.sin(a2) * L * 0.35, T * 0.04, 3.4, 1.0 + 0.3 * r.random())
    needles(x0, y0, x1, y1, T * 0.055, 3.0, 1.2)
    return im


def fern(seed):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x0, y0 = T * 0.5, T * 0.98
    n = 22
    for i in range(n):
        t = i / (n - 1)
        y = y0 - t * T * 0.93
        L = T * 0.36 * math.sin(math.pi * (0.12 + 0.88 * t) ** 0.8) * (1.0 - 0.25 * t) + 6
        for s in (-1, 1):
            a = -math.pi / 2 + s * (1.15 - 0.35 * t)
            col = jitter((70 + 50 * t, 128 + 40 * t, 48), r, 0.12, 0.05)
            draw_leaf(d, x0, y, a, L, L * 0.2, col, lobes=9, rib=True)
    d.line([(x0, y0), (x0, y0 - T * 0.93)], fill=(86, 104, 44, 255), width=5)
    return im


def blades(seed):
    """A fan of grass blades from the tile's bottom edge: the far grass card."""
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    bl = []
    for i in range(46):
        x = T * r.uniform(0.06, 0.94)
        h = T * r.uniform(0.35, 0.97) * (1.0 - 0.5 * abs(x / T - 0.5))
        lean = r.uniform(-0.3, 0.3) + (x / T - 0.5) * 0.7
        bl.append((h, x, lean))
    bl.sort(reverse=True)
    for h, x, lean in bl:
        w = T * r.uniform(0.012, 0.024)
        dry = r.random() < 0.22
        segs = 10
        L, R = [], []
        for s in range(segs + 1):
            t = s / segs
            cx = x + lean * h * t * t
            cy = T - h * t
            ww = w * (1.0 - t ** 1.6)
            L.append((cx - ww, cy))
            R.append((cx + ww, cy))
        base = (58, 104, 34) if not dry else (120, 122, 52)
        tip = (128, 176, 62) if not dry else (196, 180, 96)
        for s in range(segs):
            t = (s + 0.5) / segs
            c = tuple(base[i] + (tip[i] - base[i]) * t for i in range(3))
            d.polygon([L[s], L[s + 1], R[s + 1], R[s]], fill=rgb(jitter(c, r, 0.07, 0.03)))
    return im


def seedgrass(seed):
    """Tall pioneer grass with seed heads (the first thing up on cleared ground)."""
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(13):
        x = T * r.uniform(0.2, 0.8)
        h = T * r.uniform(0.6, 0.95)
        lean = r.uniform(-0.35, 0.35)
        pts = [(x + lean * h * (s / 12) ** 2, T - h * s / 12) for s in range(13)]
        d.line(pts, fill=(150, 150, 74, 255), width=4)
        # the head: small spikelets down the top third
        for s in range(8, 13):
            px, py = pts[s]
            for k in range(4):
                a = -math.pi / 2 + r.uniform(-1.0, 1.0)
                l2 = T * r.uniform(0.02, 0.045)
                d.line([(px, py), (px + math.cos(a) * l2, py + math.sin(a) * l2)], fill=rgb(jitter((206, 186, 112), r, 0.1)), width=5)
    for i in range(16):  # low leaves
        x = T * r.uniform(0.25, 0.75)
        a = -math.pi / 2 + r.uniform(-0.9, 0.9)
        draw_leaf(d, x, T * 0.99, a, T * r.uniform(0.2, 0.42), T * 0.03, jitter((92, 132, 50), r), rib=False)
    return im


def bark():
    r = random.Random(5)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 255))
    px = np.zeros((T, T, 3), np.float32)
    rs = np.random.RandomState(4)
    W = T // 3
    # birch: chalk white, dark lenticels and scars
    b = np.full((T, W, 3), (214, 208, 196), np.float32) * (0.9 + 0.1 * rs.rand(T, 1, 1)) * (0.94 + 0.06 * rs.rand(T, W, 1))
    px[:, :W] = b
    # oak: brown, vertical furrows
    col = rs.rand(1, W) * 0.5 + 0.5 * np.repeat(rs.rand(1, W // 6 + 1), 6, axis=1)[:, :W]
    furrow = np.clip(col + 0.25 * rs.rand(T, W) - 0.1, 0, 1)
    px[:, W:2 * W] = np.array((96, 78, 60), np.float32) * (0.45 + 0.75 * furrow[..., None])
    # pine: red-brown plates
    plate = np.repeat(np.repeat(rs.rand(T // 24 + 1, W // 12 + 1), 24, axis=0), 12, axis=1)[:T, :W]
    px[:, 2 * W:3 * W] = np.array((128, 84, 58), np.float32) * (0.55 + 0.6 * plate[..., None]) * (0.9 + 0.1 * rs.rand(T, W, 1))
    px[:, 3 * W:] = px[:, 3 * W - 1:3 * W]
    im = Image.fromarray(np.clip(px, 0, 255).astype(np.uint8)).convert("RGBA")
    d = ImageDraw.Draw(im)
    for i in range(70):  # birch lenticels
        x = r.uniform(0, W - 30)
        y = r.uniform(0, T)
        w = r.uniform(10, 46)
        d.ellipse([x, y, x + w, y + r.uniform(3, 8)], fill=(52, 46, 42, 255))
    for i in range(7):
        x = r.uniform(10, W - 50)
        y = r.uniform(0, T)
        d.polygon([(x, y), (x + 34, y - 12), (x + 68, y), (x + 34, y + 16)], fill=(40, 36, 34, 255))
    for i in range(40):  # oak cracks
        x = W + r.uniform(4, W - 4)
        y = r.uniform(0, T)
        d.line([(x, y), (x + r.uniform(-5, 5), y + r.uniform(30, 110))], fill=(44, 34, 26, 255), width=4)
    for i in range(60):  # pine plate gaps
        x = 2 * W + r.uniform(2, W - 2)
        y = r.uniform(0, T)
        d.line([(x, y), (x + r.uniform(-3, 3), y + r.uniform(20, 60))], fill=(58, 34, 24, 255), width=4)
    return im.filter(ImageFilter.GaussianBlur(1.2))


def ramps():
    """Four vertical ramps (v = 0 at the tile's bottom): blade, dry blade, stem, seed/tan."""
    px = np.zeros((T, T, 4), np.float32)
    cols = [((34, 70, 22), (140, 186, 70)), ((92, 98, 40), (206, 190, 104)), ((44, 78, 28), (110, 150, 60)), ((120, 100, 60), (214, 196, 130))]
    rs = np.random.RandomState(9)
    t = np.linspace(1.0, 0.0, T)[:, None, None]  # row 0 = top = tip
    for i, (a, b) in enumerate(cols):
        seg = np.array(a, np.float32) + (np.array(b, np.float32) - np.array(a, np.float32)) * (t ** 0.8)
        px[:, i * T // 4:(i + 1) * T // 4, :3] = seg * (0.96 + 0.08 * rs.rand(T, T // 4, 1))
    px[..., 3] = 255
    return Image.fromarray(np.clip(px, 0, 255).astype(np.uint8), "RGBA")


def daisy(seed, petals=17, ring=2, centre=(232, 176, 40), white=(244, 242, 236)):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = T / 2
    for k in range(ring):
        n = petals
        for i in range(n):
            a = i * math.tau / n + k * math.pi / n + r.uniform(-0.06, 0.06)
            ln = T * (0.47 - 0.05 * k) * r.uniform(0.9, 1.0)
            v = (0.86 if k == 0 else 1.0) * r.uniform(0.95, 1.0)
            d.polygon(leaf_poly(c, c, a, ln, T * 0.105), fill=rgb(white, v))
            d.line([(c, c), (c + math.cos(a) * ln * 0.8, c + math.sin(a) * ln * 0.8)], fill=rgb(white, v * 0.9), width=3)
    rr = T * 0.115
    d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=rgb(centre))
    for i in range(60):
        a = r.uniform(0, math.tau)
        q = rr * math.sqrt(r.random()) * 0.9
        d.ellipse([c + math.cos(a) * q - 4, c + math.sin(a) * q - 4, c + math.cos(a) * q + 4, c + math.sin(a) * q + 4], fill=rgb(centre, r.uniform(0.7, 1.15)))
    return im


def poppy(seed):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = T / 2
    for i in range(5):
        a = i * math.tau / 5 + 0.3
        px, py = c + math.cos(a) * T * 0.2, c + math.sin(a) * T * 0.2
        rr = T * 0.265
        v = 0.88 + 0.12 * (i % 2)
        d.ellipse([px - rr, py - rr, px + rr, py + rr], fill=rgb((244, 242, 236), v))
    for i in range(40):  # creases
        a = r.uniform(0, math.tau)
        d.line([(c + math.cos(a) * T * 0.1, c + math.sin(a) * T * 0.1), (c + math.cos(a) * T * 0.42, c + math.sin(a) * T * 0.42)], fill=(226, 224, 218, 255), width=3)
    rr = T * 0.1
    d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=(44, 40, 30, 255))
    for i in range(14):
        a = i * math.tau / 14
        d.ellipse([c + math.cos(a) * rr - 7, c + math.sin(a) * rr - 7, c + math.cos(a) * rr + 7, c + math.sin(a) * rr + 7], fill=(228, 190, 60, 255))
    return im


def umbel(seed):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = T / 2
    for i in range(15):
        a = i * math.tau / 15 + r.uniform(-0.1, 0.1)
        q = T * r.uniform(0.2, 0.37) if i % 3 else T * 0.1
        ux, uy = c + math.cos(a) * q, c + math.sin(a) * q
        d.line([(c, c), (ux, uy)], fill=(96, 132, 60, 255), width=4)
        for k in range(22):
            b = r.uniform(0, math.tau)
            p = T * 0.085 * math.sqrt(r.random())
            s = r.uniform(5, 9)
            d.ellipse([ux + math.cos(b) * p - s, uy + math.sin(b) * p - s, ux + math.cos(b) * p + s, uy + math.sin(b) * p + s], fill=rgb((246, 244, 238), r.uniform(0.86, 1.0)))
    return im


def lupin(seed):
    """A flower spike from the side: florets up a stem, buds at the tip."""
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    x = T / 2
    d.line([(x, T), (x, T * 0.08)], fill=(84, 122, 52, 255), width=7)
    n = 34
    for i in range(n):
        t = i / (n - 1)
        y = T * 0.97 - t * T * 0.9
        w = T * 0.2 * (1.0 - t) ** 0.7 + T * 0.03
        for s in (-1, 1):
            px = x + s * w * r.uniform(0.3, 1.0)
            rr = T * (0.05 - 0.028 * t) * r.uniform(0.8, 1.15)
            v = 0.8 + 0.2 * r.random() - 0.18 * t
            d.ellipse([px - rr, y - rr * 0.8, px + rr, y + rr * 0.8], fill=rgb((244, 242, 238), v))
    return im


def rosette(seed):
    r = random.Random(seed)
    im = Image.new("RGBA", (T, T), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = T / 2
    for k in range(3):
        n = 9 - k
        for i in range(n):
            a = i * math.tau / n + k * 0.5 + r.uniform(-0.15, 0.15)
            ln = T * (0.48 - 0.11 * k) * r.uniform(0.85, 1.0)
            col = jitter((60 + 24 * k, 112 + 22 * k, 40 + 6 * k), r, 0.1, 0.05)
            draw_leaf(d, c, c, a, ln, ln * 0.3, col, lobes=7)
    return im


def moss(seed):
    rs = np.random.RandomState(seed)
    n = T
    # blobby cushion: sum of soft discs, thresholded; fine speckle for the tiny leaves
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float32)
    f = np.zeros((n, n), np.float32)
    for i in range(26):
        a = rs.rand() * math.tau
        q = n * 0.33 * math.sqrt(rs.rand())
        cx, cy = n / 2 + math.cos(a) * q, n / 2 + math.sin(a) * q
        rr = n * (0.07 + 0.11 * rs.rand())
        f += np.exp(-((xx - cx) ** 2 + (yy - cy) ** 2) / (2 * rr * rr))
    f /= f.max()
    sp = np.repeat(np.repeat(rs.rand(n // 4, n // 4), 4, axis=0), 4, axis=1)
    sp2 = np.repeat(np.repeat(rs.rand(n // 16, n // 16), 16, axis=0), 16, axis=1)
    v = 0.55 + 0.5 * sp + 0.25 * sp2 + 0.35 * f
    a = np.array((56, 92, 30), np.float32)
    b = np.array((134, 164, 58), np.float32)
    col = a + (b - a) * np.clip(f * 0.8 + sp2 * 0.5 - 0.2, 0, 1)[..., None]
    col *= v[..., None] * 0.8
    alpha = np.clip((f - 0.2 + (sp - 0.5) * 0.2) * 9.0, 0, 1) * 255
    px = np.dstack([np.clip(col, 0, 255), alpha]).astype(np.uint8)
    return Image.fromarray(px, "RGBA").filter(ImageFilter.GaussianBlur(1.5))


def fill_under(im):
    """Mean colour under the transparent pixels (clean mipmaps)."""
    px = np.asarray(im).astype(np.float32)
    a = px[..., 3:4] / 255.0
    if a.sum() < 1:
        return im
    mean = (px[..., :3] * a).sum(axis=(0, 1)) / a.sum()
    out = px.copy()
    out[..., :3] = px[..., :3] * a + mean * (1.0 - a)
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def main():
    tiles = [
        spray(11, (34, 78, 28), (104, 150, 50), 13, 5, 30, 16, lobes=5),
        spray(12, (62, 104, 30), (158, 188, 66), 12, 4, 19, 13, radial=False, droop=1.0),
        pine(13),
        spray(14, (34, 84, 32), (104, 150, 52), 15, 5, 17, 10),
        fern(15),
        blades(16),
        bark(),
        ramps(),
        daisy(18),
        poppy(19),
        umbel(20),
        lupin(21),
        rosette(22),
        moss(23),
        spray(24, (40, 86, 34), (108, 150, 60), 12, 4, 22, 12, blossom=(250, 232, 238)),
        seedgrass(25),
    ]
    atlas = Image.new("RGBA", (T * 4, T * 4), (0, 0, 0, 0))
    for i, t in enumerate(tiles):
        atlas.paste(fill_under(t), ((i % 4) * T, (i // 4) * T))
    atlas = atlas.resize((1024, 1024), Image.LANCZOS)
    atlas.save(OUT)
    # a look sheet on mid grey, for eyes
    sheet = Image.new("RGBA", atlas.size, (110, 110, 110, 255))
    sheet.alpha_composite(atlas)
    sheet.convert("RGB").save(os.path.join(os.environ.get("FLORA_SHEET_DIR", "/tmp"), "flora_atlas_sheet.jpg"), quality=85)
    print("wrote", OUT)


if __name__ == "__main__":
    main()
