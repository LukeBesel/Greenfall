class_name Stations
extends Node3D
## Bale automation and "remove it for good" at the base. Owns three optional machines:
##   Conveyor feeder (automation/conveyor.gd): hopper pad + belt into the depot scale.
##   Auto-baler (automation/auto_baler.gd): a field press cleaner robots tip their hoppers into.
##   Recycler (automation/recycler.gd): shreds and smelts bales into bolts + building stock.
## Bought in the Hub tab (ui/stations_panel.gd). State: GameState.world["stations"].
## Robots call the static hooks (claim_dump / dump_step / haul_drop / on_feeder).
## Dev hooks: --stations=all (or conveyor,baler,recycler) builds them free, --route=N sets auto-route,
## --stations-demo puts bales on the belts, --stations-pose=K freezes the baler at press progress K.

const HOPPER_POS := Vector3(7.0, 0.0, -0.8)
const RECYCLER_POS := Vector3(7.0, 0.0, -4.8)
const DEMO_BALER_POS := Vector3(-5.8, 0.0, -2.2)
## Auto-route settings: 0 = off, N = every Nth bale on the feeder goes to the recycler.
const ROUTES: Array[int] = [0, 4, 2, 1]

var world: Node
var data: Dictionary = {}
var conveyor: Conveyor
var baler: AutoBaler
var recycler: Recycler
var route_n: int = 0
var route_count: int = 0


func _ready() -> void:
	add_to_group("stations")
	add_to_group("persist")
	data = Economy.read_json("res://data/stations.json")
	var st: Dictionary = state()
	route_n = int(st.get("route_n", 0))
	route_count = int(st.get("route_count", 0))
	if DevHooks.has("stations"):
		var which: String = DevHooks.get_s("stations", "all")
		for id: String in ["conveyor", "recycler"]:
			if which == "all" or which == "1" or id in which:
				st[id] = true
		if (which == "all" or which == "1" or "baler" in which) and not st.has("baler"):
			st["baler"] = {"pos": [DEMO_BALER_POS.x, DEMO_BALER_POS.z]}
		if DevHooks.has("route"):
			route_n = int(DevHooks.get_f("route", 2.0))
	if st.get("conveyor", false):
		_spawn_conveyor()
	if st.get("recycler", false):
		_spawn_recycler()
	if st.has("baler"):
		var p: Array = st["baler"].get("pos", [DEMO_BALER_POS.x, DEMO_BALER_POS.z])
		_spawn_baler(Vector3(float(p[0]), 0.0, float(p[1])), false)
		baler.restore(st["baler"])
	_restore_held(st.get("held", []))
	st.erase("held")
	if DevHooks.has("stations-demo"):
		_demo_feed.call_deferred()


static func of(n: Node) -> Stations:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group("stations") as Stations


func state() -> Dictionary:
	if not GameState.world.has("stations"):
		GameState.world["stations"] = {}
	return GameState.world["stations"]


func def(id: String) -> Dictionary:
	return data.get(id, {})


func hub_level() -> int:
	if world and world.get("hub") != null:
		return int(world.hub.level)
	return int(GameState.world.get("hub_level", 1))


## Upgrade multipliers (data/upgrades.json tab "hub"; bases of 1.0 in data/patch.json).
static func belt_mult() -> float:
	return maxf(Economy.stat("belt_speed"), 0.1)


static func baler_mult() -> float:
	return maxf(Economy.stat("baler_speed"), 0.1)


static func yield_mult() -> float:
	return maxf(Economy.stat("recycler_yield"), 0.1)


# --- Building ----------------------------------------------------------------------

func built(id: String) -> bool:
	match id:
		"conveyor":
			return conveyor != null
		"auto_baler":
			return baler != null
		"recycler":
			return recycler != null
	return false


## "" when it can be built now, else why not.
func block_reason(id: String) -> String:
	if built(id):
		return tr("Built.")
	# Research gate. Runs after built() so stations already standing in older saves (or placed by
	# the --stations dev hook) stay usable.
	if Research.exists(id) and not Research.has(id):
		return tr("Requires research: %s.") % tr(str(Research.def(id).get("name", id)))
	var d: Dictionary = def(id)
	if hub_level() < int(d.get("requires_level", 1)):
		return tr("Requires hub level %d.") % int(d.get("requires_level", 1))
	if not Hub.can_pay(d.get("cost", {})):
		return tr("Not enough materials.")
	return ""


