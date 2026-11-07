class_name Fleet
extends Node3D
## Owns all helper robots: building from parts, tier upgrades (fleet-wide per type), save/load.

const NAMES: Array[String] = ["Bolt", "Rivet", "Tin", "Sprocket", "Gizmo", "Piston", "Nib", "Widget", "Ratchet", "Cog", "Dibs", "Fuse", "Grommet", "Pip", "Socket", "Tack"]

var world: Node
## Refill points for waterers (base barrel, placed Water Tanks, clean lake hexes).
var water_net: WaterNet
var _report_done: bool = false


func _ready() -> void:
	add_to_group("persist")
	if world != null:
		water_net = WaterNet.new()
		water_net.name = "WaterNet"
		water_net.world = world
		add_child(water_net)


func _process(_delta: float) -> void:
	# --bot-report (or any --robots run): print what every robot got done just before --quit-after ends the run.
	if _report_done or not (DevHooks.has("bot-report") or DevHooks.has("robots")) or not DevHooks.has("quit-after"):
		return
	if DevHooks._elapsed >= DevHooks.get_f("quit-after", 5.0) - 1.0:
		_report_done = true
		print_report()


func print_report() -> void:
	print("[bots] ---- robot report (%d robots, %d/%d hexes clean) ----" % [robots().size(), world.field.junk_hexes_cleaned() if world else 0, world.field.junk_hex_count if world else 0])
	for r: Robot in robots():
		var parts: PackedStringArray = []
		for k: String in r.log_stats:
			if k != "stall_s" and float(r.log_stats[k]) > 0.0:
				parts.append("%s=%s" % [k, str(snappedf(float(r.log_stats[k]), 0.1))])
		print("[bots] %-8s %-9s %s | %s | stalled %.0fs | idle %.0fs" % [r.robot_name, r.type_id, ", ".join(parts), r.status_text(), float(r.log_stats.get("stall_s", 0.0)), float(r.log_stats.get("idle_s", 0.0))])


func robots() -> Array[Robot]:
	var out: Array[Robot] = []
	for c: Node in get_children():
		if c is Robot:
			out.append(c)
	return out


func count(type_id: String) -> int:
	var n: int = 0
	for r: Robot in robots():
		if r.type_id == type_id:
			n += 1
	return n


func tier_of(type_id: String) -> int:
	return int(GameState.flags.get("tier_" + type_id, 0))


## Best stored part of a type (highest rarity), or -1 index into GameState.parts.
func _best_part(part_type_idx: int, min_rarity: int = 0) -> int:
	var best: int = -1
	for i: int in GameState.parts.size():
		var p: Dictionary = GameState.parts[i]
		if int(p["type"]) == part_type_idx and int(p["rarity"]) >= min_rarity:
			if best < 0 or int(p["rarity"]) > int(GameState.parts[best]["rarity"]):
				best = i
	return best


static func part_index(part_id: String) -> int:
	var types: Array = Economy.parts.get("types", [])
	for i: int in types.size():
		if str(types[i]["id"]) == part_id:
			return i
	return -1


## Lowest Control Core rarity that some robot type's next Mk tier needs (huge when none does).
## Cores at or above it are worth keeping for upgrade_tier.
func core_keep_rarity() -> int:
	var need: int = 1 << 30
	for tid: String in Economy.robot_order:
		var t: int = tier_of(tid)
		if t + 1 >= Economy.robot_tiers.size():
			continue
		var r: int = int(Economy.robot_tiers[t + 1].get("requires_core_rarity", 0))
		if r >= 0:
			need = mini(need, r)
	return need


## Recipe status: Array of {part_id, name, have: bool, rarity: int}.
## Non-core slots take the best part in storage. The "core" slot spares tier-up cores: it takes
## the best core below core_keep_rarity(), and only if there is none, the weakest one above it.
func recipe_status(type_id: String) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	var keep: int = core_keep_rarity()
	for part_id: String in Economy.robots[type_id].get("recipe", []):
		var idx: int = part_index(part_id)
		var have: int = -1
		for i: int in GameState.parts.size():
			if used.has(i) or int(GameState.parts[i]["type"]) != idx:
				continue
			if have < 0:
				have = i
				continue
			var ri: int = int(GameState.parts[i]["rarity"])
			var rh: int = int(GameState.parts[have]["rarity"])
			if part_id == "core":
				if (ri < keep) != (rh < keep):
					if ri < keep:
						have = i  # a spare core always beats one needed for a Mk tier
				elif (ri > rh) if ri < keep else (ri < rh):
					have = i
			elif ri > rh:
				have = i
		if have >= 0:
			used[have] = true
		out.append({"part_id": part_id, "name": Economy.part_type(idx).get("name", part_id), "have": have >= 0,
			"rarity": int(GameState.parts[have]["rarity"]) if have >= 0 else -1, "index": have})
	return out


