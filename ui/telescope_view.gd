class_name TelescopeView
extends CanvasLayer
## [scope] What you see through the Telescope (automation/telescope.gd).
##   System: the two suns and the planets on their orbits (data/solar_system.json when it exists,
##   else data/telescope.json planets_default). Worlds you've visited can be picked; the one you
##   stand on is marked. A ui/system_map.gd with a `planet_picked` signal is used instead if present.
##   Remote: the picked world's base district (ui/remote_district.gd) from its saved state, with
##   its crew at work, framed like an eyepiece (art/shaders/telescope_lens.gdshader), a reticle and
##   readouts. Send a care package from here. Holding a Ledger wreck or a deer in the reticle
##   unlocks a Codex entry.
## Pad: D-pad moves focus, A presses, right stick orbits / zooms, B (Esc) backs out.

signal closed

const SOLAR_PATH: String = "res://data/solar_system.json"
const LINE := Color(0.78, 0.92, 1.0, 0.55)

var world: Node
var is_open: bool = false
var mode: String = "system"
var entries: Array[Dictionary] = []
var picked: int = -1
var district: RemoteDistrict

var _root: Control
var _vp: SubViewport
var _tex: TextureRect
var _lens: ShaderMaterial
var _cam: Camera3D
var _env: WorldEnvironment
var _sun_a: DirectionalLight3D
var _sun_b: DirectionalLight3D
var _orrery: Node3D
var _planet_nodes: Array[Node3D] = []
var _sel_ring: MeshInstance3D
var _reticle: Control
var _title: Label
var _left: Label
var _right: Label
var _hint: Label
var _bar: HBoxContainer
var _care_btn: Button
var _first: Control
var _t: float = 0.0
var _yaw: float = 0.6
var _pitch: float = 0.62
var _dist: float = 62.0
var _focus := Vector3.ZERO
var _focus_goal := Vector3.ZERO
var _look_i: int = 0
var _spot_t: Dictionary = {}
var _drag: bool = false


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.visible = false
	add_child(_root)


# --- Open / close ------------------------------------------------------------------------------

func open_view(pick: int = -1) -> void:
	if is_open:
		return
	is_open = true
	_build()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)
	get_tree().paused = true
	get_tree().root.disable_3d = true  # the district behind the eyepiece needn't render
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if world and world.get("hud") != null:
		world.hud.visible = false
	EventBus.ui_modal_changed.emit(true)
	if Codex.unlock("sightings:first_light"):
		EventBus.toast.emit(tr("Codex: First Light"), "info")
	_show_system()
	if pick >= 0:
		var vis: Array[int] = []
		for i: int in entries.size():
			if bool(entries[i]["visited"]):
				vis.append(i)
		if not vis.is_empty():
			_zoom_to(vis[clampi(pick, 0, vis.size() - 1)], true)
	if DevHooks.has("scope-debug"):
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			print("[scope] open mode=%s entries=%d picked=%d root_vis=%s alpha=%.2f vp=%s bots=%d" % [mode, entries.size(), picked, str(_root.visible), _root.modulate.a, str(_vp.size), district.bots.size() if district else -1]))


func close_view() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	for c: Node in _root.get_children():
		c.queue_free()
	district = null
	get_tree().root.disable_3d = false
	get_tree().paused = false
	if world and world.get("hud") != null:
		world.hud.visible = true
	EventBus.ui_modal_changed.emit(false)
	closed.emit()


# --- Data --------------------------------------------------------------------------------------

static func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return d if d is Dictionary else {}


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	if v is String and (v as String).begins_with("#"):
		return Color(str(v))
	return fallback


## The binary pair (star_a warm primary, star_b cool orange companion), from the solar system file.
static func stars() -> Dictionary:
	var d: Dictionary = _read_json(SOLAR_PATH)
	var a: Dictionary = d.get("star_a", {}) if d.get("star_a") is Dictionary else {}
	var b: Dictionary = d.get("star_b", {}) if d.get("star_b") is Dictionary else {}
	return {"a": {"color": _col(a.get("color"), Color(1.0, 0.95, 0.85)), "size": float(a.get("size", a.get("base_size", 1.0))), "energy": float(a.get("energy", a.get("base_intensity", 1.0)))},
		"b": {"color": _col(b.get("color"), Color(1.0, 0.62, 0.38)), "size": float(b.get("size", b.get("base_size", 0.55))), "energy": float(b.get("energy", b.get("base_intensity", 0.25)))}}


