#!/usr/bin/env python3
"""Art guard, the file side (tools/art_guard.sh runs it; docs/ART_BASELINE.md).

  python3 tools/art_guard.py static OUT.json          census of art/: models, textures, sizes
  python3 tools/art_guard.py compare DIR [--write-baseline] [--baseline FILE]
        reads DIR/static.json and the logs of the guard's Godot runs (DIR/*.log), compares them
        with the baseline (docs/art_baseline.json) and prints [artguard] PASS/FAIL/WARN lines;
        exit 1 on any FAIL. --write-baseline stores what DIR holds as the new baseline.
  python3 tools/art_guard.py self-test                plants each file-side fault, checks it is caught

Models: every .glb / .gltf under art/ (triangles per node instance, materials, primitives with no
material, images and their size, animations, skins, the importer's generate_lods). Textures:
every image under art/ with its .import (compress/mode, compress/normal_map). Sizes: art/ total.
"""
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "docs", "art_baseline.json")
IMG_EXT = (".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr", ".hdr", ".bmp", ".svg", ".ktx", ".ktx2", ".dds")


# ---------------------------------------------------------------------------- image headers
def image_size(data):
    """(w, h) from PNG / JPEG / WebP bytes, or None."""
    if data[:8] == b"\x89PNG\r\n\x1a\n" and len(data) >= 24:
        return struct.unpack(">II", data[16:24])
    if data[:2] == b"\xff\xd8":
        i = 2
        while i + 9 < len(data):
            if data[i] != 0xFF:
                i += 1
                continue
            m = data[i + 1]
            if m in (0xD8, 0x01) or 0xD0 <= m <= 0xD7:
                i += 2
                continue
            seg = struct.unpack(">H", data[i + 2:i + 4])[0]
            if m in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
                h, w = struct.unpack(">HH", data[i + 5:i + 9])
                return (w, h)
            i += 2 + seg
        return None
    if data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        if data[12:16] == b"VP8 " and len(data) >= 30:
            w, h = struct.unpack("<HH", data[26:30])
            return (w & 0x3FFF, h & 0x3FFF)
        if data[12:16] == b"VP8L" and len(data) >= 25:
            b = data[21:25]
            w = 1 + (((b[1] & 0x3F) << 8) | b[0])
            h = 1 + (((b[3] & 0xF) << 10) | (b[2] << 2) | ((b[1] & 0xC0) >> 6))
            return (w, h)
    return None


def read_import(path):
    """The [params] of a Godot .import file as a dict of strings, or None if there is none."""
    p = path + ".import"
    if not os.path.exists(p):
        return None
    out = {}
    for line in open(p, encoding="utf-8", errors="replace"):
        line = line.strip()
        if "=" in line and not line.startswith("["):
            k, v = line.split("=", 1)
            out[k.strip()] = v.strip()
    return out


# ---------------------------------------------------------------------------- glTF
def load_gltf(path):
    """(json, bin bytes or None) of a .glb or .gltf."""
    raw = open(path, "rb").read()
    if path.endswith(".glb"):
        if raw[:4] != b"glTF":
            raise ValueError("not a glb")
        jl = struct.unpack("<I", raw[12:16])[0]
        j = json.loads(raw[20:20 + jl])
        b = None
        o = 20 + jl
        if o + 8 <= len(raw):
            bl = struct.unpack("<I", raw[o:o + 4])[0]
            b = raw[o + 8:o + 8 + bl]
        return j, b
    return json.loads(raw), None


def model_census(path, rel):
    try:
        j, binb = load_gltf(path)
    except Exception as e:  # noqa: BLE001
        return {"error": "unreadable: %s" % e}
    acc = j.get("accessors", [])
    meshes = j.get("meshes", [])
    mats = j.get("materials", [])
    mesh_tris = []
    no_mat = 0
    prims = 0
    vcol = False
    for m in meshes:
        t = 0
        for p in m.get("primitives", []):
            prims += 1
            mode = p.get("mode", 4)
            if "indices" in p:
                n = acc[p["indices"]]["count"]
            else:
                n = acc[p["attributes"]["POSITION"]]["count"] if "POSITION" in p.get("attributes", {}) else 0
            if mode == 4:
                t += n // 3
            elif mode in (5, 6):
                t += max(n - 2, 0)
            if "material" not in p:
                no_mat += 1
            if "COLOR_0" in p.get("attributes", {}):
                vcol = True
        mesh_tris.append(t)
    tris = 0
    mesh_nodes = 0
    for nd in j.get("nodes", []):
        if "mesh" in nd:
            tris += mesh_tris[nd["mesh"]]
            mesh_nodes += 1
    if mesh_nodes == 0:
        tris = sum(mesh_tris)
    # Images: embedded (bufferView) or files next to the model.
    imgs = []
    bvs = j.get("bufferViews", [])
    for im in j.get("images", []):
        size = None
        if "bufferView" in im and binb is not None:
            bv = bvs[im["bufferView"]]
            o = bv.get("byteOffset", 0)
            size = image_size(binb[o:o + min(bv["byteLength"], 65536)])
        elif "uri" in im and not im["uri"].startswith("data:"):
            ip = os.path.join(os.path.dirname(path), im["uri"].replace("%20", " "))
            if os.path.exists(ip):
                size = image_size(open(ip, "rb").read(65536))
        imgs.append(list(size) if size else None)
    blender_default = sorted({m.get("name", "") for m in mats if re.fullmatch(r"Material(\.\d+)?", m.get("name", ""))})
    imp = read_import(path) or {}
    names = [n.get("name", "") for n in j.get("nodes", [])]
    return {
        "bytes": os.path.getsize(path),
        "tris": tris,
        "meshes": len(meshes),
        "primitives": prims,
        "materials": len(mats),
        "material_names": sorted({m.get("name", "") for m in mats}),
        "prims_without_material": no_mat,
        "blender_default_materials": blender_default,
        "vertex_colors": vcol,
        "images": imgs,
        "max_image": max([max(s) for s in imgs if s] or [0]),
        "animations": sorted(a.get("name", "") for a in j.get("animations", [])),
        "skins": len(j.get("skins", [])),
        "nodes": len(names),
        "node_names_hash": hashlib.sha1("\n".join(sorted(names)).encode()).hexdigest()[:12],
        "msft_lod": "MSFT_lod" in j.get("extensionsUsed", []),
        "generate_lods": imp.get("meshes/generate_lods", "true") == "true" if imp else None,
        "import_committed": None,
    }


