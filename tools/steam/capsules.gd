extends Node
## Steam store art compositor. Crops and Lanczos-resizes the in-game master renders
## (tools/steam/capsule_stage.tscn) to every Steam capsule size and lays the "GREENFALL" wordmark
## on top with the game's own title font (StoreArt.logo_font), then writes PNGs. With --icons it
## also draws the achievement icons (ResearchIcons kinds, as in the Codex) at 256x256, unlocked + locked.
##
##   xvfb-run -a -s "-screen 0 3840x2160x24" godot --path . --rendering-driver vulkan \
##     res://tools/steam/capsules.tscn -- --in=/abs/dir/with/masters --out=/abs/out/dir [--icons] [--only=PREFIX]
## Masters expected in --in: master_wide.png (16:9, >= 2560x1440), master_hero.png (3840x1240).
## Specs: [name, width, height, master, focus x, focus y, zoom (1 = largest crop), logo layout]
## Layouts: "" none, "left", "left_big", "top", "bg" (dimmed, no logo), "only" (transparent logo).

const SPECS: Array = [
	["header_capsule_920x430", 920, 430, "master_wide", 0.5, 0.5, 1.0, "left"],
	["small_capsule_462x174", 462, 174, "master_wide", 0.5, 0.52, 1.0, "left_big"],
	["main_capsule_1232x706", 1232, 706, "master_wide", 0.5, 0.5, 1.0, "left"],
	["vertical_capsule_748x896", 748, 896, "master_wide", 0.5, 0.5, 1.0, "top"],
	["library_capsule_600x900", 600, 900, "master_wide", 0.5, 0.5, 1.0, "top"],
	["library_hero_3840x1240", 3840, 1240, "master_hero", 0.5, 0.5, 1.0, ""],
	["page_background_1438x810", 1438, 810, "master_wide", 0.5, 0.5, 1.0, "bg"],
	["library_logo_1280x720", 1280, 720, "", 0.5, 0.5, 1.0, "only"],
]

var _in: String
var _out: String


func _ready() -> void:
	_in = DevHooks.get_s("in", ProjectSettings.globalize_path("res://screenshots/steam"))
	_out = DevHooks.get_s("out", _in)
	DirAccess.make_dir_recursive_absolute(_out)
	_run.call_deferred()


func _run() -> void:
	var only: String = DevHooks.get_s("only", "")
	for spec: Array in SPECS:
		if only != "" and not str(spec[0]).begins_with(only):
			continue
		await _compose(spec)
	if DevHooks.has("icons"):
		await _icons()
	print("[capsules] done -> ", _out)
	get_tree().quit()


func _load_master(name_: String) -> Image:
	var p: String = _in.path_join(name_ + ".png")
	var img := Image.load_from_file(p)
	if img == null or img.is_empty():
		push_error("missing master " + p)
		return null
	img.convert(Image.FORMAT_RGBA8)
	return img


## Largest crop of `src` with the target aspect around the focus point, Lanczos-resized.
static func crop_resize(src: Image, w: int, h: int, fx: float, fy: float, zoom: float) -> Image:
	var a: float = float(w) / float(h)
	var ch: float = minf(src.get_height(), src.get_width() / a) / maxf(zoom, 1.0)
	var cw: float = ch * a
	var x: float = clampf(fx * src.get_width() - cw * 0.5, 0.0, src.get_width() - cw)
	var y: float = clampf(fy * src.get_height() - ch * 0.5, 0.0, src.get_height() - ch)
	var img: Image = src.get_region(Rect2i(int(x), int(y), int(cw), int(ch)))
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	return img


func _compose(spec: Array) -> void:
	var w: int = spec[1]
	var h: int = spec[2]
	var layout: String = spec[7]
	var vp := SubViewport.new()
	vp.size = Vector2i(w, h)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(w, h)
	vp.add_child(root)
	if str(spec[3]) != "":
		var src: Image = _load_master(spec[3])
		if src == null:
			vp.queue_free()
			return
		var bg := TextureRect.new()
		bg.texture = ImageTexture.create_from_image(crop_resize(src, w, h, spec[4], spec[5], spec[6]))
		bg.size = Vector2(w, h)
		root.add_child(bg)
	match layout:
		"left", "left_big":
			_wash(root, w, h, true)
			var big: bool = layout == "left_big"
			_logo(root, w * (0.6 if big else 0.44), Vector2(w * (0.06 if big else 0.06), h * (0.5 if big else 0.3)), false)
		"top":
			_wash(root, w, h, false)
			_logo(root, w * 0.84, Vector2(w * 0.5, h * 0.12), true)
		"bg":
			# Store page background: dimmed so the page text reads over it.
			var dim := ColorRect.new()
			dim.color = Color(0.03, 0.04, 0.05, 0.62)
			dim.size = Vector2(w, h)
			root.add_child(dim)
		"only":
			_logo(root, w * 0.9, Vector2(w * 0.5, h * 0.5), true)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = vp.get_texture().get_image()
	if layout != "only":
		img.convert(Image.FORMAT_RGB8)
	var path: String = _out.path_join(str(spec[0]) + ".png")
	img.save_png(path)
	print("[capsules] ", path, " ", img.get_size())
	vp.queue_free()


