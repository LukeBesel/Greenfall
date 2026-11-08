class_name SystemMap
extends CanvasLayer
## [home] The solar-system hologram, the hero UI for travel (Homeward, systems/homeward.gd): a 3D
## orrery of the Verdance system in its own World3D. Two suns at the centre (Hearth and its
## orange companion Ember, data/solar_system.json) circle each other; thin glowing orbit lines;
## the five planets in their looks with a restoration ring, their name, % and the drive they need;
## a parallax starfield. Select a planet (D-pad / list / click) and the camera glides in to it.
## On the planet Lumi is on, "Choose a district" zooms all the way in and hands over to the survey
## globe (ui/globe_view.gd: hubs and districts); closing the globe zooms back out to the system.
## Elsewhere, Launch flies the rocket there (automation/rocket.gd -> HomewardDirector). Left
## cards: system restoration, relics and the rocket's interplanetary drive (build the next tier).
## Opens from the survey globe (M > Solar system), the pause menu or --open=system. Also the view
## of an interplanetary flight (fly()). Pad: D-pad / stick move focus, A presses, B / Esc backs out.

signal closed

const HOLO := Color(0.45, 0.88, 1.0)
const GOLD := Color(1.0, 0.78, 0.36)
const AU_UNITS: float = 8.0
const HOME_CAM := Vector3(0, 33.0, 44.0)
## [sysmap] Each planet is a detailed PlanetGlobe (ui/planet_globe.gd). Map radius per planet, and
## how far its rings reach (in radii: Ochre's dust, Rime's ice spikes, Anvil's embers); orbits are
## spaced from these so no ring ever sweeps through a neighbouring planet.
const GLOBE_R: Dictionary = {"verdance": 1.95, "ochre": 1.5, "tidewell": 2.0, "anvil": 1.7, "rime": 1.45}
const RING_REACH: Dictionary = {"ochre": 2.6, "rime": 2.45, "anvil": 2.2}
const SUN_ZONE: float = 4.4
const ORBIT_GAP: float = 0.3
## Overview camera: a low, wide angle (elevation in radians), pulled back by OVERVIEW_DIST x the
## system's extent and aimed a little toward the viewer so the near lanes stay on screen. Tuned
## so every planet stays clear of the cards at 16:9 and reads at 17-40 px radius (720p).
const OVERVIEW_ELEV: float = 0.45
const OVERVIEW_DIST: float = 1.65
const OVERVIEW_AIM: float = 0.4
## The selected planet swells a little in the overview so its silhouette and rings read.
const SELECT_GROW: float = 1.3
## Zoomed framing: the globe fills this share of the screen height, its rings at most RING_FILL.
const GLOBE_FILL: float = 0.55
const RING_FILL: float = 0.8

var world: Node
var is_open: bool = false
var selected: int = 0
var _root: Control
var _svc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _sys: Node3D
var _planets: Array[Node3D] = []
var _globes: Array[PlanetGlobe] = []  # [sysmap]
var _orbit_rs: Array[float] = []
var _resto_t: float = 0.0
var _rings: Array[MeshInstance3D] = []
var _labels: Array[Label3D] = []
var _orbits: Array[MeshInstance3D] = []
var _orbit_mats: Array[StandardMaterial3D] = []
var _sun_a: Node3D
var _sun_b: Node3D
var _marker: MeshInstance3D
var _cards: Control
var _left: VBoxContainer
var _right: VBoxContainer
var _list: VBoxContainer
var _first: Control
var _fade: ColorRect
var _fly_from: int = -1
var _fly_to: int = -1
var _fly_t: float = -1.0
var _fly_dur: float = 3.0
var _locked: bool = false
var _t: float = 0.0
## Camera framing: eased toward the target each frame (zoom in on a planet, back out).
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _cam_k: float = 1.0
var _cam_dur: float = 1.2
var _zoom_planet: int = -1
var _handing_over: bool = false


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_root.visible = false


# --- Open / close ----------------------------------------------------------------------------

