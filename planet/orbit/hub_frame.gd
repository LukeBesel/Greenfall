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
## The ground round a hub that the frame's systems place things on, in rings of hexes (about
## SLEEP_M). A placement area, not a district: districts have their own sizes (systems/districts.gd).
const AREA_RINGS: int = 18

var so: SliceOrbit
var hub: int = -1
var _hosts: Dictionary = {}  # name -> Callable(frame, hub) -> Node
var _t: float = 0.0


func setup(p_so: SliceOrbit) -> void:
	so = p_so
	name = "HubFrame"
	check_now()


## Registers a system made per hub; it is built right away when a hub is near.
func host(key: String, make: Callable) -> void:
	_hosts[key] = make
	if hub >= 0:
		_build(key)


func node(key: String) -> Node:
	return get_node_or_null(NodePath(key))


## The cells round the hub that the frame's systems place things on (AREA_RINGS rings).
func region() -> PackedInt32Array:
	if hub < 0:
		return PackedInt32Array()
	var g: OrbitPlanet = so.globe
	return g.grid.cells_around(int(g.sites[hub]["cell"]), AREA_RINGS)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = POLL_S
	check_now()


func check_now() -> void:
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
	if hub >= 0 and cur_m > SLEEP_M:
		_set_hub(-1)
	if best >= 0 and best != hub and best_m < WAKE_M and _site_ready(best):
		_set_hub(best)


## [v4world] Owner playtest 3 #55: a hub's outposts, eggs and relay are placed only once its town
## is built, so its buildings' footprints are known and nothing lands inside one.
func _site_ready(i: int) -> bool:
	var sm: Variant = so.globe.get("site_manager") if so and so.globe else null
	if not (sm is SiteManager):
		return true
	var p: SitePrefab = (sm as SiteManager).prefab(i)
	return p != null and p.is_built


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