# --- Crews and caps ----------------------------------------------------------------------

## Base level (hub level) that sets crew caps.
func base_level() -> int:
	if world != null and world.get("hub") != null:
		return int(world.hub.level)
	return int(GameState.world.get("hub_level", 1))


## Max robots per crew: base + per_level * hub level (data/robots.json "crew_cap").
func crew_cap() -> int:
	var c: Dictionary = Economy.robot_cfg.get("crew_cap", {})
	return int(c.get("base", 3)) + int(c.get("per_level", 3)) * base_level()


## The crew a newly built robot of this type joins (multibots start as cleaners).
static func crew_of_type(type_id: String) -> String:
	var r: String = str(Economy.robots.get(type_id, {}).get("role", "clean"))
	return "clean" if r == "any" else r


func crew_size(role_id: String) -> int:
	return robots_with_role(role_id).size()


## Specialist robot types that make up a crew (for the Command panel's Build buttons).
static func types_for_role(role_id: String) -> Array[String]:
	var out: Array[String] = []
	for id: String in Economy.robot_order:
		if str(Economy.robots[id].get("role", "")) == role_id:
			out.append(id)
	return out


## Multibot jobs, in the order a new one fills them.
const MULTI_JOBS: Array[String] = ["clean", "plant", "water"]


## First crew a new robot of this type can join without breaking the cap ("" = all full).
## Specialists have one crew; a multibot can take any job with room.
func join_crew(type_id: String) -> String:
	var jobs: Array[String] = [crew_of_type(type_id)]
	if str(Economy.robots.get(type_id, {}).get("role", "")) == "any":
		jobs = MULTI_JOBS
	for j: String in jobs:
		if crew_size(j) < crew_cap():
			return j
	return ""


## "" if the type can be built now, else why not (research, crew cap, parts, cubes).
func build_block_reason(type_id: String) -> String:
	if not Research.robot_unlocked(type_id):
		return "Locked · research %s" % str(Research.def(Research.robot_requirement(type_id)).get("name", "?"))
	if join_crew(type_id) == "":
		return "Crew full (%d/%d): upgrade the hub" % [crew_size(crew_of_type(type_id)), crew_cap()]
	var missing: int = 0
	for r: Dictionary in recipe_status(type_id):
		if not r["have"]:
			missing += 1
	if missing > 0:
		return "Missing %d part%s" % [missing, "" if missing == 1 else "s"]
	if not GameState.can_afford("cubes", build_cost(type_id)):
		return "Not enough cubes"
	return ""


func build_cost(type_id: String) -> BigNum:
	var base: float = float(Economy.robots[type_id].get("cost", 100))
	return BigNum.from_float(base * pow(1.35, count(type_id)))


func can_build(type_id: String) -> bool:
	return build_block_reason(type_id) == ""


func build(type_id: String, at: Vector3) -> Robot:
	if not can_build(type_id):
		return null
	var crew: String = join_crew(type_id)
	var status: Array = recipe_status(type_id)
	var rarity_sum: float = 0.0
	var to_remove: Array[int] = []
	for r: Dictionary in status:
		to_remove.append(int(r["index"]))
		rarity_sum += float(r["rarity"])
	GameState.spend("cubes", build_cost(type_id))
	to_remove.sort()
	to_remove.reverse()
	for i: int in to_remove:
		GameState.parts.remove_at(i)
	var bonus: float = 0.05 * rarity_sum / maxf(status.size(), 1.0)
	var rname: String = NAMES[randi() % NAMES.size()] + "-%02d" % (randi() % 100)
	while find_robot(rname) != null:
		rname = NAMES[randi() % NAMES.size()] + "-%02d" % (randi() % 100)
	var r := spawn(type_id, tier_of(type_id), at, bonus, rname)
	if str(Economy.robots[type_id].get("role", "")) == "any":
		r.job = crew  # start in a crew that has room
	GameState.inc_stat("robots_built")
	EventBus.robot_built.emit(r.robot_name)
	var quirk: String = str(RobotBuilder.trait_def(RobotBuilder.trait_of(r)).get("name", "")).to_lower()  # [drones] personality
	EventBus.toast.emit("%s %s assembled. It looks around, then gets to work.%s" % [Economy.robots[type_id]["name"], r.robot_name, (" Seems %s." % quirk) if quirk != "" else ""], "story")
	return r


func spawn(type_id: String, tier: int, at: Vector3, bonus: float, rname: String) -> Robot:
	var r := Robot.new()
	r.type_id = type_id
	r.tier = tier
	r.rarity_bonus = bonus
	r.robot_name = rname
	r.world = world
	add_child(r)
	r.global_position = at
	# Boot-up: a little flash of sparks and a servo whine.
	Vfx.burst("sparkle", at + Vector3(0, 0.6, 0), Color(1.0, 0.8, 0.4), 0.6)
	Audio.play("servo", 0.7, -8.0)
	return r


