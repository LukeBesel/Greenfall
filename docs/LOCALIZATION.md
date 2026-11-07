# Localization

Greenfall uses Godot's built-in `TranslationServer` with gettext PO files. English is the source
language: every msgid is the English text, so an untranslated string simply shows in English.

```
locale/
  greenfall.pot   template, generated (never edit)
  pseudo.po       pseudo-locale, generated (never edit)
  de.po fr.po es.po pt_BR.po zh_CN.po ja.po
                  complete MACHINE DRAFTS (Nov 2026), not yet reviewed by native speakers
```

All six languages are complete drafts written by an AI translator (2,968 strings each, Nov 2026;
the second pass filled wildlife, Lumi designs and the late game). They are
shown to players today (Settings > Gameplay > Language, and "System default" on a matching OS), so
a review pass per language is the next step before a store release; see "Reviewing a machine
draft" below.

The PO files are registered in `project.godot` under `internationalization/locale/translations`
and are exported by the `locale/*.po` include filter in `export_presets.cfg`.

## How strings get translated

- **Code.** Player-facing strings in GDScript go through `tr("...")`, plurals through
  `tr_n("%d part", "%d parts", n) % n`. In `static func`s use `TranslationServer.translate("...")`
  (and `translate_plural`). `robots/robot.gd` uses a local `_t("...")` for its status line.
- **Format strings, not concatenation.** `tr("Sold %s cubes") % x`, never `"Sold " + x + " cubes"`, so
  a translation can move the number. Several values: `tr("%s fleet upgraded to %s.") % [a, b]`.
- **Data files.** `data/*.json` stay in English. The English text is the msgid and is passed through
  `tr()` where it is shown (`tr(str(def["name"]))`). Formatted data strings (`"Press %d metal bales"`,
  WREN lines with `{name}`) are translated *before* formatting: `tr(str(t["text"])) % n`,
  `tr(line).format({...})`.
- **Sinks.** Toasts (`ui/notify_stack.gd`), subtitles (`ui/subtitles.gd`), Ledger lines
  (`story/ledger_uplink.gd`) and cinematic captions (`story/cine.gd`) also pass their text through
  `tr()`, so raw data lines handed to them are translated even when the caller forgot. Translating
  an already-translated string is harmless (it is not a msgid, so it comes back unchanged).
- **Const tables.** `const` arrays/dictionaries cannot call `tr()`. They are translated where they
  are shown, and marked for the extractor with a trailing `# l10n` comment (one line) or a
  `# l10n:begin` / `# l10n:end` block. Dictionary keys are never extracted (they are ids).
- **Controls.** Labels and Buttons auto-translate a plain msgid in `.text`, so literal-only text
  updates live when the language changes. Text built in code refreshes when its screen is rebuilt
  (the Settings panel rebuilds itself on a language change).
- **Logic never compares translated text.** Where code used to test display text
  (`why.begins_with("Energy")`), it now compares against the translated prefix or the English
  source (`Robot.status_text()` stays English for logic; `status_label()` is the display copy).

## Extracting strings

```
python3 tools/extract_strings.py          # rebuild POT + pseudo.po, merge new msgids into *.po
python3 tools/extract_strings.py --check  # CI: exit 1 if the POT is out of date
```

It scans:

- GDScript: `tr`, `atr`, `_t`, `tr_n`, `TranslationServer.translate(_plural)`, plus `# l10n`-marked
  lines and blocks. Scenes (`.tscn`): `text`, `tooltip_text`, `placeholder_text`, `title`.
- JSON: the fields in `JSON_RULES` (`name`, `desc`, `hint`, `text`, `title`, `body`, `lore`,
  `toast`, `prompt`, `hud`, `tagline`, `unit`, `header`, ...), every line pool in
  `wren_lines.json`, the Ledger's line pools in `ledger.json`, the `wren` pools in `events.json`,
  and memory-shard `kind`s. Data-only files (`assets.json`, `steam.json`, tuning files) are skipped.
  When a new JSON file or field is player-facing, add it to `JSON_RULES`.