## Soft dark wash behind the logo (left edge or top) so it reads over the scene.
func _wash(root: Control, w: int, h: int, left: bool) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.025, 0.035, 0.6))
	g.add_point(0.45, Color(0.02, 0.025, 0.035, 0.28))
	g.set_color(1, Color(0.02, 0.025, 0.035, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 256
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0) if left else Vector2(0, 1)
	var t := TextureRect.new()
	t.texture = gt
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.size = Vector2(w * 0.62, h) if left else Vector2(w, h * 0.4)
	root.add_child(t)


## The wordmark: GREENFALL in the title font with the amber underline. `width` is the text width;
## `anchor` is the left-middle point (centered=false) or the center (centered=true).
func _logo(root: Control, width: float, anchor: Vector2, centered: bool) -> void:
	var text: String = "GREENFALL"
	# Fit the size (tracking scales with it, as on the title screen: 10 px at 92 px).
	var size: int = 100
	var font: FontVariation
	var tw: Vector2
	for _i: int in 3:
		font = StoreArt.logo_font(0.55, int(round(size * 0.11)))
		tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
		size = maxi(8, int(size * width / maxf(tw.x, 1.0)))
	font = StoreArt.logo_font(0.55, int(round(size * 0.11)))
	tw = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", StoreArt.LOGO_COLOR)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.4))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", maxi(2, int(size * 0.045)))
	l.add_theme_constant_override("shadow_outline_size", maxi(1, int(size * 0.05)))
	var line_h: float = font.get_height(size)
	var pos: Vector2 = anchor - Vector2(tw.x * 0.5, line_h * 0.5) if centered else anchor - Vector2(0, line_h * 0.5)
	l.position = pos
	root.add_child(l)
	var bar := ColorRect.new()
	bar.color = Color(1.0, 0.7, 0.26)
	var bw: float = tw.x * 0.17
	bar.size = Vector2(bw, maxf(2.0, size * 0.035))
	bar.position = Vector2(anchor.x - bw * 0.5 if centered else pos.x + size * 0.03, pos.y + line_h * 0.95)
	root.add_child(bar)


## Achievement icons for Steamworks: 256x256, coloured (unlocked) and grey (locked).
func _icons() -> void:
	var dir: String = _out.path_join("achievement_icons")
	DirAccess.make_dir_recursive_absolute(dir)
	for a: Dictionary in Achievements.defs():
		for locked: bool in [false, true]:
			var vp := SubViewport.new()
			vp.size = Vector2i(256, 256)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			add_child(vp)
			var bg := ColorRect.new()
			bg.color = Color(0.07, 0.075, 0.085) if not locked else Color(0.09, 0.09, 0.09)
			bg.size = Vector2(256, 256)
			vp.add_child(bg)
			var ring := Panel.new()
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0, 0, 0, 0)
			sb.border_color = Color(1.0, 0.7, 0.26, 0.9) if not locked else Color(0.4, 0.4, 0.4, 0.6)
			sb.set_border_width_all(6)
			sb.set_corner_radius_all(40)
			sb.anti_aliasing = true
			ring.add_theme_stylebox_override("panel", sb)
			ring.position = Vector2(14, 14)
			ring.size = Vector2(228, 228)
			vp.add_child(ring)
			var col: Color = Color(1.0, 0.78, 0.35) if not locked else Color(0.5, 0.5, 0.5)
			var ic := ResearchIcons.IconView.new(str(a.get("icon", "star")), 168.0, col)
			ic.position = Vector2(44, 44)
			ic.size = Vector2(168, 168)
			vp.add_child(ic)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img: Image = vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGB8)
			img.save_png(dir.path_join("%s%s.png" % [str(a["id"]).to_upper(), "_locked" if locked else ""]))
			vp.queue_free()
	print("[capsules] icons -> ", dir)
