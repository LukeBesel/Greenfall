class_name FarYard
extends Node3D
## [v10base] Every far base's own yard, on its landing pad (owner playtest 3 #104: "all bases need
## to have spots to build new workbench and locker and bot builder and all that"; #102/critic A:
## bales could not be sold away from home).
## A far base's pad is the same 21 m kit yard as base 1's, so its machines stand where base 1's do
## (site-local metres, the anchors of VerdanceSite.START_YARD_ANCHORS):
##   - the trash bin and its scale stand ready on landing, in the same marked, lit bay (west side):
##     a base where nothing can be sold has no way to pay for anything else;
##   - marked build spots (BuildSpot: hazard corners, dashed outline, the machine's picture sign)
##     for this base's workbench, locker and Bot Bay. E at a spot shows its price and builds it;
##     the machine then stands there and works like base 1's (the workbench's menu, the Locker,
##     the Bot Bay's own screen: robots built there roll out at this base).
## Built-state per base: HubPlan.state(site)["yard"][id] (saved with the orbit); the Bot Bay's is
## BotBay's own (GameState.orbit.bot_bays[site]). Prices: data/planets.json hub_defaults.yard.
## A base's yard is made the first time Lumi is there in a session and kept (a handful of nodes).
## Use: FarYard.attach(orbit_sites) after HubPurpose; FarYard.of(world).

const POLL_S: float = 0.5
## id -> [site-local position, yaw, footprint (x across, z deep; front +Z), sign id, E reach]
const SPOTS: Dictionary = {
	"bench": [Vector3(-8.0, 0, 7.5), PI * 0.5, Vector2(2.8, 1.6), "workbench", 3.0],
	"locker": [Vector3(8.5, 0, 0.2), -PI * 0.5, Vector2(1.9, 1.4), "locker", 2.4],
	"bot_bay": [Vector3(8.0, 0, 7.6), -PI * 0.5, Vector2(3.2, 2.6), "bot_bay", 2.6],
}
const ORDER: Array[String] = ["bench", "locker", "bot_bay"]
const DEPOT_AT := Vector3(-8.0, 0, 2.0)
const BIN_AT := Vector3(-8.0, 0, -1.3)
const SIDE_YAW: float = PI * 0.5

signal built(site: int, id: String)

var sites: OrbitSites
var so: SliceOrbit
var sm: SiteManager
var planet: String = "verdance"
var _t: float = 0.0
var _roots: Dictionary = {}   # site -> Node3D
var _depots: Dictionary = {}  # site -> Depot
var _models: Dictionary = {}  # "site:id" -> Node3D (the built machine)
var _e: Dictionary = {}       # "site:id" -> Node3D (the spot's E point)


static func attach(p_sites: OrbitSites) -> FarYard:
	var y := FarYard.new()
	y.name = "FarYard"
	y.sites = p_sites
	y.so = p_sites.so
	y.sm = p_sites.sm
	y.planet = p_sites.sm.planet_id if p_sites.sm else "verdance"
	p_sites.add_child(y)
	return y


static func of(world: Node) -> FarYard:
	var os_: OrbitSites = OrbitSites.of(world) if world else null
	return os_.get_node_or_null("FarYard") as FarYard if os_ else null


# --- State and prices --------------------------------------------------------------------------

static func is_built(site: int, id: String) -> bool:
	if id == "bot_bay":
		return BotBay.built(str(site))
	var st: Dictionary = HubPlan.peek(site)
	var y: Variant = st.get("yard", null)
	if y is Dictionary:
		return bool((y as Dictionary).get(id, false))
	# A save from before the build spots: a woken base had its field bench for free.
	return id == "bench" and bool(st.get("woken", false))


static func mark_built(site: int, id: String) -> void:
	var st: Dictionary = HubPlan.state(site)
	if not (st.get("yard") is Dictionary):
		st["yard"] = {"bench": is_built(site, "bench")}
	(st["yard"] as Dictionary)[id] = true
	if id == "bot_bay":
		BotBay.mark_built(str(site))
	elif id == "locker":
		GameState.flags["locker_owned"] = true


static func cost(planet_id: String, id: String) -> Dictionary:
	var y: Variant = HubPlan.defaults(planet_id).get("yard", {})
	var c: Variant = (y as Dictionary).get(id, {}) if y is Dictionary else {}
	return c if c is Dictionary else {}


