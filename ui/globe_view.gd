class_name GlobeView
extends CanvasLayer
## Holographic survey map of the whole planet. Every hex is drawn colored by its surveyed state:
## junk, clean, planted, growing, restored, water; cities outlined, hubs and Patch marked.
## The map is a snapshot: it shows when it was surveyed and can be refreshed for a fee
## (later: survey drone upgrades for periodic updates, then a live layer).

signal closed

const COLORS: Dictionary = {
	PlanetData.State.JUNK: Color(1.0, 0.45, 0.1),
	PlanetData.State.CLEAN: Color(0.4, 1.0, 0.3),
	PlanetData.State.PLANTED: Color(0.3, 0.95, 0.5),
	PlanetData.State.GROWING: Color(0.2, 1.0, 0.7),
	PlanetData.State.RESTORED: Color(0.75, 1.0, 0.45),
	PlanetData.State.WATER: Color(0.08, 0.2, 0.45),
}

var planet: PlanetData
## [orbE] Round planet (--orbit): the survey reads SphereCells (same ids as `planet`) and draws the
## far shell's big hexes; sphere_grid places the "you are here" marker; Lumi holds it on local up.
var cells: SphereCells
var shell: SphereShell
var sphere_grid: SphereGrid
var _shell_snap: Image
var patch_cell_provider: Callable = func() -> int: return -1
var is_open: bool = false

