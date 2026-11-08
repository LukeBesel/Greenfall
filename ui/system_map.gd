class_name SystemMap
extends CanvasLayer
## [home] The solar-system hologram, the hero UI for travel (Homeward, systems/homeward.gd): a 3D
## orrery of the Verdance system in its own World3D. Two suns at the centre (Hearth and its
## orange companion Ember, data/solar_system.json) circle each other; thin orbit lines; each planet
## a detailed PlanetGlobe (ui/planet_globe.gd); a parallax starfield.
## [sysmap2] A clean view: no text in the 3D scene. Only discovered planets show (they are found in
## campaign order, Homeward.discovered); the one Lumi is on wears a soft gold ring. One small panel
## at the right edge describes the selected planet (status, restoration, launch / build the drive it
## needs) with a one-line system summary; the orrery is framed into the space left of it with an
## off-axis projection, so no planet ever passes under the panel.
## Select a planet (Left/Right, click) and Accept / click zooms in to it. On the planet Lumi is on,
## "Choose a district" zooms all the way in and hands over to the survey globe (ui/globe_view.gd:
## hubs and districts); closing the globe zooms back out to the system. Elsewhere, Launch flies the
## rocket there (automation/rocket.gd -> HomewardDirector). Opens from the survey globe (M > Solar
## system), the pause menu or --open=system. Also the view of an interplanetary flight (fly()).
## Pad: Left/Right pick a planet, A zooms in (then presses the panel button), B / Esc backs out.

signal closed

const HOLO := Color(0.45, 0.88, 1.0)
const GOLD := Color(1.0, 0.78, 0.36)
const AU_UNITS: float = 8.0
const FOV: float = 42.0
const NEAR: float = 0.05
## [sysmap] Map radius per planet, and how far its rings reach (in radii: Ochre's dust, Rime's ice
## spikes, Anvil's embers); orbits are spaced so no ring ever sweeps through a neighbouring planet.
const GLOBE_R: Dictionary = {"verdance": 1.95, "ochre": 1.5, "tidewell": 2.0, "anvil": 1.7, "rime": 1.45}
## [orbE] Map radius of a Verdance-sized globe; each planet is scaled by its real globe (GlobeSize).
const GLOBE_BASE: float = 1.75
const RING_REACH: Dictionary = {"ochre": 2.6, "rime": 2.45, "anvil": 2.2}
const SUN_ZONE: float = 4.4
const ORBIT_GAP: float = 0.3
## Overview camera elevation (radians): low and wide. Its distance is fitted to the discovered
## planets, so the view starts close around Verdance and widens as the system is found.
const OVERVIEW_ELEV: float = 0.45
## The selected planet swells a little in the overview so its silhouette and rings read.
const SELECT_GROW: float = 1.3
## Zoomed framing: the globe fills this share of the screen height, its rings at most RING_FILL.
const GLOBE_FILL: float = 0.55
const RING_FILL: float = 0.8
## The info panel (canvas px) and the margin kept around it and the screen edge.
const PANEL_W: float = 300.0
const MARGIN: float = 24.0