Rerun it after any text change. Existing translations are kept, new msgids are added empty, and
msgids that disappeared stay at the end of each `.po` as obsolete `#~` entries (Poedit and Weblate
can drop them). Source references (`#: ui/hud.gd:289`, `#: data/goals.json:goals[hex_1].text`)
tell translators where a string appears.

### Context comments

A `# TRANSLATORS: ...` comment on the line(s) right above a `tr()` call is copied into the POT as
an extracted comment (`#.`), which Poedit, Weblate and Crowdin show next to the string:

```gdscript
# TRANSLATORS: %s is a junk type, e.g. "metal". Shown on the hopper gauge.
label.text = tr("%s bale") % kind
```

For one English word with two meanings, use a context: `tr("Clean", "hex state")` gives a separate
`msgctxt` entry.

## Adding a language

1. Create `locale/xx.po` with just a header (copy `locale/de.po`'s first lines; set `Language: xx`
   and the right `Plural-Forms`, e.g. `nplurals=3; plural=(n%10==1 && n%100!=11 ? 0 : n%10>=2 && n%10<=4 && (n%100<10 || n%100>=20) ? 1 : 2);` for Russian).
2. Run `python3 tools/extract_strings.py`: every msgid is merged in, empty.
3. Add `res://locale/xx.po` to `internationalization/locale/translations` in `project.godot`.
4. Add `["xx", "Name in its own language"]` to `Settings.LANGUAGES` (`autoload/Settings.gd`).
5. When the translation is complete, add `"xx"` to `Settings.SYSTEM_LOCALES` so "System default"
   picks it on a matching OS (`Settings.system_locale_for()` maps `de_AT` to `de`, `pt_PT` to
   `pt_BR`, `zh_Hans_CN` to `zh_CN`; Traditional Chinese stays English). Until then players choose
   it by hand, so an OS in that language never sees a half-translated game.
6. Check fonts (below), then play with `--locale=xx`.

## Translators: working with the PO files

- **Poedit** (desktop): open `locale/xx.po`. Use *Catalog > Update from POT file* with
  `locale/greenfall.pot` if the PO is older than the POT. Save writes the `.po` (and an `.mo`, which
  Godot does not need; it can be deleted).
- **Weblate**: add a component with file mask `locale/*.po`, template `locale/greenfall.pot`, file
  format "gettext PO file", and exclude `locale/pseudo.po`. Weblate's checks for "C format" catch
  broken `%s`/`%d`.
- **Crowdin**: source file `locale/greenfall.pot`, translation path `locale/%two_letters_code%.po`
  (`%locale_with_underscore%` for `pt_BR` and `zh_CN`), ignore `locale/pseudo.po`.

Rules for every translation:

- Keep every placeholder: `%s`, `%d`, `%.1f`, `%%`, `{name}`, `{scoop}`-style key glyph templates,
  and `[b]`/`[color=...]`/`[k]`/`[p]` tags. The order of `%s` may not change in one string (GDScript
  formats by position); if a sentence needs a different order, ask for the string to be split.
  `tests/test_l10n.gd` fails when a translation drops or adds a placeholder.
- Interaction prompts start with the key letter: keep the leading `E   ` (`E   read the sign`);
  the HUD replaces it with the current key or button glyph.
- Keep `\n` line breaks where the layout needs them; text may be about 35% longer than English
  (the pseudo-locale tests that), much longer will be clipped.
- Place names (Old Town, Verdance, the districts) and robot names are proper nouns and are not in
  the POT; "GREENFALL" (the logo) stays as is.

## Reviewing a machine draft

The six full translations were drafted by an AI translator in one pass, with this brief: cozy,
warm, playful; Lumi is a small, brave seed-keeper robot; WREN is a dry, kind AI companion; the
Ledger is a cold corporate antagonist in a formal, bureaucratic register. Lumi, LM-1, WREN, Cradle,
Verdance, Greenfall and the robot model names (Scoopie, Haul Bug, Seedling, Drip, Skimmer,
Multibot) were kept in Latin script; the Ledger keeps its English name too.

