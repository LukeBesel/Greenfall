"""[art7] The flora kit, built in code: blender -b --python art/models/flora/build_flora.py

Writes flora.glb next to this file: every plant CellVerdure (plants/cell_verdure.gd) stands on
cleaned ground, one mesh object each, all mapped onto flora_atlas.png (build_atlas.py) and drawn
with one shared material (plants/flora.gdshader).

Vertex data the shader reads:
  COLOR.r  sway weight (how far the wind moves this vertex, in mesh units per unit of wind)
  COLOR.g  ambient occlusion (1 open .. 0.4 deep inside a crown or at a clump's foot)
  COLOR.b  flutter phase of the leaf card (0..1), so cards of one crown do not move as one
  COLOR.a  what it is: 0 wood/stem (opaque to light), 0.5 leaf (light shines through),
           1 petal (also takes the instance's colour)
  NORMAL   "puffed": out from the crown or clump centre, so a crown shades as one soft volume
Sizes: trees and bushes are in metres. Grass, weeds and flowers are about 1 unit tall and are
scaled per instance. Names: grass_a grass_b grass_lod moss weed fern, flower_<daisy|poppy|umbel|
lupin|aster>, bush_<a|b|c>, tree_<birch|oak|pine|blossom>_<0|1|2> (sapling, young, grown) and
..._lod for ages 1 and 2.
"""
import math
import os
import random

import bpy
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
V = np.array


def nrm(v):
    v = np.asarray(v, float)
    L = np.linalg.norm(v)
    return v / L if L > 1e-9 else V([0.0, 0.0, 1.0])


def tile_uv(tile, s, t):
    """s, t in 0..1 across a tile (t up) -> Blender UV (origin bottom left)."""
    col, row = tile % 4, tile // 4
    e = 0.012
    s = e + s * (1 - 2 * e)
    t = e + t * (1 - 2 * e)
    return ((col + s) / 4.0, 1.0 - (row + 1 - t) / 4.0)