## Planet list: solar system file (or defaults), matched to profile worlds; unmatched worlds added.
func _gather() -> void:
	entries.clear()
	var src: Array = []
	var sd: Dictionary = _read_json(SOLAR_PATH)
	var pl: Variant = sd.get("planets", null)
	if pl is Array:
		src = pl
	elif pl is Dictionary:
		for k: Variant in pl:
			var e: Dictionary = ((pl as Dictionary)[k] as Dictionary).duplicate() if (pl as Dictionary)[k] is Dictionary else {}
			e["id"] = str(e.get("id", k))
			src.append(e)
	if src.is_empty():
		src = RemoteProgress.cfg().get("planets_default", [])
	var defaults: Dictionary = {}
	for e: Dictionary in RemoteProgress.cfg().get("planets_default", []):
		defaults[str(e["id"])] = e
	for p: Variant in src:
		if not (p is Dictionary):
			continue
		var pd: Dictionary = p
		var id: String = str(pd.get("id", pd.get("name", "")).to_lower())
		var dflt: Dictionary = defaults.get(id, {})
		entries.append({"id": id, "name": str(pd.get("name", dflt.get("name", id.capitalize()))), "orbit_au": float(pd.get("orbit_au", dflt.get("orbit_au", 1.0 + entries.size() * 0.8))),
			"color": _col(pd.get("color", dflt.get("color")), Color(0.6, 0.6, 0.62)), "world": {}, "visited": false, "here": false})
	var worlds: Array = CradleMode.worlds().duplicate()
	if not RemoteProgress.sample.is_empty():
		worlds.append(RemoteProgress.sample["world"])
	var visited: Array = RemoteProgress.visited_worlds()
	for w: Dictionary in worlds:
		var key: String = str(w.get("planet_id", w.get("planet", w.get("id", "")))).to_lower()
		var nm: String = str(w.get("name", "")).to_lower()
		var hit: int = -1
		for i: int in entries.size():
			if entries[i]["world"].is_empty() and (entries[i]["id"] == key or entries[i]["id"] == nm or str(entries[i]["name"]).to_lower() == nm):
				hit = i
				break
		if hit < 0:
			var last: float = 0.0
			for e: Dictionary in entries:
				last = maxf(last, float(e["orbit_au"]))
			var pc: Array = ArkBridge.PLANET_COLORS.get(str(w.get("type", "")), [Color(0.55, 0.5, 0.45)])
			entries.append({"id": nm, "name": str(w.get("name", "?")), "orbit_au": last + 0.9, "color": pc[0], "world": {}, "visited": false, "here": false})
			hit = entries.size() - 1
		entries[hit]["world"] = w
		entries[hit]["here"] = int(w.get("index", -1)) == CradleMode.current_index() and w != RemoteProgress.sample.get("world", {})
		entries[hit]["visited"] = visited.has(w)


# --- Build ---------------------------------------------------------------------------------------

func _build() -> void:
	for c: Node in _root.get_children():
		c.queue_free()
	_planet_nodes.clear()
	_spot_t.clear()
	_gather()
	var size: Vector2 = _root.get_viewport_rect().size
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.size = Vector2i(maxi(int(size.x), 320), maxi(int(size.y), 180))
	_vp.msaa_3d = Viewport.MSAA_2X if Settings.quality >= 2 else Viewport.MSAA_DISABLED
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_root.add_child(_vp)
	_tex = TextureRect.new()
	_tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tex.texture = _vp.get_texture()
	_tex.stretch_mode = TextureRect.STRETCH_SCALE
	_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_lens = ShaderMaterial.new()
	_lens.shader = preload("res://art/shaders/telescope_lens.gdshader")
	_tex.material = _lens
	_tex.mouse_filter = Control.MOUSE_FILTER_PASS
	_tex.gui_input.connect(_on_view_input)
	_root.add_child(_tex)
	_env = WorldEnvironment.new()
	_env.environment = Environment.new()
	_vp.add_child(_env)
	_cam = Camera3D.new()
	_cam.current = true
	_vp.add_child(_cam)
	_sun_a = DirectionalLight3D.new()
	_sun_b = DirectionalLight3D.new()
	_vp.add_child(_sun_a)
	_vp.add_child(_sun_b)
	_reticle = Control.new()
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reticle.draw.connect(_draw_reticle)
	_root.add_child(_reticle)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 44)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_child(margin)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(col)
	_title = UITheme.label("", 15, Color(0.86, 0.95, 1.0, 0.9))
	col.add_child(_title)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	_left = UITheme.label("", 14, Color(0.82, 0.92, 0.98, 0.85))
	top.add_child(_left)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(sp)
	_right = UITheme.label("", 14, Color(0.82, 0.92, 0.98, 0.85))
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_right)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(fill)
	_hint = UITheme.label("", 13, UITheme.MUTED)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_hint)
	_bar = HBoxContainer.new()
	_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bar.add_theme_constant_override("separation", 10)
	col.add_child(_bar)