## Next tier requirements for a type: {cost: BigNum, core_rarity: int, ok: bool, reason: String}
func tier_requirements(type_id: String) -> Dictionary:
	var t: int = tier_of(type_id)
	if t + 1 >= Economy.robot_tiers.size():
		return {"maxed": true}
	var nt: Dictionary = Economy.robot_tiers[t + 1]
	var cost := BigNum.from_float(float(Economy.robots[type_id].get("cost", 100)) * float(nt.get("cost_mult", 1)))
	var need: int = int(nt.get("requires_core_rarity", 0))
	var core_i: int = _best_part(part_index("core"), need)
	var bolts := BigNum.from_float([10.0, 40.0, 150.0][clampi(t, 0, 2)])
	var ok: bool = GameState.can_afford("cubes", cost) and core_i >= 0 and GameState.can_afford("bolts", bolts)
	var reason: String = ""
	if core_i < 0:
		reason = "Needs a %s Control Core" % Economy.rarity(need).get("name", "?")
	elif not GameState.can_afford("cubes", cost):
		reason = "Not enough cubes"
	elif not GameState.can_afford("bolts", bolts):
		reason = "Not enough bolts (scrap spare parts at Haggle's)"
	return {"maxed": false, "cost": cost, "bolts": bolts, "core_rarity": need, "ok": ok, "reason": reason, "next": nt}


func upgrade_tier(type_id: String) -> bool:
	var req: Dictionary = tier_requirements(type_id)
	if req.get("maxed", false) or not req["ok"]:
		return false
	GameState.spend("cubes", req["cost"])
	GameState.spend("bolts", req["bolts"])
	GameState.parts.remove_at(_best_part(part_index("core"), int(req["core_rarity"])))
	var t: int = tier_of(type_id) + 1
	GameState.flags["tier_" + type_id] = t
	# Fast-build moment: each robot of this type gets rebuilt in a shower of sparks.
	for r: Robot in robots():
		if r.type_id == type_id:
			r.tier = t
			r.rebuild_visual()
			Vfx.burst("big_sparkle", r.global_position + Vector3(0, 0.6, 0), Color(0.5, 0.9, 1.0) if t >= 2 else Color(1.0, 0.8, 0.4))
	Audio.play("fanfare", 1.0, -6.0)
	EventBus.toast.emit("%s fleet upgraded to %s." % [Economy.robots[type_id]["name"], Economy.tier_name(t)], "story")
	return true


## Multibot allocation: how many multibots work each job.
func allocation() -> Dictionary:
	var a: Dictionary = {"clean": 0, "plant": 0, "water": 0}
	for r: Robot in robots():
		if r.type_id == "multibot":
			a[r.job] = int(a.get(r.job, 0)) + 1
	return a


func move_job(from_job: String, to_job: String) -> bool:
	if from_job == to_job or crew_size(to_job) >= crew_cap():
		return false  # crew full
	for r: Robot in robots():
		if r.type_id == "multibot" and r.job == from_job:
			r.set_job(to_job)
			return true
	return false


func apply_preset(clean_pct: float, plant_pct: float) -> void:
	var mb: Array[Robot] = []
	for r: Robot in robots():
		if r.type_id == "multibot":
			mb.append(r)
	var n: int = mb.size()
	var nc: int = int(round(n * clean_pct))
	var np: int = int(round(n * plant_pct))
	var want: Dictionary = {"clean": mini(nc, n), "plant": clampi(np, 0, maxi(n - nc, 0)), "water": maxi(n - nc - np, 0)}
	# Room per job = cap minus the specialists already in that crew.
	var cap: int = crew_cap()
	var room: Dictionary = {}
	for j: String in MULTI_JOBS:
		var multi_in: int = 0
		for r: Robot in mb:
			if r.job == j:
				multi_in += 1
		room[j] = maxi(cap - (crew_size(j) - multi_in), 0)
		want[j] = mini(int(want[j]), int(room[j]))
	var left: int = n - int(want["clean"]) - int(want["plant"]) - int(want["water"])
	for j: String in MULTI_JOBS:
		var add: int = mini(left, int(room[j]) - int(want[j]))
		want[j] = int(want[j]) + add
		left -= add
	# Bots already in a job with quota stay put; the rest move to jobs with quota left.
	var quota: Dictionary = want.duplicate()
	var movers: Array[Robot] = []
	for r: Robot in mb:
		if int(quota.get(r.job, 0)) > 0:
			quota[r.job] = int(quota[r.job]) - 1
		else:
			movers.append(r)
	for r: Robot in movers:
		for j: String in MULTI_JOBS:
			if int(quota[j]) > 0:
				quota[j] = int(quota[j]) - 1
				r.set_job(j)
				break
		# No job has room: the bot keeps its job (only possible in an already over-cap save).