static func title(id: String) -> String:
	match id:
		"bench":
			return TranslationServer.translate("Workbench")
		"locker":
			return TranslationServer.translate("Locker")
		"bot_bay":
			return TranslationServer.translate("Bot Bay")
	return id


# --- Where things are (for the card's beam, the checks) -----------------------------------------

## The far base Lumi is at, or -1 (home, or between bases).
func site() -> int:
	var s: int = sites.purpose.site if sites.purpose else -1
	return s if s > 0 and _roots.has(s) else -1


## World point in front of base `i`'s spot `id` (where Lumi stands to press E), or null.
func spot_point(i: int, id: String) -> Variant:
	var e: Node3D = _e.get("%d:%s" % [i, id]) as Node3D
	return e.global_position if e and e.is_inside_tree() else null


## The built workbench of the far base Lumi is at, else null.
func bench_point() -> Variant:
	var i: int = site()
	if i < 0 or not FarYard.is_built(i, "bench"):
		return null
	var m: Node3D = _models.get("%d:bench" % i) as Node3D
	return m.global_position if m and m.is_inside_tree() else null


## The trash bin of the far base Lumi is at or near (where the chest is emptied and bales are
## sold), else null: the nearest far yard's within NEAR_BIN_M.
const NEAR_BIN_M: float = 450.0


func bin_point() -> Variant:
	var p: Node3D = so.w.get("patch") as Node3D
	if p == null:
		return null
	var best: Variant = null
	var bd: float = NEAR_BIN_M
	for i: int in _depots:
		var d: Depot = _depots[i] as Depot
		if d and d.is_inside_tree():
			var m: float = d.global_position.distance_to(p.global_position)
			if m < bd:
				bd = m
				best = d.bin_world()
	return best


func depot(i: int) -> Depot:
	return _depots.get(i) as Depot


## The next thing to build at base i that the base's chain asks for ("" when none).
func spot_node(i: int, id: String) -> Node3D:
	var r: Node3D = _roots.get(i) as Node3D
	return r.get_node_or_null("Spot_%s/BuildSpot_%s" % [id, id]) as Node3D if r else null


# --- SitePrefab's anchor calls, for Depot.seat_bin ------------------------------------------------

func anchor(nm: String) -> Variant:
	return self if nm == "bin" else null


func anchor_local(_nm: String) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, SIDE_YAW), BIN_AT)


# --- Building the yard ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	_t += delta
	if _t < POLL_S:
		return
	_t = 0.0
	var i: int = sites.purpose.site if sites.purpose else -1
	if i <= 0 or _roots.has(i) or sites.hop.flying or HubPlan.entry(planet, i).is_empty() or not PlanetCfg.uses_towns(planet):
		return
	var p: SitePrefab = sm.prefab(i)
	if p == null or not p.is_built or so.w.get("interactables") == null:
		return
	_make(i)