func _button(text: String, cb: Callable, w: float = 150.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, 40)
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(cb)
	_bar.add_child(b)
	return b


func _clear_scene() -> void:
	for n: Node in _vp.get_children():
		if n != _env and n != _cam and n != _sun_a and n != _sun_b:
			n.queue_free()
	for b: Node in _bar.get_children():
		b.queue_free()
	_planet_nodes.clear()
	_orrery = null
	_sel_ring = null  # [camp] freed with the orrery: never touch a stale ring
	district = null
	_first = null


static func _glow_mat(c: Color, e: float) -> StandardMaterial3D:
	return Telescope._glow_mat(c, e)


static func _halo_tex() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0.55))
	g.set_color(1, Color(1, 1, 1, 0.0))
	g.add_point(0.25, Color(1, 1, 1, 0.16))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 128
	t.height = 128
	return t


func _halo(parent: Node3D, c: Color, size: float) -> void:
	var s := Sprite3D.new()
	s.texture = _halo_tex()
	s.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	s.modulate = Color(c.r, c.g, c.b, 0.5)
	s.pixel_size = size / 128.0
	s.shaded = false
	s.transparent = true
	s.no_depth_test = false
	parent.add_child(s)


# --- System view (orrery) -----------------------------------------------------------------------

static func orbit_r(au: float) -> float:
	return 7.0 + au * 9.0


func _show_system() -> void:
	mode = "system"
	_clear_scene()
	_lens.set_shader_parameter("vignette", 0.5)
	var e: Environment = _env.environment
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.01, 0.016)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.18, 0.2, 0.24)
	e.ambient_light_energy = 0.5
	e.glow_enabled = true
	e.glow_intensity = 0.35
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.1
	e.fog_enabled = false
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_sun_a.visible = false
	_sun_b.visible = false
	# The guarded hook: a full system map from the solar-system work, if it has landed.
	var custom: bool = false
	if ResourceLoader.exists("res://ui/system_map.gd"):
		var scr: Variant = load("res://ui/system_map.gd")
		if scr is GDScript and (scr as GDScript).can_instantiate():
			var inst: Object = (scr as GDScript).new()
			if inst is Node3D and inst.has_signal("planet_picked"):
				_vp.add_child(inst as Node3D)
				inst.connect("planet_picked", _on_map_picked)
				custom = true
			elif inst is Node:
				(inst as Node).queue_free()
	_orrery = Node3D.new()
	_vp.add_child(_orrery)
	if not custom:
		_build_orrery()
	_cam.fov = 34.0
	_dist = 122.0
	_title.text = tr("TELESCOPE  ·  SYSTEM VIEW")
	var nv: int = 0
	for i: int in entries.size():
		var en: Dictionary = entries[i]
		var label: String = tr(str(en["name"]))
		if bool(en["here"]):
			label = tr("%s (here)") % label
		elif not bool(en["visited"]):
			label = tr("%s  ·  not visited") % label
		var b := _button(label, _on_pick.bind(i), 170.0)
		b.focus_entered.connect(func() -> void: _select(i))
		if bool(en["visited"]):
			nv += 1
			if _first == null:
				_first = b
	_button(tr("Close"), close_view, 120.0)
	if _first == null and _bar.get_child_count() > 0:
		_first = _bar.get_child(0) as Control
	_left.text = tr("Two suns, one system.\nWorlds visited: %d") % nv
	_right.text = ""
	_hint.text = tr("Pick a world you've visited to watch its crew. The one you stand on can't see itself.") if nv > 0 else tr("No other world visited yet. Seed or visit another world from the Ark Bridge, then come back.")
	if _first:
		_first.call_deferred("grab_focus")


