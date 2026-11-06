class_name CommandView
extends CanvasLayer
## Command mode: the camera lifts into an overhead view of the real district (RTS style).
## Hex outlines are drawn on the ground, robots get coloured rings, and the base gets a marker.
## Pick a crew (cleaners / haulers / planters / waterers) or one robot in the panel, then mark
## hexes on the ground to give it a work zone. Modes: Priority (zone first, then roam), Stay
## (zone only), Follow me (hexes around Patch) or Recall (park at the base).

signal closed

const ROLE_COLORS: Dictionary = {
	"clean": Color(1.0, 0.7, 0.3),
	"haul": Color(0.55, 0.75, 1.0),
	"plant": Color(0.55, 0.92, 0.45),
	"water": Color(0.4, 0.85, 0.95),
	"skim": Color(0.45, 1.0, 0.75),
}
const ROLE_NAMES: Dictionary = {"clean": "Cleaners", "haul": "Haulers", "plant": "Planters", "water": "Waterers", "skim": "Skimmers"}
const MODE_NAMES: Dictionary = {"priority": "Priority", "stay": "Stay", "follow": "Follow me", "recall": "Recall"}
const MODE_HELP: Dictionary = {
	"priority": "Works the marked hexes first, then the rest of the district.",
	"stay": "Works only the marked hexes, and waits there when they are done.",
	"follow": "Works the hexes around you, wherever you go.",
	"recall": "Comes back and parks at the base.",
}

var world: Node
var is_open: bool = false

var _root: Control
var _input_area: Control
var _list: VBoxContainer
var _title: Label
var _mode_row: HBoxContainer
var _mode_help: Label
var _info: RichTextLabel
var _sel_key: String = "clean"
var _sel_bot: bool = false
var _paint: int = 0  # 0 none, 1 add, -1 remove
var _pan_drag: bool = false
var _hover_hex: int = -1
var _list_t: float = 0.0
var _tank_btn: Button
var _overlay_t: float = 0.0