class Mb:
    """Mesh under construction. Blender axes: z up (the exporter turns it to y up)."""

    def __init__(self):
        self.v, self.n, self.uv, self.c, self.f = [], [], [], [], []

    def vert(self, p, n, uv, c):
        self.v.append(tuple(p))
        self.n.append(tuple(nrm(n)))
        self.uv.append(uv)
        self.c.append(tuple(c))
        return len(self.v) - 1

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def card(self, centre, right, up, tile, col, n=None, n_spread=0.0, uvr=(0, 0, 1, 1), sway_up=0.0, ao_up=0.0):
        """A textured quad: centre, half-extent vectors. col = (r, g, b, a); sway_up adds weight
        along the card's up (a hanging or standing card moves more at its free end)."""
        centre, right, up = V(centre, float), V(right, float), V(up, float)
        nn = nrm(np.cross(right, up)) if n is None else nrm(n)
        ids = []
        for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            p = centre + right * sx + up * sy
            u = uvr[0] + (uvr[2] - uvr[0]) * (sx * 0.5 + 0.5)
            v = uvr[1] + (uvr[3] - uvr[1]) * (sy * 0.5 + 0.5)
            cc = list(col)
            cc[0] = col[0] + sway_up * (sy * 0.5 + 0.5)
            cc[1] = min(1.0, col[1] + ao_up * (sy * 0.5 + 0.5))
            ids.append(self.vert(p, nn + nrm(p - centre) * n_spread, tile_uv(tile, u, v), cc))
        self.quad(*ids)

    def blade(self, base, out, h, w, lean, ramp, col_a, sway, segs=2, rnd=None, up_n=0.75):
        """A curved grass blade or stem: `segs` quads and a tip. ramp = column 0..3 of tile 7."""
        base, out = V(base, float), nrm(out)
        side = nrm(np.cross(out, (0, 0, 1)))
        prev = None
        for i in range(segs + 1):
            t = i / (segs + 1.0)
            p = base + out * lean * t * t + V([0, 0, h * t])
            ww = w * (1.0 - 0.45 * t)
            n = nrm(V([0, 0, 1.0]) * up_n + out * (1.0 - up_n))
            uvc = tile_uv(7, (ramp + 0.5) / 4.0, t)
            c = (sway * t * t, 0.45 + 0.55 * t, 0.0, col_a)
            cur = (self.vert(p - side * ww, n, uvc, c), self.vert(p + side * ww, n, uvc, c))
            if prev:
                self.quad(prev[0], prev[1], cur[1], cur[0])
            prev = cur
        tip = base + out * lean + V([0, 0, h])
        k = self.vert(tip, (0, 0, 1), tile_uv(7, (ramp + 0.5) / 4.0, 1.0), (sway, 1.0, 0.0, col_a))
        self.f.append((prev[0], prev[1], k))
        return tip

    def tube(self, pts, radii, sides, strip, sway, ao=1.0, vscale=0.5):
        """A bark tube along pts. strip = 0 birch, 1 oak, 2 pine (thirds of tile 6)."""
        pts = [V(p, float) for p in pts]
        rings = []
        dist = 0.0
        for i, p in enumerate(pts):
            d = nrm(pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)])
            a = nrm(np.cross(d, (0.3, 0.9, 0.1)))
            b = np.cross(d, a)
            if i:
                dist += np.linalg.norm(p - pts[i - 1])
            tv = abs(((dist * vscale) % 2.0) - 1.0)  # mirror-repeat inside the tile
            ring = []
            for s in range(sides + 1):
                th = math.tau * s / sides
                nn = a * math.cos(th) + b * math.sin(th)
                su = abs((2.0 * s / sides) - 1.0)
                uv = tile_uv(6, (strip + 0.08 + 0.84 * su) / 3.0 * 0.99, 0.02 + 0.96 * tv)
                ring.append(self.vert(p + nn * radii[i], nn, uv, (sway[i], ao if i else ao * 0.6, 0.0, 0.0)))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(sides):
                self.quad(rings[i][s], rings[i][s + 1], rings[i + 1][s + 1], rings[i + 1][s])

    def tris(self):
        return len(self.f)

    def to_object(self, name, coll, mat):
        me = bpy.data.meshes.new(name)
        me.from_pydata(self.v, [], self.f)
        me.update()
        me.uv_layers.new(name="UVMap")
        me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="CORNER")
        # fetch the layers only now: adding an attribute moves the others in memory
        uvl = me.uv_layers["UVMap"]
        col = me.color_attributes["Col"]
        for li, loop in enumerate(me.loops):
            uvl.data[li].uv = self.uv[loop.vertex_index]
            col.data[li].color = self.c[loop.vertex_index]
        for p in me.polygons:
            p.use_smooth = True
        if hasattr(me, "use_auto_smooth"):
            me.use_auto_smooth = True
        me.normals_split_custom_set_from_vertices(self.n)
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        coll.objects.link(ob)
        return ob


# --- small plants (about 1 unit tall, scaled per instance) ---------------------------------------

def grass_cards(m, r, n_mid, n_out, tile=5):
    """A patch of sward about 1.4 units across: crossed blade cards in the middle and satellites
    leaning out round them (so it reads from the play camera above as well as from the side)."""
    for k in range(n_mid):
        a = k * math.pi / n_mid + r.uniform(-0.2, 0.2)
        m.card((0, 0, 0.5), V([math.cos(a), math.sin(a), 0]) * 0.55, (0, 0, 0.5), tile, (0.0, 0.5, r.random(), 0.5), n=(0, 0, 1), sway_up=0.34, ao_up=0.5)
    for k in range(n_out):
        a = math.tau * k / n_out + r.uniform(-0.4, 0.4)
        out = V([math.cos(a), math.sin(a), 0])
        side = nrm(np.cross(out, (0, 0, 1)))
        lean = r.uniform(0.3, 0.55)
        up = nrm(V([0, 0, 1.0]) + out * lean) * r.uniform(0.36, 0.48)
        c = out * r.uniform(0.38, 0.55) + up
        m.card(c, side * r.uniform(0.42, 0.55), up, tile, (0.0, 0.5, r.random(), 0.5), n=(0, 0, 1), sway_up=0.34, ao_up=0.5)