# ---------------------------------------------------------------------------- census
def git_files(root):
    try:
        out = subprocess.run(["git", "-C", root, "ls-files", "art"], capture_output=True, text=True, check=True).stdout
        return set(out.split("\n"))
    except Exception:  # noqa: BLE001
        return None


def static_census(root=ROOT):
    art = os.path.join(root, "art")
    tracked = git_files(root)
    models, textures = {}, {}
    total = 0
    by_dir = {}
    for dp, dn, fn in os.walk(art):
        dn[:] = [d for d in dn if not d.startswith(".") and not os.path.exists(os.path.join(dp, d, ".gdignore"))]
        for f in fn:
            p = os.path.join(dp, f)
            rel = os.path.relpath(p, root)
            sz = os.path.getsize(p)
            total += sz
            top = "/".join(rel.split("/")[:3])
            by_dir[top] = by_dir.get(top, 0) + sz
            low = f.lower()
            if low.endswith((".glb", ".gltf")):
                c = model_census(p, rel)
                if tracked is not None:
                    c["import_committed"] = (rel + ".import") in tracked
                models[rel] = c
            elif low.endswith(IMG_EXT):
                imp = read_import(p)
                size = image_size(open(p, "rb").read(65536))
                textures[rel] = {
                    "size": list(size) if size else None,
                    "bytes": sz,
                    "import": imp is not None,
                    "import_committed": ((rel + ".import") in tracked) if tracked is not None else None,
                    "mode": imp.get("compress/mode") if imp else None,
                    "normal_map": imp.get("compress/normal_map") if imp else None,
                    "is_normal": "_nor_gl_" in low or "_normal" in low or low.endswith("_nor.png"),
                }
    # Estimated video memory of the textures (mipmaps +1/3): VRAM-compressed ~1 byte/px, else 4.
    vram = 0
    for t in textures.values():
        if t["size"]:
            bpp = 1.0 if t["mode"] == "2" else 4.0
            vram += t["size"][0] * t["size"][1] * bpp * 4 / 3
    for m in models.values():
        for s in m.get("images", []) or []:
            if s:
                vram += s[0] * s[1] * 1.0 * 4 / 3
    return {"models": models, "textures": textures, "art_bytes": total, "art_dirs": by_dir,
            "texture_vram_est": int(vram)}


# ---------------------------------------------------------------------------- the logs
def _num(s):
    return float(s.replace(",", ""))


def parse_logs(d):
    """Numbers and verdicts from the guard's Godot runs (DIR/*.log)."""
    out = {}

    def rd(name):
        p = os.path.join(d, name)
        return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else None

    t = rd("world.log")
    if t is not None:
        m = re.findall(r"^\[artguard\] JSON (.*)$", t, re.M)
        if m:
            try:
                out["world"] = json.loads(m[-1])
            except ValueError:
                out["world_error"] = "the [artguard] JSON line did not parse"
        else:
            out["world_error"] = "no [artguard] JSON line (the world run did not finish; see world.log)"
        out["world_script_errors"] = len(re.findall(r"SCRIPT ERROR", t))
        out["world_load_errors"] = sorted(set(re.findall(r"(?:Failed loading resource|Cannot open file|No loader found for resource|Resource file not found): ?(\S+)", t)))
    t = rd("city_walk.log")
    if t is not None:
        m = re.search(r"\[walk\] start town: (\d+) m2 free, (\d+) m2 reached from the pad, out of town to (.*?), (\d+) unreachable pockets.*?junk (\d+) pieces / (\d+) unreachable", t)
        out["city_walk"] = {"pass": "[walk] PASS" in t, "free_m2": int(m.group(1)) if m else None,
                            "reached_m2": int(m.group(2)) if m else None, "ways_out": m.group(3) if m else None,
                            "pockets": int(m.group(4)) if m else None,
                            "junk": int(m.group(5)) if m else None, "junk_unreachable": int(m.group(6)) if m else None}
    t = rd("site_reach.log")
    if t is not None:
        hubs = {}
        for m in re.finditer(r"^\[reach\] (\S+) hub (\d+) (\S+): (\d+)/(\d+) anchors reachable, (\d+) m2 walkable", t, re.M):
            hubs[m.group(2)] = {"site": m.group(3), "anchors": int(m.group(4)), "of": int(m.group(5)), "m2": int(m.group(6))}
        out["site_reach"] = {"pass": bool(re.search(r"^\[reach\] \S+: PASS", t, re.M)), "hubs": hubs}
    t = rd("target_reach.log")
    if t is not None:
        hubs = {}
        for m in re.finditer(r"^\[targets\] hub (\d+) \((\S+)\): (\d+) targets .*?, (\d+) unreachable", t, re.M):
            hubs[m.group(1)] = {"site": m.group(2), "targets": int(m.group(3)), "unreachable": int(m.group(4))}
        m = re.search(r"^\[targets\] (\d+) targets on (\d+) hubs, (\d+) unreachable", t, re.M)
        out["target_reach"] = {"pass": "[targets] PASS" in t, "hubs": hubs,
                               "targets": int(m.group(1)) if m else None, "unreachable": int(m.group(3)) if m else None}
    t = rd("perf.log")
    if t is not None:
        m = re.search(r"\[loader\] ready in (\d+) ms, longest frame (\d+) ms", t)
        hl = [float(h) for h in re.findall(r"^\[hitch\] t=[\d.]+s frame \d+ ms \(cpu (\d+)\)", t, re.M)]
        summ = re.findall(r"^\[hitch\] \d+s: (\d+) frames, (\d+) over \d+ ms, longest (\d+) ms", t, re.M)
        out["perf"] = {"ready_ms": int(m.group(1)) if m else None, "longest_frame_ms": int(m.group(2)) if m else None,
                       "hitches": len(hl), "frames": sum(int(x[0]) for x in summ) if summ else None,
                       "hitch_worst_ms": max(hl) if hl else 0.0,
                       "hitch_total_ms": round(sum(hl), 1)}
    t = rd("render.log")
    if t is not None:
        views = {}
        for m in re.finditer(r"^\[artguard-view\] (\S+) draw_calls=(\d+) objects=(\d+) prims=(\d+) tex_mem=(\d+) vmem=(\d+)", t, re.M):
            views[m.group(1)] = {"draw_calls": int(m.group(2)), "objects": int(m.group(3)), "prims": int(m.group(4)),
                                 "tex_mem": int(m.group(5)), "vmem": int(m.group(6))}
        out["render"] = views
    return out


