class_name FieldBenchSites
extends Node3D
## Shows the field benches (rules: systems/camp/field_benches.gd) and takes the E press at them.
## For each city with a kit or a bench, a FieldBenchModel stands on its site prefab's bench anchor
## (by the landing pad) while the site is built; a reach point that never goes away carries the
## Interactables entry: E at a kit sets the bench up, E at a bench opens the workbench (open_fn).
## Arriving in a new city says the kit is there (a toast); setting it up plays its moment.
## Queries for the slice: ready_near(pos) (the bench Lumi can use here), nearest(pos) (where the
## guidance beam points), at_field_bench() (Lumi stands at a field bench, not the start one).
## Use: FieldBenchSites.attach(world, site_manager, districts, interactables, patch, open_fn), then
## rules.load_state(saved, has_key).
## Dev: --field-bench-shot[=M] (with --orbit-hop=SITE): once Lumi is in a city whose kit stands, the
## bench is set up and Lumi stands M m (default SHOT_M) in front of it and a little to the side,
## the camera behind her.

const NODE_NAME: String = "FieldBenches"
## How often the models follow the sites being built and freed (s).
const SYNC_S: float = 0.5
## The reach point stands this far in front of the bench (m): Lumi works at its front edge.
const FRONT_M: float = 0.6
const FLAG_SHOT: String = "field-bench-shot"
const SHOT_M: float = 2.4
## Lumi stands this far to the side in a dev shot, so she does not hide the bench.
const SHOT_SIDE_M: float = 1.6

var rules := FieldBenches.new()
var site_manager: SiteManager
var patch: Node3D
## Opens the workbench screen (scenes/slice_orbit.gd open_upgrades).
var open_fn: Callable
## The follow camera (dev shots only).
var cam: SphereCam

var _ia: Interactables
var _reach: Dictionary[String, Node3D] = {}  # district id -> reach point (child of this node)
var _models: Dictionary = {}  # district id -> model on its site prefab (freed with the site: untyped, checked with is_instance_valid)
var _shown_ready: Dictionary[String, bool] = {}  # district id -> the model's state now
var _sync_t: float = 0.0
var _shot_done: bool = false
var _shot_settle: int = 0
var _world: Node


static func attach(world: Node, p_sm: SiteManager, p_districts: Districts, p_ia: Interactables, p_patch: Node3D, p_open: Callable) -> FieldBenchSites:
	var fb := FieldBenchSites.new()
	fb.name = NODE_NAME
	fb.site_manager = p_sm
	fb.patch = p_patch
	fb.open_fn = p_open
	fb._ia = p_ia
	fb._world = world
	fb.rules.setup(p_districts)
	world.add_child(fb)
	return fb


static func of(world: Node) -> FieldBenchSites:
	return world.get_node_or_null(NODE_NAME) as FieldBenchSites if world else null


func _enter_tree() -> void:
	if not EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.connect(_on_district_entered)


func _exit_tree() -> void:
	if EventBus.district_entered.is_connected(_on_district_entered):
		EventBus.district_entered.disconnect(_on_district_entered)


func _process(delta: float) -> void:
	_sync_t -= delta
	if _sync_t <= 0.0:
		_sync_t = SYNC_S
		sync()
		if DevHooks.has(FLAG_SHOT) and not _shot_done:
			_dev_shot()


# --- Queries ------------------------------------------------------------------------------------

## The city whose set-up bench is within reach of `pos`, or "".
func ready_near(pos: Vector3) -> String:
	for id: String in rules.set_up_ids():
		var r: Node3D = _reach.get(id) as Node3D
		if r != null and r.visible and OrbitUp.ground_dist(pos, r.global_position) < FieldBenches.reach_m():
			return id
	return ""


## Whether Lumi stands at a field bench (not the start yard's).
func at_field_bench() -> bool:
	return patch != null and patch.is_inside_tree() and ready_near(patch.global_position) != ""


## The nearest field bench to `pos` (kits too when `kits`): its reach point, or null when there is none.
func nearest(pos: Vector3, kits: bool = true) -> Variant:
	var best: Variant = null
	var best_d: float = INF
	for e: Dictionary in rules.shown():
		if not kits and not bool(e["ready"]):
			continue
		var at: Vector3 = point_of(str(e["id"]))
		var d: float = pos.distance_to(at)
		if d < best_d:
			best_d = d
			best = at
	return best


## Where the bench of city `id` is (its reach point while the site is built, else the landing pad).
func point_of(id: String) -> Vector3:
	var r: Node3D = _reach.get(id) as Node3D
	if r != null and r.visible:
		return r.global_position
	var site: int = rules.districts.site_of(id) if rules.districts else -1
	return site_manager.pad_xf(site).origin if site_manager and site >= 0 else Vector3.ZERO


# --- Showing ------------------------------------------------------------------------------------