def grass_a(seed):
    r = random.Random(seed)
    m = Mb()
    grass_cards(m, r, 3, 3)
    for b in range(6):  # a few real blades standing clear of the cards
        a = math.tau * b / 6 + r.uniform(-0.4, 0.4)
        out = V([math.cos(a), math.sin(a), 0])
        m.blade(out * r.uniform(0.1, 0.6), out, r.uniform(0.7, 1.1), r.uniform(0.014, 0.024), r.uniform(0.15, 0.5), 1 if r.random() < 0.3 else 0, 0.5, 0.42)
    return m


def grass_b(seed):
    r = random.Random(seed)
    m = Mb()
    for k in range(3):
        a = k * math.pi / 3 + 0.2
        m.card((0, 0, 0.5), V([math.cos(a), math.sin(a), 0]) * 0.42, (0, 0, 0.5), 15, (0.0, 0.6, r.random(), 0.5), n=(0, 0, 1), sway_up=0.55, ao_up=0.4)
    for b in range(4):
        a = math.tau * b / 4 + r.uniform(-0.3, 0.3)
        out = V([math.cos(a), math.sin(a), 0])
        m.blade(out * r.uniform(0.03, 0.2), out, r.uniform(0.35, 0.6), 0.022, r.uniform(0.15, 0.4), 0, 0.5, 0.35)
    return m


def grass_lod(seed):
    r = random.Random(seed)
    m = Mb()
    grass_cards(m, r, 2, 3)
    return m


def moss(seed):
    m = Mb()
    m.card((0, 0, 0.03), (0.5, 0, 0), (0, 0.5, 0), 13, (0.0, 0.9, 0.0, 0.0), n=(0, 0, 1))
    return m


def flower_head(m, top, out, size, tile, r, tilt=0.5):
    """A head card tipped a little toward `out` (so it reads from above and from the side)."""
    side = nrm(np.cross(out, (0, 0, 1)))
    up = nrm(out * math.cos(tilt) + V([0, 0, 1.0]) * math.sin(tilt))
    m.card(top, side * size, up * size, tile, (0.34, 1.0, r.random(), 1.0), n=(0, 0, 1))


def weed(seed):
    """A pioneer: a leaf rosette flat on the ground and two small flower heads."""
    r = random.Random(seed)
    m = Mb()
    m.card((0, 0, 0.05), (0.5, 0, 0), (0, 0.5, 0), 12, (0.0, 0.85, 0.0, 0.5), n=(0, 0, 1))
    m.card((0.05, 0.02, 0.12), (0.34, 0.1, 0.1), (-0.1, 0.34, 0.06), 12, (0.03, 1.0, 0.3, 0.5), n=(0, 0, 1))
    for k in range(2):
        a = r.uniform(0, math.tau)
        out = V([math.cos(a), math.sin(a), 0])
        top = m.blade(out * 0.05, out, r.uniform(0.45, 0.75), 0.02, 0.12, 2, 0.0, 0.3, segs=1)
        flower_head(m, top, out, 0.13, 8, r, 0.9)
    return m