func _build_orrery() -> void:
	var st: Dictionary = stars()
	var a: Dictionary = st["a"]
	var b: Dictionary = st["b"]
	var pair := Node3D.new()
	pair.name = "Pair"
	_orrery.add_child(pair)
	var sun_nodes: Array[Node3D] = []  # [globes] the globes are lit from these
	for k: int in 2:
		var s: Dictionary = a if k == 0 else b
		var n := MeshInstance3D.new()
		n.mesh = ProcMesh.sphere(1.9 * float(s["size"]), 24, 12)
		n.material_override = _glow_mat(s["color"], 2.2 if k == 0 else 1.6)
		n.position = Vector3(-1.4, 0, 0) if k == 0 else Vector3(3.6, 0, 0)
		pair.add_child(n)
		sun_nodes.append(n)
		_halo(n, s["color"], 11.0 * float(s["size"]))
		var l := OmniLight3D.new()
		l.light_color = s["color"]
		l.light_energy = 2.4 * clampf(float(s["energy"]) * (1.0 if k == 0 else 2.4), 0.2, 3.0)
		l.omni_range = 140.0
		l.omni_attenuation = 0.6
		n.add_child(l)
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.16)
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	for i: int in entries.size():
		var en: Dictionary = entries[i]
		var r: float = orbit_r(float(en["orbit_au"]))
		var ring := MeshInstance3D.new()
		ring.mesh = ProcMesh.torus(r - 0.05, r + 0.05, 128, 3)
		ring.material_override = ring_mat
		_orrery.add_child(ring)
		var pivot := Node3D.new()
		pivot.rotation.y = float(i) * 2.1 + 0.4
		pivot.set_meta("speed", 0.05 / pow(maxf(float(en["orbit_au"]), 0.2), 1.5))
		_orrery.add_child(pivot)
		# [globes] Procedural planet globes (relief, clouds, rim, rings) lit by the two suns.
		var pr: float = 1.0 + 0.25 * float(i % 3)
		var p := PlanetGlobe.new()
		p.radius = pr
		p.max_lod = 2 if Settings.quality >= 2 else 1
		p.position = Vector3(r, 0, 0)
		pivot.add_child(p)
		p.setup(str(en["id"]), _globe_restoration(en), en["color"])
		if sun_nodes.size() == 2:
			p.track_suns(sun_nodes[0], sun_nodes[1])
		var lab := Label3D.new()
		lab.text = tr(str(en["name"])).to_upper()
		lab.font_size = 40
		lab.pixel_size = 0.03
		lab.outline_size = 0
		lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lab.modulate = Color(0.85, 0.93, 1.0, 0.85 if bool(en["visited"]) or bool(en["here"]) else 0.4)
		lab.position = Vector3(0, pr + 1.4, 0)
		p.add_child(lab)
		if bool(en["here"]):
			var mark := MeshInstance3D.new()
			mark.mesh = ProcMesh.torus(pr + 0.35, pr + 0.45, 32, 3)
			mark.material_override = _glow_mat(Color(1.0, 0.75, 0.35), 1.2)
			p.add_child(mark)
		_planet_nodes.append(p)
	_sel_ring = MeshInstance3D.new()
	_sel_ring.mesh = ProcMesh.torus(2.0, 2.1, 48, 3)
	_sel_ring.material_override = _glow_mat(Color(0.6, 0.9, 1.0), 1.6)
	_orrery.add_child(_sel_ring)
	_sel_ring.visible = false


## [globes] How restored a world's globe looks: the live planet for the one you stand on, else
## its saved district share (a district is only part of the planet, so it counts half).
func _globe_restoration(en: Dictionary) -> float:
	if bool(en.get("here", false)) and world and world.get("planet") != null and world.planet.has_method("restored_fraction"):
		return clampf(float(world.planet.restored_fraction()), 0.0, 1.0)
	if bool(en.get("visited", false)):
		return clampf(float(RemoteProgress.snapshot(en["world"]).get("share", 0.0)) * 0.5, 0.0, 1.0)
	return 0.0