# ---------------------------------------------------------------------------- compare
DEFAULT_MARGINS = {
    "load_ready_pct": 35.0,        # [loader] ready in N ms: the box is shared, so timings are noisy
    "load_ready_abs_ms": 4000,
    "longest_frame_pct": 50.0,
    "longest_frame_abs_ms": 400,
    "hitch_count_abs": 6,          # frames over 30 ms on the walk, more than baseline + this
    "hitch_count_pct": 50.0,
    "walk_m2_pct": 4.0,            # walkable / reached area of the start town
    "site_m2_pct": 6.0,            # walkable area per hub (site-reach)
    "model_tris_pct": 50.0,        # a model or builder over its baseline by more than this
    "model_tris_abs": 3000,
    "render_pct": 40.0,            # draw calls / primitives at the fixed views
    "tex_mem_pct": 40.0,
    "art_bytes_pct": 60.0,
}
DEFAULT_BUDGETS = {
    "glb_tris": 120000,            # one .glb, all its node instances
    "builder_tris": 200000,        # one procedural build (Lumi, a robot, a kit building)
    "lumi_tris": 150000,
    "robot_tris": 30000,
    "texture_px": 2048,            # the longest side of one texture
}


class Report:
    def __init__(self):
        self.fails, self.warns, self.passes = [], [], []

    def fail(self, area, msg):
        self.fails.append((area, msg))
        print("[artguard] FAIL %s: %s" % (area, msg))

    def warn(self, area, msg):
        self.warns.append((area, msg))
        print("[artguard] WARN %s: %s" % (area, msg))

    def ok(self, area, msg):
        self.passes.append((area, msg))
        print("[artguard] PASS %s: %s" % (area, msg))


def worse(now, base, pct, abs_):
    """now is worse than base by more than pct % and abs_."""
    if now is None or base is None:
        return False
    return now > base * (1.0 + pct / 100.0) and now - base > abs_


def compare_static(r, cur, base, margins, budgets, allow):
    bm = base.get("models", {})
    cm = cur.get("models", {})
    nfail = len(r.fails)
    for path, c in sorted(cm.items()):
        b = bm.get(path)
        if "error" in c:
            r.fail("model", "%s: %s" % (path, c["error"]))
            continue
        if c["tris"] > budgets["glb_tris"] and path not in allow.get("over_budget", []) and not (b and b["tris"] >= c["tris"]):
            r.fail("model", "%s: %d triangles, over the budget of %d per model" % (path, c["tris"], budgets["glb_tris"]))
        if b and worse(c["tris"], b["tris"], margins["model_tris_pct"], margins["model_tris_abs"]):
            r.fail("model", "%s: %d triangles, baseline %d (+%.0f%%)" % (path, c["tris"], b["tris"], 100.0 * (c["tris"] / max(b["tris"], 1) - 1)))
        if c["prims_without_material"] > (b["prims_without_material"] if b else 0):
            r.fail("model", "%s: %d mesh primitives with no material (Godot draws them default white)" % (path, c["prims_without_material"]))
        if c["blender_default_materials"] and not (b and b["blender_default_materials"]):
            r.warn("model", "%s: Blender's default material names %s (a material left unnamed?)" % (path, c["blender_default_materials"]))
        if b and b.get("generate_lods") and c.get("generate_lods") is False and not c.get("msft_lod"):
            r.fail("model", "%s: the old model had LODs (meshes/generate_lods=true), the new import has none" % path)
        if not b and c.get("generate_lods") is False and not c.get("msft_lod") and c["tris"] > 2000:
            r.fail("model", "%s: new model with %d triangles and no LODs (meshes/generate_lods=false)" % (path, c["tris"]))
        if c["max_image"] > budgets["texture_px"]:
            r.fail("model", "%s: an embedded image of %d px (budget %d)" % (path, c["max_image"], budgets["texture_px"]))
        if c.get("import_committed") is False and not (b and b.get("import_committed") is False):
            r.fail("model", "%s: its .import file is not committed (import settings are then whatever Godot defaults to)" % path)
        if b:
            gone = sorted(set(b.get("material_names", [])) - set(c.get("material_names", [])))
            if gone:
                r.warn("model", "%s: materials gone %s (code that sets materials by name finds nothing)" % (path, gone))
            agone = sorted(set(b.get("animations", [])) - set(c.get("animations", [])))
            if agone:
                r.fail("model", "%s: animations gone %s" % (path, agone))
    for path in sorted(set(bm) - set(cm)):
        r.warn("model", "%s: removed (the baseline had it; fine if no code loads it: the world run fails on a missing load)" % path)
    if len(r.fails) == nfail:
        r.ok("models", "%d models in art/, %d triangles in all, budgets and LODs hold" % (len(cm), sum(c.get("tris", 0) for c in cm.values())))
    # Textures.
    nfail = len(r.fails)
    bt = base.get("textures", {})
    for path, t in sorted(cur.get("textures", {}).items()):
        b = bt.get(path)
        if t["size"] and max(t["size"]) > budgets["texture_px"] and not (b and b["size"] and max(b["size"]) >= max(t["size"])):
            r.fail("texture", "%s: %dx%d, over the %d px budget" % (path, t["size"][0], t["size"][1], budgets["texture_px"]))
        if not t["import"]:
            r.fail("texture", "%s: no .import file (run the import; commit it)" % path)
            continue
        if t.get("import_committed") is False and not (b and b.get("import_committed") is False):
            r.fail("texture", "%s: its .import file is not committed" % path)
        if path.startswith("art/kit/decals/"):
            continue  # decal atlases (tools/kit_decals.py) keep lossless
        if b is None:
            if t["mode"] != "2":
                r.fail("texture", "%s: new texture without compress/mode=2 (VRAM compressed; CLAUDE.md Assets)" % path)
            if t["is_normal"] and t["normal_map"] != "1":
                r.fail("texture", "%s: new normal map without compress/normal_map=1" % path)
        else:
            if b["mode"] == "2" and t["mode"] != "2":
                r.fail("texture", "%s: compress/mode was 2, now %s" % (path, t["mode"]))
            if b.get("normal_map") == "1" and t["normal_map"] != "1":
                r.fail("texture", "%s: compress/normal_map was 1, now %s" % (path, t["normal_map"]))
    if len(r.fails) == nfail:
        r.ok("textures", "%d textures, import settings hold (new ones VRAM compressed)" % len(cur.get("textures", {})))
    # Sizes.
    if worse(cur["art_bytes"], base.get("art_bytes"), margins["art_bytes_pct"], 50 * 2 ** 20):
        r.fail("size", "art/ is %.0f MB, baseline %.0f MB" % (cur["art_bytes"] / 2 ** 20, base["art_bytes"] / 2 ** 20))
    else:
        r.ok("size", "art/ %.0f MB (baseline %.0f MB), est. texture memory %.0f MB (baseline %.0f MB)" % (
            cur["art_bytes"] / 2 ** 20, base.get("art_bytes", 0) / 2 ** 20, cur["texture_vram_est"] / 2 ** 20, base.get("texture_vram_est", 0) / 2 ** 20))
    if worse(cur["texture_vram_est"], base.get("texture_vram_est"), margins["tex_mem_pct"], 32 * 2 ** 20):
        r.fail("size", "estimated texture memory %.0f MB, baseline %.0f MB" % (cur["texture_vram_est"] / 2 ** 20, base["texture_vram_est"] / 2 ** 20))