var _snapshot := PackedByteArray()
var _snapshot_time: float = -1.0
var _root: Control
var _vp: SubViewport
var _pivot: Node3D
var _globe: MeshInstance3D
var _marker: MeshInstance3D
var _cam: Camera3D
var _age: Label
var _ark: Label
var _resurvey: Button
var _drag: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.3
var _zoom: float = 3.2
var _hub_list: VBoxContainer
var _pct: Label
var _pct_sub: Label
var _bar: ProgressBar
var _rows: VBoxContainer
var _big: Label
var _grid_lines: MeshInstance3D
## Hand-held mode: Patch raises a claw and projects the globe into the real world.
var holder: Node3D  # Patch (has .model: PatchModel)
var world_root: Node3D
var _dim: ColorRect
var _svc: SubViewportContainer
var _anchor: Node3D
var _beam: MeshInstance3D
var _world_cam: Camera3D
var _prev_cam: Camera3D
var _handheld: bool = false
var _holo_mat: ShaderMaterial
var rocket_ready: Callable = func() -> bool: return false
## Why the rocket can't launch right now (shown in the hub list while rocket_ready is false).
var rocket_lock_text: Callable = func() -> String: return "Locked. Upgrade your base to level 5 to build the launch pad."
var launch_to: Callable = func(_hub: int) -> void: pass
## [orbD] Which hubs the launch list offers (indices into planet.hubs); unset: the flat game's
## base hubs. On a walkable globe: the hub sites (planet/sites/orbit_sites.gd).
var hub_order: Callable = Callable()
var current_hub: int = 0
var _fly_t: float = -1.0
var _fly_from := Vector3.ZERO
var _fly_to := Vector3.ZERO
var _fly_dur: float = 5.0
## Set by fly(): the rocket flight hologram can't be dismissed (the scene reloads after it).
var _flight_locked: bool = false
## [home] Opens the solar-system map (set by systems/homeward_director.gd); the button hides without it.
var open_system: Callable = Callable()
var _system_btn: Button
## [v2map] Owner note 40: on the round game the map is only a map; the rocket's destination list
## (ui/rocket_picker.gd, E at the rocket) does the travel. false hides the Rocket card.
var travel_in_map: bool = true
var _rocket_card: Control
var _hint: PromptLabel
## [v2map] How many bases the legend counts (the round globe has its hub sites, not planet.hubs).
var hub_count: Callable = Callable()


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.9)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_dim = dim
	var svc := SubViewportContainer.new()
	_svc = svc
	svc.stretch = true
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_4X
	svc.add_child(_vp)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	_globe = MeshInstance3D.new()
	_pivot.add_child(_globe)
	_marker = MeshInstance3D.new()
	_marker.mesh = ProcMesh.sphere(0.03, 10, 5)
	_marker.material_override = Mats.lamp(Color(1.0, 0.95, 0.6), 2.0)
	_pivot.add_child(_marker)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 0.35
	env.glow_bloom = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Left: survey card (big percentage + counts), then the show-on-map card.
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 12)
	left.position = Vector2(28, 28)
	_root.add_child(left)
	var c1: Array = _holo_card(tr("Survey"), 300, tr("Verdance  ·  hand-held projection"))
	left.add_child(c1[0])
	var b1: VBoxContainer = c1[1]
	_pct = UITheme.label("0.0 %", 40, HOLO.lerp(Color.WHITE, 0.7))
	b1.add_child(_pct)
	_pct_sub = UITheme.label("", 13, UITheme.MUTED)
	b1.add_child(_pct_sub)
	_bar = ProgressBar.new()
	_bar.show_percentage = false
	_bar.custom_minimum_size = Vector2(0, 8)
	_bar.add_theme_stylebox_override("fill", UITheme.box(_legend_col(PlanetData.State.CLEAN), Color(0, 0, 0, 0), 0, 4, 0))
	_bar.add_theme_stylebox_override("background", UITheme.box(Color(_legend_col(PlanetData.State.JUNK), 0.35), Color(0, 0, 0, 0), 0, 4, 0))
	b1.add_child(_bar)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 4)
	b1.add_child(_rows)
	for k: Array in [["junk", _legend_col(PlanetData.State.JUNK), tr("Not cleaned yet")], ["clean", _legend_col(PlanetData.State.CLEAN), tr("Cleaned")],
			["planted", _legend_col(PlanetData.State.PLANTED), tr("Planted")], ["growing", _legend_col(PlanetData.State.GROWING), tr("Growing")],
			["restored", _legend_col(PlanetData.State.RESTORED), tr("Restored")], ["cities", Color(0.85, 0.88, 0.92), tr("Cities")],
			["hubs", Color(1.0, 0.75, 0.25), tr("Bases")]]:
		var r: HBoxContainer = UITheme.stat_row(k[1], k[2])
		r.name = k[0]
		_rows.add_child(r)
	_age = UITheme.label("", 13, UITheme.GOLD)
	b1.add_child(_age)
	_ark = UITheme.label("", 13, Color(0.6, 1.0, 0.55))  # [bloom] Seed Ark / Verdance Bloom line
	b1.add_child(_ark)
	_resurvey = Button.new()
	_resurvey.custom_minimum_size = Vector2(0, 38)
	_holo_button(_resurvey)
	_resurvey.pressed.connect(_on_resurvey)
	b1.add_child(_resurvey)
	_system_btn = Button.new()  # [home] zoom out to the solar-system map (ui/system_map.gd)
	_system_btn.custom_minimum_size = Vector2(0, 38)
	_system_btn.text = tr("Solar system")
	_holo_button(_system_btn)
	_system_btn.pressed.connect(func() -> void:
		if open_system.is_valid() and not _flight_locked:
			close_view()
			open_system.call())
	b1.add_child(_system_btn)
	# Right: rocket destinations.
	var right := VBoxContainer.new()
	right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right.offset_right = -28
	right.offset_top = 28
	right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_root.add_child(right)
	_rocket_card = right
	var c2: Array = _holo_card(tr("Rocket"), 320, tr("Travel between bases"))
	right.add_child(c2[0])
	_hub_list = VBoxContainer.new()
	_hub_list.add_theme_constant_override("separation", 6)
	(c2[1] as VBoxContainer).add_child(_hub_list)
	# [v2map] Top centre: big readout and the controls on one soft plate (at the bottom the
	# subtitles covered them, and bare text over the daylit world was hard to read).
	var top := PanelContainer.new()
	top.add_theme_stylebox_override("panel", UITheme.box(Color(0.02, 0.06, 0.06, 0.62), Color(0, 0, 0, 0), 0, 12, 10))
	top.set_anchors_preset(Control.PRESET_CENTER_TOP)
	top.grow_horizontal = Control.GROW_DIRECTION_BOTH
	top.offset_top = 18
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(top)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 2)
	top.add_child(tv)
	_big = UITheme.label("", 24, Color(HOLO, 0.9))
	_big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(_big)
	var hint := PromptLabel.new(tr("[k]Drag to spin   ·   Wheel to zoom   ·   [/k][p]{@look}  spin     {zoom_out}{zoom_in}  zoom     {@dpad}  launch list     [/p]{open_globe}  close"), 13)  # [deck]
	hint.align_center = true
	tv.add_child(hint)
	_hint = hint
	_root.visible = false