func _select(i: int) -> void:
	picked = i
	if mode != "system" or i < 0 or i >= entries.size():
		return
	var en: Dictionary = entries[i]
	var w: Dictionary = en["world"]
	var hk: int = Homeward.planet_index(str(en.get("id", "")))  # [sysmap2] spotting reveals the next planet on the map
	if hk > 0 and Homeward.spot(hk):
		EventBus.toast.emit(tr("Spotted %s: it now shows on the system map") % Homeward.planet_name(hk), "info")
	if bool(en["visited"]):
		var snap: Dictionary = RemoteProgress.snapshot(w)
		_right.text = tr("%s\nDistrict %d%% clean · %d robots\nLast visit %s") % [tr(str(en["name"])), int(round(float(snap.get("share", 0.0)) * 100.0)), (snap.get("robots", []) as Array).size(), ago_text(float(snap.get("saved_unix", 0.0)))]
	elif bool(en["here"]):
		_right.text = tr("%s\nYou are here.") % tr(str(en["name"]))
	else:
		# [sysmap2] no "not visited": a planet past the next one in order is still too faint to chart
		_right.text = tr("An unknown world.\nToo faint to chart yet.") if hk > 0 and not Homeward.discovered(hk) else tr("%s\nCharted. No landing yet.") % tr(str(en["name"]))


func _on_pick(i: int) -> void:
	var en: Dictionary = entries[i]
	if not bool(en["visited"]):
		Audio.play("buzz", 1.2, -10.0)
		_hint.text = tr("You stand on %s.") % tr(str(en["name"])) if bool(en["here"]) else tr("%s: nobody of yours down there yet.") % tr(str(en["name"]))
		return
	_zoom_to(i)


func _on_map_picked(id: Variant) -> void:
	for i: int in entries.size():
		if str(entries[i]["id"]) == str(id) or int(entries[i]["world"].get("index", -99)) == int(id if (id is int or id is float) else -98):
			_on_pick(i)
			return


static func ago_text(unix: float) -> String:
	if unix <= 0.0:
		return TranslationServer.translate("unknown")
	var s: float = maxf(0.0, Time.get_unix_time_from_system() - unix)
	if s < 3600.0:
		return TranslationServer.translate("%d min ago") % int(s / 60.0)
	if s < 86400.0 * 2.0:
		return TranslationServer.translate("%.1f h ago") % (s / 3600.0)
	return TranslationServer.translate("%d days ago") % int(s / 86400.0)


# --- Remote view --------------------------------------------------------------------------------

func _zoom_to(i: int, instant: bool = false) -> void:
	picked = i
	if instant:
		_show_remote(i)
		return
	Audio.play("whoosh", 1.2, -10.0)
	var tw := create_tween()
	tw.tween_method(func(v: float) -> void: _lens.set_shader_parameter("fade", v), 0.0, 1.0, 0.35)
	tw.tween_callback(_show_remote.bind(i))
	tw.tween_method(func(v: float) -> void: _lens.set_shader_parameter("fade", v), 1.0, 0.0, 0.5)


func _suns_for(planet_id: String, au: float) -> Dictionary:
	# The shared helper from the solar-system work, if it has landed.
	for gc: Dictionary in ProjectSettings.get_global_class_list():
		if str(gc.get("class", "")) == "SolarSystem":
			var scr: Variant = load(str(gc["path"]))
			if scr is GDScript:
				for m: Dictionary in (scr as GDScript).get_script_method_list():
					if str(m.get("name", "")) == "suns_for":
						var r: Variant = (scr as GDScript).call("suns_for", planet_id)
						if r is Dictionary and (r as Dictionary).has("a"):
							return r
			break
	var st: Dictionary = stars()
	var k: float = clampf(1.0 / pow(maxf(au, 0.3), 0.6), 0.35, 1.5)
	var da: Vector3 = Vector3(0.45, -0.72, -0.53).normalized()
	var db: Vector3 = da.rotated(Vector3.UP, deg_to_rad(14.0))
	return {"a": {"dir": da, "color": st["a"]["color"], "size": float(st["a"]["size"]) * k, "energy": float(st["a"]["energy"]) * k},
		"b": {"dir": db, "color": st["b"]["color"], "size": float(st["b"]["size"]) * k, "energy": float(st["b"]["energy"]) * k}}