func _make(i: int) -> void:
	var root := Node3D.new()
	root.name = "FarYard_%d" % i
	add_child(root)
	root.global_transform = sm.sites[i]["transform"]
	_roots[i] = root
	# The trash bin and its scale, ready on landing.
	var dep := Depot.new()
	dep.name = "Depot"
	dep.world = so.w
	dep.patch = so.w.get("patch")
	root.add_child(dep)
	dep.transform = Transform3D(Basis(Vector3.UP, SIDE_YAW), DEPOT_AT)
	dep.seat_bin(self)
	_depots[i] = dep
	root.add_child(YardSite.bin_bay(DEPOT_AT, BIN_AT))
	var ia: Interactables = so.w.get("interactables") as Interactables
	for id: String in ORDER:
		var sp: Array = SPOTS[id]
		var holder := Node3D.new()
		holder.name = "Spot_%s" % id
		holder.transform = Transform3D(Basis(Vector3.UP, float(sp[1])), sp[0])
		root.add_child(holder)
		var size: Vector2 = sp[2]
		BuildSpot.mark(holder, id, size, func() -> bool: return FarYard.is_built(i, id), Callable(), str(sp[3]))
		var e := Node3D.new()
		e.name = "E"
		e.position = Vector3(0, 0, size.y * 0.5 + 0.9)
		holder.add_child(e)
		_e["%d:%s" % [i, id]] = e
		ia.register(e, float(sp[4]),
			func() -> String: return _prompt(i, id),
			func() -> void: _use(i, id),
			func() -> bool: return is_instance_valid(e) and e.is_inside_tree() and not sites.hop.flying and (id == "locker" or not FarYard.is_built(i, id)))
		_stand(i, id, holder)
	print("[faryard] base %d (%s): bin ready; built %s" % [i, HubPlan.hub_name(planet, i), str(ORDER.filter(func(id: String) -> bool: return FarYard.is_built(i, id)))])
	if DevHooks.has("faryard-look"):
		_dev_look.call_deferred(i)
	if DevHooks.has("faryard-built"):  # dev: this base's machines stand from the start (probes)
		for id: String in ORDER:
			build(i, id, true)
	if DevHooks.has("faryard-probe"):  # dev: where the landmark stands from the pad, and what TargetReach says there
		var inv: Transform3D = root.global_transform.affine_inverse()
		var rk: Vector3 = inv * sites.sm.pad_xf(i).origin
		print("[faryard] base %d: site origin %s, rocket pad at site-local (%.1f, %.1f), Lumi at site-local %s" % [i, str(root.global_position.snapped(Vector3.ONE * 0.1)), rk.x, rk.z,
			str((inv * (so.w.get("patch") as Node3D).global_position).snapped(Vector3.ONE * 0.1)) if so.w.get("patch") else "-"])
		if DevHooks.has("faryard-probe-at"):  # a world point (x,y,z) in this site's metres
			var a: PackedStringArray = DevHooks.get_s("faryard-probe-at", "0,0,0").split(",")
			if a.size() == 3:
				print("[faryard] base %d: %s is at site-local %s" % [i, DevHooks.get_s("faryard-probe-at", ""), str((inv * Vector3(float(a[0]), float(a[1]), float(a[2]))).snapped(Vector3.ONE * 0.1))])
		var lm: Dictionary = sites.purpose.landmark(i)
		if not lm.is_empty():
			var tr_: TargetReach = TargetReach.for_world(so.w, true)
			var lp: Vector3 = root.global_transform.affine_inverse() * (lm["pos"] as Vector3)
			var d: Vector3 = (lm["pos"] as Vector3).normalized()
			print("[faryard] base %d landmark at site-local (%.1f, %.1f, %.1f); why '%s', escapes %s, open spot %.1f m off" % [i, lp.x, lp.y, lp.z,
				tr_.why(d) if tr_ else "?", str(tr_.escapes(d)) if tr_ else "?", tr_.open_spot(lm["pos"]).distance_to(lm["pos"]) if tr_ else -1.0])


## The machine on its spot (hidden until built; the Bot Bay shows itself).
func _stand(i: int, id: String, holder: Node3D) -> void:
	var m: Node3D
	match id:
		"bench":
			m = sites.purpose.make_bench()
			var sign_mi: MeshInstance3D = MachineArt.sign_post("workbench", 2.3).mi(0.15, "Sign")
			sign_mi.position = Vector3(-1.2, 0, -0.3)
			m.add_child(sign_mi)
		"locker":
			m = Node3D.new()
			m.name = "Locker"
			var body: MeshInstance3D = YardArt.locker().mi(0.12, "LockerBody")
			m.add_child(body)
			YardArt.set_powered(body, true)
			YardArt.solid(m, Vector3(1.3, 2.2, 0.75), Vector3(0, 1.1, 0), "LockerSolid")
		"bot_bay":
			var bay := BotBay.new()
			holder.add_child(bay)
			bay.setup(so.w, str(i))
			bay.transform = Transform3D.IDENTITY
			bay.reseat()
			_models["%d:%s" % [i, id]] = bay
			return
	holder.add_child(m)
	_models["%d:%s" % [i, id]] = m
	_show(m, FarYard.is_built(i, id))


static func _show(n: Node3D, on: bool) -> void:
	n.visible = on
	for c: Node in n.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = not on


# --- E at a spot -----------------------------------------------------------------------------------

func _prompt(i: int, id: String) -> String:
	if FarYard.is_built(i, id):
		return tr("E   open locker") if id == "locker" else ""
	var c: Dictionary = FarYard.cost(planet, id)
	return tr("E   Build here: %s  (%s)") % [FarYard.title(id), Currencies.cost_text(c)]


func _use(i: int, id: String) -> void:
	if FarYard.is_built(i, id):
		if id == "locker":
			var lk: LockerCabinet = so.w.get_node_or_null("LockerCabinet") as LockerCabinet
			if lk:
				lk.open()
		return
	build(i, id)


