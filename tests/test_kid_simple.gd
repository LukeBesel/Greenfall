extends GutTest
## [v6screens] Owner: simple enough for a 5-year-old, and no option that does nothing on the round
## world. Settings no longer offers "Number format" (nothing on screen used it), "Best-value tags"
## (the workbench has no upgrade cards to tag) or the translators' "Pseudo (test)" language.


func _texts(root: Node) -> Array[String]:
	var out: Array[String] = []
	for n: Node in root.find_children("*", "Label", true, false):
		out.append((n as Label).text)
	for n: Node in root.find_children("*", "Button", true, false):
		out.append((n as Button).text)
	return out


func test_no_dead_options_in_settings() -> void:
	var sp := SettingsPanel.new()
	add_child_autofree(sp)
	await get_tree().process_frame
	for i: int in SettingsPanel.TABS.size():
		sp.select_tab(i)
		await get_tree().process_frame
	var all: String = " | ".join(_texts(sp))
	assert_false(all.contains(tr("Number format")), "no Number format option")
	assert_false(all.contains(tr("Best-value tags")), "no Best-value tags option")
	assert_false(all.contains("Pseudo (test)"), "no test language in the picker")
	assert_true(all.contains(tr("Language")), "the language picker is still there")


func test_pseudo_only_for_testers() -> void:
	var lang0: String = Settings.language
	var ov0: String = Settings.locale_override
	Settings.language = ""
	Settings.locale_override = ""
	assert_false(SettingsPanel.picker_languages().any(func(l: Array) -> bool: return str(l[0]) == "pseudo"))
	Settings.locale_override = "pseudo"
	assert_true(SettingsPanel.picker_languages().any(func(l: Array) -> bool: return str(l[0]) == "pseudo"), "--locale=pseudo still shows it")
	Settings.language = lang0
	Settings.locale_override = ov0
	assert_eq(SettingsPanel.picker_languages().size() + (0 if SettingsPanel.picker_languages().any(func(l: Array) -> bool: return str(l[0]) == "pseudo") else 1), Settings.LANGUAGES.size())