var world: Node
var is_open: bool = false
## [v2map] Owner (Nov 8, note 40): travel happens only at the rocket (E at its pad). Opened as a
## map (M > Solar system, pause menu) the panel only describes planets; open_map(_, true) from the
## rocket's destination list (ui/rocket_picker.gd) shows the Launch buttons.
var travel: bool = false
## [v2map] Travel mode, the planet Lumi is on: back to the rocket's hub list (set by the picker).
var on_here: Callable = Callable()
var selected: int = 0
var _root: Control
var _svc: SubViewportContainer
var _vp: SubViewport
var _cam: Camera3D
var _sys: Node3D
var _planets: Array[Node3D] = []
var _globes: Array[PlanetGlobe] = []  # null for planets not discovered yet
var _orbit_rs: Array[float] = []
var _resto_t: float = 0.0
var _orbits: Array[MeshInstance3D] = []
var _orbit_mats: Array[StandardMaterial3D] = []
var _sun_a: Node3D
var _sun_b: Node3D
var _marker: MeshInstance3D
var _ship: ShipModel  # [ship] Lumi's ship at its current tier
var _cards: Control
var _panel: PanelContainer
var _first: Control
var _fade: ColorRect
var _fly_from: int = -1
var _fly_to: int = -1
var _fly_t: float = -1.0
var _fly_dur: float = 3.0
var _locked: bool = false
var _t: float = 0.0
## Camera framing: eased toward the target each frame (zoom in on a planet, back out). The frustum
## offset (off-axis shift, near-plane units) eases with it.
var _cam_from := Transform3D()
var _cam_to := Transform3D()
var _off_from := Vector2.ZERO
var _off_to := Vector2.ZERO
var _cam_k: float = 1.0
var _cam_dur: float = 1.2
var _zoom_planet: int = -1
var _handing_over: bool = false
var _ov_xf := Transform3D()
var _ov_off := Vector2.ZERO


func _ready() -> void:
	layer = 19
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_root.visible = false


# --- Open / close ----------------------------------------------------------------------------

func open_map(from_planet: bool = false, p_travel: bool = false) -> void:
	if is_open:
		return
	is_open = true
	travel = p_travel  # [v2map]
	selected = clampi(Homeward.current_planet(), 0, Homeward.planets().size() - 1)
	get_viewport().disable_3d = true  # the district behind is fully covered: don't render it
	_build()
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.35)
	if from_planet:  # back from the globe: start close on the planet, then pull out
		_cam.global_transform = _planet_frame(selected, 1.6 * _globe_r(selected))
		_cam.frustum_offset = _zoom_off()
		_frame(_ov_xf, _ov_off, 1.6)
	else:
		_cam.global_transform = Transform3D(Basis(), _ov_xf.origin * 1.35).looking_at(Vector3.ZERO, Vector3.UP)
		_cam.frustum_offset = _ov_off
		_frame(_ov_xf, _ov_off, 1.4)
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
	_cam.fov = FOV  # PlanetGlobe's LOD reads it
	_cam.projection = Camera3D.PROJECTION_FRUSTUM  # off-axis: the orrery sits left of the panel
	_cam.size = 2.0 * NEAR * tan(deg_to_rad(FOV) * 0.5)
	_cam.near = NEAR
	_cam.far = 900.0
	_vp.add_child(_cam)
	_cam.current = true
	_sys = Node3D.new()
	_vp.add_child(_sys)
	_build_stars()
	_build_suns()
	_planets.clear()
	_globes.clear()
	_orbits.clear()
	_orbit_mats.clear()
	_layout_orbits()
	for k: int in Homeward.planets().size():
		_build_planet(k)
	_fit_overview()
	_marker = MeshInstance3D.new()
	_marker.mesh = ProcMesh.sphere(0.16, 12, 6)
	_marker.material_override = Mats.lamp(Color(1.0, 0.95, 0.7), 4.0)
	_marker.visible = false
	_sys.add_child(_marker)
	_ship = ShipModel.for_display()  # [ship] parked by the current planet, flies the trips
	_ship.scale = Vector3.ONE * 0.045 * ShipTiers.scale_of(_ship.tier)
	_sys.add_child(_ship)
	for n: Node in _ship.find_children("*", "Label3D", true, false):  # [sysmap2] hull lettering is unreadable at map scale and the map has no 3D text
		n.get_parent().remove_child(n)
		n.free()
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
	_panel = null


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
	n.add_child(halo)  # no OmniLight: the globes light themselves from these nodes
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


