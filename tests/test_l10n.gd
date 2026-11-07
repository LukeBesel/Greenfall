extends GutTest
## Localization: the PO files load, the pseudo-locale translates code and data strings, keeps every
## placeholder, and the language setting persists and applies.

const TEST_PATH: String = "user://test_l10n_settings.cfg"
const SPEC: String = "%%|%[-+ 0#]*(?:\\d+|\\*)?(?:\\.\\d+)?[sdifxXoceEgGvc]|\\{[^{}\\s]*\\}"

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


func _placeholders(s: String) -> Array:
	var re := RegEx.create_from_string(SPEC)
	var out: Array = []
	for m: RegExMatch in re.search_all(s):
		out.append(m.get_string())
	return out


func test_translations_registered() -> void:
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	for l: String in ["pseudo", "de", "es"]:
		assert_true(l in locales, "%s loaded" % l)


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
	for path: String in ["res://locale/pseudo.po", "res://locale/de.po", "res://locale/es.po"]:
		var t: Translation = load(path)
		assert_not_null(t, path)
		var bad: Array[String] = []
		var n: int = 0
		for msg: String in t.get_message_list():
			var out: String = t.get_message(msg)
			if out == "" or msg == "":
				continue
			n += 1
			var a: Array = _placeholders(msg)
			var b: Array = _placeholders(out)
			a.sort()
			b.sort()
			if a != b:
				bad.append(msg)
		assert_true(n > 0, "%s has translations" % path)
		assert_eq(bad, [] as Array[String], "%s placeholders" % path)


func test_sample_german_and_spanish() -> void:
	TranslationServer.set_locale("de")
	assert_eq(tr("New Game"), "Neues Spiel")
	assert_eq(tr("Resume"), "Fortsetzen")
	TranslationServer.set_locale("es")
	assert_eq(tr("Settings"), "Ajustes")
	# Untranslated strings fall back to English.
	assert_eq(tr("Contrast"), "Contrast")


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
