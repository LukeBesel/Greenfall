# Localization

Greenfall uses Godot's built-in `TranslationServer` with gettext PO files. English is the source
language: every msgid is the English text, so an untranslated string simply shows in English.

```
locale/
  greenfall.pot   template, generated (never edit)
  pseudo.po       pseudo-locale, generated (never edit)
  de.po, es.po    tiny samples: main menu, pause menu, language picker
```

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
   picks it on a matching OS. Until then players choose it by hand (the German and Spanish samples
   are deliberately not in that list, so a German OS never sees a half-translated game).
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
  TR ...), Greek and Cyrillic, checked in `tests/test_l10n.gd` and by hand. **No CJK or Hangul.**
- **Ledger terminal font**: `ui/fonts/AnonymousPro-*.ttf`. Covers Latin-1, Latin Extended-A, Greek
  and Cyrillic; lacks `ẞ` and some Latin Extended-B / Additional letters; **no CJK or Hangul.**
- **Robot body stencils** (`player/designs/*`, `robots/robot_visual.gd`) use system monospace fonts
  for decals; they are art and stay English.

For ZH-CN, JA and KO, both fonts need a fallback: add a CJK font (e.g. Noto Sans CJK SC / JP / KR,
or one subset font per language to keep the size down: a full Noto CJK is 15-20 MB) as a
`FontFile.fallbacks` entry on the UI theme font and the Ledger font, loaded only when that locale
is active. Godot falls back to system fonts on desktop by default, which works on most Windows and
macOS machines but not reliably on Linux or the Steam Deck, so ship the fallback. Cyrillic (RU)
needs no new font. No large font files are in the repository yet.

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