**Why the entries are not marked `#, fuzzy`.** Godot's PO loader skips fuzzy entries at runtime
(checked on 4.7: a fuzzy entry comes back untranslated), and `tools/extract_strings.py` drops `#,`
flags when it rewrites the files. So the draft status lives in each file's header comment
(`# MACHINE DRAFT ... Reviewed: none yet.`), which the extractor keeps.

Review workflow, per language:

1. Load `locale/xx.po` in Poedit or a Weblate component (setup above). Weblate can mark every
   string "needs editing" on import, which gives reviewers a queue without breaking the game.
2. Review in this order: the UI (`ui/`, `autoload/Settings.gd`, `.tscn` references), story and WREN
   lines (`data/wren_lines.json`, `story/`), the Ledger (`data/ledger.json`, `story/ledger*.gd`;
   keep the bureaucratic tone), then codex, goals and achievements (`data/*.json`).
3. Play with `--locale=xx` and the pseudo checks below; in particular watch buttons and HUD
   labels for overflow (German and French run long) and check the tone of WREN against the brief.
4. Keep placeholders, the `E   ` prompt prefix, `[k]`/`[p]`/bbcode tags and `\n` breaks (rules
   above). `tests/test_l10n.gd` checks placeholders, the prompt prefix, completeness and plurals.
5. For `zh_CN` and `ja`, rebuild the font subsets after editing (`python3 tools/build_cjk_fonts.py`,
   below); the test fails if a translation uses a character the font lacks.
6. When a language is reviewed, edit its header comment to `Reviewed: <who>, <date>` (and drop
   "MACHINE DRAFT"), and note it in docs/ROADMAP.md.

Known draft caveats a reviewer should look at:

- **Part rarity + part name** use one pattern, `{rarity} {part}` with msgctxt "part name"
  (`L10nFmt.part_name()`); fr/es/pt_BR put the adjective after the noun. The rarity adjective is one
  translated word, so it does not agree in gender with every part (the drafts pick one form).
- **Robot traits** (`Cautious`, `Speedy`, ...) fill `" Seems %s."`; `Curious` and `Sleepy` share a
  msgid with an achievement and an eye pose, so one word must fit both.
- **Animal names** fill `"E   take a photo of the %s"` etc.; the drafts avoid gendered articles.
- The "THANK YOU, PATCH" street sign keeps the robot's old name on purpose.
- The token icon is `◆` (U+25C6). The UI fonts lack it; both CJK subsets carry it in their base
  set and are attached as fallbacks in every locale, so it renders everywhere.
- `tools/l10n_merge_draft.py` is the tool the drafts were merged with (it validates placeholders
  between msgid and msgstr); it reads draft TSVs from the untracked `.l10n_work/` folder.

## Filling a content drop

New content arrives in English and shows in English until translated; `tests/test_l10n.gd`
(`test_full_translations_complete`) fails while any language misses a string. To fill it:

1. `python3 tools/extract_strings.py` (new msgids are merged in, empty).
2. `python3 tools/l10n_status.py` prints coverage per language; `--export` writes
   `.l10n_work/todo.tsv` (untracked): every missing string in the keyed draft format, with its
   translator notes and source references. `--missing de` lists one language; `--check` exits 1 on
   any gap.
3. Copy it to `.l10n_work/<lang>_<chunk>.tsv` per language and replace the English after each tab
   (`=msgid<TAB>text`; plurals `=msgid<TAB>P<TAB>form0<TAB>form1`; a msgctxt entry is `=ctx::msgid`).
4. `python3 tools/l10n_merge_draft.py de fr es pt_BR zh_CN ja` merges and checks placeholders,
   brace keys, tags and the `E   ` prefix; then `python3 tools/build_cjk_fonts.py` for zh_CN/ja.

Shared display formats live in `systems/l10n_fmt.gd` (`L10nFmt`): use `reward()` / `amount()` for
"+N <currency>", `part_name()` / `part_label()` for rarity + part, `stat_effect()` for research
lines, instead of joining English words in code.

## Pseudo-locale (testing)

`locale/pseudo.po` is generated from the POT: letters get accents, every string is wrapped in
brackets and padded about 35% longer, e.g. `Scoop junk` -> `[Šçôôþ ĵûñķ ~]`. Placeholders, bbcode
tags and the prompt `E` are left intact. It shows at a glance:

- text that is still plain English was never passed through `tr()`,
- a missing `]` means the text was cut off (layout overflow),
- `?` boxes mean the font lacks a glyph.

Pick it in Settings > Gameplay > Language > Pseudo (test), or start with `--locale=pseudo`.
An automated pass lists on-screen text that skipped translation:

```
godot --headless --path . -- --fresh --autoplay --locale=pseudo --l10n-audit --time-scale=4 --quit-after=200
# -> [l10n-audit] table at exit, also written to screenshots/l10n_audit.txt
```

Dev hook: `--locale=xx` forces any locale for one run (never saved). The setting itself is stored as
`[ui] language` in `user://settings.cfg` (`""` = System default).

## Fonts

- **UI font**: Godot's built-in default (`ThemeDB.fallback_font`, Open Sans SemiBold), used through
  `UITheme.font()` and the title font. Covers Latin-1, Latin Extended-A/B (DE, FR, ES, PT, PL, CS,
  TR ...), Greek and Cyrillic, checked in `tests/test_l10n.gd` and by hand. No CJK or Hangul of
  its own.
- **Ledger terminal font**: `ui/fonts/AnonymousPro-*.ttf`. Covers Latin-1, Latin Extended-A, Greek
  and Cyrillic; lacks `ẞ` and some Latin Extended-B / Additional letters; no CJK of its own.
- **CJK fallback**: `ui/fonts/cjk/NotoSansSC-Subset.otf` (1.6 MB) and `NotoSansJP-Subset.otf`
  (1.7 MB), Noto Sans CJK Regular (OFL 1.1, `ui/fonts/cjk/OFL_NotoSansCJK.txt`). `ui/cjk_fallback.gd`
  (`CJKFallback.apply()`, called from `Settings.apply_language()`) adds both as `fallbacks` on the
  UI font and the Ledger font; the one matching the locale goes first, so shared Han characters
  get Japanese or Simplified Chinese glyph shapes. Both are always attached, so the language
  picker shows 简体中文 and 日本語 in every locale.
- **Rebuilding the subsets.** Each subset holds every character its `.po` uses plus a base set
  (kana, CJK punctuation, full-width forms, GB2312 level 1 for SC, JIS X 0208 level 1 for JP), so
  most review edits need no rebuild. After editing `zh_CN.po` or `ja.po`:
  `apt-get install -y --no-install-recommends fonts-noto-cjk` (once), then
  `python3 tools/build_cjk_fonts.py`. `tests/test_l10n.gd` (`test_cjk_glyphs_render`) fails when a
  character is missing.
- **Korean** would need a third subset (index 1, Noto Sans CJK KR, in `tools/build_cjk_fonts.py`).
- **Robot body stencils** (`player/designs/*`, `robots/robot_visual.gd`) use system monospace fonts
  for decals; they are art and stay English.

## What is not translated (yet)

- World signage in 3D: shop signs and banners in `planet/street_dressing.gd`, robot body decals
  (`HAUL`, `SKM-1`, stencils), the Ledger drone's hull text. They read as part of the art.
- Proper names: districts and the planet (`planet/planet_data.gd`), robot names (`robots/fleet.gd`).
- Developer-only text: logs, `tools/` reports, the Steam status line, store-art renderers.
- The credits list parsed from `docs/CREDITS.md` (asset names and authors).

## Steam store languages to aim for first

German, French, Spanish (Spain), Portuguese (Brazil), Simplified Chinese, Japanese, Korean,
Russian, in roughly that order: DE/FR/ES/PT-BR reuse the current fonts; RU needs only Cyrillic
(covered); ZH-CN/JA/KO need the CJK fallback above and a layout pass (shorter strings, but taller
glyphs). Steam lists "Interface" and "Subtitles" support per language; Greenfall has no voice, so
interface + subtitles is full support. Store pages, capsule text and the trailer are localized
separately in Steamworks (see docs/steam/).

Locale codes: `de`, `fr`, `es`, `pt_BR`, `zh_CN`, `ja`, `ko`, `ru`.