# 3D
var _cam: Camera3D
var _prev_cam: Camera3D
var _focus := Vector3.ZERO
var _height: float = 105.0
var _cam_pos := Vector3.ZERO
var _overlay: Node3D
var _grid_mi: MeshInstance3D
var _zone_mi: MeshInstance3D
var _line_mat: StandardMaterial3D
var _markers: Dictionary = {}  # robot name -> Node3D
var _base_marker: Node3D
var _you_marker: Node3D


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.visible = false
	add_child(_root)
	# Whole screen catches map input; the panels sit on top of it.
	_input_area = Control.new()
	_input_area.set_anchors_preset(Control.PRESET_FULL_RECT)
	_input_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_input_area.gui_input.connect(_map_input)
	_root.add_child(_input_area)
	# Soft vignette so the overhead view reads as a mode, not gameplay.
	var vig := TextureRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.05, 1.05)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.0, 0.02, 0.04, 0.5))
	g.gradient = grad
	vig.texture = g
	vig.stretch_mode = TextureRect.STRETCH_SCALE
	_root.add_child(vig)

	var side := PanelContainer.new()
	side.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 14))
	side.position = Vector2(20, 20)
	side.custom_minimum_size = Vector2(300, 0)
	_root.add_child(side)
	var sv := VBoxContainer.new()
	sv.add_theme_constant_override("separation", 8)
	side.add_child(sv)
	sv.add_child(UITheme.label("COMMAND", 12, UITheme.MUTED))
	_title = UITheme.label("", 22)
	sv.add_child(_title)
	_mode_row = HBoxContainer.new()
	_mode_row.add_theme_constant_override("separation", 4)
	sv.add_child(_mode_row)
	for m: String in Fleet.MODES:
		var b := Button.new()
		b.text = MODE_NAMES[m]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(_on_mode.bind(m))
		b.set_meta("mode", m)
		_style_button(b, UITheme.GOLD, false)
		_mode_row.add_child(b)
	_mode_help = UITheme.label("", 13, UITheme.MUTED)
	_mode_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_mode_help.custom_minimum_size = Vector2(272, 36)
	sv.add_child(_mode_help)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	sv.add_child(row)
	var here := Button.new()
	here.text = "Mark around me"
	here.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	here.pressed.connect(func() -> void:
		for h: int in world.field.hexes_near(world.patch.global_position, 1):
			if world.field.hex_hub[h] == 0 and world.field.is_water(h) == (_sel_key == "skim" and not _sel_bot):
				world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, true)
		Audio.play("blip", 1.0, -8.0)
		_refresh()
		_rebuild_zone())
	_style_button(here, UITheme.CREAM, false)
	row.add_child(here)
	var clear := Button.new()
	clear.text = "Clear"
	clear.pressed.connect(func() -> void:
		world.fleet.clear_order(_sel_key, _sel_bot)
		Audio.play("click", 0.9, -8.0)
		_refresh()
		_rebuild_zone())
	_style_button(clear, UITheme.CREAM, false)
	row.add_child(clear)
	# Water Tank: a refill station for waterers, built where Patch stands.
	_tank_btn = Button.new()
	_tank_btn.add_theme_font_size_override("font_size", 13)
	_tank_btn.pressed.connect(func() -> void:
		var net: WaterNet = world.fleet.water_net
		if net and net.place_tank(world.patch.global_position):
			Audio.play("buy", 1.0, -4.0)
		else:
			Audio.play("buzz", 1.2, -8.0)
		_refresh_build())
	_style_button(_tank_btn, ROLE_COLORS["water"], false)
	sv.add_child(_tank_btn)
	var sep := ColorRect.new()
	sep.color = UITheme.RUST
	sep.custom_minimum_size = Vector2(0, 1)
	sv.add_child(sep)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 360)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sv.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 2)
	scroll.add_child(_list)

	# Top-right progress readout and bottom key hints.
	var info_panel := PanelContainer.new()
	info_panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 10))
	info_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	info_panel.offset_right = -20
	info_panel.offset_top = 20
	info_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(info_panel)
	_info = RichTextLabel.new()
	_info.bbcode_enabled = true
	_info.fit_content = true
	_info.autowrap_mode = TextServer.AUTOWRAP_OFF
	_info.add_theme_font_override("normal_font", UITheme.font())
	_info.add_theme_font_size_override("normal_font_size", 14)
	_info.custom_minimum_size = Vector2(330, 0)
	info_panel.add_child(_info)
	var keys_panel := PanelContainer.new()
	keys_panel.add_theme_stylebox_override("panel", UITheme.box(UITheme.PLUM, UITheme.RUST, 1, 6, 8))
	keys_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	keys_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	keys_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	keys_panel.offset_bottom = -14
	keys_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(keys_panel)
	var keys := UITheme.label("Left drag  mark      Right drag  unmark      WASD / middle drag  move      Wheel  zoom      B  back", 13, UITheme.MUTED)
	keys_panel.add_child(keys)


