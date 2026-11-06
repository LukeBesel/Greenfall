class_name Fleet
extends Node3D
## Owns all helper robots: building from parts, tier upgrades (fleet-wide per type), save/load.

const NAMES: Array[String] = ["Bolt", "Rivet", "Tin", "Sprocket", "Gizmo", "Piston", "Nib", "Widget", "Ratchet", "Cog", "Dibs", "Fuse", "Grommet", "Pip", "Socket", "Tack"]

var world: Node


func _ready() -> void:
	add_to_group("persist")


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


## Recipe status: Array of {part_id, name, have: bool, rarity: int}.
func recipe_status(type_id: String) -> Array:
	var out: Array = []
	var used: Dictionary = {}
	for part_id: String in Economy.robots[type_id].get("recipe", []):
		var idx: int = part_index(part_id)
		var have: int = -1
		for i: int in GameState.parts.size():
			if used.has(i):
				continue
			if int(GameState.parts[i]["type"]) == idx and (have < 0 or int(GameState.parts[i]["rarity"]) > int(GameState.parts[have]["rarity"])):
				have = i
		if have >= 0:
			used[have] = true
		out.append({"part_id": part_id, "name": Economy.part_type(idx).get("name", part_id), "have": have >= 0,
			"rarity": int(GameState.parts[have]["rarity"]) if have >= 0 else -1, "index": have})
	return out


func build_cost(type_id: String) -> BigNum:
	var base: float = float(Economy.robots[type_id].get("cost", 100))
	return BigNum.from_float(base * pow(1.35, count(type_id)))


func can_build(type_id: String) -> bool:
	for r: Dictionary in recipe_status(type_id):
		if not r["have"]:
			return false
	return GameState.can_afford("cubes", build_cost(type_id))


func build(type_id: String, at: Vector3) -> Robot:
	if not can_build(type_id):
		return null
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
	var r := spawn(type_id, tier_of(type_id), at, bonus, NAMES[randi() % NAMES.size()] + "-%02d" % (randi() % 100))
	GameState.inc_stat("robots_built")
	EventBus.robot_built.emit(r.robot_name)
	EventBus.toast.emit("%s %s assembled. It looks around, then gets to work." % [Economy.robots[type_id]["name"], r.robot_name], "story")
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
	for i: int in n:
		mb[i].set_job("clean" if i < nc else ("plant" if i < nc + np else "water"))


func persist_save() -> void:
	var arr: Array = []
	for r: Robot in robots():
		arr.append(r.to_dict())
	GameState.world["robots"] = arr


func restore() -> void:
	for d: Dictionary in GameState.world.get("robots", []):
		var p: Array = d.get("pos", [0.0, 0.0, 0.0])
		var r := spawn(str(d["type"]), int(d.get("tier", 0)), Vector3(float(p[0]), float(p[1]) + 0.1, float(p[2])), float(d.get("rarity_bonus", 0.0)), str(d.get("name", "Bot")))
		r.work_hex = int(d.get("hex", -1))
		r.job = str(d.get("job", "clean"))
		r.hopper.from_dict(d.get("hopper", {}))
