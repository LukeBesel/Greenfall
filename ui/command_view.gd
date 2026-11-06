class_name CommandView
extends CanvasLayer
## Top-down tactical map of the district, fed by the robots' own telemetry (always live).
## Pick a crew (all cleaners / haulers / planters / waterers) or a single robot on the left,
## then paint hexes on the map to give it a work zone. Choose how it treats the zone:
## Priority (zone first, then roam), Stay (zone only), Follow me (hexes around Patch) or
## Recall (park at the hub). Robots show as live icons with a line to what they are doing.

signal closed

const ROLE_COLORS: Dictionary = {
	"clean": Color(1.0, 0.72, 0.28),
	"haul": Color(0.55, 0.78, 1.0),
	"plant": Color(0.55, 0.95, 0.45),
	"water": Color(0.45, 0.85, 1.0),
}
const HOLO := Color(0.38, 0.9, 1.0)
const HOLO_DIM := Color(0.38, 0.9, 1.0, 0.25)
const BG := Color(0.012, 0.03, 0.05, 0.95)
const ROLE_NAMES: Dictionary = {"clean": "Cleaners", "haul": "Haulers", "plant": "Planters", "water": "Waterers"}
const MODE_NAMES: Dictionary = {"priority": "Priority", "stay": "Stay in zone", "follow": "Follow me", "recall": "Recall"}
const MODE_HELP: Dictionary = {
	"priority": "Work the painted hexes first, then the rest of the district.",
	"stay": "Work only the painted hexes. Wait there when they are done.",
	"follow": "Work the hexes around you, wherever you go.",
	"recall": "Come back and park at the hub.",
}

var world: Node
var is_open: bool = false

var _root: Control
var _map: Control
var _list: VBoxContainer
var _title: Label
var _mode_row: HBoxContainer
var _mode_help: Label
var _footer: Label
var _sel_key: String = "clean"
var _sel_bot: bool = false
var _bg: ImageTexture
var _bg_rect := Rect2()
var _zoom: float = 1.2
var _pan := Vector2.ZERO
var _paint: int = 0  # 0 none, 1 add, -1 remove
var _pan_drag: bool = false
var _hover_hex: int = -1
var _list_t: float = 0.0


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = BG
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)

	var hb := HBoxContainer.new()
	hb.set_anchors_preset(Control.PRESET_FULL_RECT)
	hb.offset_left = 24
	hb.offset_top = 20
	hb.offset_right = -24
	hb.offset_bottom = -20
	hb.add_theme_constant_override("separation", 18)
	_root.add_child(hb)

	var side := PanelContainer.new()
	var sp := UITheme.box(Color(0.02, 0.07, 0.1, 0.85), Color(HOLO, 0.35), 1, 2, 14)
	sp.shadow_color = Color(HOLO, 0.12)
	sp.shadow_size = 10
	side.add_theme_stylebox_override("panel", sp)
	side.custom_minimum_size = Vector2(310, 0)
	hb.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 8)
	sv.add_child(hdr)
	var bar := ColorRect.new()
	bar.color = HOLO
	bar.custom_minimum_size = Vector2(4, 18)
	hdr.add_child(bar)
	hdr.add_child(UITheme.label("F L E E T   C O M M A N D", 13, HOLO))
	var uplink := UITheme.label("● LIVE", 11, Color(0.4, 1.0, 0.6))
	uplink.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	uplink.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	uplink.name = "Live"
	hdr.add_child(uplink)
	_title = UITheme.label("", 24)
	sv.add_child(_title)
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 4)
	sv.add_child(_mode_row)
	for m: String in Fleet.MODES:
		var b := Button.new()
		b.text = MODE_NAMES[m]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 30)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_mode.bind(m))
		b.set_meta("mode", m)
		_style_button(b, HOLO, false)
		_mode_row.add_child(b)
	_mode_help = UITheme.label("", 13, UITheme.MUTED)
	_mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_help.custom_minimum_size = Vector2(270, 36)
	sv.add_child(_mode_help)
	var row := HBoxContainer.new()
	sv.add_child(row)
	var clear := Button.new()
	clear.text = "Clear orders"
	clear.pressed.connect(func() -> void:
		world.fleet.clear_order(_sel_key, _sel_bot)
		Audio.play("click", 0.9, -8.0)
		_refresh())
	_style_button(clear, Color(1.0, 0.5, 0.4), false)
	row.add_child(clear)
	var here := Button.new()
	here.text = "Zone around me"
	here.pressed.connect(func() -> void:
		for h: int in world.field.hexes_near(world.patch.global_position, 1):
			if world.field.hex_hub[h] == 0 and not world.field.is_water(h):
				world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, true)
		Audio.play("blip", 1.0, -8.0)
		_refresh())
	_style_button(here, HOLO, false)
	row.add_child(here)
	var sep := ColorRect.new()
	sep.color = Color(HOLO, 0.25)
	sep.custom_minimum_size = Vector2(0, 1)
	sv.add_child(sep)
	sv.add_child(UITheme.label("C R E W S", 11, Color(HOLO, 0.7)))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_list)

	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(mv)
	_map = Control.new()
	_map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_STOP
	_map.draw.connect(_draw_map)
	_map.gui_input.connect(_map_input)
	mv.add_child(_map)
	_footer = UITheme.label("", 12, Color(HOLO, 0.6))
	mv.add_child(_footer)