## The globe radius of planet k in map units.
func _globe_r(k: int) -> float:
	var id: String = _pid_of(k)
	if GlobeSize.IDS.has(id):  # [orbE] planets differ in size: the map follows the globes
		return GLOBE_BASE * pow(GlobeSize.scale_of(id), 0.7)  # gently compressed: Anvil (2x) reads big, still fits the orrery
	if GLOBE_R.has(id):
		return float(GLOBE_R[id])
	return 0.85 + float(Homeward.planet_def(k).get("orbit", 1.0)) * 0.1


## Outer edge of the planet's own rings (or its atmosphere halo when it has none).
func _ring_out(k: int) -> float:
	return _globe_r(k) * float(RING_REACH.get(_pid_of(k), 1.15))


## Everything drawn around planet k: rings plus the gold "Lumi is here" ring just outside them.
func _reach(k: int) -> float:
	return _ring_out(k) + 0.12


## Orbits in AU order, each lane wide enough that no ring reaches a neighbouring globe. Laid out
## for all five planets, so a planet never moves when another is discovered.
func _layout_orbits() -> void:
	var n: int = Homeward.planets().size()
	_orbit_rs.resize(n)
	var r: float = SUN_ZONE
	var prev: int = -1
	for k: int in _au_order():
		if prev < 0:
			r += _reach(k)
		else:
			r += maxf(_reach(prev) + _globe_r(k), _reach(k) + _globe_r(prev)) + ORBIT_GAP
		_orbit_rs[k] = r
		prev = k


## Planet indices from the suns outward.
func _au_order() -> Array[int]:
	var order: Array[int] = []
	for k: int in Homeward.planets().size():
		order.append(k)
	order.sort_custom(func(a: int, b: int) -> bool: return SolarSystem.orbit_au(_pid_of(a)) < SolarSystem.orbit_au(_pid_of(b)))
	return order


func _orbit_angle(k: int) -> float:
	var au: float = SolarSystem.orbit_au(_pid_of(k))
	return 0.6 + k * 2.4 + _t * 0.05 / pow(au, 1.5)


func _planet_pos(k: int) -> Vector3:
	var a: float = _orbit_angle(k)
	var r: float = _orbit_r(k)
	return Vector3(cos(a) * r, sin(a * 1.0 + k) * 0.25 * r * 0.08, sin(a) * r)


func _build_planet(k: int) -> void:
	var d: Dictionary = Homeward.planet_def(k)
	var known: bool = Homeward.discovered(k)
	# Orbit line (only for discovered planets: an empty lane would give the next one away).
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
	om.albedo_color = Color(HOLO, 0.16)
	var orbit := MeshInstance3D.new()
	orbit.mesh = im
	orbit.material_override = om
	orbit.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	orbit.visible = known
	_sys.add_child(orbit)
	_orbits.append(orbit)
	_orbit_mats.append(om)
	var p := Node3D.new()
	p.visible = known
	_sys.add_child(p)
	_planets.append(p)
	if not known:
		_globes.append(null)
		return
	# The planet: a detailed PlanetGlobe (relief, clouds, rings, restoration greening), lit from
	# the map's two sun nodes.
	var g := PlanetGlobe.new()
	g.radius = _globe_r(k)
	g.max_lod = 2 if Settings.quality >= 1 else 1
	p.add_child(g)
	g.setup(str(d.get("id", "")), Homeward.stored_pct(k), _planet_color(k))
	g.track_suns(_sun_a, _sun_b)
	_globes.append(g)
	if k == Homeward.current_planet():  # [orbE] the walked globe shows its real cells and Lumi's spot
		var sh: SphereShell = _walked_shell()
		if sh:
			g.set_cells(sh)
			_update_here(g)
	if k == Homeward.current_planet():  # where Lumi is: a soft gold ring, no text
		var ring := MeshInstance3D.new()
		var rr: float = _ring_out(k) + 0.04
		ring.mesh = _arc_mesh(rr, rr + 0.07, 1.0)
		var rm := StandardMaterial3D.new()
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rm.albedo_color = Color(GOLD, 0.45)
		ring.material_override = rm
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.name = "HereRing"
		p.add_child(ring)


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