func build(id: String) -> bool:
	if block_reason(id) != "":
		return false
	if not Hub.pay(def(id).get("cost", {})):
		return false
	var st: Dictionary = state()
	match id:
		"conveyor":
			st["conveyor"] = true
			_spawn_conveyor()
			conveyor.build_in()
			EventBus.toast.emit(tr("Conveyor Feeder online. Drop bales on the yellow pad."), "story")
		"recycler":
			st["recycler"] = true
			_spawn_recycler()
			recycler.build_in()
			EventBus.toast.emit(tr("Recycler lit. Bales that go in here are gone for good."), "story")
		"auto_baler":
			var p: Vector3 = frontier_pos()
			_spawn_baler(p, true)
			st["baler"] = baler.to_dict()
			EventBus.toast.emit(tr("Auto-baler dropped at the cleaning frontier. Cleaners will tip their hoppers into it."), "story")
	Audio.play("buy", 1.0, -2.0)
	return true


## Moves the auto-baler to the current cleaning frontier (small fee).
func relocate_baler() -> bool:
	if baler == null or not baler.idle():
		return false
	if not Hub.pay(def("auto_baler").get("relocate_cost", {})):
		return false
	baler.drop_at(frontier_pos())
	state()["baler"] = baler.to_dict()
	return true


## A clean, open spot next to the most junk: the clean (or yard) hex closest to the centroid of
## what is left, weighted by remaining junk.
func frontier_pos() -> Vector3:
	if world == null or world.get("field") == null:
		return DEMO_BALER_POS
	var field: HexField = world.field
	var c := Vector3.ZERO
	var wsum: float = 0.0
	for id: int in field.hex_count():
		if field.hex_hub[id] != 0 or field.is_clean(id) or field.is_water(id):
			continue
		var w: float = 1.0 - field.removed_fraction(id)
		c += field.hex_center(id) * w
		wsum += w
	if wsum <= 0.0:
		return DEMO_BALER_POS
	c /= wsum
	var best: int = -1
	var best_d: float = INF
	for id: int in field.hex_count():
		if field.hex_hub[id] == 2 or field.is_water(id) or not field.is_clean(id):
			continue
		var hc: Vector3 = field.hex_center(id)
		if hc.length() < 9.0:
			continue  # keep the base yard free
		var d: float = hc.distance_squared_to(c)
		if d < best_d:
			best_d = d
			best = id
	if best < 0:
		var dir: Vector3 = Vector3(c.x, 0, c.z).normalized()
		return dir * 10.0 if dir != Vector3.ZERO else DEMO_BALER_POS
	var p: Vector3 = field.hex_center(best)
	return Vector3(p.x, 0.0, p.z)


func _spawn_conveyor() -> void:
	if conveyor:
		return
	conveyor = Conveyor.new()
	conveyor.name = "Conveyor"
	conveyor.stations = self
	add_child(conveyor)
	if recycler:
		conveyor.add_recycler_line()


func _spawn_recycler() -> void:
	if recycler:
		return
	recycler = Recycler.new()
	recycler.name = "Recycler"
	recycler.stations = self
	recycler.position = RECYCLER_POS
	add_child(recycler)
	if conveyor:
		conveyor.add_recycler_line()


func _spawn_baler(pos: Vector3, animate: bool) -> void:
	if baler == null:
		baler = AutoBaler.new()
		baler.name = "AutoBaler"
		baler.stations = self
		add_child(baler)
	if animate:
		baler.drop_at(pos)
	else:
		baler.place(pos)


# --- Routing -----------------------------------------------------------------------

## Where the next bale on the feeder goes: "recycler" every Nth bale (if built), else "depot".
func next_route() -> String:
	if recycler == null or route_n <= 0:
		return "depot"
	route_count += 1
	if route_count % route_n == 0:
		return "recycler"
	return "depot"


func cycle_route() -> void:
	var i: int = ROUTES.find(route_n)
	route_n = ROUTES[(i + 1) % ROUTES.size()]
	route_count = 0
	state()["route_n"] = route_n


static func route_text(n: int) -> String:
	match n:
		0:
			return TranslationServer.translate("Off: every bale to the scale")
		1:
			return TranslationServer.translate("All bales to the recycler")
		2:
			return TranslationServer.translate("Every 2nd bale to the recycler")
		3:
			return TranslationServer.translate("Every 3rd bale to the recycler")
	return TranslationServer.translate("Every %dth bale to the recycler") % n


# --- Robot hooks (robots/robot.gd) ----------------------------------------------------

## Cleaner with a full hopper: head for the auto-baler instead of baling on the spot.
static func claim_dump(r: Robot) -> bool:
	# Only cleaners tip into the baler: a Skimmer (or a Multibot on another job) would set
	# dump_to that its think step never reads and loop at the shore forever.
	if r.role() != "clean":
		return false
	var s: Stations = of(r)
	if s == null or s.baler == null or r.hopper.is_empty() or r.hopper.pending > 0.0:
		return false
	if not s.baler.can_accept(r.hopper.fill):
		return false
	if r.global_position.distance_to(s.baler.global_position) > float(s.def("auto_baler").get("service_range", 34.0)):
		return false
	r.set_meta("dump_to", s.baler)
	return true