## Holo button: dark glass, thin glowing border, a coloured stripe on the left for crews.
func _style_button(b: Button, col: Color, stripe: bool) -> void:
	var mk := func(bg_a: float, border_a: float, glow: float) -> StyleBoxFlat:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col.r * 0.25, col.g * 0.25, col.b * 0.3, bg_a)
		sb.border_color = Color(col, border_a)
		sb.set_border_width_all(1)
		if stripe:
			sb.border_width_left = 4
		sb.set_corner_radius_all(2)
		sb.content_margin_left = 12 if stripe else 8
		sb.content_margin_right = 8
		sb.content_margin_top = 4
		sb.content_margin_bottom = 4
		sb.shadow_color = Color(col, glow)
		sb.shadow_size = 6 if glow > 0.0 else 0
		return sb
	b.add_theme_stylebox_override("normal", mk.call(0.35, 0.3, 0.0))
	b.add_theme_stylebox_override("hover", mk.call(0.55, 0.6, 0.0))
	b.add_theme_stylebox_override("pressed", mk.call(0.85, 0.95, 0.25))
	b.add_theme_stylebox_override("hover_pressed", mk.call(0.9, 1.0, 0.3))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", col.lerp(Color.WHITE, 0.3))
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


func open_view() -> void:
	if world == null:
		return
	if _bg == null:
		_bake_background()
	is_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("blip", 0.8, -6.0)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)
	if _sel_bot and world.fleet.find_robot(_sel_key) == null:
		_select("clean", false)
	_refresh()


func close_view() -> void:
	if not is_open:
		return
	is_open = false
	_paint = 0
	_root.visible = false
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func select(key: String, is_bot: bool) -> void:
	_select(key, is_bot)


func _select(key: String, is_bot: bool) -> void:
	_sel_key = key
	_sel_bot = is_bot
	Audio.play("click", 1.1, -10.0)
	_refresh()


func _on_mode(m: String) -> void:
	world.fleet.set_mode(_sel_key, _sel_bot, m)
	Audio.play("servo", 1.4, -10.0)
	_refresh()


func _sel_color() -> Color:
	if _sel_bot:
		var r: Robot = world.fleet.find_robot(_sel_key)
		return ROLE_COLORS.get(r.role(), Color.WHITE) if r else Color.WHITE
	return ROLE_COLORS.get(_sel_key, Color.WHITE)


func _sel_order() -> Dictionary:
	var f: Fleet = world.fleet
	if f.has_order(_sel_key, _sel_bot):
		return f.order(_sel_key, _sel_bot)
	return {}