func open_map(from_planet: bool = false) -> void:
	if is_open:
		return
	is_open = true
	selected = clampi(Homeward.current_planet(), 0, Homeward.planets().size() - 1)
	get_viewport().disable_3d = true  # the district behind is fully covered: don't render it
	_build()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)
	if from_planet:  # back from the globe: start close on the planet, then pull out
		_cam.global_transform = _planet_frame(selected, 1.6 * _globe_r(selected))
		_frame(_overview(), 1.6)
	else:
		_cam.global_transform = Transform3D(Basis(), _overview().origin * 1.35).looking_at(Vector3.ZERO, Vector3.UP)
		_frame(_overview(), 1.4)
	if not _locked:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		EventBus.ui_modal_changed.emit(true)
		if _first:
			_first.call_deferred("grab_focus")
	if world and world.get("hud") != null:
		world.hud.visible = false
	Codex.unlock("homeward:binary_suns")
	Audio.play("whoosh", 0.7, -8.0)


func close_map(keep_paused: bool = false) -> void:
	if not is_open or _locked:
		return
	is_open = false
	_root.visible = false
	_teardown()
	get_viewport().disable_3d = false
	if keep_paused:
		return
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.get("hud") != null:
		world.hud.visible = true
	closed.emit()
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


## The interplanetary flight: a glowing marker arcs between two planets (can't be dismissed).
func fly(from_k: int, to_k: int, duration: float) -> void:
	_fly_from = from_k
	_fly_to = to_k
	_fly_dur = maxf(duration, 0.5)
	_fly_t = 0.0
	_locked = true
	selected = to_k
	if not is_open:
		open_map()
	else:
		_rebuild_cards()
	Audio.play("whoosh", 0.5, -4.0)


# --- 3D scene ----------------------------------------------------------------------------------

func _build() -> void:
	_teardown()
	_svc = SubViewportContainer.new()
	_svc.stretch = true
	_svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_svc)
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_svc.add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var pano := PanoramaSkyMaterial.new()
	pano.panorama = SpaceStage._stars()
	pano.energy_multiplier = 0.9
	sky.sky_material = pano
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.3, 0.38, 0.5)
	env.ambient_light_energy = 0.35
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.03
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	_cam = Camera3D.new()
	_cam.fov = 42.0
	_cam.near = 0.05
	_cam.far = 900.0
	_vp.add_child(_cam)
	_cam.current = true
	_sys = Node3D.new()
	_vp.add_child(_sys)
	_build_stars()
	_build_suns()
	_planets.clear()
	_globes.clear()
	_layout_orbits()
	_rings.clear()
	_labels.clear()
	_orbits.clear()
	_orbit_mats.clear()
	for k: int in Homeward.planets().size():
		_build_planet(k)
	_marker = MeshInstance3D.new()
	_marker.mesh = ProcMesh.sphere(0.16, 12, 6)
	_marker.material_override = Mats.lamp(Color(1.0, 0.95, 0.7), 4.0)
	_marker.visible = false
	_sys.add_child(_marker)
	_cards = Control.new()
	_cards.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cards.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_cards)
	_fade = ColorRect.new()
	_fade.color = Color(0.0, 0.02, 0.04, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	_rebuild_cards()


func _teardown() -> void:
	for c: Node in _root.get_children():
		c.queue_free()
	_svc = null
	_vp = null
	_first = null


## Two shells of tiny star points at different depths (they slide past each other: parallax).
func _build_stars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for shell: Array in [[90.0, 500, 0.12], [170.0, 700, 0.22]]:
		var q := QuadMesh.new()
		q.size = Vector2.ONE * float(shell[2])
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = q
		mm.instance_count = int(shell[1])
		for i: int in mm.instance_count:
			var d := Vector3(rng.randfn(), rng.randfn() * 0.6, rng.randfn()).normalized()
			mm.set_instance_transform(i, Transform3D(Basis(), d * float(shell[0])))
			var b: float = pow(rng.randf(), 3.0)
			mm.set_instance_color(i, Color(0.75 + b * 0.25, 0.82 + b * 0.18, 1.0, 0.35 + b * 0.65))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _glow_tex()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = m
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_sys.add_child(mmi)


func _sun(col: Color, r: float, energy: float) -> Node3D:
	var n := Node3D.new()
	var core := MeshInstance3D.new()
	core.mesh = ProcMesh.sphere(r, 32, 16)
	core.material_override = Mats.lamp(col, energy)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(core)
	var halo := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * r * 5.0
	halo.mesh = q
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hm.albedo_texture = _glow_tex()
	hm.albedo_color = Color(col.r, col.g, col.b, 0.55)
	halo.material_override = hm
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(halo)  # [sysmap] no OmniLight: the globes light themselves from these nodes
	_sys.add_child(n)
	return n


func _build_suns() -> void:
	var c: Dictionary = SolarSystem.cfg()
	var ca: Color = SolarSystem._col((c.get("star_a", {}) as Dictionary).get("color"), Color(1.0, 0.95, 0.85))
	var cb: Color = SolarSystem._col((c.get("star_b", {}) as Dictionary).get("color"), Color(1.0, 0.62, 0.38))
	_sun_a = _sun(ca, 1.25, 2.6)
	_sun_b = _sun(cb, 0.62, 3.0)


func _planet_color(k: int) -> Color:
	var d: Dictionary = Homeward.planet_def(k)
	var col: Variant = HomewardDirector.registry_entry(str(d["id"])).get("color")  # data/planets.json looks, if merged
	if col is Array and (col as Array).size() >= 3:
		return Color(float(col[0]), float(col[1]), float(col[2]))
	if col is String and Color.html_is_valid(str(col)):
		return Color.html(str(col))
	var c: Array = d.get("color", [0.5, 0.5, 0.5])
	return Color(float(c[0]), float(c[1]), float(c[2]))


func _orbit_r(k: int) -> float:
	if k >= 0 and k < _orbit_rs.size():
		return _orbit_rs[k]
	return SolarSystem.orbit_au(_pid_of(k)) * AU_UNITS


func _pid_of(k: int) -> String:
	return str(Homeward.planet_def(k).get("id", "verdance"))


## [sysmap] The globe radius of planet k in map units.
func _globe_r(k: int) -> float:
	var id: String = _pid_of(k)
	if GLOBE_R.has(id):
		return float(GLOBE_R[id])
	return 0.85 + float(Homeward.planet_def(k).get("orbit", 1.0)) * 0.1


## Outer edge of the planet's own rings (or its atmosphere halo when it has none).
func _ring_out(k: int) -> float:
	return _globe_r(k) * float(RING_REACH.get(_pid_of(k), 1.15))


## Everything drawn around planet k: rings plus the restoration halo just outside them.
func _reach(k: int) -> float:
	return _ring_out(k) + 0.12


## Orbits in AU order, each lane wide enough for the planet's rings and its neighbours'.
func _layout_orbits() -> void:
	var n: int = Homeward.planets().size()
	var order: Array[int] = []
	for k: int in n:
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return SolarSystem.orbit_au(_pid_of(a)) < SolarSystem.orbit_au(_pid_of(b)))
	_orbit_rs.resize(n)
	var r: float = SUN_ZONE
	var prev: int = -1
	for k: int in order:
		if prev < 0:
			r += _reach(k)
		else:  # neither planet's rings (or halo) can reach the other's globe, even when aligned
			r += maxf(_reach(prev) + _globe_r(k), _reach(k) + _globe_r(prev)) + ORBIT_GAP
		_orbit_rs[k] = r
		prev = k