## The free screen area for the orrery, in half-height units around the screen centre (x right,
## y up): everything left of the panel, inside the margin.
func free_rect() -> Rect2:
	var vs: Vector2 = _root.get_viewport_rect().size if _root and _root.is_inside_tree() else Vector2(1280, 720)
	vs = Vector2(maxf(vs.x, 1.0), maxf(vs.y, 1.0))
	var h: float = vs.y * 0.5
	var x0: float = (MARGIN - vs.x * 0.5) / h
	var x1: float = (vs.x - PANEL_W - MARGIN * 2.0 - vs.x * 0.5) / h
	var y: float = (h - MARGIN) / h
	return Rect2(x0, -y, x1 - x0, 2.0 * y)


## Frustum offset (near-plane units) that moves view point `from` (half-height units) to `to`.
func _off_for(from: Vector2, to: Vector2) -> Vector2:
	return (from - to) * NEAR * tan(deg_to_rad(FOV) * 0.5)


## Overview: a fixed low elevation, pulled back until every discovered planet (with its rings,
## swollen when selected) and the suns fit the free area, then shifted to centre there.
func _fit_overview() -> void:
	var known: Array[int] = []
	for k: int in _planets.size():
		if Homeward.discovered(k):
			known.append(k)
	var e: float = SUN_ZONE
	for k: int in known:
		e = maxf(e, _orbit_r(k) + _reach(k))
	var fr: Rect2 = free_rect()
	var lo: float = 0.5
	var hi: float = 8.0
	for _i: int in 26:
		var m: float = (lo + hi) * 0.5
		var bx: Rect2 = _overview_box(_overview_at(e * m), known)
		if bx.size.x <= fr.size.x and bx.size.y <= fr.size.y:
			hi = m
		else:
			lo = m
	_ov_xf = _overview_at(e * hi)
	_ov_off = _off_for(_overview_box(_ov_xf, known).get_center(), fr.get_center())


func _overview_at(dist: float) -> Transform3D:
	var eye := Vector3(0.0, sin(OVERVIEW_ELEV), cos(OVERVIEW_ELEV)) * dist
	return Transform3D(Basis(), eye).looking_at(Vector3.ZERO, Vector3.UP)


## Screen box (half-height units, y up, no offset) of the suns and the given planets over their
## whole orbits.
func _overview_box(xf: Transform3D, ks: Array[int]) -> Rect2:
	var t: float = tan(deg_to_rad(FOV) * 0.5)
	var inv: Transform3D = xf.affine_inverse()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var pts: Array = []
	for i: int in 16:
		var a: float = TAU * i / 16.0
		pts.append([Vector3(cos(a), 0.0, sin(a)) * SUN_ZONE * 0.75, 0.6])
	for k: int in ks:
		var rr: float = _reach(k) * SELECT_GROW
		for i: int in 36:
			var a: float = TAU * i / 36.0
			pts.append([Vector3(cos(a), 0.0, sin(a)) * _orbit_r(k), rr])
	for pr: Array in pts:
		var v: Vector3 = inv * (pr[0] as Vector3)
		var z: float = maxf(-v.z, 0.01)
		var c := Vector2(v.x / z / t, v.y / z / t)
		var rad: float = float(pr[1]) / z / t
		lo = Vector2(minf(lo.x, c.x - rad), minf(lo.y, c.y - rad))
		hi = Vector2(maxf(hi.x, c.x + rad), maxf(hi.y, c.y + rad))
	return Rect2(lo, hi - lo)


## The offset that centres a zoomed planet (on the view axis) in the free area.
func _zoom_off() -> Vector2:
	return _off_for(Vector2.ZERO, free_rect().get_center())