func _refresh() -> void:
	var f: Fleet = world.fleet
	var od: Dictionary = _sel_order()
	var mode: String = str(od.get("mode", "priority")) if not od.is_empty() else ""
	if _sel_bot:
		var r: Robot = f.find_robot(_sel_key)
		var own: bool = not od.is_empty()
		_title.text = "%s  ·  %s" % [_sel_key, Economy.robots.get(r.type_id, {}).get("name", r.type_id) if r else "?"]
		if not own and r:
			mode = ""
			_mode_help.text = "Following the %s crew orders. Paint hexes or pick a mode to give this robot its own." % ROLE_NAMES.get(r.role(), "").to_lower()
	else:
		_title.text = "%s  (%d)" % [ROLE_NAMES[_sel_key], f.robots_with_role(_sel_key).size()]
	_title.add_theme_color_override("font_color", _sel_color())
	if mode != "" or not _sel_bot:
		_mode_help.text = MODE_HELP.get(mode if mode != "" else "priority", "") if mode != "" else "No orders: roaming the whole district. Paint hexes on the map to set a work zone."
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	_rebuild_list()
	_footer.text = "[LMB] PAINT ZONE    [RMB] ERASE    [MMB / WHEEL] PAN · ZOOM    [B / ESC] CLOSE"
	_map.queue_redraw()


