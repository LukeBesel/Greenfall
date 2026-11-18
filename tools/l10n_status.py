#!/usr/bin/env python3
"""Translation coverage per language, and the list of strings still to translate.

    python3 tools/l10n_status.py               # coverage table for every locale/*.po (not pseudo)
    python3 tools/l10n_status.py --missing de  # print the untranslated msgids of one language
    python3 tools/l10n_status.py --export      # write .l10n_work/todo.tsv (untranslated in any language)
    python3 tools/l10n_status.py --check       # exit 1 unless every language is complete (CI)

Run `python3 tools/extract_strings.py` first so the catalog is current. The export uses the keyed
draft format of tools/l10n_merge_draft.py:

    # translator note (from a `# TRANSLATORS:` comment) / where it is used
    =msgid<TAB>English                       (copy to .l10n_work/<lang>_fill.tsv, replace the English)
    =msgid<TAB>P<TAB>singular<TAB>plural     (give one form per plural form of the language)
    =ctx::msgid<TAB>English                  (an entry with a msgctxt)

then `python3 tools/l10n_merge_draft.py de fr ...` merges and validates placeholders.
tests/test_l10n.gd (test_full_translations_complete) fails while any string is missing.
"""
import glob
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_strings as ex  # noqa: E402

WORK = os.path.join(ex.ROOT, ".l10n_work")


def esc(s: str) -> str:
    return s.replace("\\", "\\\\").replace("\n", "\\n").replace("\t", "\\t")


def langs() -> list[str]:
    out = []
    for p in sorted(glob.glob(os.path.join(ex.LOCALE_DIR, "*.po"))):
        name = os.path.splitext(os.path.basename(p))[0]
        if name != "pseudo":
            out.append(name)
    return out


def missing(cat, lang: str) -> list[tuple]:
    tr, _ = ex.read_po(os.path.join(ex.LOCALE_DIR, lang + ".po"))
    out = []
    for k in cat.entries:
        v = tr.get(k)
        if not v or (isinstance(v, list) and not all(v)):
            out.append(k)
    return out


def main() -> int:
    argv = sys.argv[1:]
    cat = ex.build()
    total = len(cat.entries)
    if "--missing" in argv:
        lang = argv[argv.index("--missing") + 1]
        for ctx, msgid in missing(cat, lang):
            print(("%s::" % ctx if ctx else "") + esc(msgid))
        return 0
    gaps: dict = {}
    for lang in langs():
        gaps[lang] = missing(cat, lang)
    print("%-7s %9s %8s %7s" % ("lang", "done", "missing", "cover"))
    for lang, miss in gaps.items():
        done = total - len(miss)
        print("%-7s %4d/%4d %8d %6.1f%%" % (lang, done, total, len(miss), 100.0 * done / max(total, 1)))
    if "--export" in argv:
        todo = []
        seen = set()
        for miss in gaps.values():
            for k in miss:
                if k not in seen:
                    seen.add(k)
                    todo.append(k)
        todo.sort(key=list(cat.entries.keys()).index)
        os.makedirs(WORK, exist_ok=True)
        path = os.path.join(WORK, "todo.tsv")
        with open(path, "w", encoding="utf-8") as fh:
            for ctx, msgid in todo:
                e = cat.entries[(ctx, msgid)]
                for c in e["comments"]:
                    fh.write("# %s\n" % c)
                fh.write("# %s\n" % " ".join(e["refs"][:3]))
                key = "=" + ("%s::" % ctx if ctx else "") + esc(msgid)
                if e["plural"]:
                    fh.write("%s\tP\t%s\t%s\n" % (key, esc(msgid), esc(e["plural"])))
                else:
                    fh.write("%s\t%s\n" % (key, esc(msgid)))
        print("wrote %s (%d strings)" % (os.path.relpath(path, ex.ROOT), len(todo)))
    if "--check" in argv:
        return 1 if any(gaps.values()) else 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
