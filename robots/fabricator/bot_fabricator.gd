class_name BotFabricator
extends Node
## [orbC] The Bot Fabricator: a bot-building bot (owner, Nov 8). A Hub build (data/builds.json
## bot_fabricator, systems/camp/hub_builds.gd) unlocked from the 3rd campaign planet (Tidewell)
## on. Once built at a planet's base it builds robots by itself from cubes and parts, following a
## mix the player sets in its one panel (ui/fabricator_panel.gd: a weight per robot type, and
## pause). Each new robot joins the hub with the fewest robots and goes out to work on its own.
## The fleet cap scales with the planet's size (data/fabricator.json cap_per_kcell x hexes), so
## fleets reach the hundreds; on the round planet only near robots are real (SphereCrew far
## records and its near budget keep that cheap).
##
## State (persists with the save): GameState.flags["fabricator"][planet id] =
##   {built, paused, mix: {type: weight}, queue: [type, ...] (one-offs, built before the mix),
##    made: {type: n}, cur: type being built ("" = none), t: 0..1}
##
## UI API (ui/fabricator_panel.gd, the workbench Bots tab): BotFabricator.of(world) -> node, then
## mix() / set_mix(d) / set_weight(t, w) / weight(t), queue() / enqueue(t) / clear_queue(),
## upcoming(n), cap_now(), fleet_size(), built_count(), paused() / set_paused(on), status_line(),
## and static robot_cost(t), types(), built(world), unlocked(world), cost().
## The node itself is rebuilt by attach(world) whenever a world with a built Fabricator starts.

signal robot_made(type_id: String)

const PATH: String = "res://data/fabricator.json"

static var _cfg: Dictionary = {}

var world: Node
var planet_id: String = "verdance"
## Adapter to the world's robots: spawn_fn.call(type_id, tier) -> bool, count_fn.call() -> int.
var spawn_fn: Callable
var count_fn: Callable
var cap: int = 0
var status: String = ""
## The yard's 3D model (systems/camp/fabricator_model.gd), beside the Depot.
var model: Node3D
var _model_on: bool = false
## Types it may build (empty = BotFabricator.types(): what research has unlocked).
var only_types: Array[String] = []


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func state(pid: String) -> Dictionary:
	if not (GameState.flags.get("fabricator") is Dictionary):
		GameState.flags["fabricator"] = {}
	var all: Dictionary = GameState.flags["fabricator"]
	if not (all.get(pid) is Dictionary):
		all[pid] = {"built": false, "paused": false, "mix": (cfg().get("default_mix", {"scoopie": 3, "haulbug": 1}) as Dictionary).duplicate(),
			"queue": [], "made": {}, "cur": "", "t": 0.0}
	return all[pid]


## The planet a world is on: the globe's planet on the round planet, else the campaign planet.
static func planet_of(w: Node) -> String:
	var so: Object = w.get("orbit") if w != null else null
	if so != null and so.get("globe") != null:
		var sp: Variant = (so.get("globe") as Object).get("spec")
		if sp is Dictionary:
			return str((sp as Dictionary).get("id", "verdance"))
	var k: int = Homeward.current_planet()
	var d: Dictionary = Homeward.planet_def(k)
	return str(d.get("id", "verdance")) if not d.is_empty() else "verdance"


## Unlocked from the unlock planet on (and stays unlocked once seen); --fabricator for dev.
static func unlocked(w: Node) -> bool:
	if bool(GameState.flags.get("fabricator_unlocked", false)) or DevHooks.has("fabricator"):
		return true
	var need: int = Homeward.planet_index(str(cfg().get("unlock_planet", "tidewell")))
	var here: int = Homeward.planet_index(planet_of(w))
	if need >= 0 and here >= need:
		GameState.flags["fabricator_unlocked"] = true
		return true
	return false


static func built(w: Node) -> bool:
	return bool(state(planet_of(w)).get("built", false))


static func cost() -> Dictionary:
	return (cfg().get("cost", {"cubes": 30000, "parts": 900}) as Dictionary).duplicate()


static func block_reason(w: Node) -> String:
	if built(w):
		return TranslationServer.translate("Built.")
	if not unlocked(w):
		return TranslationServer.translate("Not yet.")
	if not Hub.can_pay(cost()):
		return TranslationServer.translate("Not enough materials.")
	return ""


