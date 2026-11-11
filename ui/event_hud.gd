class_name EventHUD
extends CanvasLayer
## World-event and streak overlay (owned by WorldEvents):
##   top centre    event banner: name, what to do, live progress, time left; or a "contract ready" nudge
##   on screen     a diamond marker over the event (clamped to the screen edge with an arrow when off-screen)
##   bottom right  cleaning streak meter: tier pips, fill bar, bale bonus
##   full screen   camera flash (wildlife photos) and a soft cool tint while it rains

var events: WorldEvents

var _root: Control
var _banner: PanelContainer
var _b_icon: Label
var _b_title: Label
var _b_hint: Label
var _b_prog: Label
var _b_time: Label
var _nudge: Label
var _marker: Control
var _streak: PanelContainer
var _s_tier: Label
var _s_bonus: Label
var _s_bar: ProgressBar
var _s_pips: Array[ColorRect] = []
var _flash: ColorRect
var _rain: ColorRect
var _shown_id: String = ""
var _pulse: float = 0.0
var _t: float = 0.0


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	# Rain tint sits below the main HUD (layer 5) so text stays crisp.
	var tint := CanvasLayer.new()
	tint.layer = 2
	add_child(tint)
	_rain = ColorRect.new()
	_rain.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rain.color = Color(0.22, 0.3, 0.42, 0.0)
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint.add_child(_rain)
	_marker = Control.new()
	_marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.draw.connect(_draw_marker)
	_root.add_child(_marker)
	_build_banner()
	_build_streak()
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 1, 1, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)
	if events:
		events.streak_tier_up.connect(func(_t2: int) -> void: _pulse = 1.0)


func _build_banner() -> void:
	# [hud] Slim two-line pill: diamond, name and timer on top; what to do and progress below.
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	mc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mc.add_theme_constant_override("margin_top", 16)
	mc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(mc)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_BEGIN
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mc.add_child(vb)
	_banner = PanelContainer.new()
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.custom_minimum_size = Vector2(340, 0)
	vb.add_child(_banner)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 0)
	_banner.add_child(tv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	tv.add_child(top)
	_b_icon = UITheme.label("◆", 13, UITheme.GOLD)
	_b_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(_b_icon)
	_b_title = UITheme.label("", 14, UITheme.GOLD)
	_b_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(_b_title)
	_b_time = UITheme.label("", 14, UITheme.CREAM)
	top.add_child(_b_time)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	tv.add_child(bottom)
	_b_hint = UITheme.label("", 13, UITheme.CREAM)
	bottom.add_child(_b_hint)
	_b_prog = UITheme.label("", 12, UITheme.MUTED)
	_b_prog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_b_prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_b_prog)
	_banner.visible = false
	_nudge = UITheme.label("", 13, UITheme.GREEN)
	_nudge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_nudge)


func _build_streak() -> void:
	# [hud] Small and panel-free, to the right of the hotbar; only visible while a streak runs.
	_streak = PanelContainer.new()
	_streak.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_streak.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_streak.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_streak.offset_left = 150.0
	_streak.offset_right = 290.0
	_streak.offset_top = -90.0
	_streak.offset_bottom = -36.0
	_root.add_child(_streak)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.alignment = BoxContainer.ALIGNMENT_END
	_streak.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	vb.add_child(top)
	top.add_child(UITheme.label(tr("STREAK"), 12, UITheme.MUTED))
	_s_tier = UITheme.label("x0", 16, UITheme.CREAM)
	top.add_child(_s_tier)
	_s_bonus = UITheme.label("", 12, UITheme.GREEN)
	top.add_child(_s_bonus)
	var pips := HBoxContainer.new()
	pips.add_theme_constant_override("separation", 3)
	vb.add_child(pips)
	var n: int = events.streak.max_tier if events else 5
	for i: int in n:
		var p := ColorRect.new()
		p.custom_minimum_size = Vector2(18, 3)
		p.color = Color(1, 1, 1, 0.12)
		pips.add_child(p)
		_s_pips.append(p)
	_s_bar = ProgressBar.new()
	_s_bar.show_percentage = false
	_s_bar.max_value = 1.0
	_s_bar.custom_minimum_size = Vector2(0, 2)
	_s_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(_s_bar)
	_streak.modulate.a = 0.0