## One think step while driving to the auto-baler. Tips the hopper on arrival.
static func dump_step(r: Robot) -> Vector3:
	var b: AutoBaler = r.get_meta("dump_to", null) as AutoBaler
	if b == null or not is_instance_valid(b) or r.hopper.is_empty():
		r.remove_meta("dump_to")
		return Vector3.ZERO
	var m: Vector3 = r._steer(b.dump_point(), 0.8)
	if m == Vector3.ZERO:
		var from: Vector3 = r.global_position + Vector3(0, 0.8, 0)
		b.accept(r.hopper.take_all(), from)
		r._busy = 1.0
		r.remove_meta("dump_to")
		GameState.inc_stat("robot_dumps")
	return m


## Hauler drop-off: the conveyor hopper when it is closer than the scale.
static func haul_drop(r: Node3D, depot_pos: Vector3) -> Vector3:
	var s: Stations = of(r)
	if s == null or s.conveyor == null:
		return depot_pos
	if s.world and s.world.get("depot") != null and (s.world.depot as Depot).pad_contains(r.global_position):
		return depot_pos
	var hp: Vector3 = s.conveyor.hopper_pos()
	if r.global_position.distance_squared_to(hp) < r.global_position.distance_squared_to(depot_pos):
		return hp
	return depot_pos


## True for bales sitting on a feeder pad (haulers leave those alone).
static func on_feeder(c: JunkCube) -> bool:
	var s: Stations = of(c)
	if s == null:
		return false
	return (s.conveyor != null and s.conveyor.pad_contains(c.global_position)) \
		or (s.recycler != null and s.recycler.pad_contains(c.global_position))


# --- Helpers -----------------------------------------------------------------------

func patch_node() -> Node3D:
	return world.get("patch") if world and world.get("patch") != null else null


## Puts a bale back into the world as a loose physics body.
func release_cube(c: JunkCube, pos: Vector3, vel: Vector3 = Vector3.ZERO) -> void:
	var root: Node = world.get_node_or_null("Cubes") if world else null
	if root == null:
		root = self
	if c.get_parent() != root:
		if c.get_parent():
			c.reparent(root, true)
		else:
			root.add_child(c)
	c.global_position = pos
	c.claimed = false
	c.set_meta("reserved", false)
	c.set_carried(false)
	c.linear_velocity = vel


func add_loose(c: JunkCube, pos: Vector3) -> void:
	if world and world.has_method("add_cube"):
		world.add_cube(c)
	else:
		add_child(c)
	c.global_position = pos


func persist_save() -> void:
	var st: Dictionary = state()
	st["route_n"] = route_n
	st["route_count"] = route_count
	if baler:
		st["baler"] = baler.to_dict()
	var held: Array = []
	if conveyor:
		held.append_array(conveyor.held_dicts())
	if recycler:
		held.append_array(recycler.held_dicts())
	if baler:
		held.append_array(baler.held_dicts())
	st["held"] = held


func _restore_held(list: Array) -> void:
	var i: int = 0
	for cd: Dictionary in list:
		var c: JunkCube = JunkCube.from_dict(cd)
		var base: Vector3 = conveyor.hopper_pos() if conveyor else Vector3(1.5, 0, 1.5)
		add_loose(c, base + Vector3(-0.5 + (i % 3) * 0.5, 0.5 + (i / 3) * 0.6, -0.4 + (i % 2) * 0.6))
		i += 1


func _demo_feed() -> void:
	# Bales already riding the belts (and one on the pad) so screenshots show the line working.
	var kinds: Array = ["metal", "plastic", "glass", "rubber", "paper", "electronics"]
	var made: Array[JunkCube] = []
	for k: int in 6:
		var dom: String = kinds[k % kinds.size()]
		var cols: Array[Color] = [Color.html(str(Economy.junk_types.get(dom, {}).get("cube_color", "#888888")))]
		var c: JunkCube = JunkCube.create(BigNum.from_float(20.0 + k), {"fill": 0.85 + 0.05 * (k % 3), "colors": cols, "volume": 12.0, "dominant": dom})
		add_loose(c, (conveyor.hopper_pos() if conveyor else Vector3(1.5, 0, 0)) + Vector3(0, 0.7, 0))
		made.append(c)
	if conveyor:
		conveyor.demo_load(made)
	if baler:
		baler.accept({"metal": 9.0, "plastic": 7.0}, baler.global_position + Vector3(0, 2.5, -2.0))
		if DevHooks.has("stations-pose"):
			# Freeze the press mid-stroke for a screenshot.
			baler._start_press()
			baler._t = baler._dur * DevHooks.get_f("stations-pose", 0.3)
			baler._update_visuals(0.0)
			baler.set_physics_process(false)