func _extent() -> float:
	var e: float = SUN_ZONE
	for k: int in _orbit_rs.size():
		e = maxf(e, _orbit_rs[k] + _reach(k))
	return e


func _orbit_angle(k: int) -> float:
	var au: float = SolarSystem.orbit_au(str(Homeward.planet_def(k).get("id", "verdance")))
	return 0.6 + k * 2.4 + _t * 0.05 / pow(au, 1.5)


func _planet_pos(k: int) -> Vector3:
	var a: float = _orbit_angle(k)
	var r: float = _orbit_r(k)
	return Vector3(cos(a) * r, sin(a * 1.0 + k) * 0.25 * r * 0.08, sin(a) * r)


func _build_planet(k: int) -> void:
	var d: Dictionary = Homeward.planet_def(k)
	var col: Color = _planet_color(k)
	var pct: float = Homeward.stored_pct(k)
	var here: bool = k == Homeward.current_planet()
	var open: bool = here or Homeward.can_reach(k) or Homeward.world_of(k) >= 0
	var radius: float = _globe_r(k)
	var halo_r: float = _ring_out(k) + 0.04
	# Orbit line.
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var r: float = _orbit_r(k)
	for i: int in 161:
		var a: float = TAU * i / 160.0
		im.surface_add_vertex(Vector3(cos(a) * r, 0, sin(a) * r))
	im.surface_end()
	var om := StandardMaterial3D.new()
	om.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	om.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	om.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	om.albedo_color = Color(HOLO, 0.22)
	var orbit := MeshInstance3D.new()
	orbit.mesh = im
	orbit.material_override = om
	orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sys.add_child(orbit)
	_orbits.append(orbit)
	_orbit_mats.append(om)
	# [sysmap] The planet: a detailed PlanetGlobe (relief, clouds, rings, restoration greening),
	# lit from the map's two sun nodes.
	var p := Node3D.new()
	_sys.add_child(p)
	var g := PlanetGlobe.new()
	g.radius = radius
	g.max_lod = 2 if Settings.quality >= 1 else 1
	p.add_child(g)
	g.setup(str(d.get("id", "")), pct, col)
	g.track_suns(_sun_a, _sun_b)
	_globes.append(g)
	# Restoration ring: a dim full ring with the restored share lit green.
	var ring := MeshInstance3D.new()
	ring.mesh = _arc_mesh(halo_r, halo_r + 0.08, pct)
	ring.material_override = Mats.lamp(Color(0.55, 1.0, 0.6), 2.0)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.add_child(ring)
	var back := MeshInstance3D.new()
	back.mesh = _arc_mesh(halo_r, halo_r + 0.08, 1.0)
	var bm := StandardMaterial3D.new()
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_color = Color(HOLO, 0.12)
	bm.cull_mode = BaseMaterial3D.CULL_DISABLED
	back.material_override = bm
	back.position.y = -0.01
	p.add_child(back)
	_rings.append(ring)
	# Label: name, %, and the drive it needs.
	var lab := Label3D.new()
	lab.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lab.fixed_size = true
	lab.pixel_size = 0.0008
	lab.font_size = 26
	lab.outline_size = 7
	lab.outline_modulate = Color(0, 0.02, 0.05, 0.8)
	lab.no_depth_test = true
	lab.position = Vector3(0, radius * 1.25 + 0.3, 0)
	var tag: String
	if here:
		tag = tr("you are here")
	elif Homeward.restored(k):
		tag = tr("restored")
	elif open:
		tag = "%d%%" % int(floor(pct * 100.0 + 0.0001))
	else:
		tag = tr("needs %s") % tr(str(Homeward.drive_def(int(d.get("nav", 5))).get("name", "")))
	lab.text = "%s\n%s" % [Homeward.planet_name(k).to_upper(), tag]
	lab.modulate = Color.WHITE if open else Color(0.75, 0.8, 0.85, 0.8)
	p.add_child(lab)
	_labels.append(lab)
	_planets.append(p)


