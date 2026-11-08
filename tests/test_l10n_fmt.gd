extends GutTest
## [i18n2] L10nFmt: reward suffixes, rarity + part names and research effect lines go through one
## translatable pattern each, so languages can reorder words and pick plural forms.

var _saved: String


func before_each() -> void:
	_saved = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_saved)


func test_reward_suffixes_english_plurals() -> void:
	TranslationServer.set_locale("en")
	assert_eq(L10nFmt.reward("cubes", 25), "+25 cubes")
	assert_eq(L10nFmt.reward("parts", 1), "+1 part")
	assert_eq(L10nFmt.reward("seeds", 2), "+2 seeds")
	assert_eq(L10nFmt.rewards({"cubes": 25, "parts": 1}), "+25 cubes  +1 part")
	# [money] legacy ids show as the currency they pay now (trinket = 150 cubes, bolt = 5 parts)
	Currencies.warn_legacy = false
	assert_eq(L10nFmt.reward("bolts", 2), "+10 parts")
	assert_eq(L10nFmt.rewards({"cubes": 25, "trinkets": 1}), "+175 cubes")
	Currencies.warn_legacy = true
	assert_eq(L10nFmt.reward("mystery", 3), "+3 mystery", "unknown currency falls back")


func test_reward_suffixes_translate() -> void:
	TranslationServer.set_locale("de")
	assert_eq(L10nFmt.reward("seeds", 1), "+1 Samen")
	assert_eq(L10nFmt.reward("cubes", 3), "+3 Würfel")
	TranslationServer.set_locale("fr")
	assert_eq(L10nFmt.reward("cubes", 1), "+1 cube")
	assert_eq(L10nFmt.reward("cubes", 25), "+25 cubes")
	TranslationServer.set_locale("ja")
	assert_eq(L10nFmt.reward("cubes", 25), "+25 キューブ")


func test_big_amounts() -> void:
	TranslationServer.set_locale("en")
	assert_eq(L10nFmt.amount("seeds", 1.0, true), "+1 seed")
	assert_eq(L10nFmt.amount("cubes", 40.0), "40 cubes")
	assert_eq(L10nFmt.amount("parts", 3.0), "3 parts")
	assert_eq(L10nFmt.amount("sheet_metal", 3.0), "3 parts", "[money] old materials are parts")
	TranslationServer.set_locale("de")
	assert_eq(L10nFmt.amount("parts", 1.0, true), "+1 Teil")


func test_part_name_word_order() -> void:
	TranslationServer.set_locale("en")
	assert_eq(L10nFmt.part_name(0, 0), "Rusty Chassis Frame")
	TranslationServer.set_locale("de")
	assert_eq(L10nFmt.part_name(0, 0), "Rostig Fahrgestell")
	TranslationServer.set_locale("fr")  # adjective after the noun
	assert_eq(L10nFmt.part_name(0, 0), "Châssis Rouillé")
	TranslationServer.set_locale("es")
	assert_true(L10nFmt.part_name(0, 0).begins_with("Bastidor"), L10nFmt.part_name(0, 0))
	assert_eq(L10nFmt.part_label("", "Battery"), "Battery", "no rarity, no join")


func test_research_effect_lines() -> void:
	TranslationServer.set_locale("en")
	assert_true("+10% Scoopie speed" in Research.effect_lines("salvage_logic"), str(Research.effect_lines("salvage_logic")))
	assert_eq(L10nFmt.stat_effect("2", false, "", "tank"), "+2 tank")
	TranslationServer.set_locale("fr")
	assert_eq(L10nFmt.stat_effect("10", true, "Scoopie", "vitesse"), "+10 % de vitesse pour Scoopie")
	TranslationServer.set_locale("de")
	var de: Array[String] = Research.effect_lines("salvage_logic")
	assert_false(de.is_empty())
	assert_true(de[0].contains("Scoopie") and de[0].contains("10"), str(de))
	assert_false(de[0].contains("speed"), "stat name translated: %s" % de[0])


## The token icon renders: the UI and Ledger fonts reach ◆ (through the CJK fallbacks).
func test_token_glyph_in_fonts() -> void:
	Settings.apply_language()
	for f: Font in [UITheme.font(), LedgerUplink.mono_font()]:
		assert_true(f.has_char("◆".unicode_at(0)), "%s has the token glyph" % f)
	TranslationServer.set_locale("en")