func _show_remote(i: int) -> void:
	mode = "remote"
	_clear_scene()
	_lens.set_shader_parameter("vignette", 0.6)
	var en: Dictionary = entries[i]
	var w: Dictionary = en["world"]
	var snap: Dictionary = RemoteProgress.snapshot(w)
	district = RemoteDistrict.new()
	_vp.add_child(district)
	district.setup(snap, w)
	district.boost = RemoteProgress.care_cfg().get("boost_mult", 2.0) if RemoteProgress.boost_left(w) > 0.0 else 1.0
	var pal: Dictionary = district.palette
	var e: Environment = _env.environment
	var sky := Sky.new()
	var psm := ProceduralSkyMaterial.new()
	psm.sky_top_color = (pal["sky"] as Color).darkened(0.25)
	psm.sky_horizon_color = (pal["sky"] as Color).lightened(0.25)
	psm.ground_horizon_color = pal["far"]
	psm.ground_bottom_color = (pal["far"] as Color).darkened(0.4)
	psm.sun_angle_max = 8.0
	sky.sky_material = psm
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.7
	e.glow_enabled = true
	e.glow_intensity = 0.25
	e.glow_bloom = 0.01
	e.glow_hdr_threshold = 1.15
	e.fog_enabled = true
	e.fog_light_color = pal["fog"]
	e.fog_density = 0.0045
	e.fog_aerial_perspective = 0.4
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var suns: Dictionary = _suns_for(str(en["id"]), float(en["orbit_au"]))
	for k: int in 2:
		var s: Dictionary = suns["a" if k == 0 else "b"]
		var l: DirectionalLight3D = _sun_a if k == 0 else _sun_b
		l.visible = true
		var dir: Vector3 = s.get("dir", Vector3(0.4, -0.7, -0.5))
		if dir.length() < 0.01:
			dir = Vector3(0.4, -0.7, -0.5)
		l.basis = Basis.looking_at(dir.normalized(), Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.FORWARD)
		l.light_color = s.get("color", Color.WHITE)
		l.light_energy = (1.15 if k == 0 else 0.55) * clampf(float(s.get("energy", 1.0)) * (1.0 if k == 0 else 3.0), 0.15, 2.0)
		l.light_angular_distance = 0.6 * float(s.get("size", 1.0))
		l.shadow_enabled = k == 0
		l.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	_focus = _front_point()
	_focus_goal = _focus
	_look_i = 1
	_dist = 62.0
	_cam.fov = 24.0
	_title.text = tr("TELESCOPE  ·  %s") % tr(str(en["name"])).to_upper()
	_button(tr("◀ Look"), func() -> void: _cycle_look(-1), 120.0)
	_first = _button(tr("Look ▶"), func() -> void: _cycle_look(1), 120.0)
	_care_btn = _button("", _on_care, 300.0)
	_button(tr("Back to system"), _show_system, 170.0)
	_hint.text = tr("Right stick or drag: turn and zoom.  Hold something in the reticle to log it.")
	_refresh_remote()
	if _first:
		_first.call_deferred("grab_focus")
	if DevHooks.has("scope-look"):
		_look_i = int(DevHooks.get_f("scope-look", 1.0)) - 1
		_cycle_look(1)
		_focus = _focus_goal


func _front_point() -> Vector3:
	if district == null:
		return Vector3.ZERO
	var j: Array[int] = district._junk_order()
	if j.is_empty():
		return Vector3(0, 0, 4)
	return district.center_of(j[0]) * 0.7


func _look_points() -> Array[Vector3]:
	var pts: Array[Vector3] = [Vector3(0, 0, 0), _front_point()]
	if district:
		for i: int in district.state.size():
			if district.state[i] == 2:
				pts.append(district.center_of(i))
				break
		for k: String in district.spot_nodes:
			pts.append((district.spot_nodes[k] as Node3D).position)
	return pts


