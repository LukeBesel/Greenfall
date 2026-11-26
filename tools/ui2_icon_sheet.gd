extends Control
## [ui2] Currency icon sheet: the three currency glyphs at HUD, workbench and large sizes on the
## dark HUD panel colour, saved to --out=PATH (default screenshots/ui2_icons.png). Run with a
## display: xvfb-run -a godot --path . --rendering-driver opengl3 res://tools/ui2_icon_sheet.tscn


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.045, 0.05, 0.058)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var vb := VBoxContainer.new()
	vb.position = Vector2(40, 30)
	vb.add_theme_constant_override("separation", 26)
	add_child(vb)
	for px: float in [16.0, 24.0, 36.0, 72.0, 128.0]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", int(maxf(px * 0.6, 18.0)))
		vb.add_child(row)
		for cur: String in ["cubes", "parts", "seeds"]:
			var ic := CurrencyIcon.new(cur, px)
			ic.line_w = clampf(px / 14.0, 1.2, 2.4)
			row.add_child(ic)
			var l := Label.new()
			l.text = "1.2K" if px <= 36.0 else ""
			l.add_theme_font_size_override("font_size", int(maxf(px * 0.8, 13.0)))
			row.add_child(l)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var out: String = "res://screenshots/ui2_icons.png"
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var img: Image = get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	print("[icons] saved ", out)
	get_tree().quit()