## A bright core with a soft, thin halo (stars, sun halos).
static func _glow_tex() -> GradientTexture2D:
	var g := GradientTexture2D.new()
	g.width = 128
	g.height = 128
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.16, 0.22, 0.45, 1.0])
	grad.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0.22), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0)])
	g.gradient = grad
	return g


## A flat ring segment from 12 o'clock clockwise, `frac` of the way round.
static func _arc_mesh(r0: float, r1: float, frac: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n: int = maxi(2, int(72 * clampf(frac, 0.0, 1.0)))
	if frac <= 0.001:
		return ArrayMesh.new()
	for i: int in n:
		var a0: float = -PI * 0.5 + TAU * frac * i / n
		var a1: float = -PI * 0.5 + TAU * frac * (i + 1) / n
		var p00 := Vector3(cos(a0) * r0, 0, sin(a0) * r0)
		var p01 := Vector3(cos(a0) * r1, 0, sin(a0) * r1)
		var p10 := Vector3(cos(a1) * r0, 0, sin(a1) * r0)
		var p11 := Vector3(cos(a1) * r1, 0, sin(a1) * r1)
		for v: Vector3 in [p00, p01, p11, p00, p11, p10]:
			st.add_vertex(v)
	return st.commit()


# --- Camera ------------------------------------------------------------------------------------

func _overview() -> Transform3D:
	# [sysmap] Low and wide: the whole system fits between the cards, near planets read large.
	var e: float = _extent()
	var eye := Vector3(0.0, sin(OVERVIEW_ELEV), cos(OVERVIEW_ELEV)) * e * OVERVIEW_DIST
	return Transform3D(Basis(), eye).looking_at(Vector3(0.0, 0.0, e * OVERVIEW_AIM), Vector3.UP)


## [sysmap] Zoomed-in distance for planet k: the globe fills GLOBE_FILL of the screen height and
## its rings at most RING_FILL, so the relief, clouds and rings read (a 15 px globe is a dot).
func _zoom_dist(k: int) -> float:
	var t: float = tan(deg_to_rad(_cam.fov if _cam else 42.0) * 0.5)
	var eye: float = maxf(_globe_r(k) / (t * GLOBE_FILL), _ring_out(k) / (t * RING_FILL))
	return eye / 1.52  # _planet_frame's offset is ~1.52 x dist long


## Close on planet k (dist in planet radii-ish units), from the sun side so it is lit.
func _planet_frame(k: int, dist: float) -> Transform3D:
	var p: Vector3 = _planet_pos(k)
	var out: Vector3 = Vector3(p.x, 0, p.z).normalized() if p.length() > 0.1 else Vector3.BACK
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var eye: Vector3 = p - out * dist * 1.1 + side * dist * 0.9 + Vector3(0, dist * 0.55, 0)
	return Transform3D(Basis(), eye).looking_at(p + Vector3(0, 0.1, 0), Vector3.UP)


func _frame(to: Transform3D, dur: float) -> void:
	_cam_from = _cam.global_transform if _cam else to
	_cam_to = to
	_cam_k = 0.0
	_cam_dur = maxf(0.05, dur)


func _zoom_to(k: int) -> void:
	_zoom_planet = k
	_frame(_planet_frame(k, _zoom_dist(k)), 1.3)


# --- Cards -------------------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if _cards == null:
		return
	for c: Node in _cards.get_children():
		c.queue_free()
	_first = null
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 10)
	_left.position = Vector2(28, 28)
	_cards.add_child(_left)
	_build_left()
	_right = VBoxContainer.new()
	_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_right.offset_right = -28
	_right.offset_top = 28
	_right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_right.add_theme_constant_override("separation", 10)
	_cards.add_child(_right)
	_build_right()
	var hint := UITheme.label(tr("In flight") if _locked else tr("D-pad / click  pick a planet      Enter / A  choose      Esc / B  back"), 13, Color(HOLO, 0.7))
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
	hint.offset_top = -40
	hint.offset_bottom = -18
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cards.add_child(hint)