const HOLO := Color(0.45, 0.88, 1.0)


## Translucent projected pane: faint cyan glass, hairline edge, corner ticks, light title.
func _holo_card(title: String, width: float, subtitle: String) -> Array:
	var pc := PanelContainer.new()
	var sb := UITheme.box(Color(0.04, 0.16, 0.22, 0.55), Color(HOLO, 0.45), 1, 2, 14)
	sb.shadow_color = Color(HOLO, 0.1)
	sb.shadow_size = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pc.add_child(body)
	body.add_child(UITheme.label(subtitle, 11, Color(HOLO, 0.7)))
	body.add_child(UITheme.label(title.to_upper(), 20, HOLO.lerp(Color.WHITE, 0.5)))
	var line := ColorRect.new()
	line.color = Color(HOLO, 0.5)
	line.custom_minimum_size = Vector2(0, 1)
	body.add_child(line)
	# Corner ticks drawn over the pane.
	var ticks := Control.new()
	ticks.set_anchors_preset(Control.PRESET_FULL_RECT)
	ticks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(ticks)
	ticks.draw.connect(func() -> void:
		var sz: Vector2 = ticks.size
		var c := Color(HOLO, 0.9)
		for corner: Vector2 in [Vector2.ZERO, Vector2(sz.x, 0), Vector2(0, sz.y), sz]:
			var dx: float = 1.0 if corner.x == 0.0 else -1.0
			var dy: float = 1.0 if corner.y == 0.0 else -1.0
			ticks.draw_line(corner, corner + Vector2(dx * 12, 0), c, 2.0)
			ticks.draw_line(corner, corner + Vector2(0, dy * 12), c, 2.0))
	return [pc, body]


func _holo_button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.box(Color(HOLO, 0.16), Color(HOLO, 0.6), 1, 2, 8))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(HOLO, 0.3), Color(HOLO, 0.9), 1, 2, 8))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(HOLO, 0.45), HOLO, 1, 2, 8))
	b.add_theme_stylebox_override("disabled", UITheme.box(Color(HOLO, 0.04), Color(HOLO, 0.15), 1, 2, 8))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", HOLO.lerp(Color.WHITE, 0.6))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(HOLO, 0.35))


func survey_cost() -> BigNum:
	return BigNum.from_float(40.0 + 3.0 * float(planet.restored_count()))


## Takes a fresh snapshot of the planet state (free on first use).
func survey() -> void:
	if cells and shell:  # [orbE]
		shell.update(1000.0)  # flush pending big-hex aggregates first
		_shell_snap = SphereMapMesh.snapshot(shell)
	_snapshot = cells.state.duplicate() if cells else planet.state.duplicate()
	_snapshot_time = float(GameState.stats.get("time_played", 0.0))
	_build_mesh()