## The Hub build: pays, marks it built for this planet and starts it.
static func build(w: Node) -> bool:
	if block_reason(w) != "" or not Hub.pay(cost()):
		return false
	state(planet_of(w))["built"] = true
	attach(w)
	return true


## Fleet cap on a round planet of `cells` hexes.
static func cap_for_cells(cells: int) -> int:
	return maxi(1, roundi(float(cells) / 1000.0 * float(cfg().get("cap_per_kcell", 0.6))))


## Cubes and parts for one robot of a type (no growth with the fleet's size).
static func robot_cost(type_id: String) -> Dictionary:
	var d: Dictionary = Economy.robots.get(type_id, {})
	var m: float = float(cfg().get("cost_mult", 0.6))
	return {"cubes": ceilf(float(d.get("cost", 100)) * m), "parts": ceilf(float(d.get("parts", 30)) * m)}


static func can_pay_robot(type_id: String) -> bool:
	var c: Dictionary = robot_cost(type_id)
	return GameState.can_afford("cubes", BigNum.from_float(float(c["cubes"]))) and GameState.can_afford("parts", BigNum.from_float(float(c["parts"])))


static func pay_robot(type_id: String) -> bool:
	if not can_pay_robot(type_id):
		return false
	var c: Dictionary = robot_cost(type_id)
	GameState.spend("cubes", BigNum.from_float(float(c["cubes"])))
	GameState.spend("parts", BigNum.from_float(float(c["parts"])))
	return true


## Robot types the player can put in the mix (unlocked by research, in the game's order).
static func types() -> Array[String]:
	var out: Array[String] = []
	for id: String in Economy.robot_order:
		if Research.robot_unlocked(id) or DevHooks.has("fabricator"):
			out.append(id)
	return out


## Puts the Fabricator node into a world whose base has one built (idempotent). Returns it or null.
static func attach(w: Node) -> BotFabricator:
	if w == null or not built(w):
		return null
	var f: BotFabricator = w.get_node_or_null("BotFabricator") as BotFabricator
	if f == null:
		f = BotFabricator.new()
		f.name = "BotFabricator"
		w.add_child(f)
	f.world = w
	f.planet_id = planet_of(w)
	f._wire()
	f._place_model()
	return f


## Site-local / yard spot of the model: beside the Depot, 5 m to its left, facing the same way.
const MODEL_OFFSET := Vector3(-5.0, 0.0, 0.0)


func _place_model() -> void:
	if model != null and is_instance_valid(model):
		return
	var dp: Node3D = world.get("depot") as Node3D if "depot" in world else null
	if dp == null or dp.get_parent() == null:
		return
	model = FabricatorModel.new()
	model.name = "FabricatorModel"
	# Same parent as the Depot (the yard, or the start site's prefab on the globe), so the model
	# sits on that ground in its local frame (+Y up).
	dp.get_parent().add_child(model)
	model.transform = dp.transform * Transform3D(Basis(), MODEL_OFFSET)
	var so: Object = world.get("orbit")
	if so != null and so.get("crews") != null and (so.get("crews") as Object).get("crew") != null:
		var crew: SphereCrew = (so.get("crews") as Object).get("crew")
		crew.set_obstacles("fabricator", [[crew.surface.up_at(model.global_position), 2.8]])
	_model_on = false
	model.call("set_building", false)
	if DevHooks.has("fabricator-build"):
		print("[fabricator] model under %s, %.1f m from the Depot" % [str(model.get_parent().name), model.global_position.distance_to(dp.global_position)])


func _sync_model() -> void:
	if model == null or not is_instance_valid(model):
		return
	var st: Dictionary = state(planet_id)
	# On while the line runs (a robot in the bay, or the next one starting this tick); off when
	# paused, waiting for cubes and parts, the fleet is full or the mix is empty.
	var on: bool = not bool(st.get("paused", false)) and (str(st.get("cur", "")) != "" or status == "Building.")
	if on != _model_on:
		_model_on = on
		model.call("set_building", on)
		if DevHooks.has("fabricator-build"):
			print("[fabricator] building %s (%s)" % [str(on), status_line()])


