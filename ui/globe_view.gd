class_name GlobeView
extends CanvasLayer
## Holographic survey map of the whole planet. Every hex is drawn colored by its surveyed state:
## junk, clean, planted, growing, restored, water; cities outlined, hubs and Patch marked.
## The map is a snapshot: it shows when it was surveyed and can be refreshed for a fee
## (later: survey drone upgrades for periodic updates, then a live layer).

signal closed

const COLORS: Dictionary = {
	PlanetData.State.JUNK: Color(0.75, 0.38, 0.22),
	PlanetData.State.CLEAN: Color(0.95, 0.82, 0.5),
	PlanetData.State.PLANTED: Color(0.55, 0.85, 0.35),
	PlanetData.State.GROWING: Color(0.3, 0.8, 0.45),
	PlanetData.State.RESTORED: Color(0.2, 0.95, 0.55),
	PlanetData.State.WATER: Color(0.15, 0.4, 0.8),
}

var planet: PlanetData
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
var _stats: Label
var _age: Label
var _resurvey: Button
var _drag: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.3
var _zoom: float = 3.2


func _ready() -> void:
	layer = 18
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var svc := SubViewportContainer.new()
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
	_marker.mesh = ProcMesh.sphere(0.02, 10, 5)
	_marker.material_override = Mats.lamp(Color(1.0, 0.75, 0.25), 6.0)
	_pivot.add_child(_marker)
	_cam = Camera3D.new()
	_cam.fov = 40.0
	_vp.add_child(_cam)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.glow_enabled = true
	env.glow_intensity = 0.8
	env.glow_bloom = 0.15
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	# Side panel.
	var mc := MarginContainer.new()
	mc.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	for side: String in ["margin_left", "margin_top"]:
		mc.add_theme_constant_override(side, 36)
	_root.add_child(mc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	mc.add_child(vb)
	vb.add_child(UITheme.label("S U R V E Y   M A P", 13, UITheme.MUTED))
	vb.add_child(UITheme.label("VERDANCE", 30, UITheme.CREAM))
	_age = UITheme.label("", 14, UITheme.GOLD)
	vb.add_child(_age)
	_stats = UITheme.label("", 15, UITheme.CREAM)
	vb.add_child(_stats)
	_resurvey = Button.new()
	_resurvey.custom_minimum_size = Vector2(240, 44)
	_resurvey.pressed.connect(_on_resurvey)
	vb.add_child(_resurvey)
	var close := Button.new()
	close.text = "Close   M"
	close.custom_minimum_size = Vector2(240, 40)
	close.pressed.connect(close_view)
	vb.add_child(close)
	vb.add_child(UITheme.label("drag to spin  ·  wheel to zoom", 12, UITheme.MUTED))
	_root.visible = false


func survey_cost() -> BigNum:
	return BigNum.from_float(40.0 + 3.0 * float(planet.restored_count()))


## Takes a fresh snapshot of the planet state (free on first use).
func survey() -> void:
	_snapshot = planet.state.duplicate()
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
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	_refresh_text()


func close_view() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


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
	for s: int in _snapshot:
		counts[s] = int(counts.get(s, 0)) + 1
		if s != PlanetData.State.WATER:
			land += 1
	var pct := func(k: int) -> String: return "%.3f%%" % (100.0 * float(counts.get(k, 0)) / maxf(land, 1))
	_stats.text = "Hexes   %d  (%d land)\nJunk   %s\nClean   %s\nPlanted   %s\nGrowing   %s\nRestored   %s\nCities   %d" % [
		_snapshot.size(), land, pct.call(PlanetData.State.JUNK), pct.call(PlanetData.State.CLEAN),
		pct.call(PlanetData.State.PLANTED), pct.call(PlanetData.State.GROWING), pct.call(PlanetData.State.RESTORED), planet.cities.size()]
	var age: float = float(GameState.stats.get("time_played", 0.0)) - _snapshot_time
	_age.text = "surveyed %s ago%s" % [_fmt_age(age), "   ·   OUTDATED" if age > 600.0 else ""]
	_resurvey.text = "Re-survey   %s cubes" % Settings.fmt(survey_cost())


func _fmt_age(s: float) -> String:
	if s < 60.0:
		return "%d s" % int(s)
	if s < 3600.0:
		return "%d min" % int(s / 60.0)
	return "%.1f h" % (s / 3600.0)


func _build_mesh() -> void:
	var g: GeoSphere = planet.grid
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	for i: int in g.cell_count():
		var st: int = _snapshot[i]
		var col: Color = COLORS.get(st, Color.WHITE)
		if planet.city[i] >= 0 and st != PlanetData.State.WATER:
			col = col.lerp(Color(0.75, 0.78, 0.82), 0.45)
		if st == PlanetData.State.JUNK:
			col = col.darkened(0.35 * planet.junk[i])
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
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission = Color(0.05, 0.12, 0.12)
	m.surface_set_material(0, mat)
	_globe.mesh = m


func _process(delta: float) -> void:
	if not is_open:
		return
	if not _drag:
		_yaw += delta * 0.08
	_pivot.rotation = Vector3(_pitch, _yaw, 0.0)
	_cam.position = Vector3(0, 0, _zoom)
	_cam.look_at(Vector3.ZERO)
	var pc: int = patch_cell_provider.call()
	if pc >= 0:
		_marker.position = planet.grid.centers[pc] * 1.02
		_marker.scale = Vector3.ONE * (1.0 + 0.3 * sin(Time.get_ticks_msec() * 0.008))
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
		close_view()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadMotion:
		var jm: InputEventJoypadMotion = event
		if jm.axis == JOY_AXIS_RIGHT_X:
			_yaw += jm.axis_value * 0.05


func focus_on(cell: int) -> void:
	var c: Vector3 = planet.grid.centers[cell]
	_yaw = -atan2(c.x, c.z)
	_pitch = asin(clampf(c.y, -1.0, 1.0))