def compare_world(r, cur, base, margins, budgets):
    if "world_error" in cur:
        r.fail("world", cur["world_error"])
        return
    w = cur.get("world")
    if w is None:
        return
    bw = base.get("world", {})
    for f in w.get("fails", []):
        r.fail(f.get("area", "world"), f.get("msg", str(f)))
    for f in w.get("warns", []):
        r.warn(f.get("area", "world"), f.get("msg", str(f)))
    allow = base.get("allow", {})
    # Mesh / collider audit: a walk-through spot or invisible wall the baseline did not have.
    aud, baud = w.get("audit", {}), bw.get("audit", {})
    for kind, label, allow_key in (("leaks", "walk-through (visible, no collider: Lumi passes through it)", "passable"),
                                   ("walls", "invisible wall (a collider with nothing visible over it)", "invisible")):
        new = []
        for x in aud.get(kind, []):
            if any(a in x["key"] for a in allow.get(allow_key, [])):
                continue
            if any(b["key"] == x["key"] and abs(b["at"][0] - x["at"][0]) + abs(b["at"][1] - x["at"][1]) < 2.5 for b in baud.get(kind, [])):
                continue
            new.append(x)
        for x in new[:12]:
            r.fail("collider", "%s: %s at site (%.1f, %.1f) size %s" % (label, x["key"], x["at"][0], x["at"][1], x["size"]))
        if len(new) > 12:
            r.fail("collider", "%d more %s spots (see world.log)" % (len(new) - 12, kind))
        gone = [b for b in baud.get(kind, []) if not any(b["key"] == x["key"] and abs(b["at"][0] - x["at"][0]) + abs(b["at"][1] - x["at"][1]) < 2.5 for x in aud.get(kind, []))]
        if not new:
            r.ok("collider", "no new %s spots in the start yard and town (%d now, %d in the baseline%s)" % (
                kind, len(aud.get(kind, [])), len(baud.get(kind, [])), ", %d of those gone" % len(gone) if gone else ""))
    # Rig contract, Locker, film: names that worked on the baseline and do not now.
    rig, brig = w.get("rig", {}), bw.get("rig", {})
    for k, what in (("missing", "member"), ("nodes_missing", "node"), ("anims_missing", "animation")):
        new = sorted(set(rig.get(k, [])) - set(brig.get(k, [])))
        if new:
            r.fail("rig", "Lumi's model lacks %ss the code uses: %s" % (what, ", ".join(new)))
    if rig and not any(set(rig.get(k, [])) - set(brig.get(k, [])) for k in ("missing", "nodes_missing", "anims_missing")):
        r.ok("rig", "every one of the %d model members, node names and animations the code uses exists on Lumi" % rig.get("members", 0))
    lk, blk = w.get("locker", {}), bw.get("locker", {})
    new = sorted(set(lk.get("dead", [])) - set(blk.get("dead", [])))
    if new:
        r.fail("locker", "Locker choices that no longer change Lumi: %s" % ", ".join(new))
    elif lk:
        r.ok("locker", "%d Locker choices tried, none newly without effect (%d change nothing now, %d in the baseline: %s)" % (
            lk.get("tried", 0), len(lk.get("dead", [])), len(blk.get("dead", [])), ", ".join(blk.get("dead", [])) or "-"))
    if lk and blk and lk.get("tried", 0) < blk.get("tried", 0):
        r.fail("locker", "%d Locker choices tried, baseline %d (options gone)" % (lk["tried"], blk["tried"]))
    fm, bfm = w.get("film", {}), bw.get("film", {})
    new = sorted(set(fm.get("bad", [])) - set(bfm.get("bad", [])))
    for b in new:
        r.fail("film", b)
    lost = sorted(set(bfm.get("nodes_found", [])) - set(fm.get("nodes_found", [])))
    if lost:
        r.fail("film", "nodes the opening film looks up by name are gone from its sets: %s" % ", ".join(lost))
    if fm and not new and not lost:
        r.ok("film", "%d shots: code, cues, lines, anchors and %d looked-up nodes all there" % (fm.get("shots", 0), len(fm.get("nodes_found", []))))
    # Lighting, sky and water settings: changes are listed for the merge (expected in a look pass).
    lk2, blk2 = w.get("look", {}), bw.get("look", {})
    changed = []
    moving = re.compile(r"(^|_)(t|time|phase|clock)$")

    def differs(x, y):
        if isinstance(x, (int, float)) and isinstance(y, (int, float)) and not isinstance(x, bool):
            return abs(x - y) > max(0.01 * max(abs(x), abs(y)), 1e-4)
        if isinstance(x, str) and isinstance(y, str) and re.fullmatch(r"[0-9a-f]{8}", x) and re.fullmatch(r"[0-9a-f]{8}", y):
            return max(abs(int(x[i:i + 2], 16) - int(y[i:i + 2], 16)) for i in range(0, 8, 2)) > 3
        return x != y
    for grp in sorted(set(lk2) | set(blk2)):
        a, b = lk2.get(grp, {}), blk2.get(grp, {})
        for k in sorted(set(a) | set(b)):
            if moving.search(k) or (isinstance(a.get(k), str) and a.get(k, "").startswith("(")):
                continue  # follows the clock (cloud drift, the sun and moon, the camera)
            if differs(a.get(k), b.get(k)):
                changed.append("%s.%s %s -> %s" % (grp, k, b.get(k), a.get(k)))
    if changed and blk2:
        r.warn("look", "%d lighting/sky/water settings changed: %s%s" % (len(changed), "; ".join(changed[:25]), " ..." if len(changed) > 25 else ""))
    elif lk2:
        r.ok("look", "lighting, sky and water settings as in the baseline")
    # Builders: triangles per procedural build.
    bb = bw.get("builders", {})
    nfail = len(r.fails)
    for k, c in sorted(w.get("builders", {}).items()):
        cap = budgets["lumi_tris"] if k.startswith("lumi/") else budgets["robot_tris"] if k.startswith("robot/") else budgets["builder_tris"]
        if c["tris"] > cap:
            r.fail("builder", "%s: %d triangles, budget %d" % (k, c["tris"], cap))
        b = bb.get(k)
        if b and worse(c["tris"], b["tris"], margins["model_tris_pct"], margins["model_tris_abs"]):
            r.fail("builder", "%s: %d triangles, baseline %d" % (k, c["tris"], b["tris"]))
        if c.get("white", 0) > (b.get("white", 0) if b else 0):
            r.fail("builder", "%s: %d visible surfaces with no material (default white), baseline %d" % (k, c["white"], b.get("white", 0) if b else 0))
    for k in sorted(set(bb) - set(w.get("builders", {}))):
        r.fail("builder", "%s: no longer builds (baseline had it)" % k)
    if len(r.fails) == nfail:
        r.ok("builders", "%d procedural builds within budget and baseline" % len(w.get("builders", {})))
    # Colliders: a changed census is news, not a fault by itself (the mesh/collider audit judges).
    bc, cc = bw.get("colliders", {}), w.get("colliders", {})
    for area in sorted(cc):
        c, b = cc[area], bc.get(area)
        if b and (c["count"] != b["count"] or c["hash"] != b["hash"]):
            r.warn("colliders", "%s: %d solid shapes (baseline %d), layout hash %s (baseline %s)" % (area, c["count"], b["count"], c["hash"], b["hash"]))
    if "white_surfaces" in w:
        b = bw.get("white_surfaces", {}).get("count", 0)
        c = w["white_surfaces"]["count"]
        if c > b:
            r.fail("materials", "%d visible surfaces in the start area with no material (default white), baseline %d; e.g. %s" % (c, b, w["white_surfaces"].get("eg", [])))
        else:
            r.ok("materials", "no new default-white surfaces in the start area (%d, baseline %d)" % (c, b))