static func of(w: Node) -> BotFabricator:
	return w.get_node_or_null("BotFabricator") as BotFabricator if w != null else null


## Connects to the world's robots: the SphereCrew on the round planet, the Fleet on a flat district.
func _wire() -> void:
	var so: Object = world.get("orbit")
	if so != null and so.get("crews") != null and (so.get("crews") as Object).get("crew") != null:
		var crew: SphereCrew = (so.get("crews") as Object).get("crew")
		var g: Object = so.get("globe")
		cap = cap_for_cells((g.get("grid") as SphereGrid).cell_count())
		count_fn = func() -> int: return crew.robots().size()
		spawn_fn = func(type_id: String, tier: int) -> bool: return spawn_on_globe(crew, g.get("sites"), type_id, tier)
		return
	var fl: Fleet = world.get("fleet") as Fleet
	if fl != null:
		cap = fl.crew_cap() * int(cfg().get("flat_cap_crews", 3))
		count_fn = func() -> int: return fl.robots().size()
		spawn_fn = func(type_id: String, tier: int) -> bool:
			var dp: Node3D = world.get("depot") as Node3D
			var at: Vector3 = (dp.global_position if dp else Vector3.ZERO) + Vector3(randf_range(-2.0, 2.0), 0.3, randf_range(1.5, 3.0))
			var r: Robot = fl.spawn(type_id, tier, at, 0.0, Fleet.NAMES[randi() % Fleet.NAMES.size()] + "-%02d" % (randi() % 100))
			if str(Economy.robots[type_id].get("role", "")) == "any":
				var j: String = fl.join_crew(type_id)
				r.job = j if j != "" else "clean"
			return r != null


## A new globe robot: assigned to the hub with the fewest robots (so the crew spreads over the
## planet by itself) and delivered beside that hub (the start hub's depot for the start hub).
static func spawn_on_globe(crew: SphereCrew, sites: Array, type_id: String, tier: int) -> bool:
	var per_hub: Dictionary = {}
	for s: Dictionary in sites:
		per_hub[int(s["cell"])] = 0
	for u: Dictionary in crew.robots():
		if per_hub.has(int(u["hub"])):
			per_hub[int(u["hub"])] = int(per_hub[int(u["hub"])]) + 1
	var hub: int = crew.hub_cell
	var best: int = 1 << 30
	for h: int in per_hub:  # sites[0] (the start hub) first on ties
		if int(per_hub[h]) < best:
			best = int(per_hub[h])
			hub = h
	# Hubs are 1.6-5.5 km apart across lakes: the robot is shipped to its hub's site (as a far
	# record when that is away from Lumi) instead of trekking there, and starts work at once.
	var at: int = crew.depot_of(crew.hub_cell) if hub == crew.hub_cell else hub
	var ring: PackedInt32Array = crew.grid.cells_around(at, 1)
	var land: Array[int] = []
	for c: int in ring:
		if c != at and crew.cells.state[c] != 5:
			land.append(c)
	crew.spawn(type_id, tier, land[randi() % land.size()] if not land.is_empty() else at, hub)
	return true


## Next type to build: the one furthest below its share of the mix ("" = empty mix).
static func next_type(mix: Dictionary, made: Dictionary, allowed: Array[String]) -> String:
	var wsum: float = 0.0
	var msum: float = 0.0
	for t: String in allowed:
		wsum += maxf(0.0, float(mix.get(t, 0)))
		msum += float(made.get(t, 0))
	if wsum <= 0.0:
		return ""
	var best: String = ""
	var best_gap: float = -INF
	for t: String in allowed:
		var w: float = float(mix.get(t, 0))
		if w <= 0.0:
			continue
		var gap: float = w / wsum - float(made.get(t, 0)) / maxf(msum + 1.0, 1.0)
		if gap > best_gap + 1e-9:
			best_gap = gap
			best = t
	return best


func set_weight(type_id: String, w: int) -> void:
	state(planet_id)["mix"][type_id] = clampi(w, 0, int(cfg().get("max_weight", 9)))


func weight(type_id: String) -> int:
	return int((state(planet_id)["mix"] as Dictionary).get(type_id, 0))


func mix() -> Dictionary:
	return (state(planet_id)["mix"] as Dictionary).duplicate()


