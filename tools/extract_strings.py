#!/usr/bin/env python3
"""Builds the translation template locale/greenfall.pot and the pseudo-locale locale/pseudo.po,
and merges new strings into every other locale/*.po. Rerunnable: existing translations are kept,
new msgids are added empty, msgids that disappeared are kept as obsolete (#~) entries.

Sources:
  * GDScript: tr("..."), tr("...", "context"), atr("..."), _t("...") (a local tr wrapper), tr_n("one", "many", n),
    TranslationServer.translate("...") / translate_plural(...). A line (or the block between
    `# l10n:begin` and `# l10n:end`) marked with a `# l10n` comment also has every prose literal
    on it extracted: use that for const tables that are translated where they are shown.
    A `# TRANSLATORS: ...` comment on the line(s) just above a call becomes a translator note.
  * Scenes (.tscn): text / tooltip_text / placeholder_text / title properties.
  * data/*.json: the player-facing fields listed in JSON_RULES below.

Usage:  python3 tools/extract_strings.py [--check]
  --check  exit 1 if the POT on disk is out of date (for CI), write nothing.
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import OrderedDict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOCALE_DIR = os.path.join(ROOT, "locale")
POT_PATH = os.path.join(LOCALE_DIR, "greenfall.pot")
PSEUDO_PATH = os.path.join(LOCALE_DIR, "pseudo.po")

# Folders never scanned (dev tools, tests, vendored addons, store-art renderers).
SKIP_DIRS = {".godot", "addons", "tests", "website", "builds", "build", "screenshots", ".git"}
SKIP_FILES = {"tools/steam", "steam/store_art.gd", "steam/store_shots.gd"}

# --- JSON rules --------------------------------------------------------------------------------
# Keys whose string values (or nested string arrays) are shown to the player, per file.
# "*" = defaults for any file not listed. A rule value of "ALL" means every string under that
# top-level key (line pools). Keys starting with "_" are docs and never extracted.
COMMON_KEYS = {"name", "desc", "hint", "text", "text_1", "title", "body", "lore", "toast", "prompt",
               "final_prompt", "hud", "tagline", "unit", "header", "lines", "label", "subtitle",
               "caption", "quote", "short"}
JSON_RULES: dict[str, dict] = {
    "*": {"keys": COMMON_KEYS},
    "wren_lines.json": {"all_top": True},
    "shards.json": {"keys": COMMON_KEYS | {"kind"}},
    "ledger.json": {"keys": COMMON_KEYS, "pools": {"act1", "act2", "act3", "coupons", "drop_warn", "friendly",
                                                   "jammed", "lonely", "cinematic"}},
    "events.json": {"keys": COMMON_KEYS, "pools": {"wren"}},
    "songs.json": {"keys": COMMON_KEYS | {"genre", "bio"}},  # [tunes] artists and songs
    # Data-only files: nothing player-facing (asset lists, tuning, Steam API stat names).
    "assets.json": {"skip": True},
    "steam.json": {"skip": True},
    "patch.json": {"skip": True},
    "planet.json": {"skip": True},
    "lumi_level.json": {"skip": True},
    "world_looks.json": {"skip": True},  # [worlds2] look tuning only
}
# Strings that look like ids, colours, paths or speaker tags are never extracted from pools.
ID_KEYS = {"id", "icon", "ears", "shape", "style", "pattern", "action", "mode", "kind", "type", "body", "anim", "set", "source", "stat", "look"}
SPEAKERS = {"wren", "ledger", "lumi", "patch", "narrator", "sys"}

# --- GDScript patterns ------------------------------------------------------------------------
STR = r'"((?:[^"\\\n]|\\.)*)"'
SSTR = r"'((?:[^'\\\n]|\\.)*)'"
ANY = r'(?:%s|%s)' % (STR, SSTR)
RE_TR = re.compile(r'(?<![\w.])(?:tr|atr|_t|TranslationServer\.translate)\(\s*' + ANY + r'(?:\s*,\s*' + ANY + r')?\s*\)')
RE_TRN = re.compile(r'(?<![\w.])(?:tr_n|atr_n|TranslationServer\.translate_plural)\(\s*' + ANY + r'\s*,\s*' + ANY
                    + r'\s*,[^,()]*(?:\([^()]*\))?[^,()]*(?:,\s*' + ANY + r')?\s*\)')
RE_LIT = re.compile(r'(?<![&^\w])' + STR)
RE_TSCN = re.compile(r'^(text|tooltip_text|placeholder_text|title) = "((?:[^"\\]|\\.)*)"\s*$')


def gd_unescape(s: str) -> str:
    """GDScript string escapes -> real text."""
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            n = s[i + 1]
            m = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "'": "'", "\\": "\\", "a": "\a", "b": "\b",
                 "f": "\f", "v": "\v"}
            if n in m:
                out.append(m[n])
                i += 2
                continue
            if n == "u" and i + 6 <= len(s):
                out.append(chr(int(s[i + 2:i + 6], 16)))
                i += 6
                continue
            if n == "U" and i + 8 <= len(s):
                out.append(chr(int(s[i + 2:i + 8], 16)))
                i += 8
                continue
            out.append(n)
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def po_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t").replace("\r", "\\r")


def po_unescape(s: str) -> str:
    return gd_unescape(s)


def is_prose(t: str) -> bool:
    """Heuristic for `# l10n`-marked lines and JSON pools: words, not ids/paths/colours."""
    if not re.search(r"[A-Za-z]{2,}", t):
        return False
    if t.startswith(("res://", "user://", "#", "--")):
        return False
    if " " not in t.strip() and ("_" in t or "/" in t or re.match(r"^[a-z0-9.\-]+$", t)):
        return False
    return True


class Catalog:
    def __init__(self) -> None:
        # key (ctx, msgid) -> dict(plural, refs[], comments[])
        self.entries: "OrderedDict[tuple, dict]" = OrderedDict()

    def add(self, msgid: str, ref: str, ctx: str = "", plural: str = "", comment: str = "") -> None:
        if msgid.strip() == "":
            return
        key = (ctx, msgid)
        e = self.entries.get(key)
        if e is None:
            e = {"plural": plural, "refs": [], "comments": []}
            self.entries[key] = e
        if plural and not e["plural"]:
            e["plural"] = plural
        if ref not in e["refs"]:
            e["refs"].append(ref)
        if comment and comment not in e["comments"]:
            e["comments"].append(comment)


def rel(p: str) -> str:
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def walk_files(ext: str):
    for dp, dn, fn in os.walk(ROOT):
        r = rel(dp)
        dn[:] = sorted(d for d in dn if d not in SKIP_DIRS and not (r + "/" + d).lstrip("./") in SKIP_FILES)
        if r.split("/")[0] in SKIP_DIRS:
            continue
        for f in sorted(fn):
            if f.endswith(ext):
                p = os.path.join(dp, f)
                if rel(p) in SKIP_FILES:
                    continue
                yield p


def grp(m, a: int, b: int) -> str | None:
    v = m.group(a)
    if v is None:
        v = m.group(b)
    return v


def scan_gd(cat: Catalog, path: str) -> None:
    r = rel(path)
    note: list[str] = []
    block = False
    with open(path, encoding="utf-8") as fh:
        for no, line in enumerate(fh, 1):
            s = line.strip()
            if s.startswith("#"):
                m = re.match(r"#\s*TRANSLATORS:\s*(.*)", s)
                if m:
                    note.append(m.group(1))
                elif "l10n:begin" in s:
                    block = True
                elif "l10n:end" in s:
                    block = False
                continue
            comment = " ".join(note)
            ref = "%s:%d" % (r, no)
            for m in RE_TRN.finditer(line):
                one, many = grp(m, 1, 2), grp(m, 3, 4)
                ctx = grp(m, 5, 6) or ""
                cat.add(gd_unescape(one), ref, gd_unescape(ctx), gd_unescape(many), comment)
            for m in RE_TR.finditer(line):
                msg = grp(m, 1, 2)
                ctx = grp(m, 3, 4) or ""
                cat.add(gd_unescape(msg), ref, gd_unescape(ctx), "", comment)
            code = line.split(" #", 1)[0] if " #" in line else line
            if block or re.search(r"#\s*l10n\b", line):
                for m in RE_LIT.finditer(code):
                    t = gd_unescape(m.group(1))
                    if code[m.end():].lstrip().startswith(":"):
                        continue  # a dict key (an id)
                    key = re.search(r'"(\w+)"\s*:\s*$', code[:m.start()])
                    # Lower-case single words are ids, except as the value of a non-id key.
                    if is_prose(t) or (key and key.group(1) not in ID_KEYS and re.match(r"^[a-z][a-z ]*$", t)):
                        cat.add(t, ref, "", "", comment)
            if s:
                note = []


def scan_tscn(cat: Catalog, path: str) -> None:
    r = rel(path)
    with open(path, encoding="utf-8") as fh:
        for no, line in enumerate(fh, 1):
            m = RE_TSCN.match(line)
            if m and is_prose(gd_unescape(m.group(2))):
                cat.add(gd_unescape(m.group(2)), "%s:%d" % (r, no))


def scan_json(cat: Catalog, path: str) -> None:
    name = os.path.basename(path)
    rule = JSON_RULES.get(name, JSON_RULES["*"])
    if rule.get("skip"):
        return
    keys = rule.get("keys", COMMON_KEYS)
    pools = rule.get("pools", set())
    r = rel(path)
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)

    def take_all(v, ref, field=False):
        if isinstance(v, str):
            # A named player-facing field takes any word; line pools only take prose.
            ok = re.search(r"[A-Za-z]", v) if field else re.search(r"[A-Za-z]{2,}", v) and v.lower() not in SPEAKERS \
                and not re.match(r"^[a-z0-9]+(_[a-z0-9]+)+$", v)
            if ok:
                cat.add(v, ref)
        elif isinstance(v, list):
            for x in v:
                take_all(x, ref, field)
        elif isinstance(v, dict):
            for k, x in v.items():
                if not k.startswith("_"):
                    take_all(x, ref)

    def walk(v, path_s):
        if isinstance(v, dict):
            for k, x in v.items():
                if k.startswith("_"):
                    continue
                p = path_s + "." + k
                if k in keys and (isinstance(x, str) or isinstance(x, list)):
                    take_all(x, r + ":" + p.lstrip("."), True)
                else:
                    walk(x, p)
        elif isinstance(v, list):
            for i, x in enumerate(v):
                ident = x.get("id") if isinstance(x, dict) else None
                walk(x, path_s + "[%s]" % (ident if ident is not None else i))

    if rule.get("all_top"):
        for k, x in data.items():
            if not k.startswith("_"):
                take_all(x, r + ":" + k)
        return
    for k, x in data.items():
        if k.startswith("_"):
            continue
        if k in pools:
            take_all(x, r + ":" + k)
        else:
            walk(x, k)


# --- PO writing / reading ------------------------------------------------------------------------

def po_str(keyword: str, s: str) -> str:
    if "\n" in s[:-1]:
        parts = s.split("\n")
        lines = [p + "\n" for p in parts[:-1]] + ([parts[-1]] if parts[-1] else [])
        return '%s ""\n' % keyword + "".join('"%s"\n' % po_escape(x) for x in lines)
    return '%s "%s"\n' % (keyword, po_escape(s))


def header(lang: str, plural: str) -> str:
    h = ("Project-Id-Version: Greenfall\\n\nReport-Msgid-Bugs-To: \\n\nMIME-Version: 1.0\\n\n"
         "Content-Type: text/plain; charset=UTF-8\\n\nContent-Transfer-Encoding: 8bit\\n\n")
    if lang:
        h += "Language: %s\\n\n" % lang
    if plural:
        h += "Plural-Forms: %s\\n\n" % plural
    return 'msgid ""\nmsgstr ""\n' + "".join('"%s"\n' % x for x in h.split("\n") if x)


def write_po(path: str, cat: Catalog, lang: str, plural: str, translations: dict | None,
             obsolete: dict | None = None, preamble: str = "") -> str:
    out = [preamble, header(lang, plural)]
    nplurals = 2
    m = re.search(r"nplurals\s*=\s*(\d+)", plural or "")
    if m:
        nplurals = int(m.group(1))
    for (ctx, msgid), e in cat.entries.items():
        out.append("\n")
        for c in e["comments"]:
            out.append("#. %s\n" % c)
        refs = e["refs"]
        for i in range(0, len(refs), 3):
            out.append("#: %s\n" % " ".join(refs[i:i + 3]))
        if ctx:
            out.append(po_str("msgctxt", ctx))
        out.append(po_str("msgid", msgid))
        tr = (translations or {}).get((ctx, msgid))
        if e["plural"]:
            out.append(po_str("msgid_plural", e["plural"]))
            forms = tr if isinstance(tr, list) else []
            for i in range(nplurals if lang else 2):
                out.append(po_str("msgstr[%d]" % i, forms[i] if i < len(forms) else ""))
        else:
            out.append(po_str("msgstr", tr if isinstance(tr, str) else ""))
    def obs(text: str) -> str:
        # [money] Every line of an obsolete entry gets "#~ ": a bare continuation line of a
        # multi-line string is read by Godot as part of the previous live msgstr.
        return "".join("#~ " + ln + "\n" for ln in text.rstrip("\n").split("\n"))

    for (ctx, msgid), tr in (obsolete or {}).items():
        if not tr:
            continue
        out.append("\n")
        if ctx:
            out.append(obs(po_str("msgctxt", ctx)))
        out.append(obs(po_str("msgid", msgid)))
        if isinstance(tr, list):
            for i, f in enumerate(tr):
                out.append(obs(po_str("msgstr[%d]" % i, f)))
        else:
            out.append(obs(po_str("msgstr", tr)))
    text = "".join(out)
    return text


def read_po(path: str) -> tuple[dict, dict]:
    """-> (translations {(ctx, msgid): str | [forms]}, header fields)."""
    entries: dict = {}
    head: dict = {}
    cur: dict = {}
    field = None

    def flush():
        nonlocal cur
        if "msgid" in cur:
            ctx = cur.get("msgctxt", "")
            if cur["msgid"] == "" and not ctx:
                for line in cur.get("msgstr", "").split("\n"):
                    if ":" in line:
                        k, v = line.split(":", 1)
                        head[k.strip()] = v.strip()
            elif cur.get("plurals"):
                entries[(ctx, cur["msgid"])] = [cur["plurals"][i] for i in sorted(cur["plurals"])]
            else:
                entries[(ctx, cur["msgid"])] = cur.get("msgstr", "")
        cur = {}

    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if line.startswith("#~ "):
                line = line[3:].strip()
            if line.startswith("#") or not line:
                if not line and cur:
                    flush()
                continue
            m = re.match(r'^(msgctxt|msgid_plural|msgid|msgstr(?:\[(\d+)\])?)\s+"(.*)"$', line)
            if m:
                kw, idx, val = m.group(1), m.group(2), po_unescape(m.group(3))
                if kw in ("msgid", "msgctxt") and ("msgstr" in cur or cur.get("plurals")):
                    flush()
                if idx is not None:
                    cur.setdefault("plurals", {})[int(idx)] = val
                    field = ("p", int(idx))
                else:
                    cur[kw] = val
                    field = kw
                continue
            m = re.match(r'^"(.*)"$', line)
            if m and field:
                val = po_unescape(m.group(1))
                if isinstance(field, tuple):
                    cur["plurals"][field[1]] += val
                else:
                    cur[field] += val
    flush()
    return entries, head


# --- Pseudo-locale -----------------------------------------------------------------------------

ACCENTS = dict(zip(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ",
    "àbçðéƒĝĥîĵķļmñôþqŕšţûvŵxýžÀBÇÐÉFĜĤÎĴĶĻMÑÔÞQŔŠŢÛVŴXÝŽ"))
# Only Latin-1 / Latin Extended-A (plus ƒ), so the pseudo text renders in every UI font we ship;
# b, m, q, v, x have no accented form there and stay plain.
# Format specs, {placeholders}, [bbcode] tags, escapes and glyph templates stay untouched.
TOKEN = re.compile(r"%%|%[-+ 0#]*(?:\d+|\*)?(?:\.\d+)?[sdifxXoceEgGvc]|\{[^{}\s]*\}|\[/?[a-z_]+(?:=[^\]]*)?\]|\n|\t")


def pseudo(s: str) -> str:
    if s.strip() == "":
        return s
    # Interaction prompts start with the key letter ("E   read the sign"); the HUD swaps it for
    # the current glyph, so it must stay a plain leading "E".
    m = re.match(r"^E {2,}", s)
    if m:
        return m.group(0) + pseudo(s[m.end():])
    out, pos, letters = [], 0, 0
    for m in TOKEN.finditer(s):
        chunk = s[pos:m.start()]
        letters += sum(c.isalpha() for c in chunk)
        out.append("".join(ACCENTS.get(c, c) for c in chunk))
        out.append(m.group(0))
        pos = m.end()
    chunk = s[pos:]
    letters += sum(c.isalpha() for c in chunk)
    out.append("".join(ACCENTS.get(c, c) for c in chunk))
    body = "".join(out)
    # About 35% longer: pad with tildes (German/Finnish run long).
    pad = max(1, round(len(s) * 0.35) - 3) if letters else 0
    # Leading/trailing spaces and line breaks stay outside the brackets (msgfmt --check wants a
    # msgstr to start and end with "\n" exactly when its msgid does).
    lead = len(body) - len(body.lstrip(" \n"))
    trail = len(body) - len(body.rstrip(" \n"))
    core = body.strip(" \n")
    return body[:lead] + "[" + core + (" " + "~" * pad if pad else "") + "]" + (body[len(body) - trail:] if trail else "")


# --- main ----------------------------------------------------------------------------------------

def build() -> Catalog:
    cat = Catalog()
    for p in walk_files(".gd"):
        scan_gd(cat, p)
    for p in walk_files(".tscn"):
        scan_tscn(cat, p)
    data_dir = os.path.join(ROOT, "data")
    for f in sorted(os.listdir(data_dir)):
        if f.endswith(".json"):
            scan_json(cat, os.path.join(data_dir, f))
    return cat


POT_PREAMBLE = ("# Greenfall translation template. Generated by tools/extract_strings.py; do not edit by hand.\n"
                "# Placeholders (%s, %d, %.1f, {name}) and [bbcode] tags must be kept in every translation.\n"
                "#\n#, fuzzy\n")


def main() -> int:
    check = "--check" in sys.argv
    cat = build()
    pot = write_po(POT_PATH, cat, "", "nplurals=INTEGER; plural=EXPRESSION;", None, preamble=POT_PREAMBLE)
    if check:
        cur = open(POT_PATH, encoding="utf-8").read() if os.path.exists(POT_PATH) else ""
        if cur != pot:
            print("locale/greenfall.pot is out of date: run python3 tools/extract_strings.py")
            return 1
        print("POT up to date (%d strings)" % len(cat.entries))
        return 0
    os.makedirs(LOCALE_DIR, exist_ok=True)
    with open(POT_PATH, "w", encoding="utf-8") as fh:
        fh.write(pot)
    # Pseudo-locale: generated, never hand-edited.
    ps = {}
    for (ctx, msgid), e in cat.entries.items():
        ps[(ctx, msgid)] = [pseudo(msgid), pseudo(e["plural"])] if e["plural"] else pseudo(msgid)
    with open(PSEUDO_PATH, "w", encoding="utf-8") as fh:
        fh.write(write_po(PSEUDO_PATH, cat, "pseudo", "nplurals=2; plural=(n != 1);", ps,
                          preamble="# Pseudo-locale for testing (accents, brackets, ~35% longer). Generated; do not edit.\n"))
    # Merge into real languages.
    merged = []
    for f in sorted(os.listdir(LOCALE_DIR)):
        if not f.endswith(".po") or f == "pseudo.po":
            continue
        p = os.path.join(LOCALE_DIR, f)
        tr, head = read_po(p)
        lang = head.get("Language", f[:-3])
        plural = head.get("Plural-Forms", "nplurals=2; plural=(n != 1);").rstrip(";") + ";"
        obsolete = {k: v for k, v in tr.items() if k not in cat.entries}
        pre = []
        with open(p, encoding="utf-8") as fh:
            for line in fh:
                if not line.startswith("# "):
                    break
                pre.append(line)
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(write_po(p, cat, lang, plural, tr, obsolete, preamble="".join(pre)))
        done = sum(1 for k in cat.entries if (isinstance(tr.get(k), str) and tr.get(k)) or (isinstance(tr.get(k), list) and any(tr.get(k))))
        merged.append("%s %d/%d" % (lang, done, len(cat.entries)))
    by_src: dict[str, int] = {}
    for e in cat.entries.values():
        src = e["refs"][0].split(":")[0]
        kind = "json" if src.endswith(".json") else ("gd" if src.endswith(".gd") else "tscn")
        by_src[kind] = by_src.get(kind, 0) + 1
    print("greenfall.pot: %d strings (%s); pseudo.po regenerated; merged: %s" % (
        len(cat.entries), ", ".join("%s %d" % kv for kv in sorted(by_src.items())), ", ".join(merged) or "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