## Close on planet k (dist in planet radii-ish units), from the sun side so it is lit.
func _planet_frame(k: int, dist: float) -> Transform3D:
	var p: Vector3 = _planet_pos(k)
	var out: Vector3 = Vector3(p.x, 0, p.z).normalized() if p.length() > 0.1 else Vector3.BACK
	var side: Vector3 = out.cross(Vector3.UP).normalized()
	var eye: Vector3 = p - out * dist * 1.1 + side * dist * 0.9 + Vector3(0, dist * 0.55, 0)
	return Transform3D(Basis(), eye).looking_at(p + Vector3(0, 0.1, 0), Vector3.UP)


## Zoomed-in distance for planet k: the globe fills GLOBE_FILL of the screen height and its rings
## at most RING_FILL, so the relief, clouds and rings read (a 15 px globe is a dot).
func _zoom_dist(k: int) -> float:
	var t: float = tan(deg_to_rad(FOV) * 0.5)
	var eye: float = maxf(_globe_r(k) / (t * GLOBE_FILL), _ring_out(k) / (t * RING_FILL))
	return eye / 1.52  # _planet_frame's offset is ~1.52 x dist long


func _frame(to: Transform3D, off: Vector2, dur: float) -> void:
	_cam_from = _cam.global_transform if _cam else to
	_off_from = _cam.frustum_offset if _cam else off
	_cam_to = to
	_off_to = off
	_cam_k = 0.0
	_cam_dur = maxf(0.05, dur)


func _zoom_to(k: int) -> void:
	_zoom_planet = k
	_frame(_planet_frame(k, _zoom_dist(k)), _zoom_off(), 1.3)


func _unzoom() -> void:
	_zoom_planet = -1
	_frame(_ov_xf, _ov_off, 1.0)


# --- The info panel ----------------------------------------------------------------------------

func _rebuild_cards() -> void:
	if _cards == null:
		return
	for c: Node in _cards.get_children():
		c.queue_free()
	_first = null
	_panel = _info_panel()
	_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.offset_right = -MARGIN
	_panel.offset_left = -MARGIN - PANEL_W
	_cards.add_child(_panel)
	if _first and is_open and not _locked:
		_first.call_deferred("grab_focus")


func _bar(v: float, col: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(0, 5)
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
	b.clip_text = true


func _wrap(text: String, size: int, col: Color) -> Label:
	var l := UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_W - 28.0, 0)
	return l