func _rebuild_list() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var f: Fleet = world.fleet
	if f.robots().is_empty():
		var l := UITheme.label("No robots yet. Build one at the workbench (Bots tab).", 14, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for role_id: String in Fleet.ROLES:
		var bots: Array[Robot] = f.robots_with_role(role_id)
		if bots.is_empty():
			continue
		var gb := Button.new()
		var gm: String = "roam"
		if f.has_order(role_id, false):
			var god: Dictionary = f.order(role_id, false)
			gm = str(god.get("mode", "priority")) if not (str(god.get("mode", "")) == "priority" and (god.get("zone", []) as Array).is_empty()) else "roam"
		gb.text = "%s   ×%d     %s" % [ROLE_NAMES[role_id].to_upper(), bots.size(), "ROAMING" if gm == "roam" else MODE_NAMES[gm].to_upper()]
		gb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		gb.custom_minimum_size = Vector2(0, 34)
		_style_button(gb, ROLE_COLORS[role_id], true)
		gb.toggle_mode = true
		gb.button_pressed = not _sel_bot and _sel_key == role_id
		gb.pressed.connect(_select.bind(role_id, false))
		_list.add_child(gb)
		for r: Robot in bots:
			var rb := Button.new()
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rb.add_theme_font_size_override("font_size", 12)
			_style_button(rb, Color(ROLE_COLORS[role_id], 0.8), false)
			rb.toggle_mode = true
			rb.button_pressed = _sel_bot and _sel_key == r.robot_name
			rb.text = "◆ %s  %s  —  %s" % [r.robot_name, Economy.tier_name(r.tier), r.status_text()]
			rb.set_meta("bot", r.robot_name)
			rb.pressed.connect(_select.bind(r.robot_name, true))
			_list.add_child(rb)


func _process(delta: float) -> void:
	if not is_open:
		return
	_map.queue_redraw()
	_list_t += delta
	if _list_t > 0.6:
		_list_t = 0.0
		# Update statuses in place (rebuilding would eat clicks).
		for c: Node in _list.get_children():
			if c.has_meta("bot"):
				var r: Robot = world.fleet.find_robot(str(c.get_meta("bot")))
				if r:
					(c as Button).text = "◆ %s  %s  —  %s" % [r.robot_name, Economy.tier_name(r.tier), r.status_text()]


# --- Map ---------------------------------------------------------------------------------

func _extent() -> float:
	var field: HexField = world.field
	return (field.radius + 1.2) * field.hex_size * 1.75


func _bake_background() -> void:
	var field: HexField = world.field
	var ext: float = _extent()
	var res: float = 1.0
	var px: int = int(ext * 2.0 / res)
	var img := Image.create(px, px, false, Image.FORMAT_RGBA8)
	# Blueprint tones: dark lots, darker roads, faint sidewalks, building footprints a touch brighter.
	var cols: Array[Color] = [Color(0.02, 0.06, 0.08), Color(0.008, 0.02, 0.03), Color(0.05, 0.13, 0.16),
		Color(0.06, 0.16, 0.22), Color(0.03, 0.08, 0.1)]
	for j: int in px:
		var z: float = -ext + (j + 0.5) * res
		for i: int in px:
			var x: float = -ext + (i + 0.5) * res
			var c: Color = Color(0.02, 0.05, 0.07)
			if field.layout:
				c = cols[clampi(field.layout.surface_at(x, z), 0, 4)]
			img.set_pixel(i, j, c)
	_bg = ImageTexture.create_from_image(img)
	_bg_rect = Rect2(-ext, -ext, ext * 2.0, ext * 2.0)


## World meters per screen pixel mapping.
func _scale() -> float:
	var s: Vector2 = _map.size
	return minf(s.x, s.y) / (_extent() * 2.0) * _zoom


func _to_screen(p: Vector3) -> Vector2:
	return _map.size * 0.5 + (Vector2(p.x, p.z) + _pan) * _scale()


func _to_world(sp: Vector2) -> Vector3:
	var w: Vector2 = (sp - _map.size * 0.5) / _scale() - _pan
	return Vector3(w.x, 0, w.y)


func _hex_poly(id: int, shrink: float = 1.0) -> PackedVector2Array:
	var field: HexField = world.field
	var c: Vector3 = field.hex_center(id)
	var pts := PackedVector2Array()
	for k: int in 6:
		var a: float = deg_to_rad(60.0 * k + 30.0)
		pts.append(_to_screen(c + Vector3(cos(a), 0, sin(a)) * field.hex_size * shrink))
	return pts


func _hex_color(id: int) -> Color:
	var field: HexField = world.field
	if field.is_water(id):
		return Color(0.15, 0.45, 1.0)
	if field.hex_hub[id] == 1:
		return Color(1.0, 0.8, 0.35)
	if field.hex_hub[id] == 2:
		return Color(0.4, 0.45, 0.5)
	if not field.is_clean(id):
		return Color(1.0, 0.42, 0.25).lerp(Color(1.0, 0.75, 0.3), field.removed_fraction(id))
	var life: float = float(world.garden.hex_life.get(id, 0.0)) if world.garden else 0.0
	if life > 0.0:
		return Color(0.45, 1.0, 0.45).lerp(Color(0.2, 1.0, 0.65), life)
	return HOLO


func _glow_poly(pts: PackedVector2Array, col: Color, w: float) -> void:
	var loop := pts.duplicate()
	loop.append(pts[0])
	_map.draw_polyline(loop, Color(col, col.a * 0.12), w * 4.0, true)
	_map.draw_polyline(loop, Color(col, col.a * 0.3), w * 2.0, true)
	_map.draw_polyline(loop, col, w, true)


func _draw_map() -> void:
	if world == null or _bg == null:
		return
	var field: HexField = world.field
	var f: Fleet = world.fleet
	var font: Font = UITheme.font()
	var t: float = Time.get_ticks_msec() * 0.001
	var pulse: float = 0.6 + 0.4 * sin(t * 5.0)
	var sz: Vector2 = _map.size
	_map.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.01, 0.035, 0.055, 0.9))
	# City blueprint underlay.
	var a: Vector2 = _to_screen(Vector3(_bg_rect.position.x, 0, _bg_rect.position.y))
	var b: Vector2 = _to_screen(Vector3(_bg_rect.end.x, 0, _bg_rect.end.y))
	_map.draw_texture_rect(_bg, Rect2(a, b - a), false, Color(1, 1, 1, 0.85))
	# Fine grid.
	var step: float = 24.0
	for i: int in int(sz.x / step) + 1:
		_map.draw_line(Vector2(i * step, 0), Vector2(i * step, sz.y), Color(HOLO, 0.04), 1.0)
	for j: int in int(sz.y / step) + 1:
		_map.draw_line(Vector2(0, j * step), Vector2(sz.x, j * step), Color(HOLO, 0.04), 1.0)
	# Hex states: translucent fill, glowing edges, cleaning progress arcs.
	for id: int in field.hex_count():
		var col: Color = _hex_color(id)
		var poly: PackedVector2Array = _hex_poly(id, 0.94)
		var dirty: bool = field.hex_hub[id] == 0 and not field.is_clean(id) and not field.is_water(id)
		_map.draw_colored_polygon(poly, Color(col, 0.16 if dirty else 0.1))
		_glow_poly(poly, Color(col, 0.45 if dirty else 0.3), 1.0)
		if dirty:
			var rf: float = field.removed_fraction(id)
			var c: Vector2 = _to_screen(field.hex_center(id))
			var rr: float = field.hex_size * _scale() * 0.32
			_map.draw_arc(c, rr, 0.0, TAU, 32, Color(col, 0.15), 2.0, true)
			if rf > 0.005:
				_map.draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * rf, 32, Color(col, 0.9), 2.5, true)
	# Selected zone.
	var zone: Array = []
	var od: Dictionary = _sel_order()
	if not od.is_empty():
		zone = od.get("zone", [])
		if str(od.get("mode", "")) == "follow":
			zone = field.hexes_near(world.patch.global_position, 1)
	var sc: Color = _sel_color()
	for h: Variant in zone:
		var zp: PackedVector2Array = _hex_poly(int(h), 0.86)
		_map.draw_colored_polygon(zp, Color(sc, 0.1 + 0.08 * pulse))
		_glow_poly(zp, Color(sc, 0.6 + 0.4 * pulse), 1.6)
	if not _sel_bot:
		for role_id: String in Fleet.ROLES:
			if role_id == _sel_key or not f.has_order(role_id, false):
				continue
			for h: Variant in f.order(role_id, false).get("zone", []):
				var p2: PackedVector2Array = _hex_poly(int(h), 0.8)
				p2.append(p2[0])
				_map.draw_polyline(p2, Color(ROLE_COLORS[role_id], 0.35), 1.0, true)
	# Radar sweep from the hub.
	var hub_p: Vector2 = _to_screen(world.depot.global_position)
	var reach: float = maxf(sz.x, sz.y)
	for k: int in 14:
		var ang: float = t * 0.9 - float(k) * 0.025
		_map.draw_line(hub_p, hub_p + Vector2(cos(ang), sin(ang)) * reach, Color(HOLO, 0.09 * (1.0 - float(k) / 14.0)), 2.0)
	# Hover readout.
	if _hover_hex >= 0:
		var hp: PackedVector2Array = _hex_poly(_hover_hex, 0.94)
		_glow_poly(hp, Color(1, 1, 1, 0.8), 1.2)
		var txt: String = "%d%% CLEAN" % int(field.removed_fraction(_hover_hex) * 100.0) if not field.is_clean(_hover_hex) else "CLEAN"
		if field.is_water(_hover_hex):
			txt = "WATER"
		elif field.hex_hub[_hover_hex] == 1:
			txt = "BASE"
		_tag(_to_screen(field.hex_center(_hover_hex)) + Vector2(14, -26), "HEX %02d  ·  %s" % [_hover_hex, txt], Color.WHITE)
	# Bales.
	for n: Node in get_tree().get_nodes_in_group("junk_cube"):
		var cube: JunkCube = n
		if not cube.carried:
			var cp: Vector2 = _to_screen(cube.global_position)
			_map.draw_rect(Rect2(cp - Vector2(3, 3), Vector2(6, 6)), Color(1.0, 0.85, 0.5, 0.25), true)
			_map.draw_rect(Rect2(cp - Vector2(2, 2), Vector2(4, 4)), Color(1.0, 0.9, 0.6), true)
	_draw_hub(hub_p, t)
	# Robots.
	for r: Robot in f.robots():
		var rp: Vector2 = _to_screen(r.global_position)
		var col: Color = ROLE_COLORS.get(r.role(), Color.WHITE)
		var selected: bool = (_sel_bot and r.robot_name == _sel_key) or (not _sel_bot and r.role() == _sel_key)
		if r.work_hex >= 0 and r.role() == "clean":
			_map.draw_dashed_line(rp, _to_screen(field.hex_center(r.work_hex)), Color(col, 0.4), 1.0, 5.0)
		var fwd := Vector2(-sin(r.rotation.y), -cos(r.rotation.y))
		var side_v: Vector2 = fwd.orthogonal()
		var chev := PackedVector2Array([rp + fwd * 8.0, rp + side_v * 5.5 - fwd * 5.0, rp - fwd * 2.0, rp - side_v * 5.5 - fwd * 5.0])
		_map.draw_circle(rp, 11.0 if selected else 8.0, Color(col, (0.22 * pulse) if selected else 0.1))
		if selected:
			_map.draw_arc(rp, 12.0, t * 3.0, t * 3.0 + PI * 1.2, 16, Color(col, 0.9), 1.5, true)
		_map.draw_colored_polygon(chev, col.lerp(Color.WHITE, 0.25))
		if _sel_bot and r.robot_name == _sel_key:
			_tag(rp + Vector2(14, -22), r.robot_name.to_upper(), col)
	# Patch: a tiny Aurora face.
	var pp: Vector2 = _to_screen(world.patch.global_position)
	var pc := Color(0.55, 0.92, 1.0)
	_map.draw_circle(pp, 16.0 + 3.0 * pulse, Color(pc, 0.08))
	_map.draw_circle(pp, 9.0, Color(0.92, 0.95, 0.97))
	_map.draw_circle(pp, 7.0, Color(0.03, 0.05, 0.08))
	_map.draw_circle(pp + Vector2(-2.6, -0.5), 1.7, pc)
	_map.draw_circle(pp + Vector2(2.6, -0.5), 1.7, pc)
	_map.draw_arc(pp, 13.0, -t * 2.0, -t * 2.0 + PI * 0.7, 12, Color(pc, 0.8), 1.5, true)
	_map.draw_arc(pp, 13.0, -t * 2.0 + PI, -t * 2.0 + PI * 1.7, 12, Color(pc, 0.8), 1.5, true)
	_tag(pp + Vector2(16, 6), "P-47CH", pc)
	# Scanline sweep.
	var sy: float = fmod(t * 90.0, sz.y + 80.0) - 40.0
	_map.draw_rect(Rect2(0, sy - 18.0, sz.x, 18.0), Color(HOLO, 0.025))
	_map.draw_line(Vector2(0, sy), Vector2(sz.x, sy), Color(HOLO, 0.12), 1.0)
	# Frame: corner brackets + header readout.
	var bc := Color(HOLO, 0.8)
	var L: float = 26.0
	for corner: Vector2 in [Vector2(0, 0), Vector2(sz.x, 0), Vector2(0, sz.y), sz]:
		var dx: float = 1.0 if corner.x == 0.0 else -1.0
		var dy: float = 1.0 if corner.y == 0.0 else -1.0
		var o := corner + Vector2(dx, dy) * 6.0
		_map.draw_line(o, o + Vector2(dx * L, 0), bc, 2.0)
		_map.draw_line(o, o + Vector2(0, dy * L), bc, 2.0)
	var tot: int = maxi(field.junk_hex_count, 1)
	var done: int = field.junk_hexes_cleaned()
	_map.draw_string(font, Vector2(22, 30), "SECTOR // %s" % str(world.district_name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, HOLO)
	_map.draw_string(font, Vector2(22, 48), "TELEMETRY UPLINK  ·  %d UNITS ONLINE" % f.robots().size(), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(HOLO, 0.6))
	var bar_w: float = 180.0
	var bx: float = sz.x - bar_w - 22.0
	_map.draw_string(font, Vector2(bx, 30), "RECLAIMED  %d / %d" % [done, tot], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HOLO)
	_map.draw_rect(Rect2(bx, 38, bar_w, 5), Color(HOLO, 0.15))
	_map.draw_rect(Rect2(bx, 38, bar_w * float(done) / float(tot), 5), Color(0.45, 1.0, 0.65))
	# Legend.
	var ly: float = sz.y - 22.0
	var lx: float = 22.0
	for item: Array in [["JUNK", Color(1.0, 0.42, 0.25)], ["CLEAN", HOLO], ["GROWING", Color(0.35, 1.0, 0.55)], ["WATER", Color(0.15, 0.45, 1.0)], ["BASE", Color(1.0, 0.8, 0.35)]]:
		_map.draw_rect(Rect2(lx, ly - 8, 9, 9), Color(item[1], 0.8))
		_map.draw_string(font, Vector2(lx + 14, ly), str(item[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(item[1], 0.8))
		lx += 80.0


## Base beacon: pulsing rings, rotating segments and a diamond core.
func _draw_hub(c: Vector2, t: float) -> void:
	var gold := Color(1.0, 0.8, 0.35)
	for k: int in 3:
		var ph: float = fmod(t * 0.6 + float(k) / 3.0, 1.0)
		_map.draw_arc(c, 8.0 + ph * 34.0, 0.0, TAU, 40, Color(gold, 0.5 * (1.0 - ph)), 1.5, true)
	for k: int in 4:
		var a0: float = t * 1.2 + k * PI * 0.5
		_map.draw_arc(c, 17.0, a0, a0 + PI * 0.32, 10, Color(gold, 0.9), 2.5, true)
	for k: int in 3:
		var a1: float = -t * 0.7 + k * TAU / 3.0
		_map.draw_arc(c, 23.0, a1, a1 + PI * 0.18, 8, Color(gold, 0.55), 1.2, true)
	var d := PackedVector2Array([c + Vector2(0, -8), c + Vector2(8, 0), c + Vector2(0, 8), c + Vector2(-8, 0)])
	_map.draw_colored_polygon(d, Color(gold, 0.35))
	var d2 := PackedVector2Array([c + Vector2(0, -5), c + Vector2(5, 0), c + Vector2(0, 5), c + Vector2(-5, 0)])
	_map.draw_colored_polygon(d2, gold.lerp(Color.WHITE, 0.4))
	_tag(c + Vector2(28, -30), "BASE  ·  HUB LV %d" % (world.hub.level if world.hub else 1), gold)


## Small label in a bordered holo tag with a leader line.
func _tag(at: Vector2, text: String, col: Color) -> void:
	var font: Font = UITheme.font()
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x + 12.0
	var r := Rect2(at, Vector2(w, 18))
	_map.draw_rect(r, Color(0.01, 0.04, 0.06, 0.85))
	_map.draw_rect(r, Color(col, 0.7), false, 1.0)
	_map.draw_rect(Rect2(at, Vector2(3, 18)), col)
	_map.draw_string(font, at + Vector2(8, 13), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col.lerp(Color.WHITE, 0.3))


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_paint = 1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(mb.position)
			MOUSE_BUTTON_RIGHT:
				_paint = -1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(mb.position)
			MOUSE_BUTTON_MIDDLE:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom = minf(4.0, _zoom * 1.12)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom = maxf(0.6, _zoom / 1.12)
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		_hover_hex = world.field.hex_at(_to_world(mm.position))
		if _pan_drag:
			_pan += mm.relative / _scale()
		elif _paint != 0:
			_paint_at(mm.position)


func _paint_at(sp: Vector2) -> void:
	var field: HexField = world.field
	var h: int = field.hex_at(_to_world(sp))
	if h < 0 or field.hex_hub[h] != 0:
		return
	var od: Dictionary = world.fleet.order(_sel_key, _sel_bot)
	var has: bool = (od["zone"] as Array).has(h)
	if (_paint > 0) == has:
		return
	if str(od.get("mode", "")) in ["recall", "follow"]:
		od["mode"] = "priority"  # painting means "work here"
	world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, _paint > 0)
	Audio.play("blip", 1.3 if _paint > 0 else 0.9, -14.0)
	_refresh_header_only()


func _refresh_header_only() -> void:
	var od: Dictionary = _sel_order()
	var mode: String = str(od.get("mode", "")) if not od.is_empty() else ""
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	if mode != "":
		_mode_help.text = MODE_HELP.get(mode, "")


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("open_command") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_view()
		get_viewport().set_input_as_handled()
