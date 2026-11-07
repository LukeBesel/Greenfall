extends GutTest
## Localization: the PO files load, the pseudo-locale translates code and data strings, keeps every
## placeholder, and the language setting persists and applies.

const TEST_PATH: String = "user://test_l10n_settings.cfg"
# GDScript's % operator: flags + - 0, width, precision, conversions s d c o x X f v. "5% of" is text.
const SPEC: String = "%%|%[-+0]*(?:\\d+|\\*)?(?:\\.\\d+)?[sdcoxXfv]|\\{[^{}\\s]*\\}"
## [i18n] Full translations (machine drafts until reviewed) and their plural form counts.
const FULL: Dictionary = {"de": 2, "fr": 2, "es": 2, "pt_BR": 2, "zh_CN": 1, "ja": 1}
const CJK: Array[String] = ["zh_CN", "ja"]

var _saved_path: String
var _saved_lang: String
var _saved_override: String


func before_each() -> void:
	_saved_path = Settings.settings_path
	_saved_lang = Settings.language
	_saved_override = Settings.locale_override
	Settings.settings_path = TEST_PATH


func after_each() -> void:
	Settings.language = _saved_lang
	Settings.locale_override = _saved_override
	Settings.settings_path = _saved_path
	Settings.apply_language()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


## % specs must keep their order (GDScript formats by position); {named} ones may move.
func _same_placeholders(a: String, b: String) -> bool:
	var pa: Array = _placeholders(a)
	var pb: Array = _placeholders(b)
	var sa: Array = pa.filter(func(x: String) -> bool: return x.begins_with("%"))
	var sb: Array = pb.filter(func(x: String) -> bool: return x.begins_with("%"))
	if sa != sb:
		return false
	pa.sort()
	pb.sort()
	return pa == pb


func _placeholders(s: String) -> Array:
	var re := RegEx.create_from_string(SPEC)
	var out: Array = []
	for m: RegExMatch in re.search_all(s):
		out.append(m.get_string())
	return out


func test_translations_registered() -> void:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	for l: String in ["pseudo"] + FULL.keys():
		assert_true(l in locales, "%s loaded" % l)
		assert_true(ResourceLoader.exists("res://locale/%s.po" % l), "%s.po exists" % l)


func test_pseudo_translates_code_and_data_strings() -> void:
	TranslationServer.set_locale("pseudo")
	var s: String = tr("Resume")
	assert_true(s.begins_with("[") and s.ends_with("]"), "bracketed: %s" % s)
	assert_ne(s, "Resume")
	assert_true(s.length() > "Resume".length(), "longer")
	# A data string (first goal in data/goals.json) translates at the point of display.
	var goals: Dictionary = Economy.read_json("res://data/goals.json")
	var first: String = str((goals["goals"] as Array)[0]["text"])
	assert_true(tr(first).begins_with("["), "goal text translated: %s" % tr(first))
	# Formatted strings keep working.
	assert_true((tr("Hub %d") % 3).contains("3"))
	var many: String = tr_n("+%d token", "+%d tokens", 5) % 5
	assert_true(many.begins_with("[") and many.contains("5"), many)
	# A WREN line keeps its {name} placeholder.
	var wl: Dictionary = Economy.read_json("res://data/wren_lines.json")
	var line: String = str(wl["wake"][0][0])
	assert_eq(_placeholders(tr(line)), _placeholders(line))


func test_every_translation_keeps_placeholders() -> void:
	var paths: Array[String] = ["res://locale/pseudo.po"]
	for l: String in FULL:
		paths.append("res://locale/%s.po" % l)
	for path: String in paths:
		var t: Translation = load(path)
		assert_not_null(t, path)
		var bad: Array[String] = []
		var n: int = 0
		for msg: String in t.get_message_list():
			var out: String = t.get_message(msg)
			if out == "" or msg == "":
				continue
			n += 1
			if not _same_placeholders(msg, out):
				bad.append(msg)
		assert_true(n > 0, "%s has translations" % path)
		assert_eq(bad, [] as Array[String], "%s placeholders" % path)


func test_sample_german_and_spanish() -> void:
	TranslationServer.set_locale("de")
	assert_eq(tr("New Game"), "Neues Spiel")
	assert_eq(tr("Resume"), "Fortsetzen")
	TranslationServer.set_locale("es")
	assert_eq(tr("Settings"), "Ajustes")
	# Text that is not a msgid comes back unchanged.
	assert_eq(tr("Not a msgid 42"), "Not a msgid 42")


func test_language_setting_persists_and_applies() -> void:
	Settings.locale_override = ""
	Settings.language = "pseudo"
	Settings.save_settings()
	Settings.language = ""
	Settings.load_settings()
	assert_eq(Settings.language, "pseudo")
	Settings.apply_language()
	assert_eq(TranslationServer.get_locale(), "pseudo")
	# System default only picks complete languages; the dev override wins over everything.
	Settings.language = ""
	assert_true(Settings.resolved_locale() in Settings.SYSTEM_LOCALES)
	Settings.locale_override = "de"
	assert_eq(Settings.resolved_locale(), "de")


