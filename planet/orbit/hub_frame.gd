class_name HubFrame
extends Node3D
## [orbB] Per-hub frame for flat-yard systems on the globe (fauna, eggs, outposts, the Ledger,
## Garden Mode's decor). This node stands on the hub site Lumi is nearest (the site transform:
## site-local metres, +Y up, y = 0 on the pad), so a system parented here keeps its flat-game
## coordinates and maths; it converts only at its edges (to_local / to_global, the globe ground).
## When Lumi comes within WAKE_M of another hub (a walk or a rocket hop) the frame moves there and
## its systems are rebuilt for that hub; farther than SLEEP_M from every hub (the wild between
## hubs) they are freed and sleep until Lumi reaches a hub again.
## Use: frame.host("Fauna", func(f: HubFrame, hub: int) -> Node: ...) makes the node for a hub.

signal hub_changed(hub: int)  # -1: asleep

const WAKE_M: float = 220.0
const SLEEP_M: float = 320.0
const POLL_S: float = 0.5

var so: SliceOrbit
var hub: int = -1
var _hosts: Dictionary = {}  # name -> Callable(frame, hub) -> Node
var _t: float = 0.0


func setup(p_so: SliceOrbit) -> void:
	so = p_so
	name = "HubFrame"
	add_to_group("hub_frame")
	check_now()


## Registers a system made per hub; it is built right away when a hub is near.
func host(key: String, make: Callable) -> void:
	_hosts[key] = make
	if hub >= 0:
		_build(key)


func node(key: String) -> Node:
	return get_node_or_null(NodePath(key))


## The hub region's cells (the cells that count for planet %).
func region() -> PackedInt32Array:
	if hub < 0:
		return PackedInt32Array()
	if not _regions.has(hub):  # [v6qa] a few thousand cells' ring walk, asked by every system of a switch: once per hub
		var g: OrbitPlanet = so.globe
		_regions[hub] = g.grid.cells_around(int(g.sites[hub]["cell"]), SiteManager.REGION_RINGS)
	return _regions[hub]


var _regions: Dictionary = {}  # [v6qa] hub -> its region's cells


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL_S
	check_now(true)


## spread [v5load]: build a new hub's systems one a frame (the play poll); tools and the build call
## it without and get everything at once.
func check_now(spread: bool = false) -> void:
	var patch: Node3D = so.w.get("patch") if so else null
	if patch == null or so.globe == null or so.globe.sites.is_empty():
		return
	var g: OrbitPlanet = so.globe
	var best: int = -1
	var best_m: float = INF
	for s: Dictionary in g.sites:
		var m: float = g.grid.great_circle_m(patch.global_position, g.grid.centers[int(s["cell"])])
		if m < best_m:
			best_m = m
			best = int(s["index"])
	var cur_m: float = g.grid.great_circle_m(patch.global_position, g.grid.centers[int(g.sites[hub]["cell"])]) if hub >= 0 else INF
	if _switching:
		return
	if _pinned:  # [v5load] switched early (a rocket hop's veil): stay until Lumi has arrived
		if cur_m < WAKE_M:
			_pinned = false
		return
	if hub >= 0 and cur_m > SLEEP_M:
		_set_hub(-1)
	if best >= 0 and best != hub and best_m < WAKE_M and _site_ready(best):
		if spread and is_inside_tree():
			_set_hub_spread(best)  # [v5load] in play: a system a frame
		else:
			_set_hub(best)


## [v4world] Owner playtest 3 #55: a hub's outposts, eggs and relay are placed only once its town
## is built, so its buildings' footprints are known and nothing lands inside one.
func _site_ready(i: int) -> bool:
	var sm: Variant = so.globe.get("site_manager") if so and so.globe else null
	if not (sm is SiteManager):
		return true
	var p: SitePrefab = (sm as SiteManager).prefab(i)
	return p != null and p.is_built


# [v5load] Building a hub's five systems in one frame was a 1.3 s freeze each time Lumi came
# within WAKE_M of another hub (a walk, the sled, or the last seconds of a rocket hop's landing).
var _switching: bool = false
var _pinned: bool = false


## A rocket hop calls this behind its veil, once the target's town is built: the frame moves there
## now (hidden) and stays until Lumi has landed.
func switch_to(i: int) -> void:
	if i == hub or _switching or not _site_ready(i):
		return
	_set_hub(i)
	_pinned = true


## _set_hub in play: the old systems go at once, the new ones are built one a frame.
const SWITCH_SLICE_US: int = 5000  # [v6qa]


func _set_hub_spread(i: int) -> void:
	_switching = true
	for key: String in _hosts:
		var old: Node = node(key)
		if old:
			if old.has_method("persist_save"):
				old.call("persist_save")
			remove_child(old)
			old.queue_free()
	hub = i
	global_transform = so.globe.sites[i]["transform"]
	hub_changed.emit(i)  # the old systems are gone: nobody keeps a freed node
	# [v6qa] A play budget for the switch: the systems that yield to a BuildBudget (the eggs' plan and
	# spawns, the outposts one by one) spread their work over frames instead of one long frame each
	# (walk-in: eggs 1.3 s, outposts 0.5 s in one frame each).
	var own: BuildBudget = BuildBudget.begin_play(get_tree(), SWITCH_SLICE_US) if BuildBudget.current == null else null
	for key: String in _hosts:
		await get_tree().process_frame
		if not is_inside_tree() or hub != i:
			if own and BuildBudget.current == own:
				BuildBudget.end()
			_switching = false
			return
		var h: int = Hitch.t()
		_build(key)
		Hitch.mark("hub frame " + key, h)
		await BuildBudget.idle()  # [v6qa] its spread work done before the next system
		var nn: Node = node(key)
		while BuildBudget.current != null and is_instance_valid(nn) and nn.get("building") == true:
			await BuildBudget.pause("hub frame " + key)
	if own and BuildBudget.current == own:
		BuildBudget.end()
	_switching = false
	hub_changed.emit(i)
	print("[hubframe] hub %d" % i)


func _set_hub(i: int) -> void:
	for key: String in _hosts:  # the old hub's systems go (their state lives in GameState)
		var old: Node = node(key)
		if old:
			if old.has_method("persist_save"):
				old.call("persist_save")
			remove_child(old)
			old.queue_free()
	hub = i
	if i >= 0:
		global_transform = so.globe.sites[i]["transform"]
		for key: String in _hosts:
			_build(key)
	hub_changed.emit(i)
	print("[hubframe] %s" % ("hub %d" % i if i >= 0 else "asleep (between hubs)"))


func _build(key: String) -> void:
	var make: Callable = _hosts[key]
	var n: Node = make.call(self, hub)
	if n:
		n.name = key
		if n.get_parent() == null:
			add_child(n)