def fern(seed):
    r = random.Random(seed)
    m = Mb()
    for k in range(6):
        a = math.tau * k / 6 + r.uniform(-0.25, 0.25)
        out = V([math.cos(a), math.sin(a), 0])
        side = nrm(np.cross(out, (0, 0, 1)))
        L = r.uniform(0.7, 1.0)
        w = 0.15 * L
        # two quads arching up and over: the frond's base is at the tile's bottom
        p0, p1, p2 = out * 0.03, out * 0.42 * L + V([0, 0, 0.5 * L]), out * 0.95 * L + V([0, 0, 0.42 * L])
        row = []
        for p, t, sw in ((p0, 0.0, 0.0), (p1, 0.5, 0.12), (p2, 1.0, 0.4)):
            n = nrm(V([0, 0, 1.0]) + out * 0.3)
            c = (sw, 0.5 + 0.5 * t, r.random(), 0.5)
            row.append((m.vert(p - side * w, n, tile_uv(4, 0.0, t), c), m.vert(p + side * w, n, tile_uv(4, 1.0, t), c)))
        m.quad(row[0][0], row[0][1], row[1][1], row[1][0])
        m.quad(row[1][0], row[1][1], row[2][1], row[2][0])
    return m


def flower(seed, kind):
    r = random.Random(seed)
    m = Mb()
    stems = {"daisy": 5, "poppy": 4, "umbel": 3, "lupin": 4, "aster": 7}[kind]
    for k in range(stems):
        a = math.tau * k / stems + r.uniform(-0.4, 0.4)
        out = V([math.cos(a), math.sin(a), 0])
        base = out * r.uniform(0.04, 0.22)
        if kind == "lupin":
            h = r.uniform(0.7, 1.0)
            c = base + out * 0.04 + V([0, 0, h * 0.5])
            for q in range(2):
                b = a + q * math.pi / 2
                m.card(c, V([math.cos(b), math.sin(b), 0]) * 0.19, (0, 0, h * 0.5), 11, (0.0, 0.95, r.random(), 1.0), n=(0, 0, 1), sway_up=0.3)
            continue
        h = {"daisy": r.uniform(0.6, 0.9), "poppy": r.uniform(0.75, 1.0), "umbel": r.uniform(0.8, 1.0), "aster": r.uniform(0.3, 0.5)}[kind]
        top = m.blade(base, out, h, 0.018, r.uniform(0.06, 0.22), 2, 0.0, 0.34, segs=1)
        size, tile, tilt = {"daisy": (0.24, 8, 0.8), "poppy": (0.28, 9, 0.65), "umbel": (0.36, 10, 1.05), "aster": (0.18, 8, 0.95)}[kind]
        flower_head(m, top + V([0, 0, 0.01]), out, size * r.uniform(0.85, 1.1), tile, r, tilt)
    for k in range(3):  # a few leaves at the foot
        a = r.uniform(0, math.tau)
        out = V([math.cos(a), math.sin(a), 0])
        m.blade(out * 0.05, out, r.uniform(0.25, 0.4), 0.05, 0.25, 2, 0.5, 0.2, segs=1)
    return m


# --- bushes (metres) ---------------------------------------------------------------------------

def bush(seed, tiles, R, H, n_cards, card, stems=4, strip=1):
    r = random.Random(seed)
    m = Mb()
    cen = V([0, 0, H * 0.45])
    for k in range(stems):
        a = math.tau * k / stems + r.uniform(-0.4, 0.4)
        out = V([math.cos(a), math.sin(a), 0])
        pts = [out * 0.03, out * R * 0.3 + V([0, 0, H * 0.35]), out * R * 0.6 + V([0, 0, H * 0.7])]
        m.tube(pts, [0.03, 0.022, 0.01], 3, strip, [0.0, 0.02, 0.06], ao=0.6)
    for k in range(n_cards):
        # golden-angle points on a squashed dome, a second shell inside for depth
        t = (k + 0.5) / n_cards
        inner = 0.62 if k % 3 == 0 else 1.0
        el = math.acos(1.0 - t * 0.98)
        az = k * 2.39996 + r.uniform(-0.2, 0.2)
        d = V([math.sin(el) * math.cos(az), math.sin(el) * math.sin(az), math.cos(el)])
        p = V([d[0] * R, d[1] * R, max(0.12, H * 0.42 + d[2] * H * 0.58)]) * V([inner, inner, 0.6 + 0.4 * inner])
        n = nrm(p - cen * 0.6)
        ax = nrm(np.cross(n, (r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-0.2, 1))))
        ay = np.cross(n, ax)
        s = card * r.uniform(0.8, 1.2)
        ao = 0.5 + 0.5 * inner * (0.45 + 0.55 * p[2] / H)
        m.card(p, ax * s, ay * s, r.choice(tiles), (0.05 + 0.1 * p[2] / H, ao, r.random(), 1.0 if 14 in tiles else 0.5), n=n, n_spread=0.35)
    return m