static func tier_color(tier: int, max_tier: int) -> Color:
	return Color(0.45, 0.9, 1.0).lerp(Color(1.0, 0.72, 0.25), float(tier) / maxf(float(max_tier), 1.0))


func flash() -> void:
	_flash.color.a = 0.85
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func set_rain(on: bool) -> void:
	var tw := create_tween()
	tw.tween_property(_rain, "color:a", 0.14 if on else 0.0, 3.0)


func _modal() -> bool:
	var w: Node = events.world if events else null
	return w != null and w.has_method("any_modal_open") and bool(w.call("any_modal_open"))


func _process(delta: float) -> void:
	if events == null:
		return
	_t += delta
	_root.visible = not _modal()
	_banner.get_parent().get_parent().visible = Settings.hud_mode != Settings.HudMode.HIDDEN  # [hud]
	_streak.visible = Settings.hud_mode != Settings.HudMode.HIDDEN
	_update_banner()
	_update_streak(delta)
	_marker.queue_redraw()


func _update_banner() -> void:
	var a: Dictionary = events.active
	if a.is_empty():
		if _banner.visible:
			var tw := create_tween()
			tw.tween_property(_banner, "modulate:a", 0.0, 0.4)
			tw.tween_callback(func() -> void: _banner.visible = events.active.size() > 0)
		_shown_id = ""
		var ready_n: int = Contracts.count_state("done")
		_nudge.text = (tr("REQUEST READY  ·  claim it at the workbench") if ready_n == 1 else tr("%d REQUESTS READY  ·  claim them at the workbench") % ready_n) if ready_n > 0 else ""
		return
	_nudge.text = ""
	var col: Color = a.get("color", UITheme.GOLD)
	if _shown_id != str(a["id"]):
		_shown_id = str(a["id"])
		_banner.visible = true
		var sb: StyleBoxFlat = UITheme.box(Color(0.03, 0.04, 0.05, 0.55), Color(col, 0.4), 1, 14, 0)  # [hud] slim pill
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 7
		_banner.add_theme_stylebox_override("panel", sb)
		_banner.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_banner, "modulate:a", 1.0, 0.35)
		Audio.play("blip", 1.5, -10.0)
	_b_icon.add_theme_color_override("font_color", col)
	_b_icon.modulate.a = 0.65 + 0.35 * sin(_t * 4.0)
	_b_title.add_theme_color_override("font_color", col)
	_b_title.text = tr(str(a.get("name", ""))).to_upper()
	_b_hint.text = tr(str(a.get("hint", "")))
	_b_prog.text = str(a.get("progress", ""))
	var left: float = maxf(float(a.get("left", 0.0)), 0.0)
	@warning_ignore("integer_division")
	_b_time.text = "%d:%02d" % [int(left) / 60, int(left) % 60]
	_b_time.add_theme_color_override("font_color", UITheme.CREAM if left > 20.0 else Color(1.0, 0.55, 0.35))