## Slate button with a hairline border; pressed lights up in the given colour.
## Crew buttons get a coloured stripe on the left.
func _style_button(b: Button, col: Color, stripe: bool) -> void:
	var mk := func(bg: Color, border: Color) -> StyleBoxFlat:
		var sb := UITheme.box(bg, border, 1, 4, 6)
		if stripe:
			sb.border_width_left = 3
		sb.content_margin_left = 10
		return sb
	var edge: Color = col if stripe else UITheme.RUST
	b.add_theme_stylebox_override("normal", mk.call(UITheme.TEAL, edge))
	b.add_theme_stylebox_override("hover", mk.call(UITheme.PLUM_LIGHT.lightened(0.08), col if stripe else Color(1, 1, 1, 0.25)))
	var pressed_bg := Color(col.r * 0.3, col.g * 0.3, col.b * 0.3, 0.95)
	b.add_theme_stylebox_override("pressed", mk.call(pressed_bg, col))
	b.add_theme_stylebox_override("hover_pressed", mk.call(pressed_bg.lightened(0.05), col))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", UITheme.CREAM)
	b.add_theme_color_override("font_pressed_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)


# --- Open / close ------------------------------------------------------------------------

func open_view() -> void:
	if world == null:
		return
	if _overlay == null:
		_build_overlay()
	is_open = true
	_root.visible = true
	_overlay.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("whoosh", 1.2, -10.0)
	if world.get("hud") != null:
		world.hud.visible = false
	# Lift from the play camera into the overhead view.
	_prev_cam = get_viewport().get_camera_3d()
	_focus = world.patch.global_position
	_focus.y = 0.0
	_cam_pos = _prev_cam.global_position if _prev_cam else _focus + Vector3(0, 10, 10)
	_cam.global_position = _cam_pos
	_cam.current = true
	if _sel_bot and world.fleet.find_robot(_sel_key) == null:
		_sel_key = "clean"
		_sel_bot = false
	_rebuild_overlay()
	_refresh()


func close_view() -> void:
	if not is_open:
		return
	is_open = false
	_paint = 0
	_root.visible = false
	_overlay.visible = false
	if _prev_cam and is_instance_valid(_prev_cam):
		_prev_cam.current = true
	if world.get("hud") != null:
		world.hud.visible = true
	Audio.play("whoosh", 0.9, -12.0)
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


func _select(key: String, is_bot: bool) -> void:
	_sel_key = key
	_sel_bot = is_bot
	Audio.play("click", 1.1, -10.0)
	_refresh()
	_rebuild_zone()
	if is_bot:
		var r: Robot = world.fleet.find_robot(key)
		if r:
			_focus = Vector3(r.global_position.x, 0, r.global_position.z)


func _on_mode(m: String) -> void:
	world.fleet.set_mode(_sel_key, _sel_bot, m)
	Audio.play("servo", 1.4, -10.0)
	_refresh()
	_rebuild_zone()


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


func _sel_zone() -> Array:
	var od: Dictionary = _sel_order()
	if od.is_empty():
		return []
	if str(od.get("mode", "")) == "follow":
		return world.field.hexes_near(world.patch.global_position, 1)
	return od.get("zone", [])


# --- Panel ---------------------------------------------------------------------------------

func _refresh() -> void:
	var f: Fleet = world.fleet
	var od: Dictionary = _sel_order()
	var mode: String = str(od.get("mode", "")) if not od.is_empty() else ""
	if _sel_bot:
		var r: Robot = f.find_robot(_sel_key)
		_title.text = _sel_key
		if od.is_empty() and r:
			_mode_help.text = "Following the %s orders. Mark hexes or pick a mode to give it its own." % ROLE_NAMES.get(r.role(), "crew").to_lower()
	else:
		_title.text = "%s · %d / %d" % [ROLE_NAMES[_sel_key], f.robots_with_role(_sel_key).size(), f.crew_cap()]
	_title.add_theme_color_override("font_color", _sel_color())
	if mode != "":
		_mode_help.text = MODE_HELP.get(mode, "")
	elif not _sel_bot:
		_mode_help.text = "No orders yet: roaming the district. Drag on the ground to mark where to work."
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	_rebuild_list()


func _rebuild_list() -> void:
	for c: Node in _list.get_children():
		c.queue_free()
	var f: Fleet = world.fleet
	if f.robots().is_empty():
		var l := UITheme.label("No robots yet. Build one at the workbench.", 14, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(l)
		return
	for role_id: String in Fleet.ROLES:
		var bots: Array[Robot] = f.robots_with_role(role_id)
		if bots.is_empty() and Fleet.types_for_role(role_id).is_empty():
			continue
		var gb := Button.new()
		gb.alignment = HORIZONTAL_ALIGNMENT_LEFT
		gb.custom_minimum_size = Vector2(0, 32)
		_style_button(gb, ROLE_COLORS[role_id], true)
		gb.toggle_mode = true
		gb.button_pressed = not _sel_bot and _sel_key == role_id
		gb.text = "%s  %d/%d      %s" % [ROLE_NAMES[role_id], bots.size(), f.crew_cap(), _mode_label(role_id)]
		gb.pressed.connect(_select.bind(role_id, false))
		_list.add_child(gb)
		_add_build_row(role_id)
		for r: Robot in bots:
			var rb := Button.new()
			rb.alignment = HORIZONTAL_ALIGNMENT_LEFT
			rb.add_theme_font_size_override("font_size", 12)
			rb.flat = true
			rb.toggle_mode = true
			rb.button_pressed = _sel_bot and _sel_key == r.robot_name
			rb.add_theme_color_override("font_color", UITheme.MUTED)
			rb.add_theme_color_override("font_pressed_color", ROLE_COLORS[role_id])
			rb.text = _bot_line(r)
			rb.set_meta("bot", r.robot_name)
			rb.pressed.connect(_select.bind(r.robot_name, true))
			_list.add_child(rb)


## Build + Upgrade fleet buttons under a crew (they work at the workbench only).
func _add_build_row(role_id: String) -> void:
	for t: String in Fleet.types_for_role(role_id):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		b.set_meta("build_type", t)
		b.pressed.connect(func() -> void:
			var r: Robot = world.fleet.build(t, world.upgrades.build_at.call() if world.get("upgrades") else world.depot.global_position + Vector3(0, 0.2, 3))
			Audio.play("buy" if r else "buzz", 1.0, -4.0 if r else -8.0)
			_refresh())
		_style_button(b, ROLE_COLORS[role_id], false)
		row.add_child(b)
		var u := Button.new()
		u.add_theme_font_size_override("font_size", 12)
		u.set_meta("tier_type", t)
		u.pressed.connect(func() -> void:
			Audio.play("buy" if world.fleet.upgrade_tier(t) else "buzz", 0.9, -4.0)
			_refresh())
		_style_button(u, UITheme.GOLD, false)
		row.add_child(u)
		_list.add_child(row)
		var info := UITheme.label("", 11, UITheme.MUTED)
		info.set_meta("build_info", t)
		_list.add_child(info)
	_refresh_build()


## Live state of the Build / Upgrade buttons and the tank button.
func _refresh_build() -> void:
	var f: Fleet = world.fleet
	var at_bench: bool = world.near_bench() if world.has_method("near_bench") else false
	for c: Node in _list.get_children():
		if c is HBoxContainer:
			for b: Node in c.get_children():
				if b.has_meta("build_type"):
					var t: String = str(b.get_meta("build_type"))
					(b as Button).text = "Build %s  %s" % [Economy.robots[t]["name"], Settings.fmt(f.build_cost(t))]
					(b as Button).disabled = not (at_bench and f.can_build(t))
				elif b.has_meta("tier_type"):
					var req: Dictionary = f.tier_requirements(str(b.get_meta("tier_type")))
					var maxed: bool = req.get("maxed", false)
					(b as Button).text = "Max tier" if maxed else "Upgrade > %s" % str(req["next"]["name"])
					(b as Button).disabled = maxed or not (at_bench and req["ok"])
					(b as Button).tooltip_text = "" if maxed else "%s cubes, %s bolts, %s Control Core. %s" % [Settings.fmt(req["cost"]), Settings.fmt(req["bolts"]), Economy.rarity(int(req["core_rarity"])).get("name", "?"), req["reason"]]
		elif c.has_meta("build_info"):
			var t2: String = str(c.get_meta("build_info"))
			var have: int = 0
			var rs: Array = f.recipe_status(t2)
			for r: Dictionary in rs:
				if r["have"]:
					have += 1
			var why: String = f.build_block_reason(t2)
			(c as Label).text = "     parts %d/%d · %s" % [have, rs.size(), ("ready" if why == "" else why) if at_bench else "build at the workbench"]
	if _tank_btn:
		var net: WaterNet = f.water_net
		if net == null:
			_tank_btn.visible = false
		else:
			var why2: String = net.place_block_reason(world.patch.global_position)
			_tank_btn.text = "Place refill tank here  %s  (%d/%d)" % [Settings.fmt(net.tank_cost()), net.tanks.size(), int(WaterNet.cfg().get("max", 6))]
			_tank_btn.disabled = why2 != ""
			_tank_btn.tooltip_text = why2 if why2 != "" else "A Water Tank at your hex. Waterers refill at the nearest one."


func _mode_label(role_id: String) -> String:
	var f: Fleet = world.fleet
	if not f.has_order(role_id, false):
		return "roaming"
	var od: Dictionary = f.order(role_id, false)
	if str(od.get("mode", "")) == "priority" and (od.get("zone", []) as Array).is_empty():
		return "roaming"
	return MODE_NAMES[str(od.get("mode", "priority"))].to_lower()


func _bot_line(r: Robot) -> String:
	return "     %s  %s · %s" % [r.robot_name, Economy.tier_name(r.tier), r.status_text()]


# --- 3D overlay ------------------------------------------------------------------------------

func _build_overlay() -> void:
	_cam = Camera3D.new()
	_cam.fov = 50.0
	_cam.far = 900.0
	world.add_child(_cam)
	# Clear air up here: no haze or volumetric fog washing out the overview.
	var we: WorldEnvironment = world.get_node_or_null("WorldEnvironment")
	var src: Environment = we.environment if we else null
	if src == null and world.get("_env") != null:
		src = world._env
	if src:
		var env: Environment = src.duplicate()
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		env.sdfgi_enabled = false
		env.ssr_enabled = false
		_cam.environment = env
	_overlay = Node3D.new()
	_overlay.name = "CommandOverlay"
	world.add_child(_overlay)
	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line_mat.vertex_color_use_as_albedo = true
	_line_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_line_mat.no_depth_test = true
	_line_mat.render_priority = 2
	_grid_mi = MeshInstance3D.new()
	_grid_mi.material_override = _line_mat
	_grid_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.add_child(_grid_mi)
	_zone_mi = MeshInstance3D.new()
	_zone_mi.material_override = _line_mat
	_zone_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_overlay.add_child(_zone_mi)
	_base_marker = _make_pin(UITheme.GOLD, "BASE")
	_overlay.add_child(_base_marker)
	_you_marker = _make_pin(Color(0.55, 0.9, 1.0), "YOU")
	_overlay.add_child(_you_marker)
	_overlay.visible = false


func _make_pin(col: Color, text: String) -> Node3D:
	var n := Node3D.new()
	var ring := MeshInstance3D.new()
	ring.mesh = ProcMesh.torus(1.1, 1.4, 32, 4)
	ring.material_override = _flat_mat(col, 0.9)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(ring)
	var lab := Label3D.new()
	lab.text = text
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.no_depth_test = true
	lab.fixed_size = true
	lab.pixel_size = 0.00045
	lab.font_size = 30
	lab.outline_size = 8
	lab.modulate = col
	lab.position = Vector3(0, 2.5, 0)
	lab.name = "Label"
	n.add_child(lab)
	return n


func _flat_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(col, alpha)
	m.no_depth_test = true
	m.render_priority = 3
	return m


func _ground_y(p: Vector3) -> float:
	var layout: CityLayout = world.field.layout
	# Sidewalk/curb height only: never climb onto roofs.
	return clampf(layout.height_at(p.x, p.z) if layout else 0.0, 0.0, 0.3) + 0.12


func _corner(c: Vector3, k: int, r: float) -> Vector3:
	var a: float = deg_to_rad(60.0 * k + 30.0)
	var p: Vector3 = c + Vector3(cos(a), 0, sin(a)) * r
	return Vector3(p.x, _ground_y(p), p.z)


## Thick hex outline as a strip of quads hugging the ground.
func _add_hex_outline(st: SurfaceTool, id: int, shrink: float, width: float, col: Color) -> void:
	var field: HexField = world.field
	var c: Vector3 = field.hex_center(id)
	var r: float = field.hex_size * shrink
	for k: int in 6:
		var p0: Vector3 = _corner(c, k, r)
		var p1: Vector3 = _corner(c, k + 1, r)
		var q0: Vector3 = _corner(c, k, r - width)
		var q1: Vector3 = _corner(c, k + 1, r - width)
		for v: Vector3 in [p0, p1, q1, p0, q1, q0]:
			st.set_color(col)
			st.add_vertex(v)


func _add_hex_fill(st: SurfaceTool, id: int, shrink: float, col: Color) -> void:
	var field: HexField = world.field
	var c: Vector3 = field.hex_center(id)
	var r: float = field.hex_size * shrink
	var cy := Vector3(c.x, _ground_y(c), c.z)
	for k: int in 6:
		for v: Vector3 in [cy, _corner(c, k, r), _corner(c, k + 1, r)]:
			st.set_color(col)
			st.add_vertex(v)


func _hex_state_color(id: int) -> Color:
	var field: HexField = world.field
	if field.is_water(id):
		return Color(0.4, 0.7, 1.0)
	if field.hex_hub[id] != 0:
		return UITheme.GOLD
	if not field.is_clean(id):
		return Color(1.0, 0.55, 0.35)
	var life: float = float(world.garden.hex_life.get(id, 0.0)) if world.garden else 0.0
	return Color(0.5, 1.0, 0.55) if life > 0.0 else Color(0.9, 0.95, 1.0)


func _lw() -> float:
	return 0.08 + _height * 0.0035


## Progress colours, read at a glance from above:
## orange = untouched junk, blue = being cleaned, green = clean, bright green = growing.
func _progress_color(id: int) -> Color:
	var field: HexField = world.field
	if field.is_water(id) or field.hex_hub[id] != 0:
		return Color(0, 0, 0, 0)
	if not field.is_clean(id):
		return Color(1.0, 0.5, 0.2) if field.removed_fraction(id) < 0.03 else Color(0.3, 0.6, 1.0)
	var life: float = float(world.garden.hex_life.get(id, 0.0)) if world.garden else 0.0
	return Color(0.35, 0.95, 0.4) if life > 0.0 else Color(0.3, 0.8, 0.45)


func _rebuild_overlay() -> void:
	var field: HexField = world.field
	var w: float = _lw()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for id: int in field.hex_count():
		var col: Color = _progress_color(id)
		if col.a > 0.0:
			_add_hex_fill(st, id, 0.97, Color(col, 0.38))
		var edge: Color = Color(1, 1, 1, 0.55)
		if field.hex_hub[id] != 0:
			edge = Color(UITheme.GOLD, 0.9)
		elif field.is_water(id):
			edge = Color(0.6, 0.85, 1.0, 0.5)
		_add_hex_outline(st, id, 0.99, w * 0.7, edge)
	if _hover_hex >= 0:
		_add_hex_outline(st, _hover_hex, 0.99, w * 2.0, Color(1, 1, 1, 0.95))
	_grid_mi.mesh = st.commit()
	_rebuild_zone()


func _rebuild_zone() -> void:
	if _zone_mi == null:
		return
	var zone: Array = _sel_zone()
	var col: Color = _sel_color()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = 0
	for h: Variant in zone:
		_add_hex_outline(st, int(h), 0.93, _lw() * 2.5, Color(col, 0.95))
		n += 1
	# Other crews' zones, faintly.
	if not _sel_bot:
		for role_id: String in Fleet.ROLES:
			if role_id == _sel_key or not world.fleet.has_order(role_id, false):
				continue
			for h: Variant in world.fleet.order(role_id, false).get("zone", []):
				_add_hex_outline(st, int(h), 0.87, _lw() * 1.2, Color(ROLE_COLORS[role_id], 0.45))
				n += 1
	_zone_mi.mesh = st.commit() if n > 0 else null


func _update_markers(t: float) -> void:
	var f: Fleet = world.fleet
	var alive: Dictionary = {}
	var scale_k: float = clampf(_height / 35.0, 0.5, 5.0)
	for r: Robot in f.robots():
		alive[r.robot_name] = true
		var m: Node3D = _markers.get(r.robot_name)
		if m == null:
			m = _make_pin(ROLE_COLORS.get(r.role(), Color.WHITE), r.robot_name)
			_overlay.add_child(m)
			_markers[r.robot_name] = m
		var col: Color = ROLE_COLORS.get(r.role(), Color.WHITE)
		var selected: bool = (_sel_bot and r.robot_name == _sel_key) or (not _sel_bot and r.role() == _sel_key)
		var ring: MeshInstance3D = m.get_child(0)
		(ring.material_override as StandardMaterial3D).albedo_color = Color(col, 0.95 if selected else 0.5)
		m.scale = Vector3.ONE * (0.55 + (0.08 * sin(t * 5.0) if selected else 0.0)) * scale_k
		m.global_position = Vector3(r.global_position.x, _ground_y(r.global_position), r.global_position.z)
		var lab: Label3D = m.get_node("Label")
		lab.visible = _sel_bot and r.robot_name == _sel_key
		lab.modulate = col
	for k: String in _markers.keys():
		if not alive.has(k):
			(_markers[k] as Node3D).queue_free()
			_markers.erase(k)
	var dp: Vector3 = world.depot.global_position
	_base_marker.global_position = Vector3(dp.x, _ground_y(dp), dp.z)
	_base_marker.scale = Vector3.ONE * scale_k * 0.9
	var pp: Vector3 = world.patch.global_position
	_you_marker.global_position = Vector3(pp.x, _ground_y(pp), pp.z)
	_you_marker.scale = Vector3.ONE * scale_k * (0.6 + 0.05 * sin(t * 4.0))


# --- Frame ----------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open:
		return
	var t: float = Time.get_ticks_msec() * 0.001
	# WASD pans the overhead camera.
	var mv := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_forward", "move_back"))
	_focus += Vector3(mv.x, 0, mv.y) * _height * 0.9 * delta
	var lim: float = (world.field.radius + 1.0) * world.field.hex_size * 1.8
	_focus.x = clampf(_focus.x, -lim, lim)
	_focus.z = clampf(_focus.z, -lim, lim)
	var target: Vector3 = _focus + Vector3(0, _height, _height * 0.55)
	_cam_pos = _cam_pos.lerp(target, clampf(delta * 4.0, 0.0, 1.0))
	_cam.global_position = _cam_pos
	_cam.look_at(_cam_pos + (_focus - target).normalized() * 10.0, Vector3.UP)
	_update_markers(t)
	_overlay_t += delta
	if _overlay_t > 0.5:
		_overlay_t = 0.0
		_rebuild_overlay()
	var f: Fleet = world.fleet
	_info.text = "%s     %d / %d hexes clean     %d robots\n[color=#ff8033]■[/color] junk    [color=#4d99ff]■[/color] cleaning    [color=#4dcc73]■[/color] clean    [color=#59f266]■[/color] growing" % [str(world.district_name), world.field.junk_hexes_cleaned(), world.field.junk_hex_count, f.robots().size()]
	_list_t += delta
	if _list_t > 0.6:
		_list_t = 0.0
		for c: Node in _list.get_children():
			if c.has_meta("bot"):
				var r: Robot = f.find_robot(str(c.get_meta("bot")))
				if r:
					(c as Button).text = _bot_line(r)
		_refresh_build()


func _ground_hit(sp: Vector2) -> Vector3:
	var o: Vector3 = _cam.project_ray_origin(sp)
	var d: Vector3 = _cam.project_ray_normal(sp)
	if absf(d.y) < 0.001:
		return Vector3.INF
	return o + d * (-o.y / d.y)


func _hex_under(sp: Vector2) -> int:
	var p: Vector3 = _ground_hit(sp)
	if p == Vector3.INF:
		return -1
	return world.field.hex_at(p)


func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_paint = 1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(get_viewport().get_mouse_position())
			MOUSE_BUTTON_RIGHT:
				_paint = -1 if mb.pressed else 0
				if mb.pressed:
					_paint_at(get_viewport().get_mouse_position())
			MOUSE_BUTTON_MIDDLE:
				_pan_drag = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_height = maxf(14.0, _height / 1.12)
					_overlay_t = 1.0
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_height = minf(200.0, _height * 1.12)
					_overlay_t = 1.0
	elif event is InputEventMouseMotion:
		var mm: InputEventMouseMotion = event
		var h: int = _hex_under(get_viewport().get_mouse_position())
		if h != _hover_hex:
			_hover_hex = h
			_overlay_t = 1.0
		if _pan_drag:
			_focus -= Vector3(mm.relative.x, 0, mm.relative.y) * _height * 0.0025
		elif _paint != 0:
			_paint_at(get_viewport().get_mouse_position())


func _paint_at(sp: Vector2) -> void:
	var field: HexField = world.field
	var h: int = _hex_under(sp)
	if h < 0 or field.hex_hub[h] != 0:
		return
	var od: Dictionary = world.fleet.order(_sel_key, _sel_bot)
	var has: bool = (od["zone"] as Array).has(h)
	if (_paint > 0) == has:
		return
	if str(od.get("mode", "")) in ["recall", "follow"]:
		od["mode"] = "priority"  # marking ground means "work here"
	world.fleet.toggle_zone_hex(_sel_key, _sel_bot, h, _paint > 0)
	Audio.play("blip", 1.3 if _paint > 0 else 0.9, -14.0)
	_rebuild_zone()
	var mode: String = str(od.get("mode", ""))
	for b: Node in _mode_row.get_children():
		(b as Button).button_pressed = str(b.get_meta("mode")) == mode
	_mode_help.text = MODE_HELP.get(mode, "")


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("open_command") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_view()
		get_viewport().set_input_as_handled()
