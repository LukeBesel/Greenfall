extends GutTest
## [v8ui] Owner item 76: the title menu's second lines (Continue, Profiles) stay inside their
## buttons. The full title at every size, scale and language is `--menu --ui-audit` (it uses the
## longest Continue line, --menu-long-save).

const MM := preload("res://ui/main_menu.gd")


func test_continue_line_versions_drop_clock_then_date() -> void:
	var mm: Node3D = MM.new()
	mm.set("_save", MM.long_save())
	var v: Array[String] = mm.call("_save_summary_variants")
	assert_eq(v.size(), 3)
	assert_true(v[0].ends_with("28 Nov 19:30"), v[0])
	assert_true(v[1].ends_with("28 Nov"), v[1])
	assert_true(v[2].ends_with("cubes"), v[2])
	assert_true(v[0].contains("12h 51m"), v[0])
	assert_true(v[0].length() > v[1].length() and v[1].length() > v[2].length())
	mm.free()


func test_pick_fit_takes_the_longest_that_fits() -> void:
	var w: Array[float] = [500.0, 420.0, 330.0]
	assert_eq(MM.pick_fit(w, 560.0), 0)
	assert_eq(MM.pick_fit(w, 450.0), 1)
	assert_eq(MM.pick_fit(w, 340.0), 2)
	assert_eq(MM.pick_fit(w, 200.0), 2, "none fits: the shortest, cut with an ellipsis")


## The audit check that missed the bug: a Label placed by anchors in a Button runs out of it.
func test_audit_flags_text_running_out_of_a_button() -> void:
	var root := Control.new()
	root.size = Vector2(1280, 720)
	add_child_autofree(root)
	var b := Button.new()
	b.position = Vector2(80, 300)
	b.size = Vector2(340, 76)
	root.add_child(b)
	var l := Label.new()
	l.text = "Verdance  ·  12h 51m  ·  999.99K cubes  ·  28 Nov 19:30  ·  and some more"
	l.add_theme_font_size_override("font_size", 13)
	l.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	l.offset_left = 22
	l.offset_top = -32
	l.offset_bottom = -12
	b.add_child(l)
	await get_tree().process_frame
	var kinds: Array = UIAudit.layout([root], Rect2(Vector2.ZERO, root.size)).map(func(d: Dictionary) -> String: return str(d.get("kind", "")))
	assert_has(kinds, "overflow", "a too-long second line must be reported")
	l.offset_right = -20
	l.clip_text = true
	l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	await get_tree().process_frame
	kinds = UIAudit.layout([root], Rect2(Vector2.ZERO, root.size)).map(func(d: Dictionary) -> String: return str(d.get("kind", "")))
	assert_does_not_have(kinds, "overflow")