func _update_streak(delta: float) -> void:
	var s: Streak = events.streak
	var tier: int = s.tier()
	var col: Color = tier_color(tier, s.max_tier)
	var want: float = 1.0 if s.active() else 0.0
	_streak.modulate.a = move_toward(_streak.modulate.a, want, delta * (3.0 if want > 0.0 else 0.8))
	_pulse = maxf(0.0, _pulse - delta * 2.0)
	_streak.scale = Vector2.ONE * (1.0 + 0.08 * _pulse)
	_streak.pivot_offset = Vector2(0, _streak.size.y)
	_s_tier.text = "x%d" % tier
	_s_tier.add_theme_color_override("font_color", UITheme.CREAM.lerp(col, 0.5 + 0.5 * _pulse) if tier > 0 else UITheme.MUTED)
	for i: int in _s_pips.size():
		_s_pips[i].color = Color(col, 0.95) if i < tier else Color(1, 1, 1, 0.12)
	_s_bar.value = s.fill()
	_s_bar.modulate = col
	var draining: bool = s.since_scoop > s.grace_s
	_s_bonus.text = ("+%d%%" % int(round(s.bonus() * 100.0))) if tier > 0 else ""
	_s_bonus.add_theme_color_override("font_color", UITheme.MUTED if draining else UITheme.GREEN)


## Diamond over the event, or an arrow at the screen edge pointing to it.
func _draw_marker() -> void:
	var p: Variant = events.marker_pos()
	if not (p is Vector3):
		return
	var cam: Camera3D = _marker.get_viewport().get_camera_3d()
	if cam == null:
		return
	var w: Node = events.world
	var col: Color = events.active.get("color", UITheme.GOLD)
	var wp: Vector3 = (p as Vector3) + Vector3(0, 2.2, 0)
	var vs: Vector2 = _marker.size
	var behind: bool = cam.is_position_behind(wp)
	var sp: Vector2 = cam.unproject_position(wp)
	var dist: float = 0.0
	if w and w.get("patch") != null:
		dist = (p as Vector3).distance_to(w.patch.global_position)
	var margin: float = 56.0
	var on_screen: bool = not behind and sp.x > margin and sp.x < vs.x - margin and sp.y > margin and sp.y < vs.y - margin
	var bob: float = sin(_t * 3.0) * 4.0
	if on_screen:
		if dist < 4.0:
			return
		var c: Vector2 = sp + Vector2(0, bob)
		var r: float = 11.0
		var pts := PackedVector2Array([c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)])
		_marker.draw_colored_polygon(pts, Color(col, 0.25))
		pts.append(pts[0])
		_marker.draw_polyline(pts, col, 2.0, true)
		_marker.draw_circle(c, 3.0, col)
		var f: Font = UITheme.font()
		var txt: String = "%d m" % int(dist)
		var tw: float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 14).x
		_marker.draw_string_outline(f, c + Vector2(-tw * 0.5, r + 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.6))
		_marker.draw_string(f, c + Vector2(-tw * 0.5, r + 18), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
		return
	# Off screen: an arrow on the edge.
	var centre: Vector2 = vs * 0.5
	var dir: Vector2 = sp - centre
	if behind:
		dir = -dir
	if dir.length() < 0.001:
		dir = Vector2.DOWN
	dir = dir.normalized()
	var half: Vector2 = centre - Vector2(margin, margin)
	var k: float = minf(absf(half.x / dir.x) if absf(dir.x) > 0.0001 else INF, absf(half.y / dir.y) if absf(dir.y) > 0.0001 else INF)
	var at: Vector2 = centre + dir * k
	var perp := Vector2(-dir.y, dir.x)
	var tip: Vector2 = at + dir * (14.0 + bob * 0.5)
	var tri := PackedVector2Array([tip, at - dir * 4.0 + perp * 11.0, at - dir * 4.0 - perp * 11.0])
	_marker.draw_colored_polygon(tri, Color(col, 0.9))
	var f2: Font = UITheme.font()
	var t2: String = "%d m" % int(dist)
	var w2: float = f2.get_string_size(t2, HORIZONTAL_ALIGNMENT_CENTER, -1, 13).x
	var lp: Vector2 = at - dir * 26.0 + Vector2(-w2 * 0.5, 5)
	_marker.draw_string_outline(f2, lp, t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, 4, Color(0, 0, 0, 0.6))
	_marker.draw_string(f2, lp, t2, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