def compare_reach(r, cur, base, margins):
    cw, bw = cur.get("city_walk"), base.get("city_walk")
    if cw is not None:
        if not cw["pass"]:
            r.fail("walk", "--city-walk FAILs (see city_walk.log)")
        if cw["reached_m2"] is None:
            r.fail("walk", "--city-walk printed no area (the run did not finish)")
        elif bw:
            for k in ("free_m2", "reached_m2"):
                d = 100.0 * (cw[k] - bw[k]) / max(bw[k], 1)
                if abs(d) > margins["walk_m2_pct"]:
                    r.fail("walk", "start town %s %d m2, baseline %d (%+.1f%%; more = a wall gone, less = a new wall or a shut-in)" % (k, cw[k], bw[k], d))
            if cw["pockets"] > bw["pockets"]:
                r.fail("walk", "%d unreachable pockets in the start town, baseline %d" % (cw["pockets"], bw["pockets"]))
            if cw["junk_unreachable"] > bw["junk_unreachable"]:
                r.fail("walk", "%d junk pieces unreachable, baseline %d" % (cw["junk_unreachable"], bw["junk_unreachable"]))
            if cw["ways_out"] != bw["ways_out"]:
                r.fail("walk", "ways out of town: %s, baseline %s" % (cw["ways_out"], bw["ways_out"]))
        if cw["reached_m2"] is not None and not any(m[0] == "walk" for m in r.fails):
            r.ok("walk", "start town %d m2 free, %d m2 reached (baseline %s / %s)" % (cw["free_m2"], cw["reached_m2"], bw["free_m2"] if bw else "-", bw["reached_m2"] if bw else "-"))
    cs, bs = cur.get("site_reach"), base.get("site_reach")
    if cs is not None:
        n0 = len(r.fails)
        if not cs["pass"]:
            r.fail("reach", "--site-reach FAILs (see site_reach.log)")
        if not cs["hubs"]:
            r.fail("reach", "--site-reach printed no hubs (the run did not finish)")
        for h, c in sorted(cs["hubs"].items(), key=lambda x: int(x[0])):
            b = (bs or {}).get("hubs", {}).get(h)
            if c["anchors"] < c["of"]:
                r.fail("reach", "hub %s %s: %d/%d anchors reachable" % (h, c["site"], c["anchors"], c["of"]))
            if b:
                d = 100.0 * (c["m2"] - b["m2"]) / max(b["m2"], 1)
                if abs(d) > margins["site_m2_pct"]:
                    r.fail("reach", "hub %s %s: %d m2 walkable from the pad, baseline %d (%+.1f%%)" % (h, c["site"], c["m2"], b["m2"], d))
        if bs:
            for h in sorted(set(bs["hubs"]) - set(cs["hubs"])):
                r.fail("reach", "hub %s: no [reach] line (baseline had one)" % h)
        if len(r.fails) == n0:
            r.ok("reach", "%d hubs: every anchor reachable, walkable areas within %.0f%% of baseline" % (len(cs["hubs"]), margins["site_m2_pct"]))
    ct, bt = cur.get("target_reach"), base.get("target_reach")
    if ct is not None:
        n0 = len(r.fails)
        if not ct["pass"]:
            r.fail("targets", "--target-reach FAILs: %s unreachable (see target_reach.log)" % ct["unreachable"])
        if ct["targets"] is None:
            r.fail("targets", "--target-reach printed no total (the run did not finish)")
        elif bt and bt.get("targets") is not None and ct["targets"] < bt["targets"]:
            r.fail("targets", "%d targets, baseline %d (targets lost)" % (ct["targets"], bt["targets"]))
        if len(r.fails) == n0:
            r.ok("targets", "%s targets, %s unreachable (baseline %s)" % (ct["targets"], ct["unreachable"], bt.get("targets") if bt else "-"))