## Pays for and builds base i's machine `id` (free: the dev hooks and old saves). False when it
## can't be paid: a short line says what it needs.
func build(i: int, id: String, free: bool = false) -> bool:
	if FarYard.is_built(i, id) or not SPOTS.has(id):
		return false
	var c: Dictionary = FarYard.cost(planet, id)
	if not free and not GameState.spend_all(c):
		Audio.play("blip", 0.7, -6.0)
		EventBus.toast.emit(tr("Building it needs %s.") % Currencies.cost_text(c), "hint")
		return false
	FarYard.mark_built(i, id)
	var m: Node3D = _models.get("%d:%s" % [i, id]) as Node3D
	if m and id != "bot_bay":
		_show(m, true)
		m.scale = Vector3(1, 0.05, 1)  # it rises out of its marked spot
		create_tween().tween_property(m, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if m:
		Vfx.burst("sparkle", m.global_position + m.global_basis.y * 1.0, Color(1.0, 0.8, 0.4), 0.6)
	Audio.play("hydraulic", 1.0, -6.0)
	Audio.play("chime", 1.0, -4.0)
	GameState.inc_stat("far_builds")
	EventBus.toast.emit(tr("Built: %s. It is this base's own.") % FarYard.title(id), "info")
	print("[faryard] base %d: built %s" % [i, id])
	built.emit(i, id)
	return true


## Dev: --faryard-look=PREFIX (a rendered run with --orbit-hop=N --hop-skip): at the first far
## base Lumi lands on, frames of what the player sees: Lumi by the rocket as after landing
## (PREFIX_rocket.png: the prompt, the base's name and WREN on one spot was play-tester item 22),
## the pad with its bin bay and marked spots (PREFIX_pad.png), then this base's Workbench, Locker
## and Bot Bay built (free) and each seen from in front of its spot (PREFIX_<id>.png); then quits.
## --faryard-look-wait=S: seconds after the yard is made before the first frame (the title fades).
func _dev_look(i: int) -> void:
	var pre: String = DevHooks.get_s("faryard-look", "screenshots/v10/faryard")
	var p: Patch = so.w.get("patch") as Patch
	var cam: Node = p.sphere_cam if p else null
	var root: Node3D = _roots[i] as Node3D
	var pad: Transform3D = sm.pad_xf(i)
	await DevHooks.wait_wall_for(DevHooks.get_f("faryard-look-wait", 8.0))
	var looks: Array = [["rocket", pad * Vector3(4.5, 0, 3.0), pad.origin],
		["pad", root.global_transform * Vector3(4.0, 0, 9.5), root.global_transform * Vector3(-6.0, 0, 1.0)]]
	for lk: Array in looks:
		_dev_stand(p, cam, lk[1], lk[2])
		await DevHooks.wait_wall_for(3.0)
		await RenderingServer.frame_post_draw
		DevHooks.save_viewport("%s_%s.png" % [pre, lk[0]])
		print("[faryard] look %s: prompt '%s'" % [lk[0], str(p.prompt) if p else "-"])
	for id: String in ORDER:
		build(i, id, true)
	await DevHooks.wait_wall_for(2.0)
	for id: String in ORDER:
		var e: Node3D = _e["%d:%s" % [i, id]]
		var h: Node3D = e.get_parent() as Node3D
		var out: Vector3 = e.global_position - h.global_position
		_dev_stand(p, cam, e.global_position + out.normalized() * 1.2, h.global_position)
		await DevHooks.wait_wall_for(3.0)
		await RenderingServer.frame_post_draw
		DevHooks.save_viewport("%s_%s.png" % [pre, id])
		print("[faryard] look %s: prompt '%s'" % [id, str(p.prompt) if p else "-"])
	get_tree().quit()


func _dev_stand(p: Patch, cam: Node, at: Vector3, look: Vector3) -> void:
	if p == null:
		return
	var g: Vector3 = so.globe.terrain.ground(at.normalized())
	var up: Vector3 = g.normalized()
	var fwd: Vector3 = look - g
	fwd = (fwd - up * fwd.dot(up)).normalized()
	p.place_on_sphere(g, fwd)
	if cam and cam.has_method("reset_frame"):
		cam.call("reset_frame", fwd)