func _card(title: String, subtitle: String, width: float) -> Array:
	var pc := PanelContainer.new()
	var sb := UITheme.box(Color(0.03, 0.12, 0.17, 0.62), Color(HOLO, 0.4), 1, 2, 14)
	sb.shadow_color = Color(HOLO, 0.08)
	sb.shadow_size = 8
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 0)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	pc.add_child(body)
	body.add_child(UITheme.label(subtitle, 11, Color(HOLO, 0.7)))
	body.add_child(UITheme.label(title.to_upper(), 20, HOLO.lerp(Color.WHITE, 0.5)))
	var line := ColorRect.new()
	line.color = Color(HOLO, 0.45)
	line.custom_minimum_size = Vector2(0, 1)
	body.add_child(line)
	return [pc, body]


func _bar(v: float, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 6)
	b.max_value = 1.0
	b.value = v
	b.add_theme_stylebox_override("fill", UITheme.box(col, Color(0, 0, 0, 0), 0, 3, 0))
	b.add_theme_stylebox_override("background", UITheme.box(Color(HOLO, 0.12), Color(0, 0, 0, 0), 0, 3, 0))
	return b


func _button(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.box(Color(HOLO, 0.12), Color(HOLO, 0.5), 1, 2, 8))
	b.add_theme_stylebox_override("hover", UITheme.box(Color(HOLO, 0.26), Color(HOLO, 0.9), 1, 2, 8))
	b.add_theme_stylebox_override("pressed", UITheme.box(Color(HOLO, 0.4), HOLO, 1, 2, 8))
	b.add_theme_stylebox_override("focus", UITheme.box(Color(HOLO, 0.26), Color.WHITE, 1, 2, 8))
	b.add_theme_stylebox_override("disabled", UITheme.box(Color(HOLO, 0.04), Color(HOLO, 0.15), 1, 2, 8))
	b.add_theme_color_override("font_color", HOLO.lerp(Color.WHITE, 0.6))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_focus_color", Color.WHITE)
	b.add_theme_color_override("font_disabled_color", Color(HOLO, 0.4))