func _cycle_look(d: int) -> void:
	var pts: Array[Vector3] = _look_points()
	_look_i = posmod(_look_i + d, pts.size())
	_focus_goal = pts[_look_i]
	Audio.play("click", 1.2, -12.0)


func _refresh_remote() -> void:
	if district == null:
		return
	var en: Dictionary = entries[picked]
	var w: Dictionary = en["world"]
	var snap: Dictionary = district.snap
	var pend: Dictionary = RemoteProgress.pending(snap, w)
	var cubes: float = float(pend["cubes"]) + float(pend["waiting_value"])
	_left.text = tr("PLANET     %s\nDISTRICT   %.2f%% clean\nROBOTS     %d active of %d\nLAST VISIT %s") % [tr(str(en["name"])), district.district_share() * 100.0,
		district.active_bots(), district.bots.size(), ago_text(float(snap.get("saved_unix", 0.0)))]
	var bl: float = RemoteProgress.boost_left(w)
	var boost_line: String = (tr("\nCARE PACKAGE  %d:%02d left") % [int(bl / 60.0), int(bl) % 60]) if bl > 0.0 else ""
	_right.text = tr("Remote pace (%d%% of offline)\nWaiting for you: %s cubes%s") % [int(RemoteProgress.factor() * 100.0), Settings.fmt(BigNum.from_float(cubes)), boost_line]
	district.boost = float(RemoteProgress.care_cfg().get("boost_mult", 2.0)) if bl > 0.0 else 1.0
	var why: String = RemoteProgress.care_block_reason(w)
	_care_btn.text = tr("Send a care package (%s cubes)") % Settings.fmt(BigNum.from_float(RemoteProgress.care_cost()))
	_care_btn.tooltip_text = why


func _on_care() -> void:
	var w: Dictionary = entries[picked]["world"]
	var why: String = RemoteProgress.care_block_reason(w)
	if why != "":
		Audio.play("buzz", 1.2, -8.0)
		_hint.text = why
		return
	if RemoteProgress.send_care(w):
		Audio.play("buy", 1.1, -4.0)
		var c: Dictionary = RemoteProgress.care_cfg()
		_hint.text = tr("Care package away. The crew on %s works at double speed for %d minutes.") % [tr(str(entries[picked]["name"])), int(float(c.get("boost_s", 300.0)) / 60.0)]
		if district:
			var pod := MeshInstance3D.new()
			pod.mesh = ProcMesh.capsule(0.35, 1.0)
			pod.material_override = Telescope._mat(Color(0.92, 0.93, 0.94), 0.3, 0.0, 0.5)
			pod.position = Vector3(1.5, 40.0, 1.5)
			district.add_child(pod)
			var trail := MeshInstance3D.new()
			trail.mesh = ProcMesh.cyl(0.04, 0.04, 6.0, 6)
			trail.material_override = _glow_mat(Color(0.6, 0.9, 1.0), 1.4)
			trail.position = Vector3(0, 3.5, 0)
			pod.add_child(trail)
			var tw := pod.create_tween()
			tw.tween_property(pod, "position:y", 0.5, 1.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tw.tween_callback(func() -> void: trail.visible = false)
	_refresh_remote()


# --- Frame ---------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open or _cam == null:
		return
	_t += delta
	var rx: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry: float = Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	if absf(rx) > 0.2:
		_yaw -= rx * delta * 1.2
	if absf(ry) > 0.2:
		_dist += ry * delta * 30.0
	if mode == "system":
		if _orrery:
			for n: Node in _orrery.get_children():
				if n.has_meta("speed"):
					(n as Node3D).rotation.y += float(n.get_meta("speed")) * delta
			var pair: Node3D = _orrery.get_node_or_null("Pair")
			if pair:
				pair.rotation.y += delta * 0.4
		_yaw += delta * 0.02
		_pitch = 0.95
		var goal := Vector3.ZERO
		if picked >= 0 and picked < _planet_nodes.size() and _sel_ring:
			var pn: Node3D = _planet_nodes[picked]
			_sel_ring.visible = true
			_sel_ring.global_position = pn.global_position
			goal = pn.global_position * 0.25
		_focus = _focus.lerp(goal, clampf(delta * 2.0, 0.0, 1.0))
	else:
		_yaw += delta * 0.025
		_pitch = 0.62
		_focus = _focus.lerp(_focus_goal, clampf(delta * 1.6, 0.0, 1.0))
		if fmod(_t, 0.5) < delta:
			_refresh_remote()
		_check_spots(delta)
	var dr: Vector2 = _dist_range()  # [camp] one zoom range per view for wheel and stick (no snapping back)
	_dist = clampf(_dist, dr.x, dr.y)
	var off := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch)) * _dist
	_cam.position = _focus + off
	_cam.look_at(_focus, Vector3.UP)
	_reticle.queue_redraw()


