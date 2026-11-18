extends GutTest
## [v6screens] The layout checks of tools/ui_audit.gd on small made-up screens, and the Settings
## panel (whose fixes the audit found) at the narrowest size it must fit: 853x480 (1280x720 at
## interface scale 1.5).

var _root: Control


func before_each() -> void:
	_root = Control.new()
	_root.size = Vector2(800, 600)
	add_child_autofree(_root)


func _kinds(issues: Array[Dictionary]) -> Array:
	return issues.map(func(d: Dictionary) -> String: return str(d["kind"]))


func test_finds_offscreen_and_overlap() -> void:
	var a := Label.new()
	a.text = "Off the edge"
	a.position = Vector2(760, 10)
	_root.add_child(a)
	var b := Button.new()
	b.text = "One"
	b.position = Vector2(100, 100)
	b.size = Vector2(120, 40)
	_root.add_child(b)
	var c := Button.new()
	c.text = "Two"
	c.position = Vector2(140, 110)
	c.size = Vector2(120, 40)
	_root.add_child(c)
	await get_tree().process_frame
	var k: Array = _kinds(UIAudit.layout([_root], Rect2(0, 0, 800, 600)))
	assert_has(k, "offscreen")
	assert_has(k, "overlap")


func test_finds_cut_text() -> void:
	var l := Label.new()
	l.text = "A rather long name that cannot fit"
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.size = Vector2(60, 24)
	_root.add_child(l)
	await get_tree().process_frame
	assert_has(_kinds(UIAudit.layout([_root], Rect2(0, 0, 800, 600))), "clipped")


func test_clean_screen_has_no_issues() -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(20, 20)
	_root.add_child(vb)
	for t: String in ["Resume", "Settings", "Quit"]:
		var b := Button.new()
		b.text = t
		vb.add_child(b)
	await get_tree().process_frame
	assert_eq(UIAudit.layout([_root], Rect2(0, 0, 800, 600)).size(), 0)


func test_focus_on_a_hidden_control_is_found() -> void:
	var b := Button.new()
	b.text = "Shown"
	_root.add_child(b)
	var h := Button.new()
	h.text = "Hidden"
	_root.add_child(h)
	await get_tree().process_frame
	h.grab_focus()
	h.visible = false
	b.release_focus()
	var k: Array = _kinds(UIAudit.focus([_root], get_viewport()))
	assert_true(k.has("nofocus") or k.has("focus_out"), "focus lost is reported")


func test_settings_basics_focus_starts_on_a_row() -> void:
	var sp := SettingsPanel.new()
	add_child_autofree(sp)
	await get_tree().process_frame
	sp.open_panel()
	await get_tree().process_frame
	await get_tree().process_frame
	var f: Control = get_viewport().gui_get_focus_owner()
	assert_not_null(f, "something has the focus")
	assert_true(f != null and f.is_visible_in_tree(), "and it is shown (the tab row is hidden on Basics)")
	sp.close_panel()