# --- Orders (Command View) -------------------------------------------------------------
# An order is {"zone": Array[int] hex ids, "mode": String}. Modes:
#   "priority": work the zone first, then roam the district as usual.
#   "stay":     work only inside the zone; wait there when it is done.
#   "follow":   the zone is wherever Patch is (hexes around the player).
#   "recall":   park at the hub until given new orders.
# Groups are keyed by role ("clean", "haul", "plant", "water", "skim"); a single robot's own order
# (keyed by name) overrides its group's.

const MODES: Array[String] = ["priority", "stay", "follow", "recall"]
const ROLES: Array[String] = ["clean", "haul", "plant", "water", "skim"]


func _orders() -> Dictionary:
	if not GameState.world.has("orders"):
		GameState.world["orders"] = {"groups": {}, "bots": {}}
	return GameState.world["orders"]


## The order a robot follows right now ({} = free roam).
func order_for(r: Robot) -> Dictionary:
	var o: Dictionary = _orders()
	var bots: Dictionary = o.get("bots", {})
	if bots.has(r.robot_name):
		return bots[r.robot_name]
	return (o.get("groups", {}) as Dictionary).get(r.role(), {})


## Order record for a group key or robot name (creates an empty priority order).
func order(key: String, is_bot: bool) -> Dictionary:
	var o: Dictionary = _orders()
	var table: Dictionary = o["bots" if is_bot else "groups"]
	if not table.has(key):
		table[key] = {"zone": [], "mode": "priority"}
	return table[key]


func has_order(key: String, is_bot: bool) -> bool:
	return (_orders()["bots" if is_bot else "groups"] as Dictionary).has(key)


func clear_order(key: String, is_bot: bool) -> void:
	(_orders()["bots" if is_bot else "groups"] as Dictionary).erase(key)
	_reset_targets()


func toggle_zone_hex(key: String, is_bot: bool, hid: int, on: bool) -> void:
	var od: Dictionary = order(key, is_bot)
	var z: Array = od["zone"]
	var has: bool = z.has(hid)
	if on and not has:
		z.append(hid)
	elif not on and has:
		z.erase(hid)
	_reset_targets()


func set_mode(key: String, is_bot: bool, mode: String) -> void:
	order(key, is_bot)["mode"] = mode
	_reset_targets()


## Hexes a robot should work, given its order ([] = no restriction).
func zone_hexes(r: Robot) -> Array:
	var od: Dictionary = order_for(r)
	if od.is_empty():
		return []
	if str(od.get("mode", "")) == "follow" and world.patch != null:
		return world.field.hexes_near(world.patch.global_position, 1)
	return od.get("zone", [])


func mode_of(r: Robot) -> String:
	var od: Dictionary = order_for(r)
	if od.is_empty():
		return "roam"
	if str(od.get("mode", "priority")) == "priority" and (od.get("zone", []) as Array).is_empty():
		return "roam"
	return str(od.get("mode", "priority"))


func _reset_targets() -> void:
	for r: Robot in robots():
		r.reset_targets()


func robots_with_role(role_id: String) -> Array[Robot]:
	var out: Array[Robot] = []
	for r: Robot in robots():
		if r.role() == role_id:
			out.append(r)
	return out


func find_robot(rname: String) -> Robot:
	for r: Robot in robots():
		if r.robot_name == rname:
			return r
	return null


func persist_save() -> void:
	var arr: Array = []
	for r: Robot in robots():
		arr.append(r.to_dict())
	GameState.world["robots"] = arr


func restore() -> void:
	# JSON round-trips turn hex ids into floats; normalise so zone lookups match.
	var o: Dictionary = _orders()
	for t: String in ["groups", "bots"]:
		var table: Dictionary = o.get(t, {})
		for k: String in table:
			var z: Array = []
			for h: Variant in table[k].get("zone", []):
				z.append(int(h))
			table[k]["zone"] = z
	for d: Dictionary in GameState.world.get("robots", []):
		var p: Array = d.get("pos", [0.0, 0.0, 0.0])
		var r := spawn(str(d["type"]), int(d.get("tier", 0)), Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2])), float(d.get("rarity_bonus", 0.0)), str(d.get("name", "Bot")))
		r.work_hex = int(d.get("hex", -1))
		r.job = str(d.get("job", "clean"))
		r.hopper.from_dict(d.get("hopper", {}))
		r.trait_id = str(d.get("trait", ""))  # [drones] builder parts + personality
		RobotBuilder.set_build(r, d.get("build", {}))