## The selected planet: what it is, where it stands, the one thing to do there, and a one-line
## system summary. The only text on the map.
func _info_panel() -> PanelContainer:
	var k: int = selected
	var d: Dictionary = Homeward.planet_def(k)
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.03, 0.1, 0.14, 0.72), Color(HOLO, 0.32), 1, 3, 14))
	pc.custom_minimum_size = Vector2(PANEL_W, 0)
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", 7)
	pc.add_child(b)
	var t: Dictionary = WorldGen.world_type(str(d.get("type", "")))
	b.add_child(UITheme.label(tr("%s  ·  %.2f AU") % [tr(str(t.get("name", "Home world"))), SolarSystem.orbit_au(_pid_of(k))], 11, Color(HOLO, 0.7)))
	b.add_child(UITheme.label(Homeward.planet_name(k).to_upper(), 20, HOLO.lerp(Color.WHITE, 0.5)))
	var here: bool = k == Homeward.current_planet()
	var why: String = launch_blocker(world, k)
	var status: String
	var status_col: Color = UITheme.MUTED
	if _locked:
		status = tr("In flight")
		status_col = GOLD
	elif here:
		status = tr("Lumi is here")
		status_col = GOLD
	elif Homeward.restored(k):
		status = tr("Restored")
		status_col = UITheme.GREEN
	elif why == "":
		status = tr("Ready to launch")
		status_col = UITheme.GREEN
	else:
		status = why
	b.add_child(_wrap(status, 13, status_col))
	var p: float = Homeward.stored_pct(k)
	if here or p > 0.0 or Homeward.world_of(k) >= 0:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var bar := _bar(p, Color(0.55, 1.0, 0.6))
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(bar)
		row.add_child(UITheme.label("%d%%" % int(floor(p * 100.0 + 0.0001)), 13, Color.WHITE))
		b.add_child(row)
	var act := Button.new()
	act.custom_minimum_size = Vector2(0, 38)
	_button(act)
	if not travel and not _locked:  # [v2map] a map, not a launcher: travel is at the rocket
		act.text = tr("Choose a district") if here else tr("Launch from the rocket pad")
		act.disabled = not here or world == null or world.get("globe") == null
		if here:
			act.pressed.connect(_hand_to_globe)
	elif here and travel and on_here.is_valid() and not HomewardDirector.home_ready(world):  # [v2map]
		act.text = tr("Hubs on this planet")
		act.pressed.connect(func() -> void:
			close_map()
			on_here.call())
	elif here and HomewardDirector.home_ready(world):
		act.text = tr("Launch home")
		act.pressed.connect(func() -> void:
			close_map()
			HomewardDirector.launch_home(world))
	elif here:
		act.text = tr("Choose a district")
		act.disabled = _locked or world == null or world.get("globe") == null
		act.pressed.connect(_hand_to_globe)
	else:
		act.text = tr("Launch")
		act.disabled = why != "" or _locked
		act.pressed.connect(func() -> void:
			var kk: int = selected
			close_map()
			HomewardDirector.launch_planet(world, kk))
	b.add_child(act)
	_first = act
	if travel or _locked:  # [v2map] the drive is a rocket part: built from the rocket's list
		_drive_row(b, k)
	var line := ColorRect.new()
	line.color = Color(HOLO, 0.25)
	line.custom_minimum_size = Vector2(0, 1)
	b.add_child(line)
	var foot: String = tr("System %d%% restored  ·  relics %d/%d") % [int(floor(Homeward.system_pct() * 100.0 + 0.0001)), Homeward.relics().size(), Homeward.planets().size() - 1]
	if Homeward.picks() > 0:
		foot += "  ·  " + tr("%d Heirloom picks") % Homeward.picks()
	b.add_child(_wrap(foot, 11, UITheme.MUTED))
	b.add_child(_wrap(tr("Left/Right planet  ·  A zoom  ·  B back"), 10, Color(HOLO, 0.55)))
	return pc


## The interplanetary drive, shown only where it matters: the selected planet needs a better drive,
## or the Homeward rocket waits at home. Builds the next tier.
func _drive_row(b: VBoxContainer, k: int) -> void:
	var nd: Dictionary = Homeward.next_drive()
	if nd.is_empty():
		return
	var needs: bool = int(Homeward.planet_def(k).get("nav", 0)) > Homeward.drive() and Homeward.discovered(k)
	var home: bool = bool(nd.get("home_only", false)) and k == 0
	if not needs and not home:
		return
	b.add_child(_wrap("%s  ·  %s" % [tr(str(nd["name"])), Homeward.cost_text(nd.get("cost", {}))], 12, GOLD))
	var why: String = Homeward.drive_blocker(Homeward.at_home_site(world))
	var bb := Button.new()
	bb.custom_minimum_size = Vector2(0, 34)
	bb.text = tr("Build the drive") if why == "" else why
	bb.disabled = why != "" or _locked
	_button(bb)
	bb.pressed.connect(func() -> void:
		if Homeward.buy_drive(Homeward.at_home_site(world)):
			Audio.play("buy", 1.0, -4.0)
			HomewardDirector.on_drive_built(world)
			_rebuild_cards())
	b.add_child(bb)


## "" if Lumi can fly from here to planet k now, else why not.
static func launch_blocker(w: Node, k: int) -> String:
	if k == Homeward.current_planet():
		return TranslationServer.translate("You are here")
	if not Homeward.discovered(k):
		return TranslationServer.translate("Not discovered yet")
	var r: String = Homeward.reach_blocker(k, Homeward.drive(), Homeward.pct_list())
	if r != "":
		return r
	if w != null and w.has_method("rocket_status"):
		if str(w.call("rocket_status")) != "":
			return TranslationServer.translate("Rocket not ready")
	return ""