# --- trees (metres) ----------------------------------------------------------------------------

SPECIES = {
    # H per age, trunk radius per age, crown: base height share, radius share of H, shape
    "birch": {"H": (1.7, 4.2, 7.2), "r": (0.022, 0.06, 0.11), "strip": 0, "tile": (1,), "base": 0.34, "rad": 0.2, "shape": "oval", "branches": (6, 12, 20), "card": (0.36, 0.66, 0.9), "per": (2, 3, 4), "up": 0.75, "droop": 0.55, "lean": 0.12},
    "oak": {"H": (1.4, 3.6, 6.2), "r": (0.03, 0.11, 0.21), "strip": 1, "tile": (0, 0, 3), "base": 0.38, "rad": 0.4, "shape": "round", "branches": (5, 10, 16), "card": (0.36, 0.7, 1.0), "per": (2, 3, 4), "up": 0.5, "droop": 0.0, "lean": 0.08},
    "pine": {"H": (1.6, 4.6, 8.2), "r": (0.03, 0.09, 0.17), "strip": 2, "tile": (2,), "base": 0.2, "rad": 0.26, "shape": "cone", "branches": (8, 16, 26), "card": (0.3, 0.55, 0.8), "per": (1, 2, 2), "up": 0.05, "droop": 0.3, "lean": 0.03},
    "blossom": {"H": (1.3, 3.0, 4.6), "r": (0.025, 0.07, 0.13), "strip": 1, "tile": (14, 14, 3), "base": 0.46, "rad": 0.4, "shape": "round", "branches": (5, 9, 14), "card": (0.34, 0.62, 0.86), "per": (2, 3, 4), "up": 0.45, "droop": 0.1, "lean": 0.15},
}


def crown_radius(sp, t):
    """Crown half-width at height share t (0 crown base .. 1 top), as a share of its widest."""
    if sp["shape"] == "cone":
        return max(0.08, 1.0 - t) ** 0.85
    if sp["shape"] == "oval":
        return max(0.12, math.sin(math.pi * (0.12 + 0.86 * t)) ** 0.8)
    return max(0.2, math.sin(math.pi * (0.2 + 0.75 * t)) ** 0.6)