func open_view() -> void:
	if planet == null:
		return
	if _snapshot.is_empty():
		survey()
	is_open = true
	_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	Audio.play("whoosh", 0.7, -8.0)
	_set_handheld(holder != null and world_root != null)
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_refresh_text()
	_rocket_card.visible = travel_in_map  # [v2map]
	if travel_in_map:
		_refresh_hubs()
	elif not _hint.has_meta("v2map"):
		_hint.set_meta("v2map", true)
		_hint.set_template(tr("[k]Drag to spin   ·   Wheel to zoom   ·   [/k][p]{@look}  spin     {zoom_out}{zoom_in}  zoom     [/p]{open_globe}  close"))
	_focus_first.call_deferred()  # [deck] pad players need a focused control for the D-pad


## [deck] Whether the action's controller button is held (the wheel keeps its own step zoom).
func _pad_held(action: String) -> bool:
	var ev: InputEvent = Settings.binding(action, true)
	if ev is InputEventJoypadButton:
		return Input.is_joy_button_pressed(Settings.last_pad_device, (ev as InputEventJoypadButton).button_index)
	if ev is InputEventJoypadMotion:
		return Input.get_joy_axis(Settings.last_pad_device, (ev as InputEventJoypadMotion).axis) * signf((ev as InputEventJoypadMotion).axis_value) > 0.5
	return false


## [deck] First enabled Launch button, else Re-survey (the hub list was just rebuilt).
func _focus_first() -> void:
	if not is_open:
		return
	for row: Node in _hub_list.get_children():
		if row.is_queued_for_deletion():
			continue
		for b: Node in row.find_children("*", "Button", true, false):
			if not (b as Button).disabled:
				(b as Button).grab_focus()
				return
	if _resurvey and _resurvey.visible and not _resurvey.disabled:
		_resurvey.grab_focus()


func _refresh_hubs() -> void:
	for c: Node in _hub_list.get_children():
		c.queue_free()
	var ready_: bool = rocket_ready.call()
	if not ready_:
		var l := UITheme.label(str(rocket_lock_text.call()), 13, UITheme.MUTED)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_hub_list.add_child(l)
	var here: Vector3 = planet.grid.centers[planet.hubs[current_hub]]
	var order: Array = range(planet.base_hub_count if planet.base_hub_count > 0 else planet.hubs.size())  # [biomes] frontiers launch from the Rockets tab
	if hub_order.is_valid():  # [orbD]
		order = hub_order.call()
	order.sort_custom(func(a: int, b: int) -> bool:
		return here.angle_to(planet.grid.centers[planet.hubs[a]]) < here.angle_to(planet.grid.centers[planet.hubs[b]]))
	for i: int in order.filter(func(x: int) -> bool: return x != current_hub).slice(0, 5):  # [biomes]
		var cell: int = planet.hubs[i]
		var nm: String = tr(str(planet.cities[planet.city[cell]]["name"])) if planet.city[cell] >= 0 else PlanetData.BIOMES[planet.biome[cell]].capitalize().replace("_", " ") + " site"
		var km: float = here.angle_to(planet.grid.centers[cell]) * planet.radius_m / 1000.0
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", UITheme.row_box())
		var hb := HBoxContainer.new()
		row.add_child(hb)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.add_theme_constant_override("separation", 0)
		vb.add_child(UITheme.label(nm, 15, Color.WHITE))
		vb.add_child(UITheme.label(tr("%d sectors away") % int(km * 1000.0 / 17.3), 12, UITheme.MUTED))
		hb.add_child(vb)
		var b := Button.new()
		b.text = tr("Launch")
		b.disabled = not ready_
		_holo_button(b)
		b.pressed.connect(func() -> void:
			close_view()
			launch_to.call(i))
		hb.add_child(b)
		_hub_list.add_child(row)