func _select(k: int, zoom: bool = false) -> void:
	if k < 0 or k >= _planets.size() or not Homeward.discovered(k):
		return
	if k != selected:
		selected = k
		_rebuild_cards()
		Audio.play("blip", 1.2, -12.0)
	if not _locked and (zoom or (_zoom_planet >= 0 and k != _zoom_planet)):
		_zoom_to(k)


## Step the selection along the discovered planets, suns outward.
func _cycle(step: int) -> void:
	var order: Array[int] = []
	for k: int in _au_order():
		if Homeward.discovered(k):
			order.append(k)
	if order.is_empty():
		return
	_select(order[posmod(order.find(selected) + step, order.size())])


## Zoom all the way into this planet and hand over to the survey globe (hubs and districts).
func _hand_to_globe() -> void:
	if _handing_over or world == null or world.get("globe") == null:
		return
	_handing_over = true
	_frame(_planet_frame(selected, 1.2 * _globe_r(selected)), _zoom_off(), 0.9)
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
	# The two suns circle their common centre; planets ride their orbits (the globes spin).
	var sa: float = _t * 0.35
	_sun_a.position = Vector3(cos(sa), 0, sin(sa)) * 0.55
	_sun_b.position = -Vector3(cos(sa), 0, sin(sa)) * 3.4
	for k: int in _planets.size():
		_planets[k].position = _planet_pos(k)
		var sel: bool = k == selected
		# Globe, rings and gold ring swell together.
		var grow: float = SELECT_GROW if sel and _zoom_planet < 0 and _fly_t < 0.0 else 1.0
		_planets[k].scale = Vector3.ONE * lerpf(_planets[k].scale.x, grow, clampf(delta * 4.0, 0.0, 1.0))
		_orbit_mats[k].albedo_color = Color(HOLO, 0.45 if sel else 0.16)
	# Camera easing (follows a moving planet while zoomed).
	if _zoom_planet >= 0 and _cam_k >= 1.0 and not _handing_over:
		_cam_to = _planet_frame(_zoom_planet, _zoom_dist(_zoom_planet))
		_cam.global_transform = _cam.global_transform.interpolate_with(_cam_to, clampf(delta * 3.0, 0.0, 1.0))
		_cam.frustum_offset = _off_to
	elif _cam_k < 1.0:
		_cam_k = minf(1.0, _cam_k + delta / _cam_dur)
		if _zoom_planet >= 0 and not _handing_over:
			_cam_to = _planet_frame(_zoom_planet, _zoom_dist(_zoom_planet))
		var e: float = _cam_k * _cam_k * (3.0 - 2.0 * _cam_k)
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
		_cam.frustum_offset = _off_from.lerp(_off_to, e)
	else:
		# Overview: a slow drift so the starfield shells slide past each other.
		var drift := Transform3D(Basis(Vector3.UP, sin(_t * 0.07) * 0.08), Vector3.ZERO) * _ov_xf
		_cam.global_transform = _cam.global_transform.interpolate_with(drift, clampf(delta * 0.8, 0.0, 1.0))
		_cam.frustum_offset = _ov_off
	# Restoration can change while the map is open: retint the globes, don't rebuild.
	var hk2: int = Homeward.current_planet()  # [orbE] Lumi's spot follows play
	if hk2 >= 0 and hk2 < _globes.size() and _globes[hk2] and _globes[hk2].cell_shell:
		_update_here(_globes[hk2])
	_resto_t -= delta
	if _resto_t <= 0.0:
		_resto_t = 1.0
		for k: int in _globes.size():
			var g: PlanetGlobe = _globes[k]
			if g and absf(Homeward.stored_pct(k) - g.restoration) > 0.001:
				g.set_restoration(Homeward.stored_pct(k))
	if _ship and not (_fly_t >= 0.0 and _fly_from >= 0 and _fly_to >= 0):  # [ship] parked by the current planet
		var hk: int = clampi(Homeward.current_planet(), 0, _planets.size() - 1)
		_ship.position = _planet_pos(hk) + Vector3(cos(_t * 0.25), 0.35, sin(_t * 0.25)) * 1.7
		ShipModel.face_along(_ship, Vector3(-sin(_t * 0.25), 0, cos(_t * 0.25)))
	# Interplanetary flight marker.
	if _fly_t >= 0.0 and _fly_from >= 0 and _fly_to >= 0:
		_fly_t = minf(1.0, _fly_t + delta / _fly_dur)
		var a: Vector3 = _planet_pos(_fly_from)
		var b: Vector3 = _planet_pos(_fly_to)
		var mid: Vector3 = (a + b) * 0.5 + Vector3(0, a.distance_to(b) * 0.3, 0)
		var u: float = _fly_t
		var pos: Vector3 = a.lerp(mid, u).lerp(mid.lerp(b, u), u)
		_marker.visible = _ship == null  # [ship] the ship itself flies the arc
		_marker.position = pos
		if _ship:
			ShipModel.face_along(_ship, pos - _ship.position)
			_ship.position = pos
			_ship.plume.power = 1.0
		_cam.global_transform = _cam.global_transform.interpolate_with(Transform3D(Basis(), pos + Vector3(0, 6, 10)).looking_at(pos, Vector3.UP), clampf(delta * 2.0, 0.0, 1.0))
		_cam.frustum_offset = _zoom_off()