def tree(seed, name, age, lod=False):
    sp = SPECIES[name]
    r = random.Random(seed)
    m = Mb()
    H = sp["H"][age]
    r0 = sp["r"][age]
    strip = sp["strip"]
    lean_a = r.uniform(0, math.tau)
    lean = V([math.cos(lean_a), math.sin(lean_a), 0]) * sp["lean"] * H

    def axis(t):
        # the trunk's line: a gentle S, so no tree is a pole
        return lean * (t * t) + V([math.sin(t * 5.0 + seed) * 0.02 * H, math.cos(t * 4.0 + seed) * 0.02 * H, H * t])

    n_seg = 3 if lod else (5 if age else 4)
    pts = [axis(i / n_seg) for i in range(n_seg + 1)]
    radii = [r0 * (1.0 - 0.82 * (i / n_seg) ** 0.8) + (r0 * 0.5 if i == 0 else 0.0) for i in range(n_seg + 1)]
    tsw = lambda t: 0.035 * H * t * t  # the trunk bends as a whole, most at the top
    m.tube(pts, radii, 4 if lod else (5 if age == 0 else 7), strip, [tsw(i / n_seg) for i in range(n_seg + 1)])
    base_t = sp["base"]
    R = sp["rad"] * H
    cen = axis(base_t + (1.0 - base_t) * 0.45)
    n_br = sp["branches"][age]
    card = sp["card"][age]
    cards = []
    lobes = []
    for b in range(n_br):
        f = (b + 0.5) / n_br
        t = base_t + (1.0 - base_t) * (f ** 0.9) * 0.96
        az = b * 2.39996 + r.uniform(-0.3, 0.3)
        out = V([math.cos(az), math.sin(az), 0])
        ct = (t - base_t) / (1.0 - base_t)
        L = R * crown_radius(sp, ct) * r.uniform(0.8, 1.1)
        p0 = axis(t)
        rise = sp["up"] * (0.4 + 0.6 * ct)
        p1 = p0 + out * L * 0.5 + V([0, 0, L * 0.5 * rise])
        p2 = p0 + out * L + V([0, 0, L * (rise * 0.8 - sp["droop"] * 0.5)])
        br = r0 * (1.0 - 0.8 * t) * 0.5 + 0.006
        if not lod:
            m.tube([p0, p1, p2], [br, br * 0.6, br * 0.25], 3 if age == 0 else 4, strip, [tsw(t), tsw(t) + 0.03 * L, tsw(t) + 0.09 * L], ao=0.65)
        per = sp["per"][age]
        if sp["shape"] == "round":
            lobes.append((p2, out, t, L))
            per = 1 if age else per
        for k in range(per):
            q = (k + 1.0) / per
            c = p1 + (p2 - p1) * q if q > 0.5 else p0 + (p1 - p0) * (0.5 + q)
            c = c + V([r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-0.5, 0.7)]) * card * 0.25
            cards.append((c, out, q, t, L))
    # the leader: a tuft at the very top
    top = axis(1.0)
    for k in range(2 if age else 1):
        cards.append((top + V([r.uniform(-1, 1) * 0.1, r.uniform(-1, 1) * 0.1, -card * 0.2 * k]), V([math.cos(k * 2.0), math.sin(k * 2.0), 0]), 1.0, 1.0, R * 0.2))
    if lod:
        cards = cards[::3] if len(cards) > 12 else cards[::2]
        card *= 1.75
    # Round crowns are built of lobes: a small dome of sprays at each main branch's end, so the
    # crown reads as layered clouds of leaf from every side (and from the play camera above).
    n_dome = (3, 5, 7)[age] if not lod else 2
    for (pc, out, t, L) in lobes:
        lr = max(card * 0.55, L * 0.3)
        lc = pc + V([0, 0, lr * 0.15])
        for k in range(n_dome):
            el = math.acos(1.0 - (k + 0.5) / n_dome * 1.25) if n_dome > 1 else 0.3
            az = k * 2.39996 + r.uniform(0, math.tau) * (0.15 if k else 1.0) + t * 20.0
            d = V([math.sin(el) * math.cos(az), math.sin(el) * math.sin(az), math.cos(el) * 0.8])
            p = lc + d * lr * r.uniform(0.75, 1.05)
            n = nrm(d * 0.7 + nrm(p - cen) * 0.5 + V([0, 0, 0.25]))
            ax = nrm(np.cross(n, (r.uniform(-1, 1), r.uniform(-1, 1), r.uniform(-0.3, 1.0))))
            ay = np.cross(n, ax)
            s = card * r.uniform(0.6, 0.85) * (1.7 if lod else 1.0)
            radial = np.linalg.norm((p - cen)[:2]) / max(R, 0.01)
            ao = max(0.42, min(1.0, 0.5 + 0.3 * radial + 0.35 * d[2]))
            sw = tsw(t) + 0.07 * L + 0.05
            m.card(p, ax * s, ay * s, r.choice(sp["tile"]), (sw, ao, r.random(), 1.0 if name == "blossom" else 0.5), n=n, n_spread=0.3)
    for c, out, q, t, L in cards:
        side = nrm(np.cross(out, (0, 0, 1)))
        s = card * r.uniform(0.82, 1.2)
        radial = np.linalg.norm((c - cen)[:2]) / max(R, 0.01)
        ao = min(1.0, 0.42 + 0.5 * radial + 0.25 * (c[2] - cen[2]) / (H * 0.5))
        ao = max(0.4, ao)
        sw = tsw(t) + 0.06 * L * q + 0.05
        col = (sw, ao, r.random(), 1.0 if (name == "blossom") else 0.5)
        n = nrm((c - cen) + V([0, 0, 0.35 * R]))
        tile = r.choice(sp["tile"])
        if name == "pine":
            # a bough: the tile's long axis runs out along the branch, lying nearly flat and drooping
            ax = nrm(out + V([0, 0, -0.25 - 0.3 * q]))
            m.card(c, ax * s * 1.25, side * s * 0.62, tile, col, n=nrm(n + V([0, 0, 0.8])), n_spread=0.25, uvr=(0, 0.1, 1, 0.9))
            m.card(c + V([0, 0, -0.04]), ax * s * 1.1, nrm(side + V([0, 0, -0.9])) * s * 0.5, tile, (sw, ao * 0.8, r.random(), 0.5), n=nrm(n + V([0, 0, 0.3])), n_spread=0.25, uvr=(0, 0.1, 1, 0.9))
        elif name == "birch":
            # hanging sprays: the tile's twig foot is at the branch, the leaves trail down and out
            dn = nrm(V([0, 0, -1.0]) + out * 0.55)
            a2 = r.uniform(0, math.pi)
            sd = nrm(side * math.cos(a2) + out * math.sin(a2) * 0.5)
            m.card(c + dn * s * 0.55, sd * s * 0.7, -dn * s * 0.75, tile, col, n=n, n_spread=0.3, sway_up=-0.08)
        else:
            # sprays tipped between flat (seen from the play camera above) and upright (seen from the side)
            tip = r.uniform(0.25, 1.15)
            ax = nrm(side * math.cos(tip * 2.0) + out * math.sin(tip * 2.0))
            ay = nrm(np.cross(nrm(V([0, 0, 1.0]) * math.cos(tip) + out * math.sin(tip)), ax))
            m.card(c, ax * s, ay * s, tile, col, n=n, n_spread=0.35)
    return m


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    coll = bpy.context.scene.collection
    mat = bpy.data.materials.new("flora")
    kit = {
        "grass_a": grass_a(1), "grass_b": grass_b(2), "grass_lod": grass_lod(3), "moss": moss(4), "weed": weed(5), "fern": fern(6),
        "flower_daisy": flower(10, "daisy"), "flower_poppy": flower(11, "poppy"), "flower_umbel": flower(12, "umbel"),
        "flower_lupin": flower(13, "lupin"), "flower_aster": flower(14, "aster"),
        "bush_a": bush(20, (3,), 0.75, 1.0, 20, 0.36), "bush_b": bush(21, (14, 14, 3), 0.85, 1.3, 22, 0.4), "bush_c": bush(22, (0, 3), 1.1, 0.8, 20, 0.42),
    }
    for si, name in enumerate(SPECIES):
        for age in range(3):
            kit["tree_%s_%d" % (name, age)] = tree(100 + si * 10 + age, name, age)
            if age:
                kit["tree_%s_%d_lod" % (name, age)] = tree(100 + si * 10 + age, name, age, lod=True)
    for i, (name, m) in enumerate(kit.items()):
        ob = m.to_object(name, coll, mat)
        ob.location = (i * 3.0, 0, 0)  # apart in the file (for eyes); the game reads the meshes only
        print("[flora] %-22s %4d tris" % (name, m.tris()))
    bpy.ops.export_scene.gltf(filepath=os.path.join(HERE, "flora.glb"), export_format="GLB", export_colors=True, export_normals=True, export_texcoords=True, export_materials="PLACEHOLDER", export_yup=True)
    print("[flora] wrote flora.glb, %d meshes" % len(kit))


main()
