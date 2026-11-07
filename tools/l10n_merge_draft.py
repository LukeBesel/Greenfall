#!/usr/bin/env python3
"""Merge machine-draft translations into locale/<lang>.po and validate placeholders.

Draft files: .l10n_work/<lang>_<chunk>.tsv, one line per string:
    NNNN<TAB>translation                     (NNNN = index in locale/greenfall.pot order)
    NNNN<TAB>form0<TAB>form1[<TAB>form2]     (plural entries)
Escapes: \\n = newline, \\t = tab. Draft lines replace what the .po has; entries without a draft line are kept.

    python3 tools/l10n_merge_draft.py de fr ...   # merge + validate
    python3 tools/l10n_merge_draft.py --check de  # validate the .po only
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_strings as ex  # noqa: E402

ROOT = ex.ROOT
WORK = os.path.join(ROOT, ".l10n_work")
SPEC = re.compile(r"%%|%[-+0]*(?:\d+|\*)?(?:\.\d+)?[sdcoxXfv]")
BRACE = re.compile(r"\{[^{}\s]*\}")
TAG = re.compile(r"\[/?[a-z_]+(?:=[^\]]*)?\]")

LANGS = {
    "de": ("Deutsch", "nplurals=2; plural=(n != 1);"),
    "fr": ("Français", "nplurals=2; plural=(n > 1);"),
    "es": ("Español", "nplurals=2; plural=(n != 1);"),
    "pt_BR": ("Português (Brasil)", "nplurals=2; plural=(n > 1);"),
    "zh_CN": ("简体中文", "nplurals=1; plural=0;"),
    "ja": ("日本語", "nplurals=1; plural=0;"),
}
PREAMBLE = ("# %s translation of Greenfall. Merged by tools/extract_strings.py.\n"
            "# MACHINE DRAFT: every entry was written by an AI translator and needs review by a native\n"
            "# speaker (docs/LOCALIZATION.md, \"Reviewing a machine draft\"). Entries are not marked fuzzy\n"
            "# because Godot skips fuzzy entries at runtime. Reviewed: none yet.\n")


def unesc(s: str) -> str:
    return s.replace("\\\\", "\0").replace("\\n", "\n").replace("\\t", "\t").replace("\0", "\\")


def problems(msgid: str, out: str) -> list[str]:
    p = []
    if SPEC.findall(msgid) != SPEC.findall(out):
        p.append("format specs %s -> %s" % (SPEC.findall(msgid), SPEC.findall(out)))
    if sorted(BRACE.findall(msgid)) != sorted(BRACE.findall(out)):
        p.append("braces %s -> %s" % (sorted(BRACE.findall(msgid)), sorted(BRACE.findall(out))))
    if sorted(TAG.findall(msgid)) != sorted(TAG.findall(out)):
        p.append("tags differ")
    if msgid.startswith("E   ") and not out.startswith("E   "):
        p.append("lost 'E   ' prompt prefix")
    return p


def validate(lang: str, cat, tr: dict) -> int:
    bad = 0
    for (ctx, msgid), e in cat.entries.items():
        v = tr.get((ctx, msgid))
        if not v:
            continue
        pairs = [(msgid, v)] if isinstance(v, str) else [(e["plural"] if i else msgid, f) for i, f in enumerate(v) if f]
        if isinstance(v, list) and len(v) == 1:
            pairs = [(e["plural"], v[0])]
        for src, out in pairs:
            for pr in problems(src, out):
                bad += 1
                print("%s: %r: %s" % (lang, src[:60], pr))
    return bad


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    check_only = "--check" in sys.argv
    cat = ex.build()
    keys = list(cat.entries.keys())
    # Draft line numbers index the POT as it was when the draft was written (.l10n_work/src.tsv),
    # so later string extractions don't shift them.
    src_ids: dict = {}
    src_path = os.path.join(WORK, "src.tsv")
    if os.path.exists(src_path):
        for line in open(src_path, encoding="utf-8").read().split("\n"):
            parts = line.split("\t")
            if len(parts) >= 2 and re.fullmatch(r"\d{4}", parts[0]):
                src_ids[int(parts[0])] = unesc(parts[2] if parts[1] == "P" and len(parts) > 2 else parts[1])
    total_bad = 0
    for lang in args:
        name, plural = LANGS[lang]
        n_forms = int(re.search(r"nplurals=(\d+)", plural).group(1))
        path = os.path.join(ex.LOCALE_DIR, lang + ".po")
        tr, _ = ex.read_po(path) if os.path.exists(path) else ({}, {})
        if not check_only:
            for f in sorted(glob.glob(os.path.join(WORK, "%s_*.tsv" % lang))):
                for ln, line in enumerate(open(f, encoding="utf-8").read().split("\n"), 1):
                    if not line.strip():
                        continue
                    parts = line.split("\t")
                    if not re.fullmatch(r"\d{4}", parts[0]):
                        print("%s:%d: bad line" % (f, ln)); total_bad += 1; continue
                    i = int(parts[0])
                    k = ("", src_ids[i]) if i in src_ids else keys[i]
                    if k not in cat.entries:
                        print("%s:%d: msgid no longer in the POT: %r" % (f, ln, k[1][:50])); continue
                    e = cat.entries[k]
                    if len(parts) > 2 and parts[1] == "P":
                        parts = [parts[0]] + parts[2:]
                    forms = [unesc(x) for x in parts[1:]]
                    if e["plural"]:
                        if len(forms) == 1:
                            forms = forms * n_forms
                        if len(forms) != n_forms:
                            print("%s:%d: needs %d forms" % (f, ln, n_forms)); total_bad += 1; continue
                        tr[k] = forms
                    else:
                        if len(forms) != 1:
                            print("%s:%d: tab inside a translation" % (f, ln)); total_bad += 1; continue
                        tr[k] = forms[0]
            obsolete = {k: v for k, v in tr.items() if k not in cat.entries}
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(ex.write_po(path, cat, lang, plural, tr, obsolete, preamble=PREAMBLE % name))
        done = sum(1 for k in keys if tr.get(k) and (isinstance(tr[k], str) or all(tr[k])))
        bad = validate(lang, cat, tr)
        total_bad += bad
        print("%s: %d/%d translated, %d problems" % (lang, done, len(keys), bad))
    return 1 if total_bad else 0


if __name__ == "__main__":
    sys.exit(main())