## Planet picking runs before the GUI: Left/Right must not move button focus, and Accept in the
## overview zooms in (once zoomed it presses the panel's focused button).
func _input(event: InputEvent) -> void:
	if not is_open or _locked or _handing_over:
		return
	if event.is_action_pressed("ui_left"):
		_cycle(-1)
	elif event.is_action_pressed("ui_right"):
		_cycle(1)
	elif event.is_action_pressed("ui_accept") and _zoom_planet < 0 and not (event is InputEventMouseButton):
		_select(selected, true)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open or _locked:
		return
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		var k: int = _pick_at()
		if k >= 0:
			_select(k, true)
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _zoom_planet >= 0:
			_unzoom()
		else:
			close_map()
		get_viewport().set_input_as_handled()


## Click picking: the discovered planet whose globe (or rings) is under the mouse, -1 if none.
func _pick_at() -> int:
	if _cam == null or _svc == null or _vp == null or _svc.size.x <= 0.0:
		return -1
	var m: Vector2 = _svc.get_local_mouse_position() * (Vector2(_vp.size) / _svc.size)
	var best: int = -1
	var best_d: float = INF
	var right: Vector3 = _cam.global_transform.basis.x
	for k: int in _planets.size():
		if not _planets[k].visible:
			continue
		var pos: Vector3 = _planets[k].global_position
		if _cam.is_position_behind(pos):
			continue
		var sp: Vector2 = _cam.unproject_position(pos)
		var pr: float = (_cam.unproject_position(pos + right * _ring_out(k) * _planets[k].scale.x) - sp).length()
		var dd: float = m.distance_to(sp)
		if dd < maxf(pr, 22.0) and dd < best_d:
			best_d = dd
			best = k
	return best


## [orbE] The round planet Lumi walks (its streamer's far shell), or null on the flat game.
func _walked_shell() -> SphereShell:
	if world == null:
		return null
	var st: Variant = world.get("streamer")
	return (st as SphereStreamer).shell if st is SphereStreamer else null


func _update_here(g: PlanetGlobe) -> void:
	var p: Variant = world.get("lumi") if world.get("lumi") != null else world.get("patch")
	if p is Node3D:
		g.set_here((p as Node3D).global_position)
		# Clean overview (owner, sysmap2): the pin only shows once zoomed in on Lumi's planet.
		g.set_here_visible(_zoom_planet == Homeward.current_planet())