func set_mix(d: Dictionary) -> void:
	var m: Dictionary = {}
	for t: String in d:
		m[t] = clampi(int(d[t]), 0, int(cfg().get("max_weight", 9)))
	state(planet_id)["mix"] = m


## One-off orders, built before the mix (in order).
func queue() -> Array:
	return (state(planet_id).get("queue", []) as Array).duplicate()


func enqueue(type_id: String) -> void:
	var st: Dictionary = state(planet_id)
	if not (st.get("queue") is Array):
		st["queue"] = []
	(st["queue"] as Array).append(type_id)


func clear_queue() -> void:
	state(planet_id)["queue"] = []


## The next `n` robots it will build (queue first, then the mix), for a preview row.
func upcoming(n: int = 5) -> Array[String]:
	var st: Dictionary = state(planet_id)
	var out: Array[String] = []
	var made: Dictionary = (st["made"] as Dictionary).duplicate()
	var allowed: Array[String] = only_types if not only_types.is_empty() else types()
	for t: Variant in st.get("queue", []):
		if out.size() < n and allowed.has(str(t)):
			out.append(str(t))
	while out.size() < n:
		var t: String = next_type(st["mix"], made, allowed)
		if t == "":
			break
		out.append(t)
		made[t] = int(made.get(t, 0)) + 1
	return out


func cap_now() -> int:
	return cap


## Robots this Fabricator has built on this planet.
func built_count() -> int:
	var n: int = 0
	for t: String in state(planet_id)["made"]:
		n += int(state(planet_id)["made"][t])
	return n


func set_paused(on: bool) -> void:
	state(planet_id)["paused"] = on


func paused() -> bool:
	return bool(state(planet_id).get("paused", false))


func fleet_size() -> int:
	return int(count_fn.call()) if count_fn.is_valid() else 0


func _process(delta: float) -> void:
	tick(delta)


## Runs the line: start a robot when it can pay (paid up front), finish it after build_s.
func tick(delta: float) -> void:
	_tick_line(delta)
	_sync_model()


func _tick_line(delta: float) -> void:
	var st: Dictionary = state(planet_id)
	if not bool(st.get("built", false)) or not spawn_fn.is_valid():
		status = ""
		return
	if bool(st.get("paused", false)):
		status = "Paused."
		return
	var cur: String = str(st.get("cur", ""))
	if cur == "":
		if fleet_size() >= cap:
			status = "Fleet full."
			return
		var allowed: Array[String] = only_types if not only_types.is_empty() else types()
		var q: Array = st.get("queue", [])
		var nt: String = str(q[0]) if not q.is_empty() and allowed.has(str(q[0])) else next_type(st["mix"], st["made"], allowed)
		if not q.is_empty() and not allowed.has(str(q[0])):
			q.pop_front()  # a queued type that is no longer allowed is dropped
		if nt == "":
			status = "Set a mix to start."
			return
		if not pay_robot(nt):
			status = "Waiting for cubes and parts."
			return
		if not q.is_empty() and str(q[0]) == nt:
			q.pop_front()
		st["cur"] = nt
		st["t"] = 0.0
		cur = nt
	st["t"] = float(st["t"]) + delta / maxf(float(cfg().get("build_s", 45.0)), 0.1)
	status = "Building."
	if float(st["t"]) < 1.0:
		return
	var tier: int = int(GameState.flags.get("tier_" + cur, 0))
	if bool(spawn_fn.call(cur, tier)):
		(st["made"] as Dictionary)[cur] = int((st["made"] as Dictionary).get(cur, 0)) + 1
		GameState.inc_stat("robots_built")
		robot_made.emit(cur)
	st["cur"] = ""
	st["t"] = 0.0


## One line for the panel.
func status_line() -> String:
	var st: Dictionary = state(planet_id)
	var cur: String = str(st.get("cur", ""))
	var head: String = TranslationServer.translate("Fleet %d / %d") % [fleet_size(), cap]
	if cur != "" and not paused():
		return head + "  ·  " + TranslationServer.translate("Building a %s, %d%%") % [TranslationServer.translate(str(Economy.robots.get(cur, {}).get("name", cur))), int(float(st["t"]) * 100.0)]
	return head + ("  ·  " + TranslationServer.translate(status) if status != "" else "")