## Rocket flight: a glowing marker arcs from one hub to another while the globe turns to follow.
func fly(from_hub: int, to_hub: int, duration: float) -> void:
	if _snapshot.is_empty():
		survey()
	_fly_from = planet.grid.centers[planet.hubs[from_hub]]
	_fly_to = planet.grid.centers[planet.hubs[to_hub]]
	_fly_dur = duration
	_fly_t = 0.0
	_flight_locked = true
	is_open = true
	_root.visible = true
	_zoom = 2.6
	Audio.play("whoosh", 0.5, -4.0)


func close_view() -> void:
	if not is_open or _flight_locked:
		return
	is_open = false
	_root.visible = false
	_set_handheld(false)
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


## Switch between the hand-held hologram in the world and the full-screen view (rocket flight).
func _set_handheld(on: bool) -> void:
	var model: PatchModel = holder.get("model") if holder else null
	if on:
		if _anchor == null:
			_anchor = Node3D.new()
			_anchor.name = "SurveyHologram"
			world_root.add_child(_anchor)
			_beam = MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0.9
			cone.bottom_radius = 0.04
			cone.height = 1.0
			cone.cap_top = false
			cone.cap_bottom = false
			_beam.mesh = cone
			var bm := StandardMaterial3D.new()
			bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			bm.cull_mode = BaseMaterial3D.CULL_DISABLED
			bm.albedo_color = Color(0.25, 0.7, 1.0) * 0.18
			_beam.material_override = bm
			_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			world_root.add_child(_beam)
			_world_cam = Camera3D.new()
			_world_cam.fov = 55.0
			_world_cam.near = 0.05
			world_root.add_child(_world_cam)
		_pivot.reparent(_anchor, false)
		_pivot.position = Vector3.ZERO
		_anchor.visible = true
		_beam.visible = true
		_prev_cam = get_viewport().get_camera_3d()
		_world_cam.global_transform = _prev_cam.global_transform if _prev_cam else Transform3D.IDENTITY
		_world_cam.current = true
		_dim.visible = false
		_svc.visible = false
		_anchor.scale = Vector3.ONE * 0.01
		create_tween().tween_property(_anchor, "scale", Vector3.ONE * 0.3, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Audio.play("sparkle", 0.6, -10.0)
		if world_root.get("hud") != null:
			world_root.hud.visible = false
		if model:
			model.holding = true
			model.set_happy(0.7)
	else:
		if _anchor and _pivot.get_parent() == _anchor:
			_pivot.reparent(_vp, false)
			_pivot.position = Vector3.ZERO
			_pivot.scale = Vector3.ONE
		if _anchor:
			_anchor.visible = false
			_beam.visible = false
		if _prev_cam and is_instance_valid(_prev_cam) and _handheld:
			_prev_cam.current = true
		_dim.visible = true
		_svc.visible = true
		if world_root and world_root.get("hud") != null:
			world_root.hud.visible = true
		if model:
			model.holding = false
	_handheld = on


func _on_resurvey() -> void:
	if not GameState.spend("cubes", survey_cost()):
		Audio.play("buzz", 1.2, -8.0)
		return
	survey()
	Audio.play("sparkle", 0.8, -6.0)
	_refresh_text()


func _refresh_text() -> void:
	var counts: Dictionary = {}
	var land: int = 0
	for st: int in _snapshot:
		counts[st] = int(counts.get(st, 0)) + 1
		if st != PlanetData.State.WATER:
			land += 1
	var junk: int = int(counts.get(PlanetData.State.JUNK, 0))
	var cleaned: int = land - junk
	var frac: float = float(cleaned) / maxf(land, 1)
	_pct.text = "%.3f %%" % (100.0 * frac)
	_pct_sub.text = tr("of the planet reclaimed  ·  %s of %s land hexes") % [_num(cleaned), _num(land)]
	_bar.value = frac * 100.0
	var vals: Dictionary = {"junk": junk, "clean": counts.get(PlanetData.State.CLEAN, 0), "planted": counts.get(PlanetData.State.PLANTED, 0),
		"growing": counts.get(PlanetData.State.GROWING, 0), "restored": counts.get(PlanetData.State.RESTORED, 0),
		"cities": planet.cities.size(), "hubs": int(hub_count.call()) if hub_count.is_valid() else planet.hubs.size()}
	for k: String in vals:
		((_rows.get_node(k) as HBoxContainer).get_node("Value") as Label).text = _num(int(vals[k]))
	_big.text = tr("%s HEXES CLEAN") % _num(cleaned)
	var age: float = float(GameState.stats.get("time_played", 0.0)) - _snapshot_time
	_age.text = tr("Surveyed %s ago%s") % [_fmt_age(age), tr("   ·   OUTDATED") if age > 600.0 else ""]
	_resurvey.text = tr("Re-survey      %s cubes") % Settings.fmt(survey_cost())
	if _system_btn:  # [home]
		_system_btn.visible = open_system.is_valid() and Homeward.system_open()  # [pace2] partial progress opens the system
	_ark.text = Bloom.globe_line()
	_ark.visible = _ark.text != ""


static func _num(n: int) -> String:
	var s: String = str(n)
	var out: String = ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return s + out


func _fmt_age(s: float) -> String:
	if s < 60.0:
		return "%d s" % int(s)
	if s < 3600.0:
		return tr("%d min") % int(s / 60.0)
	return "%.1f h" % (s / 3600.0)


func _build_mesh() -> void:
	if shell and _shell_snap:  # [orbE] the big hexes of the far shell, coloured from the snapshot
		var snap: Image = _shell_snap
		# [v2map] no gaps between the big hexes: at hand-held size they were sub-pixel and stippled
		_globe.mesh = SphereMapMesh.build(shell.coarse, func(c: int) -> Color: return SphereMapMesh.survey_color(SphereMapMesh.shares(snap, c)), 1.004, 1.0)
		if _holo_mat == null:
			_holo_mat = ShaderMaterial.new()
			_holo_mat.shader = preload("res://art/shaders/hologram.gdshader")
		_globe.mesh.surface_set_material(0, _holo_mat)
		if _grid_lines == null:
			_grid_lines = MeshInstance3D.new()
			_grid_lines.mesh = _lat_long_mesh()
			_pivot.add_child(_grid_lines)
		return
	var g: GeoSphere = planet.grid
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i: int in g.cell_count():
		var st: int = _snapshot[i]
		var col: Color = UITheme.globe_state_color(st, COLORS.get(st, Color.WHITE))
		if planet.city[i] >= 0 and st != PlanetData.State.WATER:
			col = col.lerp(Color(1.0, 0.85, 0.6), 0.3)
		if st == PlanetData.State.JUNK:
			col = col.darkened(0.25 * planet.junk[i])
		var c: Vector3 = g.centers[i] * (1.0 + (0.004 if st != PlanetData.State.WATER else -0.002))
		var corners: PackedVector3Array = g.corners(i)
		for k: int in corners.size():
			var a: Vector3 = corners[k] * (1.0 + (0.004 if st != PlanetData.State.WATER else -0.002))
			var b: Vector3 = corners[(k + 1) % corners.size()] * (1.0 + (0.004 if st != PlanetData.State.WATER else -0.002))
			# Slightly shrink toward the center so cell edges read as a grid.
			verts.append(c)
			verts.append(c.lerp(b, 0.9))
			verts.append(c.lerp(a, 0.9))
			cols.append(col)
			cols.append(col.darkened(0.25))
			cols.append(col.darkened(0.25))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if _holo_mat == null:
		_holo_mat = ShaderMaterial.new()
		_holo_mat.shader = preload("res://art/shaders/hologram.gdshader")
	m.surface_set_material(0, _holo_mat)
	_globe.mesh = m
	if _grid_lines == null:
		_grid_lines = MeshInstance3D.new()
		_grid_lines.mesh = _lat_long_mesh()
		_pivot.add_child(_grid_lines)


## Thin latitude/longitude lines just above the surface, like a holo projection grid.
func _lat_long_mesh() -> ArrayMesh:
	var v := PackedVector3Array()
	var r: float = 1.012
	for lat_i: int in range(-75, 90, 15):
		var lat: float = deg_to_rad(float(lat_i))
		for k: int in 96:
			var a0: float = TAU * k / 96.0
			var a1: float = TAU * (k + 1) / 96.0
			v.append(Vector3(cos(lat) * cos(a0), sin(lat), cos(lat) * sin(a0)) * r)
			v.append(Vector3(cos(lat) * cos(a1), sin(lat), cos(lat) * sin(a1)) * r)
	for lon_i: int in range(0, 360, 15):
		var lon: float = deg_to_rad(float(lon_i))
		for k: int in 48:
			var b0: float = -PI * 0.5 + PI * k / 48.0
			var b1: float = -PI * 0.5 + PI * (k + 1) / 48.0
			v.append(Vector3(cos(b0) * cos(lon), sin(b0), cos(b0) * sin(lon)) * r)
			v.append(Vector3(cos(b1) * cos(lon), sin(b1), cos(b1) * sin(lon)) * r)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(0.35, 0.8, 1.0, 1.0) * 0.25
	mat.disable_fog = true  # [v2map] glitch pass: the world fog greyed the hologram in hand-held mode
	mat.render_priority = 1  # after the globe (same centre: sorting flipped lines over / under it)
	m.surface_set_material(0, mat)
	return m


func _process(delta: float) -> void:
	if not is_open:
		return
	if not _drag:
		_yaw += delta * 0.08
	# [deck] Right stick spins and tilts the globe; the shoulders zoom (held, not per event).
	var look: Vector2 = Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look != Vector2.ZERO and not _flight_locked and _fly_t < 0.0:
		_yaw += look.x * delta * 2.2
		_pitch = clampf(_pitch + look.y * delta * 1.6, -1.4, 1.4)
	if _pad_held("zoom_in"):
		_zoom = maxf(1.4, _zoom * (1.0 - delta * 1.2))
	elif _pad_held("zoom_out"):
		_zoom = minf(6.0, _zoom * (1.0 + delta * 1.2))
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0, 0, _zoom)
	_cam.look_at(Vector3.ZERO)
	if _handheld:
		_place_handheld(delta)
	if _fly_t >= 0.0:
		_fly_t += delta / _fly_dur
		var t: float = clampf(_fly_t, 0.0, 1.0)
		var dir: Vector3 = _fly_from.slerp(_fly_to, t).normalized()
		_marker.position = dir * (1.02 + sin(t * PI) * 0.25)
		_yaw = lerp_angle(_yaw, -atan2(dir.x, dir.z), delta * 3.0)
		_pitch = lerpf(_pitch, asin(clampf(dir.y, -1.0, 1.0)), delta * 3.0)
		_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
		if _fly_t >= 1.0:
			_fly_t = -1.0
		return
	var pc: int = patch_cell_provider.call()
	if pc >= 0:
		_marker.position = (sphere_grid.centers[pc] if sphere_grid else planet.grid.centers[pc]) * 1.02  # [orbE]
		_marker.scale = Vector3.ONE * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.008))
		if sphere_grid:  # [orbE] "you are here": a gold pin standing on Lumi's big hex
			_here_pin(sphere_grid.centers[pc])
	if Engine.get_process_frames() % 30 == 0:
		_refresh_text()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = maxf(1.4, _zoom * 0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = minf(6.0, _zoom * 1.1)
	elif event is InputEventMouseMotion and _drag:
		var mm: InputEventMouseMotion = event
		_yaw += mm.relative.x * 0.006
		_pitch = clampf(_pitch + mm.relative.y * 0.006, -1.4, 1.4)
	elif event.is_action_pressed("open_globe") or event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _flight_locked or _fly_t >= 0.0:
			get_viewport().set_input_as_handled()
			return
		close_view()
		get_viewport().set_input_as_handled()
	# (Controller spin / zoom: polled in _process.)


func _place_handheld(delta: float) -> void:
	var model: PatchModel = holder.get("model")
	# [orbE] Local up: on a round planet "up" is the radial direction under Lumi.
	var up: Vector3 = (holder.call("up") as Vector3) if holder.has_method("up") else Vector3.UP
	var hand: Vector3 = model.hand_point() if model else holder.global_position + up * 1.0
	var r: float = 0.3
	var side: Vector3 = (model.global_basis.x if model else holder.global_basis.x).normalized()
	var fwd0: Vector3 = -(model.global_basis.z if model else holder.global_basis.z)
	fwd0 -= up * fwd0.dot(up)
	fwd0 = fwd0.normalized()
	# [v2map] Glitch pass: the globe floats in front of Lumi at eye height and the camera looks over
	# his right shoulder at it. (It used to sit at his hand with the camera in front of him, so his
	# big head covered most of the globe.)
	var center: Vector3 = holder.global_position + up * 1.25 + fwd0 * 0.75 + side * 0.05
	_anchor.global_position = center
	if up != Vector3.UP:
		_anchor.global_basis = SphereMath.basis_from_up_fwd(up, fwd0).scaled(_anchor.scale)
	# Beam: from the claw to the globe's underside.
	var bottom: Vector3 = center - up * r * 0.8
	var axis: Vector3 = bottom - hand
	var h: float = maxf(axis.length(), 0.01)
	var y: Vector3 = axis / h
	var x: Vector3 = y.cross(fwd0 if absf(y.dot(fwd0)) < 0.95 else side).normalized()
	var z: Vector3 = x.cross(y).normalized()
	_beam.global_transform = Transform3D(Basis(x * r * 0.9, y * h, z * r * 0.9), hand + axis * 0.5)
	var right: Vector3 = fwd0.cross(up).normalized()
	var dist: float = remap(_zoom, 1.4, 6.0, 1.3, 3.4)
	var want: Vector3 = center - fwd0 * dist + right * dist * 0.3 + up * dist * 0.38
	_world_cam.global_position = _world_cam.global_position.lerp(want, clampf(delta * 4.0, 0.0, 1.0))
	# Aim a little left of the globe so it sits right of centre, clear of the survey card.
	_world_cam.look_at(center - right * dist * 0.2, up)


var _pin: MeshInstance3D


func _here_pin(dir: Vector3) -> void:
	if _pin == null:
		_pin = MeshInstance3D.new()
		_pin.name = "YouAreHere"
		_pin.mesh = ProcMesh.cyl(0.006, 0.006, 1.0, 6)
		_pin.material_override = Mats.lamp(Color(1.0, 0.85, 0.45), 2.2)
		_pivot.add_child(_pin)
	var up: Vector3 = dir.normalized()
	var h: float = 0.14
	_pin.transform = Transform3D(SphereMath.basis_from_up_fwd(up, up.cross(Vector3.RIGHT if absf(up.x) < 0.9 else Vector3.FORWARD).normalized()).scaled_local(Vector3(1.0, h, 1.0)), up * (1.004 + h * 0.5))
	_marker.position = up * (1.004 + h)
	_marker.scale = Vector3.ONE * (1.4 + 0.35 * sin(Time.get_ticks_msec() * 0.008))


func focus_on(cell: int) -> void:
	var c: Vector3 = sphere_grid.centers[cell] if sphere_grid else planet.grid.centers[cell]  # [orbE]
	_yaw = -atan2(c.x, c.z)
	_pitch = asin(clampf(c.y, -1.0, 1.0))


## Legend / bar colour for a cell state (colour-blind palette aware).
func _legend_col(state: int) -> Color:
	return UITheme.globe_state_color(state, COLORS.get(state, Color.WHITE))
