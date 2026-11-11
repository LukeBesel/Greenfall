class_name SourceSites
extends Node
## The world's side of the source jobs (systems/sources.gd): where the step Lumi must do now
## stands in a city, the marker that stands there, its interact prompt, the part she carries, and
## the state of the city's source landmark (TownSite.set_source_state).
##
## A step's spot is given in the frame of the city's source landmark (TownSite.source_frame), so
## the planet's site decides where its landmark is and the job's data stays plain numbers. A city
## whose site is not built yet (Lumi is far away) has no markers; the beam then points at the
## site itself.
##
## Nothing here decides anything: it reads Sources and tells it when Lumi uses a spot.
##
## Use: var s := SourceSites.new(); world.add_child(s); s.setup(sources, districts, site_manager,
## interactables, player_fn)

const PROP_VALVE: String = "valve"
const PROP_LEVER: String = "lever"
const PROP_JAM: String = "jam"
const PROP_SOCKET: String = "socket"
const PROP_PART: String = "part"
const STATE_BROKEN: String = "broken"
const STATE_SHUT_DOWN: String = "shut_down"
const SAFETY_YELLOW := Color(0.96, 0.76, 0.1)
const VALVE_RED := Color(0.8, 0.14, 0.1)
const STEEL := Color(0.55, 0.57, 0.6)
const CRATE_CREAM := Color(0.93, 0.88, 0.74)
const CRATE_TEAL := Color(0.06, 0.52, 0.54)
const LUMI_CYAN := Color(0.25, 0.9, 1.0)
const RING_R: float = 1.1
const CARRY_UP_M: float = 1.9
const RING_PULSE_RATE: float = 3.0
## Seconds between checks that every job on offer has its markers standing (a site that was
## rebuilt takes them with it; a step may come on offer as the city is cleaned).
const CHECK_S: float = 1.0

var _sources: Sources
var _districts: Districts
var _sites: SiteManager
var _interactables: Interactables
var _player_fn: Callable
## district -> {SPOT_AT / SPOT_FROM: Node3D} for the step on offer there.
var _markers: Dictionary[String, Dictionary] = {}
var _carried: Node3D
var _ring_mat: StandardMaterial3D
var _t: float = 0.0
var _check_t: float = 0.0


## `player_fn` returns Lumi's Node3D (or null before she exists).
func setup(sources: Sources, districts: Districts, sites: SiteManager, interactables: Interactables, player_fn: Callable) -> void:
	_sources = sources
	_districts = districts
	_sites = sites
	_interactables = interactables
	_player_fn = player_fn
	sources.in_reach_fn = in_reach
	sources.changed.connect(_on_changed)
	if sites:
		sites.site_built.connect(_on_site_built)
	for id: String in sources.ids():
		refresh(id)


func _exit_tree() -> void:
	if _sources and _sources.changed.is_connected(_on_changed):
		_sources.changed.disconnect(_on_changed)
	if _sources and _sources.in_reach_fn == in_reach:
		_sources.in_reach_fn = Callable()
	if _sites and _sites.site_built.is_connected(_on_site_built):
		_sites.site_built.disconnect(_on_site_built)


func _process(delta: float) -> void:
	_t += delta
	_check_t -= delta
	if _check_t <= 0.0:
		_check_t = CHECK_S
		_check_markers()
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 1.6 + 0.8 * sin(_t * RING_PULSE_RATE)
	if _carried == null:
		return
	var lumi: Node3D = _lumi()
	if lumi:
		var up: Vector3 = lumi.global_position.normalized()
		_carried.global_position = lumi.global_position + up * CARRY_UP_M


# --- Queries ----------------------------------------------------------------------------------

## The town a city's site has built, or null while the site is not loaded.
func town_of(district: String) -> TownSite:
	var p: SitePrefab = _sites.prefab(_districts.site_of(district)) if _sites and _districts else null
	if p == null or not is_instance_valid(p) or p.content == null or not is_instance_valid(p.content):
		return null
	for c: Node in p.content.get_children():
		if c is TownSite and (c as Node3D).is_inside_tree():
			return c as TownSite
	return null