func _build_left() -> void:
	var c: Array = _card(tr("Verdance system"), tr("two suns  ·  five worlds  ·  system restoration"), 300)
	_left.add_child(c[0])
	var b: VBoxContainer = c[1]
	var sp: float = Homeward.system_pct()
	b.add_child(UITheme.label("%d %%" % int(floor(sp * 100.0 + 0.0001)), 38, HOLO.lerp(Color.WHITE, 0.7)))
	b.add_child(UITheme.label(tr("restored  ·  %d of %d planets") % [int(GameState.stats.get("planets_restored", 0)), Homeward.planets().size()], 13, UITheme.MUTED))
	b.add_child(_bar(sp, Color(0.55, 1.0, 0.6)))
	var rel := HBoxContainer.new()
	rel.add_theme_constant_override("separation", 6)
	b.add_child(rel)
	rel.add_child(UITheme.label(tr("Relics"), 13, UITheme.MUTED))
	for k: int in range(1, Homeward.planets().size()):
		var rid: String = str(Homeward.planet_def(k).get("relic", ""))
		var have: bool = rid in Homeward.relics()
		var l := UITheme.label("◆" if have else "◇", 16, GOLD if have else Color(HOLO, 0.35))
		l.tooltip_text = tr(str(Homeward.relic_def(rid).get("name", rid))) if have else tr("Restore %s") % Homeward.planet_name(k)
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		rel.add_child(l)
	if Homeward.picks() > 0:
		b.add_child(UITheme.label(tr("Heirloom picks waiting: %d (Pause > Ark Bridge)") % Homeward.picks(), 13, GOLD))
	var d: Array = _card(tr("Rocket drive"), tr("interplanetary  ·  carried to every planet"), 300)
	_left.add_child(d[0])
	var db: VBoxContainer = d[1]
	var cur: Dictionary = Homeward.drive_def(Homeward.drive())
	db.add_child(UITheme.label(tr(str(cur.get("name", "District hops only"))), 15, Color.WHITE))
	var nd: Dictionary = Homeward.next_drive()
	if nd.is_empty():
		db.add_child(UITheme.label(tr("The Homeward rocket stands ready."), 13, UITheme.GREEN))
		return
	db.add_child(UITheme.label(tr("Next: %s") % tr(str(nd["name"])), 14, GOLD))
	var dl := UITheme.label(tr(str(nd.get("desc", ""))), 12, UITheme.MUTED)
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dl.custom_minimum_size = Vector2(270, 0)
	db.add_child(dl)
	db.add_child(UITheme.label(Homeward.cost_text(nd.get("cost", {})), 13, UITheme.CREAM))
	var why: String = Homeward.drive_blocker(Homeward.at_home_site(world))
	var bb := Button.new()
	bb.custom_minimum_size = Vector2(0, 36)
	bb.text = tr("Build") if why == "" else why
	bb.disabled = why != "" or _locked
	bb.clip_text = true
	_button(bb)
	bb.pressed.connect(func() -> void:
		if Homeward.buy_drive(Homeward.at_home_site(world)):
			Audio.play("buy", 1.0, -4.0)
			HomewardDirector.on_drive_built(world)
			_rebuild_cards()
			if _first:
				_first.call_deferred("grab_focus"))
	db.add_child(bb)


func _build_right() -> void:
	var c: Array = _card(tr("Planets"), tr("pick a world"), 330)
	_right.add_child(c[0])
	_list = c[1]
	var here: int = Homeward.current_planet()
	var buttons: Array[Button] = []
	for k: int in Homeward.planets().size():
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var pct: int = int(floor(Homeward.stored_pct(k) * 100.0 + 0.0001))
		var tag: String = tr("you are here") if k == here else (tr("restored") if Homeward.restored(k) else ("%d%%" % pct if Homeward.world_of(k) >= 0 else tr("unvisited")))
		b.text = "%s   ·   %s" % [Homeward.planet_name(k).to_upper(), tag]
		b.disabled = _locked
		_button(b)
		var kk: int = k
		b.focus_entered.connect(func() -> void: _select(kk))
		b.pressed.connect(func() -> void: _select(kk, true))
		_list.add_child(b)
		buttons.append(b)
		if _first == null and k == selected:
			_first = b
	_right.add_child(_detail())


func _select(k: int, zoom: bool = false) -> void:
	if k != selected:
		selected = k
		if _right and _right.get_child_count() > 1:
			var old: Node = _right.get_child(1)
			_right.remove_child(old)
			old.queue_free()
			_right.add_child(_detail())
		Audio.play("blip", 1.2, -12.0)
	if not _locked and (zoom or (_zoom_planet >= 0 and k != _zoom_planet)):
		_zoom_to(k)