## [camp] Zoom limits: the orrery stays whole in the system view; a district stays in frame.
func _dist_range() -> Vector2:
	return Vector2(30.0, 100.0) if mode == "remote" else Vector2(80.0, 170.0)


func _check_spots(delta: float) -> void:
	if district == null:
		return
	var vs: Vector2 = Vector2(_vp.size)
	var ctr: Vector2 = vs * 0.5
	for k: String in district.spot_nodes:
		var n: Node3D = district.spot_nodes[k]
		var key: String = "sightings:ledger_wreck" if k == "ledger_wreck" else "animals:deer"
		if Codex.is_unlocked(key):
			continue
		var p: Vector3 = n.global_position
		var inview: bool = not _cam.is_position_behind(p) and _cam.unproject_position(p).distance_to(ctr) < vs.y * 0.12
		_spot_t[k] = (float(_spot_t.get(k, 0.0)) + delta) if inview else 0.0
		if float(_spot_t[k]) >= float(RemoteProgress.cfg().get("spot_s", 1.2)):
			if Codex.unlock(key):
				Audio.play("chime", 1.0, -6.0)
				var nm: String = tr("Ledger wreck") if k == "ledger_wreck" else tr("Deer")
				_hint.text = tr("Logged through the telescope: %s. New Codex entry.") % nm
				EventBus.toast.emit(tr("Codex: %s") % nm, "info")
				GameState.inc_stat("telescope_sightings")


func _draw_reticle() -> void:
	var s: Vector2 = _reticle.size
	var c: Vector2 = s * 0.5
	var col: Color = LINE
	var r: float = s.y * (0.12 if mode == "remote" else 0.0)
	if r <= 0.0:
		return
	_reticle.draw_arc(c, r, 0.0, TAU, 96, Color(col.r, col.g, col.b, 0.35), 1.2, true)
	for k: int in 4:
		var d: Vector2 = Vector2.RIGHT.rotated(k * PI * 0.5)
		_reticle.draw_line(c + d * (r + 6.0), c + d * (r + 26.0), col, 1.2, true)
		_reticle.draw_line(c + d * 6.0, c + d * 16.0, Color(col.r, col.g, col.b, 0.4), 1.0, true)
	for k: int in 36:
		var a: float = k * TAU / 36.0
		var d2: Vector2 = Vector2.RIGHT.rotated(a)
		var l: float = 6.0 if k % 3 == 0 else 3.0
		_reticle.draw_line(c + d2 * (r - l), c + d2 * r, Color(col.r, col.g, col.b, 0.3), 1.0, true)
	# Range marks: a short scale bar bottom-right of the reticle.
	var y: float = c.y + r + 40.0
	_reticle.draw_line(Vector2(c.x - 40.0, y), Vector2(c.x + 40.0, y), Color(col.r, col.g, col.b, 0.35), 1.0, true)
	for k: int in 5:
		var x: float = c.x - 40.0 + k * 20.0
		_reticle.draw_line(Vector2(x, y - 3.0), Vector2(x, y + 3.0), Color(col.r, col.g, col.b, 0.35), 1.0, true)


func _on_view_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb: InputEventMouseButton = ev
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_dist = maxf(_dist - 4.0, _dist_range().x)  # [camp]
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_dist = minf(_dist + 4.0, _dist_range().y)  # [camp]
	elif ev is InputEventMouseMotion and _drag:
		_yaw -= (ev as InputEventMouseMotion).relative.x * 0.005


func _unhandled_input(ev: InputEvent) -> void:
	if not is_open:
		return
	if ev.is_action_pressed("ui_cancel") or ev.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		if mode == "remote":
			_show_system()
		else:
			close_view()