func test_ui_font_has_latin_extended_glyphs() -> void:
	var f: Font = UITheme.font()
	var missing: String = ""
	for c: String in "àéîõüñçßøåœŝĥĵķļŕšţžŽÇÉÑÜẞ¡¿«»€":
		if not f.has_char(c.unicode_at(0)):
			missing += c
	assert_eq(missing, "", "UI font covers accented Latin")


## [i18n] Every full translation is complete, keeps the prompt key and has working plurals.
func test_full_translations_complete() -> void:
	var pot: Translation = load("res://locale/pseudo.po")
	var ids: PackedStringArray = pot.get_message_list()
	for l: String in FULL:
		var t: Translation = load("res://locale/%s.po" % l)
		var missing: Array[String] = []
		var prompt: Array[String] = []
		for msg: String in ids:
			if msg == "":
				continue
			var out: String = t.get_message(msg)
			if msg.contains(String.chr(4)):  # [i18n2] "context\u0004msgid" for msgctxt entries
				out = t.get_message(msg.get_slice(String.chr(4), 1), msg.get_slice(String.chr(4), 0))
			if out == "":
				missing.append(msg)
			elif msg.begins_with("E   ") and not out.begins_with("E   "):
				prompt.append(msg)
		# [i18n2] Strict: every msgid is translated. After a content drop, list the gaps with
		# `python3 tools/l10n_status.py --export` and merge drafts with tools/l10n_merge_draft.py.
		assert_eq(missing.size(), 0, "%s: %d untranslated, e.g. %s (run tools/l10n_status.py)" % [l, missing.size(), missing.slice(0, 3)])
		assert_eq(prompt, [] as Array[String], "%s keeps the E prompt prefix" % l)
		TranslationServer.set_locale(l)
		for n: int in [0, 1, 2, 5, 21]:
			var s: String = tr_n("+%d token", "+%d tokens", n) % n
			assert_true(s.contains(str(n)) and s != "+%d tokens" % n, "%s plural n=%d: %s" % [l, n, s])
	TranslationServer.set_locale("de")
	assert_eq(tr_n("Missing %d part", "Missing %d parts", 1) % 1, "1 Teil fehlt")
	assert_eq(tr_n("Missing %d part", "Missing %d parts", 3) % 3, "3 Teile fehlen")
	TranslationServer.set_locale("fr")  # French: 0 and 1 are singular
	assert_eq(tr_n("+%d token", "+%d tokens", 0) % 0, "+0 jeton")


## [i18n] With a CJK locale active, the UI and Ledger fonts render every character its .po uses.
func test_cjk_glyphs_render() -> void:
	for l: String in CJK:
		Settings.locale_override = l
		Settings.apply_language()
		var t: Translation = load("res://locale/%s.po" % l)
		var chars: Dictionary = {}
		for msg: String in t.get_message_list():
			for out: String in [t.get_message(msg), t.get_plural_message(msg, "", 2)]:
				for i: int in out.length():
					var c: int = out.unicode_at(i)
					if c >= 0x2E80:  # CJK blocks; symbols like ◆ are shared with English
						chars[c] = true
		assert_gt(chars.size(), 1000, "%s uses CJK characters" % l)
		for f: Font in [UITheme.font(), LedgerUplink.mono_font()]:
			var missing: String = ""
			for c: int in chars:
				if not f.has_char(c):
					missing += String.chr(c)
			assert_eq(missing, "", "%s font %s lacks: %s (run tools/build_cjk_fonts.py)" % [l, f, missing.left(40)])
		assert_eq((CJKFallback.fonts_for(l)[0] as Font).resource_path,
			CJKFallback.FONT_JP if l == "ja" else CJKFallback.FONT_SC, "%s glyph shapes first" % l)
	# The language picker's native names render in any locale.
	Settings.locale_override = "en"
	Settings.apply_language()
	for c: String in "简体中文日本語Português Français Español":
		assert_true(UITheme.font().has_char(c.unicode_at(0)), "picker glyph %s" % c)


func test_system_locale_mapping() -> void:
	assert_eq(Settings.system_locale_for("de_AT"), "de")
	assert_eq(Settings.system_locale_for("fr_CA"), "fr")
	assert_eq(Settings.system_locale_for("pt_BR"), "pt_BR")
	assert_eq(Settings.system_locale_for("pt_PT"), "pt_BR")
	assert_eq(Settings.system_locale_for("zh_CN"), "zh_CN")
	assert_eq(Settings.system_locale_for("zh_Hans_CN"), "zh_CN")
	assert_eq(Settings.system_locale_for("zh_TW"), "en")
	assert_eq(Settings.system_locale_for("ja_JP"), "ja")
	assert_eq(Settings.system_locale_for("ko_KR"), "en")
	for l: Array in Settings.LANGUAGES:
		var code: String = str(l[0])
		if code != "" and code != "pseudo":
			assert_true(code in Settings.SYSTEM_LOCALES, "%s selectable by system default" % code)