func _detail() -> Control:
	var d: Dictionary = Homeward.planet_def(selected)
	var t: Dictionary = WorldGen.world_type(str(d.get("type", "")))
	var au: float = SolarSystem.orbit_au(str(d.get("id", "verdance")))
	var c: Array = _card(Homeward.planet_name(selected), tr("%s  ·  %.2f AU from the suns") % [tr(str(t.get("name", "Home world"))), au], 330)
	var b: VBoxContainer = c[1]
	var tw := UITheme.label(tr(str(d.get("twist", ""))), 13, UITheme.CREAM)
	tw.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tw.custom_minimum_size = Vector2(300, 0)
	b.add_child(tw)
	var mods: Array[String] = []
	for id: Variant in d.get("mods", []):
		mods.append(tr(str(WorldGen.modifier(str(id)).get("name", id))))
	if not mods.is_empty():
		b.add_child(UITheme.label(", ".join(mods), 12, Color(HOLO, 0.85)))
	var p: float = Homeward.stored_pct(selected)
	b.add_child(UITheme.label(tr("Restored %d%%") % int(floor(p * 100.0 + 0.0001)), 14, Color.WHITE))
	b.add_child(_bar(p, Color(0.55, 1.0, 0.6)))
	var goal := UITheme.label(tr("Goal: %d Thriving hexes, %d bases at level 5, a Thriving landing district") % [int(d.get("thriving", 0)), int(d.get("bases", 1))] if selected > 0 else tr("Goal: the Bloom Core full (Cradle Returns)"), 12, UITheme.MUTED)
	goal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	goal.custom_minimum_size = Vector2(300, 0)
	b.add_child(goal)
	var lb := Button.new()
	lb.custom_minimum_size = Vector2(0, 40)
	_button(lb)
	var here: bool = selected == Homeward.current_planet()
	if here and HomewardDirector.home_ready(world):
		lb.text = tr("Launch home")
		lb.pressed.connect(func() -> void:
			close_map()
			HomewardDirector.launch_home(world))
	elif here:
		lb.text = tr("Choose a district")
		lb.disabled = _locked or world == null or world.get("globe") == null
		lb.pressed.connect(_hand_to_globe)
	else:
		var why: String = launch_blocker(world, selected)
		lb.text = tr("Launch") if why == "" else why
		lb.disabled = why != "" or _locked
		lb.pressed.connect(func() -> void:
			var k: int = selected
			close_map()
			HomewardDirector.launch_planet(world, k))
	lb.clip_text = true
	b.add_child(lb)
	return c[0]


## "" if Lumi can fly from here to planet k now, else why not.
static func launch_blocker(w: Node, k: int) -> String:
	if k == Homeward.current_planet():
		return TranslationServer.translate("You are here")
	var r: String = Homeward.reach_blocker(k, Homeward.drive(), Homeward.pct_list())
	if r != "":
		return r
	if w != null and w.has_method("rocket_status"):
		if str(w.call("rocket_status")) != "":
			return TranslationServer.translate("Rocket not ready")
	return ""


## Zoom all the way into this planet and hand over to the survey globe (hubs and districts).
func _hand_to_globe() -> void:
	if _handing_over or world == null or world.get("globe") == null:
		return
	_handing_over = true
	_frame(_planet_frame(selected, 1.2 * _globe_r(selected)), 0.9)
	_fade.create_tween().tween_property(_fade, "color:a", 1.0, 0.8)
	await get_tree().create_timer(0.85, true, false, true).timeout
	_handing_over = false
	close_map(true)
	var g: GlobeView = world.globe
	var holder: Node3D = g.holder
	g.holder = null  # full screen: the hologram continues the zoom
	g.open_view()
	if world.has_method("planet_cell_at"):
		g.focus_on(world.planet_cell_at(world.patch.global_position))
	g.closed.connect(func() -> void:
		g.holder = holder
		if world and is_instance_valid(world) and not bool(world.get("launching")):
			open_map(true), CONNECT_ONE_SHOT)