## Where the beam points for a city's job: the marker of the spot to go to, else the city's site
## while it is not built. Null when the job is not on offer.
func target_pos(district: String) -> Variant:
	var spot: String = _sources.active_spot(district) if _sources else ""
	if spot == "":
		return null
	var m: Node3D = marker(district, spot)
	if m != null:
		return m.global_position
	var site: int = _districts.site_of(district)
	if _sites == null or site < 0 or site >= _sites.sites.size():
		return null
	return (_sites.sites[site]["transform"] as Transform3D).origin


## The marker standing at a spot of the step on offer (null when none stands).
func marker(district: String, spot: String) -> Node3D:
	var v: Variant = (_markers.get(district, {}) as Dictionary).get(spot)
	return v as Node3D if is_instance_valid(v) and (v as Node3D).is_inside_tree() else null


## Whether Lumi stands in reach of the spot she must go to.
func in_reach(district: String) -> bool:
	var m: Node3D = marker(district, _sources.active_spot(district))
	var lumi: Node3D = _lumi()
	return m != null and lumi != null and OrbitUp.ground_dist(lumi.global_position, m.global_position) < _sources.reach_m()


# --- Markers ----------------------------------------------------------------------------------

## Rebuilds a city's markers for the step on offer and sets its landmark to the source's state.
func refresh(district: String) -> void:
	_drop_markers(district)
	var town: TownSite = town_of(district)
	if town == null:
		_show_carried(_any_carrying())
		return
	var state: String = STATE_SHUT_DOWN if _sources.is_shut(district) else STATE_BROKEN
	if town.source_state != state:
		town.set_source_state(state)
	var step: Dictionary = _sources.current_step(district)
	if not step.is_empty() and _sources.is_open(district):
		var made: Dictionary = {}
		made[Sources.SPOT_AT] = _stand(town, district, Sources.SPOT_AT, step["at"], str(step["prop"]))
		if step["type"] == Sources.TYPE_CARRY and not _sources.is_carrying(district):
			made[Sources.SPOT_FROM] = _stand(town, district, Sources.SPOT_FROM, step["from"], PROP_PART)
		_markers[district] = made
	_show_carried(_any_carrying())


## Stands the markers of a job that is on offer and has none (or lost them), and takes down
## those of a job that is no longer on offer.
func _check_markers() -> void:
	for id: String in _sources.ids():
		var wanted: bool = _sources.is_open(id) and town_of(id) != null
		var standing: bool = marker(id, Sources.SPOT_AT) != null
		if wanted != standing:
			refresh(id)


func _stand(town: TownSite, district: String, spot: String, at: Vector2, prop: String) -> Node3D:
	var m: Node3D = _prop(prop)
	m.name = "Source_%s_%s" % [district, spot]
	m.transform = town.source_frame() * Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y))
	town.add_child(m)
	if _sources.active_spot(district) == spot:
		m.add_child(_ring())
	if _interactables:
		_interactables.register(m, _sources.reach_m(), _prompt.bind(district), _use.bind(district), _usable.bind(district, spot))
	return m


func _drop_markers(district: String) -> void:
	for v: Variant in (_markers.get(district, {}) as Dictionary).values():
		if is_instance_valid(v):
			if _interactables:
				_interactables.unregister(v as Node3D)
			(v as Node3D).queue_free()
	_markers.erase(district)


func _usable(district: String, spot: String) -> bool:
	return _sources.active_spot(district) == spot and not _sources.is_engaged(district)


func _prompt(district: String) -> String:
	var line: String = tr(_sources.prompt(district))
	var cost: Dictionary = _sources.card(district).get("cost", {})
	if not cost.is_empty():
		line = tr("%s (%s)") % [line, Currencies.cost_text(cost)]
	return "E   " + line


func _use(district: String) -> void:
	if _sources.use(district):
		Audio.play("chime", 1.0, -10.0)
	elif not _sources.can_afford(district):
		EventBus.toast.emit(tr("You need %s for this.") % Currencies.cost_text(_sources.card(district).get("cost", {})), "info")