def compare_perf(r, cur, base, margins):
    c, b = cur.get("perf"), base.get("perf")
    if c is None:
        return
    n0 = len(r.fails)
    if c["ready_ms"] is None:
        r.fail("perf", "no '[loader] ready' line (the load did not finish; see perf.log)")
        return
    if b:
        if worse(c["ready_ms"], b["ready_ms"], margins["load_ready_pct"], margins["load_ready_abs_ms"]):
            r.fail("perf", "loaded in %d ms, baseline %d ms" % (c["ready_ms"], b["ready_ms"]))
        if worse(c["longest_frame_ms"], b["longest_frame_ms"], margins["longest_frame_pct"], margins["longest_frame_abs_ms"]):
            r.fail("perf", "longest load frame %d ms, baseline %d ms" % (c["longest_frame_ms"], b["longest_frame_ms"]))
        if worse(c["hitches"], b["hitches"], margins["hitch_count_pct"], margins["hitch_count_abs"]):
            r.fail("perf", "%d hitches (frames over 30 ms) on the walk, baseline %d" % (c["hitches"], b["hitches"]))
    if len(r.fails) == n0:
        r.ok("perf", "loaded in %d ms, longest frame %d ms, %d hitches on the walk (baseline %s ms / %s ms / %s)" % (
            c["ready_ms"], c["longest_frame_ms"], c["hitches"], b["ready_ms"] if b else "-", b["longest_frame_ms"] if b else "-", b["hitches"] if b else "-"))


def compare_render(r, cur, base, margins):
    c, b = cur.get("render"), base.get("render")
    if not c:
        return
    n0 = len(r.fails)
    for v, x in sorted(c.items()):
        y = (b or {}).get(v)
        if not y:
            continue
        for k, pct in (("draw_calls", margins["render_pct"]), ("prims", margins["render_pct"]), ("tex_mem", margins["tex_mem_pct"])):
            if worse(x[k], y[k], pct, 0):
                r.fail("render", "view %s: %s %d, baseline %d" % (v, k, x[k], y[k]))
    if len(r.fails) == n0:
        r.ok("render", "%d views within baseline: %s" % (len(c), ", ".join("%s %d calls %.1fM prims" % (v, x["draw_calls"], x["prims"] / 1e6) for v, x in sorted(c.items()))))