# --- Frame -------------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if not is_open or _vp == null:
		return
	_t += delta
	# The two suns circle their common centre; planets ride their orbits and spin.
	var sa: float = _t * 0.35
	_sun_a.position = Vector3(cos(sa), 0, sin(sa)) * 0.55
	_sun_b.position = -Vector3(cos(sa), 0, sin(sa)) * 3.4
	for k: int in _planets.size():
		_planets[k].position = _planet_pos(k)  # the globe spins itself
		var sel: bool = k == selected
		# Globe, rings and halo swell together (the label keeps its fixed screen size).
		var grow: float = SELECT_GROW if sel and _zoom_planet < 0 and _fly_t < 0.0 else 1.0
		_planets[k].scale = Vector3.ONE * lerpf(_planets[k].scale.x, grow, clampf(delta * 4.0, 0.0, 1.0))
		_orbit_mats[k].albedo_color = Color(HOLO, 0.5 if sel else 0.18)
		_labels[k].modulate.a = 1.0 if sel or _zoom_planet < 0 else 0.45
	# Camera easing (follows a moving planet while zoomed).
	if _zoom_planet >= 0 and _cam_k >= 1.0 and not _handing_over:
		_cam_to = _planet_frame(_zoom_planet, _zoom_dist(_zoom_planet))
		_cam.global_transform = _cam.global_transform.interpolate_with(_cam_to, clampf(delta * 3.0, 0.0, 1.0))
	elif _cam_k < 1.0:
		_cam_k = minf(1.0, _cam_k + delta / _cam_dur)
		if _zoom_planet >= 0 and not _handing_over:
			_cam_to = _planet_frame(_zoom_planet, _zoom_dist(_zoom_planet))
		var e: float = _cam_k * _cam_k * (3.0 - 2.0 * _cam_k)
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
	else:
		# Overview: a slow drift so the starfield shells slide past each other.
		var drift := Transform3D(Basis(Vector3.UP, sin(_t * 0.07) * 0.08), Vector3.ZERO) * _overview()
		_cam.global_transform = _cam.global_transform.interpolate_with(drift, clampf(delta * 0.8, 0.0, 1.0))
	# [sysmap] Restoration can change while the map is open: retint the globes, don't rebuild.
	_resto_t -= delta
	if _resto_t <= 0.0:
		_resto_t = 1.0
		for k: int in _globes.size():
			var f: float = Homeward.stored_pct(k)
			if absf(f - _globes[k].restoration) > 0.001:
				_globes[k].set_restoration(f)
	# Interplanetary flight marker.
	if _fly_t >= 0.0 and _fly_from >= 0 and _fly_to >= 0:
		_fly_t = minf(1.0, _fly_t + delta / _fly_dur)
		var a: Vector3 = _planet_pos(_fly_from)
		var b: Vector3 = _planet_pos(_fly_to)
		var mid: Vector3 = (a + b) * 0.5 + Vector3(0, a.distance_to(b) * 0.3, 0)
		var u: float = _fly_t
		var pos: Vector3 = a.lerp(mid, u).lerp(mid.lerp(b, u), u)
		_marker.visible = true
		_marker.position = pos
		_cam.global_transform = _cam.global_transform.interpolate_with(Transform3D(Basis(), pos + Vector3(0, 6, 10)).looking_at(pos, Vector3.UP), clampf(delta * 2.0, 0.0, 1.0))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or _locked:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var k: int = _pick_at()
		if k >= 0:
			if _list and k < _list.get_child_count() and _list.get_child(k) is Control:
				(_list.get_child(k) as Control).grab_focus()
			_select(k, true)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _zoom_planet >= 0:
			_zoom_planet = -1
			_frame(_overview(), 1.0)
		else:
			close_map()
		get_viewport().set_input_as_handled()


## [sysmap] Click picking: the planet whose globe (or rings) is under the mouse, -1 if none.
func _pick_at() -> int:
	if _cam == null or _svc == null or _vp == null or _svc.size.x <= 0.0:
		return -1
	var m: Vector2 = _svc.get_local_mouse_position() * (Vector2(_vp.size) / _svc.size)
	var best: int = -1
	var best_d: float = INF
	var right: Vector3 = _cam.global_transform.basis.x
	for k: int in _planets.size():
		var pos: Vector3 = _planets[k].global_position
		if _cam.is_position_behind(pos):
			continue
		var sp: Vector2 = _cam.unproject_position(pos)
		var pr: float = (_cam.unproject_position(pos + right * _ring_out(k)) - sp).length()
		var dd: float = m.distance_to(sp)
		if dd < maxf(pr, 22.0) and dd < best_d:
			best_d = dd
			best = k
	return best