func _on_changed(district: String) -> void:
	refresh(district)


func _on_site_built(i: int, _prefab: SitePrefab) -> void:
	var district: String = _districts.district_of_site(i) if _districts else ""
	if district != "" and _sources.has(district):
		refresh.call_deferred(district)


func _lumi() -> Node3D:
	var v: Variant = _player_fn.call() if _player_fn.is_valid() else null
	return v as Node3D if is_instance_valid(v) and (v as Node3D).is_inside_tree() else null


func _any_carrying() -> bool:
	for id: String in _sources.ids():
		if _sources.is_carrying(id):
			return true
	return false


func _show_carried(on: bool) -> void:
	if on and _carried == null:
		_carried = _prop(PROP_PART)
		_carried.name = "CarriedPart"
		_carried.scale = Vector3.ONE * 0.7
		add_child(_carried)
	elif not on and _carried != null:
		_carried.queue_free()
		_carried = null


# --- The marker kit (salvaged site gear: paint, bare steel, Lumi's cyan on what she must use) ---

func _prop(kind: String) -> Node3D:
	var root := Node3D.new()
	match kind:
		PROP_VALVE:
			_part(root, _cyl(0.07, 1.0), Vector3(0, 0.5, 0), SAFETY_YELLOW)
			var wheel := TorusMesh.new()
			wheel.inner_radius = 0.2
			wheel.outer_radius = 0.3
			_part(root, wheel, Vector3(0, 1.05, 0), VALVE_RED)
		PROP_LEVER:
			_part(root, _box(Vector3(0.5, 0.9, 0.35)), Vector3(0, 0.45, 0), STEEL)
			_part(root, _box(Vector3(0.52, 0.12, 0.37)), Vector3(0, 0.82, 0), SAFETY_YELLOW)
			_part(root, _cyl(0.035, 0.7), Vector3(0.12, 1.15, 0), VALVE_RED).rotation.z = -0.5
		PROP_JAM:
			for sx: float in [-0.45, 0.45]:
				_part(root, _cyl(0.04, 1.0), Vector3(sx, 0.5, 0), SAFETY_YELLOW)
			_part(root, _box(Vector3(1.0, 0.16, 0.05)), Vector3(0, 0.82, 0), SAFETY_YELLOW)
			_part(root, _box(Vector3(1.0, 0.16, 0.05)), Vector3(0, 0.42, 0), VALVE_RED)
		PROP_PART:
			_part(root, _box(Vector3(0.8, 0.6, 0.6)), Vector3(0, 0.3, 0), CRATE_CREAM)
			_part(root, _box(Vector3(0.82, 0.14, 0.62)), Vector3(0, 0.34, 0), CRATE_TEAL)
		_:
			_part(root, _cyl(0.6, 0.08), Vector3(0, 0.04, 0), STEEL)
			_part(root, _cyl(0.06, 0.5), Vector3(0, 0.3, 0), SAFETY_YELLOW)
	return root


func _part(root: Node3D, mesh: Mesh, at: Vector3, colour: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	var mat := StandardMaterial3D.new()
	mat.albedo_color = colour
	mat.roughness = 0.7
	mat.metallic = 0.2
	mi.material_override = mat
	root.add_child(mi)
	return mi


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _cyl(r: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = 12
	return c


## Lumi's cyan ring on the ground round the spot she must use.
func _ring() -> MeshInstance3D:
	if _ring_mat == null:
		_ring_mat = StandardMaterial3D.new()
		_ring_mat.albedo_color = LUMI_CYAN
		_ring_mat.emission_enabled = true
		_ring_mat.emission = LUMI_CYAN
		_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var ring := TorusMesh.new()
	ring.inner_radius = RING_R - 0.06
	ring.outer_radius = RING_R
	var mi := MeshInstance3D.new()
	mi.mesh = ring
	mi.position = Vector3(0, 0.06, 0)
	mi.material_override = _ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