def compare(d, write=False, baseline=BASELINE):
    cur = {}
    sp = os.path.join(d, "static.json")
    if os.path.exists(sp):
        cur["static"] = json.load(open(sp))
    cur.update(parse_logs(d))
    base = json.load(open(baseline)) if os.path.exists(baseline) else {}
    if write:
        unfinished = [k for k, v in (("world", cur.get("world_error")), ("city_walk", (cur.get("city_walk") or {}).get("reached_m2", 0) is None),
                                     ("site_reach", "site_reach" in cur and not cur["site_reach"]["hubs"]),
                                     ("target_reach", "target_reach" in cur and cur["target_reach"]["targets"] is None),
                                     ("perf", "perf" in cur and cur["perf"]["ready_ms"] is None)) if v]
        if unfinished:
            print("[artguard] FAIL baseline not written: these runs did not finish: %s" % ", ".join(unfinished))
            return 1
        keep = {k: base[k] for k in ("margins", "budgets", "allow", "_doc") if k in base}
        for k, v in cur.items():
            if k.endswith("_error") or k == "world_script_errors" or (k == "world" and v.get("fault")):
                continue
            base[k] = v
        base.update(keep)
        base.setdefault("margins", DEFAULT_MARGINS)
        base.setdefault("budgets", DEFAULT_BUDGETS)
        base.setdefault("allow", {"over_budget": []})
        try:
            base["sha"] = subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        except Exception:  # noqa: BLE001
            pass
        json.dump(base, open(baseline, "w"), indent=1, sort_keys=True)
        open(baseline, "a").write("\n")
        print("[artguard] baseline written: %s (%s)" % (os.path.relpath(baseline, ROOT), ", ".join(sorted(k for k in cur if not k.endswith("_error")))))
        return 0
    margins = dict(DEFAULT_MARGINS, **base.get("margins", {}))
    budgets = dict(DEFAULT_BUDGETS, **base.get("budgets", {}))
    allow = base.get("allow", {})
    r = Report()
    if "static" in cur:
        compare_static(r, cur["static"], base.get("static", {}), margins, budgets, allow)
    compare_world(r, cur, base, margins, budgets)
    lost = sorted(set(cur.get("world_load_errors", [])) - set(base.get("world_load_errors", [])))
    if lost:
        r.fail("world", "resources that failed to load: %s" % ", ".join(lost[:10]))
    if cur.get("world_script_errors"):
        r.fail("world", "%d SCRIPT ERROR lines in world.log" % cur["world_script_errors"])
    compare_reach(r, cur, base, margins)
    compare_perf(r, cur, base, margins)
    compare_render(r, cur, base, margins)
    planted = (cur.get("world") or {}).get("fault", "")
    if planted:
        expect = {"walkthrough": ("collider", "PlantedCrate"), "invisible": ("collider", "PlantedWall"), "white": ("materials", "no material"),
                  "rig": ("rig", "set_wing_flap"), "locker": ("locker", "colour eyes"), "film": ("film", "open_wing_flap"), "tris": ("builder", "lumi/aurora")}
        for f in planted.split(","):
            a, pat = expect.get(f, ("?", "?"))
            hit = any(x[0] == a and pat in x[1] for x in r.fails)
            print("[artguard] planted fault %s: %s" % (f, "caught (%s FAIL)" % a if hit else "NOT CAUGHT"))
    print("[artguard] %s: %d fail, %d warn, %d pass (baseline %s)" % ("FAIL" if r.fails else "PASS", len(r.fails), len(r.warns), len(r.passes), base.get("sha", "none")))
    return 1 if r.fails else 0


# ---------------------------------------------------------------------------- self-test
def _glb(path, tris=12, material=True, lods=True, img=None):
    """Writes a tiny glb (a triangle list) and its .import."""
    n = tris * 3
    pos = b"".join(struct.pack("<3f", float(i % 3), float(i // 3 % 2), 0.0) for i in range(n))
    binb = pos
    j = {"asset": {"version": "2.0"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"mesh": 0, "name": "Body"}],
         "meshes": [{"primitives": [dict({"attributes": {"POSITION": 0}}, **({"material": 0} if material else {}))]}],
         "materials": [{"name": "paint"}] if material else [],
         "accessors": [{"bufferView": 0, "componentType": 5126, "count": n, "type": "VEC3", "min": [0, 0, 0], "max": [2, 1, 0]}],
         "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": len(pos)}], "buffers": [{"byteLength": len(pos)}]}
    if img:
        png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", img, img) + b"\x08\x06\x00\x00\x00" + b"\0" * 4
        while len(binb) % 4:
            binb += b"\0"
        j["bufferViews"].append({"buffer": 0, "byteOffset": len(binb), "byteLength": len(png)})
        j["images"] = [{"bufferView": 1, "mimeType": "image/png"}]
        binb += png
        j["buffers"][0]["byteLength"] = len(binb)
    js = json.dumps(j).encode()
    while len(js) % 4:
        js += b" "
    while len(binb) % 4:
        binb += b"\0"
    body = struct.pack("<I4s", len(js), b"JSON") + js + struct.pack("<I4s", len(binb), b"BIN\0") + binb
    open(path, "wb").write(b"glTF" + struct.pack("<II", 2, 12 + len(body)) + body)
    open(path + ".import", "w").write("[params]\n\nmeshes/generate_lods=%s\n" % ("true" if lods else "false"))


def _tex(path, mode="2", normal="0", size=512):
    png = b"\x89PNG\r\n\x1a\n" + struct.pack(">I", 13) + b"IHDR" + struct.pack(">II", size, size) + b"\x08\x06\x00\x00\x00"
    open(path, "wb").write(png)
    open(path + ".import", "w").write("[params]\n\ncompress/mode=%s\ncompress/normal_map=%s\n" % (mode, normal))


