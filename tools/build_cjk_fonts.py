#!/usr/bin/env python3
"""Build the subset CJK fallback fonts in ui/fonts/cjk/ from the system Noto Sans CJK collection.

    apt-get install -y --no-install-recommends fonts-noto-cjk   # once (OFL 1.1)
    python3 tools/build_cjk_fonts.py                            # after editing zh_CN.po / ja.po

Each font keeps every character the matching .po file uses, plus a common base set (kana, CJK
punctuation, full-width forms, and the most frequent ~3,000 Han characters of the language) so a
reviewer's wording changes rarely need a rebuild. tests/test_l10n.gd fails if a translation uses a
character the font lacks; rerun this script then.
"""
import os
import re
import sys

from fontTools import subset
from fontTools.ttLib import TTCollection

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"
OUT = os.path.join(ROOT, "ui", "fonts", "cjk")
# locale -> (index in the .ttc, output file)
FACES = {"zh_CN": (2, "NotoSansSC-Subset.otf"), "ja": (0, "NotoSansJP-Subset.otf")}


def po_chars(path: str) -> set[str]:
    text = open(path, encoding="utf-8").read()
    out: set[str] = set()
    for m in re.finditer(r'^(?:msgstr(?:\[\d+\])?\s+)?"(.*)"$', text, re.M):
        out.update(c for c in m.group(1) if ord(c) > 0x7F)
    return out


def rng(a: int, b: int) -> set[str]:
    return {chr(c) for c in range(a, b + 1)}


def decode_range(codec: str, rows: range, cols: range) -> set[str]:
    out: set[str] = set()
    for r in rows:
        for c in cols:
            try:
                out.add(bytes([r, c]).decode(codec))
            except UnicodeDecodeError:
                pass
    return out


def base_set(locale: str) -> set[str]:
    s = rng(0x3000, 0x303F) | rng(0xFF00, 0xFFEF) | rng(0x2010, 0x2027) | set("…·—–“”‘’《》「」『』【】〈〉※〜")
    if locale == "zh_CN":
        s |= decode_range("gb2312", range(0xB0, 0xD8), range(0xA1, 0xFF))   # GB2312 level 1 (3,755 Han)
    else:
        s |= rng(0x3040, 0x309F) | rng(0x30A0, 0x30FF) | rng(0x31F0, 0x31FF)  # kana
        s |= decode_range("euc_jp", range(0xB0, 0xD0), range(0xA1, 0xFF))   # JIS X 0208 level 1 (2,965 kanji)
    return s


def main() -> int:
    if not os.path.exists(SRC):
        print("missing %s: apt-get install -y --no-install-recommends fonts-noto-cjk" % SRC)
        return 1
    os.makedirs(OUT, exist_ok=True)
    coll = TTCollection(SRC)
    for locale, (idx, name) in FACES.items():
        chars = po_chars(os.path.join(ROOT, "locale", locale + ".po")) | base_set(locale)
        font = coll.fonts[idx]
        cmap = font.getBestCmap()
        keep = sorted(ord(c) for c in chars if ord(c) in cmap)
        opts = subset.Options()
        opts.layout_features = ["*"]
        opts.name_IDs = ["*"]
        opts.notdef_outline = True
        opts.hinting = False
        opts.desubroutinize = False
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=keep)
        import copy
        f2 = copy.deepcopy(font)
        sub.subset(f2)
        path = os.path.join(OUT, name)
        f2.save(path)
        print("%s: %d chars -> %s (%.2f MB)" % (locale, len(keep), name, os.path.getsize(path) / 1e6))
    return 0


if __name__ == "__main__":
    sys.exit(main())