## Puts each kit or bench on its built site and its reach point beside it; hides the reach of sites
## that are not built.
func sync() -> void:
	if site_manager == null:
		return
	for e: Dictionary in rules.shown():
		var id: String = str(e["id"])
		var reach: Node3D = _reach_of(id)
		var p: SitePrefab = site_manager.prefab(int(e["site"]))
		if p == null or not p.is_built or not p.is_inside_tree():
			reach.visible = false
			continue
		var m: FieldBenchModel = _model_on(id, p)
		var xf: Transform3D = p.anchor_local("bench")
		if not m.transform.is_equal_approx(xf):
			m.transform = xf
		if _shown_ready.get(id, not bool(e["ready"])) != bool(e["ready"]):
			m.set_ready(bool(e["ready"]), false)
			_shown_ready[id] = bool(e["ready"])
		reach.global_transform = m.global_transform * Transform3D(Basis(), Vector3(0, 0, FRONT_M))
		reach.visible = true


func _reach_of(id: String) -> Node3D:
	var r: Node3D = _reach.get(id) as Node3D
	if r != null:
		return r
	r = Node3D.new()
	r.name = "Reach_" + id
	r.visible = false
	add_child(r)
	_reach[id] = r
	if _ia:
		_ia.register(r, FieldBenches.reach_m(), prompt.bind(id), use.bind(id))
	return r


## The model on prefab `p` (made again when the site was freed and built anew).
func _model_on(id: String, p: SitePrefab) -> FieldBenchModel:
	var m: FieldBenchModel = _models.get(id) as FieldBenchModel if is_instance_valid(_models.get(id)) else null
	if m != null and m.get_parent() == p:
		return m
	m = FieldBenchModel.new()
	m.name = "FieldBench"
	p.add_child(m)
	m.build(FieldBenches.look_of(id))
	_models[id] = m
	_shown_ready.erase(id)
	return m


# --- E at a bench --------------------------------------------------------------------------------

func prompt(id: String) -> String:
	if rules.is_set_up(id):
		return tr("E   Open the field bench")
	if FieldBenches.cost().is_empty():
		return tr("E   Set up the field bench")
	return tr("E   Set up the field bench for %s") % HubPanel.cost_text(FieldBenches.cost())


func use(id: String) -> void:
	if rules.is_set_up(id):
		if open_fn.is_valid():
			open_fn.call()
		return
	set_up(id, true)


## Sets the bench in `id` up (pays) and shows it. `animate`: the set-up moment and its toast.
func set_up(id: String, animate: bool) -> bool:
	var why: String = rules.block_reason(id)
	if why != "" or not rules.set_up(id):
		if animate:
			Audio.play("buzz", 1.2, -8.0)
			EventBus.toast.emit(why, "info")
		return false
	var m: FieldBenchModel = _models.get(id) as FieldBenchModel if is_instance_valid(_models.get(id)) else null
	if m != null and m.is_inside_tree():
		m.set_ready(true, animate)
		_shown_ready[id] = true
	if animate:
		Audio.play("hydraulic", 1.0, -6.0)
		Audio.play("chime", 1.0, -4.0)
		EventBus.toast.emit(tr("Field bench set up. Upgrades, research and robots work here now."), "info")
	return true


func _on_district_entered(id: String) -> void:
	if rules.offered(id):
		EventBus.toast.emit(tr("A field bench kit waits by the landing pad. Press %s at it to set it up.") % Settings.glyph("interact"), "info")


## Dev (--field-bench-shot): the bench of the city Lumi is in, set up, with Lumi in front of it.
func _dev_shot() -> void:
	var id: String = rules.districts.current_id() if rules.districts else ""
	var r: Node3D = _reach.get(id) as Node3D
	var os: OrbitSites = OrbitSites.of(_world)
	if id == "" or r == null or not r.visible or not (rules.offered(id) or rules.is_set_up(id)) or (os != null and os.hop.flying):
		_shot_settle = 0
		return
	_shot_settle += 1
	if _shot_settle < 4:  # two seconds on the ground after the landing
		return
	if not rules.is_set_up(id):
		set_up(id, false)
	_shot_done = true
	var m: FieldBenchModel = _models.get(id) as FieldBenchModel
	var up: Vector3 = m.global_position.normalized()
	var out: Vector3 = m.global_basis.z.normalized()
	out = (out - up * out.dot(up)).normalized()
	var side: Vector3 = up.cross(out).normalized()
	var stand: Vector3 = m.global_position + out * DevHooks.get_f(FLAG_SHOT, SHOT_M) + side * SHOT_SIDE_M
	var face: Vector3 = m.global_position - stand
	face = (face - up * face.dot(up)).normalized()
	(patch as Patch).place_on_sphere(stand + up * 0.3, face)
	if cam:
		cam.reset_frame(face)
		cam.snap()
	print("[field-bench] %s bench set up, Lumi %.1f m in front" % [id, DevHooks.get_f(FLAG_SHOT, SHOT_M)])