def self_test():
    """Each file-side fault planted on a tiny art/ tree must FAIL; the clean tree must PASS."""
    import contextlib
    import io
    ok = True

    def run(setup, expect_fail, label, base_setup=None):
        nonlocal ok
        with tempfile.TemporaryDirectory() as td:
            os.makedirs(os.path.join(td, "art/models/x"))
            os.makedirs(os.path.join(td, "art/vendor/t"))
            _glb(os.path.join(td, "art/models/x/bot.glb"), tris=100)
            _tex(os.path.join(td, "art/vendor/t/wall_diff_1k.png"))
            _tex(os.path.join(td, "art/vendor/t/wall_nor_gl_1k.png"), normal="1")
            if base_setup:
                base_setup(td)
            base = static_census(td)
            setup(td)
            cur = static_census(td)
            for c in list(base["models"].values()) + list(cur["models"].values()) + list(base["textures"].values()) + list(cur["textures"].values()):
                c["import_committed"] = None  # not a git tree
            r = Report()
            buf = io.StringIO()
            with contextlib.redirect_stdout(buf):
                compare_static(r, cur, base, DEFAULT_MARGINS, DEFAULT_BUDGETS, {})
            got = bool(r.fails)
            good = got == expect_fail
            ok = ok and good
            print("[artguard-selftest] %s %s: %s" % ("ok  " if good else "MISS", label, r.fails[0][1] if r.fails else "no fail"))

    run(lambda td: None, False, "clean tree passes")
    run(lambda td: _glb(os.path.join(td, "art/models/x/bot.glb"), tris=100, material=False), True, "a primitive lost its material")
    run(lambda td: _glb(os.path.join(td, "art/models/x/bot.glb"), tris=100, lods=False), True, "LODs turned off on a model that had them")
    run(lambda td: _glb(os.path.join(td, "art/models/x/bot.glb"), tris=200000), True, "a model over the triangle budget")
    run(lambda td: _glb(os.path.join(td, "art/models/x/bot.glb"), tris=9000), True, "a model far above its baseline")
    run(lambda td: _glb(os.path.join(td, "art/models/x/new.glb"), tris=5000, lods=False), True, "a new model without LODs")
    run(lambda td: _glb(os.path.join(td, "art/models/x/bot.glb"), tris=100, img=4096), True, "a 4K embedded texture")
    run(lambda td: _tex(os.path.join(td, "art/vendor/t/new_diff_1k.png"), mode="0"), True, "a new texture without VRAM compression")
    run(lambda td: _tex(os.path.join(td, "art/vendor/t/new_nor_gl_1k.png"), mode="2", normal="0"), True, "a new normal map without normal_map=1")
    run(lambda td: _tex(os.path.join(td, "art/vendor/t/wall_diff_1k.png"), mode="0"), True, "an old texture's compression turned off")
    run(lambda td: os.remove(os.path.join(td, "art/vendor/t/wall_diff_1k.png.import")), True, "a texture's .import missing")
    run(lambda td: _tex(os.path.join(td, "art/vendor/t/new_diff_1k.png")), False, "a good new texture passes")
    # The numbers side: walks, reach and timings against a baseline (as parse_logs gives them).
    base = {"city_walk": {"pass": True, "free_m2": 40000, "reached_m2": 38000, "ways_out": "every side", "pockets": 2, "junk": 500, "junk_unreachable": 0},
            "site_reach": {"pass": True, "hubs": {"0": {"site": "a", "anchors": 6, "of": 6, "m2": 9000}}},
            "target_reach": {"pass": True, "hubs": {}, "targets": 80, "unreachable": 0},
            "perf": {"ready_ms": 20000, "longest_frame_ms": 600, "hitches": 4, "hitch_worst_ms": 80, "hitch_total_ms": 200},
            "world": {"audit": {"leaks": [{"key": "YardSite/x/Crate", "at": [3.0, 4.0], "size": [1, 1, 1]}], "walls": []},
                      "rig": {"missing": [], "members": 40}, "locker": {"tried": 30, "dead": []}, "film": {"bad": [], "nodes_found": ["Hatch"], "shots": 21},
                      "builders": {"lumi/aurora": {"tris": 20000, "white": 0}}, "colliders": {}}}

    def num(label, mutate, expect_fail):
        nonlocal ok
        import copy
        cur = copy.deepcopy(base)
        mutate(cur)
        r = Report()
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            compare_reach(r, cur, base, DEFAULT_MARGINS)
            compare_perf(r, cur, base, DEFAULT_MARGINS)
            compare_world(r, cur, base, DEFAULT_MARGINS, DEFAULT_BUDGETS)
        good = bool(r.fails) == expect_fail
        ok = ok and good
        print("[artguard-selftest] %s %s: %s" % ("ok  " if good else "MISS", label, r.fails[0][1] if r.fails else "no fail"))

    num("same numbers pass", lambda c: None, False)
    num("timing noise inside the margin passes", lambda c: c["perf"].update(ready_ms=23000, hitches=7), False)
    num("the town's walkable area shrank", lambda c: c["city_walk"].update(reached_m2=35000), True)
    num("a wall gone: more walkable area", lambda c: c["city_walk"].update(free_m2=43000), True)
    num("a new shut-in pocket", lambda c: c["city_walk"].update(pockets=3), True)
    num("a hub's anchor cut off", lambda c: c["site_reach"]["hubs"]["0"].update(anchors=5), True)
    num("a target unreachable", lambda c: c["target_reach"].update(**{"pass": False, "unreachable": 1}), True)
    num("load time far worse", lambda c: c["perf"].update(ready_ms=32000), True)
    num("longest frame far worse", lambda c: c["perf"].update(longest_frame_ms=1400), True)
    num("many more hitches", lambda c: c["perf"].update(hitches=14), True)
    num("the load did not finish", lambda c: c["perf"].update(ready_ms=None), True)
    num("the baseline's own leak moved a little passes", lambda c: c["world"]["audit"]["leaks"][0].update(at=[3.5, 4.5]), False)
    num("a new walk-through spot", lambda c: c["world"]["audit"]["leaks"].append({"key": "KitBuilding/x/Wall", "at": [10.0, 2.0], "size": [3, 2, 0.2]}), True)
    num("a new invisible wall", lambda c: c["world"]["audit"]["walls"].append({"key": "SiteBody/x/Box", "at": [10.0, 2.0], "size": [3, 2, 0.2], "seen": 0.0}), True)
    num("a rig member gone", lambda c: c["world"]["rig"].update(missing=["set_motion (patch.gd)"]), True)
    num("a Locker choice dead", lambda c: c["world"]["locker"].update(dead=["head halo"]), True)
    num("a film node gone", lambda c: c["world"]["film"].update(nodes_found=[]), True)
    num("Lumi far heavier", lambda c: c["world"]["builders"]["lumi/aurora"].update(tris=45000), True)
    num("a builder gone", lambda c: c["world"].update(builders={}), True)
    print("[artguard-selftest] %s" % ("PASS" if ok else "FAIL"))
    return 0 if ok else 1


def main(argv):
    if len(argv) >= 3 and argv[1] == "static":
        c = static_census()
        json.dump(c, open(argv[2], "w"), indent=1, sort_keys=True)
        print("[artguard] static census: %d models, %d textures, art/ %.0f MB" % (len(c["models"]), len(c["textures"]), c["art_bytes"] / 2 ** 20))
        return 0
    if len(argv) >= 3 and argv[1] == "compare":
        bl = BASELINE
        if "--baseline" in argv:
            bl = argv[argv.index("--baseline") + 1]
        return compare(argv[2], "--write-baseline" in argv, bl)
    if len(argv) >= 2 and argv[1] == "self-test":
        return self_test()
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
