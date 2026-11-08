class_name RobotBuilder
extends Node
## [drones] Robot Builder: per-robot part slots (Chassis, Head, Mobility, Tool, Topper), the part
## inventory, crafting, Haggle's builder stall, Maker Fragments, crew presets, personality traits,
## and salvage spotting (the Scan stat). Rules are static so the UI, tests and the save round trip
## can use them without a world; one instance per slice ticks salvage finds and dev hooks.
##
## State: GameState.flags["builder"] = {inv: {part_id: n}, fragments: n, presets: {crew: build},
##   starter: bool}. Builds and traits live on each robot (Robot.build / Robot.trait_id, saved in
##   Robot.to_dict). A build is {slot: part_id}; a missing slot is the Mk tier's stock part.

const PATH: String = "res://data/robot_parts.json"
const SLOTS: Array[String] = ["chassis", "head", "mobility", "tool", "topper"]
## Generic part stats -> the concrete robot stats they scale.
const CONCRETE: Dictionary = {
	"speed": ["speed"],
	"load": ["capacity", "carry", "tank"],
	"work": ["scoop_rate", "work_rate", "refill_rate"],
	"quality": ["efficiency"],
	"reach": ["spray_radius"],
	"scan": ["scan"],
}
const CREW_COLORS: Dictionary = {
	"clean": Color(1.0, 0.7, 0.26), "haul": Color(0.4, 0.75, 1.0), "plant": Color(0.55, 0.95, 0.5),
	"water": Color(0.35, 0.85, 1.0), "skim": Color(0.3, 1.0, 0.82),
}

static var _cfg: Dictionary = {}
static var _by_id: Dictionary = {}
static var _quiet: bool = false

var world: Node
var rng := RandomNumberGenerator.new()
var _tick: float = 0.0
var _demo_done: bool = false


# --- Data ----------------------------------------------------------------------------------

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
		_by_id.clear()
		for p: Dictionary in _cfg.get("parts", []):
			_by_id[str(p["id"])] = p
	return _cfg


static func part(id: String) -> Dictionary:
	cfg()
	return _by_id.get(id, {})


static func all_parts() -> Array:
	return cfg().get("parts", [])


static func slot_name(slot: String) -> String:
	for s: Dictionary in cfg().get("slots", []):
		if str(s["id"]) == slot:
			return TranslationServer.translate(str(s["name"]))
	return slot.capitalize()


static func stat_name(id: String) -> String:
	for s: Dictionary in cfg().get("stats", []):
		if str(s["id"]) == id:
			return TranslationServer.translate(str(s["name"]))
	return id.capitalize()


static func parts_for_slot(slot: String) -> Array:
	return all_parts().filter(func(p: Dictionary) -> bool: return str(p["slot"]) == slot)


static func is_cosmetic(id: String) -> bool:
	return str(part(id).get("slot", "")) == "topper"


## Whether a part fits a robot type (tools are crew-specific; multibots take any tool).
static func fits(id: String, type_id: String) -> bool:
	var p: Dictionary = part(id)
	if p.is_empty():
		return false
	if not p.has("roles"):
		return true
	var role: String = str(Economy.robots.get(type_id, {}).get("role", "clean"))
	return role == "any" or role in (p["roles"] as Array)


static func traits() -> Array:
	return cfg().get("traits", [])


static func trait_def(id: String) -> Dictionary:
	for t: Dictionary in traits():
		if str(t["id"]) == id:
			return t
	return {}


## Deterministic trait for a robot name (old saves get one without storing anything).
static func trait_for_name(rname: String) -> String:
	var tl: Array = traits()
	if tl.is_empty():
		return ""
	return str(tl[absi(hash(rname)) % tl.size()]["id"])


# --- State ---------------------------------------------------------------------------------

static func st() -> Dictionary:
	var v: Variant = GameState.flags.get("builder")
	if not (v is Dictionary):
		v = {}
		GameState.flags["builder"] = v
	var d: Dictionary = v
	if not (d.get("inv") is Dictionary):
		d["inv"] = {}
	if not (d.get("presets") is Dictionary):
		d["presets"] = {}
	return d


static func inv() -> Dictionary:
	return st()["inv"]


static func count(id: String) -> int:
	return int(inv().get(id, 0))


static func add_part(id: String, n: int = 1) -> void:
	if part(id).is_empty():
		return
	inv()[id] = count(id) + n
	GameState.inc_stat("builder_parts_got", n)
	_note_seen(id)


static func take_part(id: String) -> bool:
	if count(id) <= 0:
		return false
	inv()[id] = count(id) - 1
	if int(inv()[id]) <= 0:
		inv().erase(id)
	return true


## [money] Maker Fragments are Parts now (data/currencies.json legacy "fragments"): a find pays
## FRAGMENT_PARTS parts; the Maker set costs parts + a Vintage-or-better robot part. Kept as calls
## so older code and the maker_fragments stat keep working.
const FRAGMENT_PARTS: float = 25.0


static func fragments() -> int:
	return 0


static func add_fragments(n: int) -> void:
	GameState.add_currency("parts", BigNum.from_float(n * FRAGMENT_PARTS))
	GameState.inc_stat("maker_fragments", n)


## Distinct toppers ever collected (for the Hat Rack achievement).
static func _note_seen(id: String) -> void:
	var seen: Array = st().get("seen", [])
	if not (id in seen):
		seen.append(id)
	st()["seen"] = seen
	var toppers: int = 0
	for p: Dictionary in parts_for_slot("topper"):
		if str(p["id"]) in seen:
			toppers += 1
	GameState.stats["builder_toppers"] = float(toppers)


# --- Stats ---------------------------------------------------------------------------------

## Product of generic mods for a build plus a trait (and the Maker set bonus).
static func generic_mods(build: Dictionary, trait_id: String = "") -> Dictionary:
	var out: Dictionary = {}
	var mul := func(mods: Dictionary) -> void:
		for k: String in mods:
			out[k] = float(out.get(k, 1.0)) * float(mods[k])
	for slot: String in build:
		mul.call(part(str(build[slot])).get("mods", {}))
	if has_set(build):
		mul.call(cfg().get("set_bonus", {}).get("mods", {}))
	if trait_id != "":
		mul.call(trait_def(trait_id).get("mods", {}))
	return out


## Concrete robot stat multipliers (speed, capacity, carry, tank, scoop_rate, ...).
static func concrete_mods(build: Dictionary, trait_id: String = "") -> Dictionary:
	var g: Dictionary = generic_mods(build, trait_id)
	var out: Dictionary = {}
	for k: String in g:
		for c: String in CONCRETE.get(k, []):
			out[c] = g[k]
	return out


static func has_set(build: Dictionary) -> bool:
	var n: int = 0
	for slot: String in build:
		if str(part(str(build[slot])).get("set", "")) == "maker":
			n += 1
	return n >= 3


## All five slots hold a builder part.
static func is_full_custom(build: Dictionary) -> bool:
	for s: String in SLOTS:
		if str(build.get(s, "")) == "":
			return false
	return true


# --- Robots --------------------------------------------------------------------------------

static func trait_of(r: Robot) -> String:
	if r.trait_id == "":
		r.trait_id = trait_for_name(r.robot_name)
	return r.trait_id


## Recompute a robot's stat multipliers from its build + trait (Robot.stat reads build_mods).
static func refresh_mods(r: Robot) -> void:
	r.build_mods = concrete_mods(r.build, trait_of(r))


## Called from Robot.rebuild_visual: fit the part meshes, the name tag and the personality node.
static func on_visual_rebuilt(r: Robot) -> void:
	refresh_mods(r)
	if r.visual:
		RobotKit.fit(r.visual, r.build, r.role())
	RobotPersona.ensure(r)


## Replace a robot's whole build (save restore, presets). Parts are not touched.
static func set_build(r: Robot, build: Dictionary) -> void:
	var b: Dictionary = {}
	for s: String in SLOTS:
		var id: String = str(build.get(s, ""))
		if id != "" and str(part(id).get("slot", "")) == s:
			b[s] = id
	r.build = b
	r.rebuild_visual()


## Fit a part ("" = stock). The old part goes back to the bin. Returns "" or why not.
static func equip(r: Robot, slot: String, id: String) -> String:
	var cur: String = str(r.build.get(slot, ""))
	if cur == id:
		return ""
	if id != "":
		var p: Dictionary = part(id)
		if p.is_empty() or str(p["slot"]) != slot:
			return TranslationServer.translate("Wrong slot")
		if not fits(id, r.type_id):
			return TranslationServer.translate("Doesn't fit a %s") % TranslationServer.translate(str(Economy.robots.get(r.type_id, {}).get("name", r.type_id)))
		if not take_part(id):
			return TranslationServer.translate("None in the parts bin")
	if cur != "":
		inv()[cur] = count(cur) + 1
	if id == "":
		r.build.erase(slot)
	else:
		r.build[slot] = id
		GameState.inc_stat("builder_parts_fitted")
	note_build(r.build)
	r.rebuild_visual()
	if r.is_inside_tree():
		Vfx.burst("sparkle", r.global_position + Vector3(0, 0.7, 0), Color(0.6, 0.95, 1.0), 0.5)
	Audio.play("clunk", 1.3, -8.0)
	Audio.play("servo", 1.4, -12.0)
	return ""


## Stats for goals and achievements after a build changes.
static func note_build(build: Dictionary) -> void:
	if is_full_custom(build):
		GameState.stats["builder_full_custom"] = maxf(float(GameState.stats.get("builder_full_custom", 0.0)), 1.0)
	if has_set(build):
		GameState.stats["builder_maker_set"] = 1.0


## Rename a robot (unique in the fleet). Its own Command order follows the new name.
static func rename(fleet: Fleet, r: Robot, new_name: String) -> String:
	var n: String = new_name.strip_edges().left(16)
	if n == r.robot_name:
		return ""
	if n.length() < 2:
		return TranslationServer.translate("Names need at least 2 letters")
	if fleet and fleet.find_robot(n) != null:
		return TranslationServer.translate("Another robot is already called %s") % n
	if fleet:
		var bots: Dictionary = (GameState.world.get("orders", {}) as Dictionary).get("bots", {})
		if bots.has(r.robot_name):
			bots[n] = bots[r.robot_name]
			bots.erase(r.robot_name)
	r.robot_name = n
	var p: RobotPersona = r.get_node_or_null(RobotPersona.NODE_NAME) as RobotPersona
	if p:
		p.refresh()
	GameState.inc_stat("builder_renamed")
	return ""


# --- Getting parts -------------------------------------------------------------------------

static func source_kind(id: String) -> String:
	return str(part(id).get("source", {}).get("kind", ""))


## Research gate for research-source parts ("" = none or done).
static func locked_research(id: String) -> String:
	var src: Dictionary = part(id).get("source", {})
	var rid: String = str(src.get("research", ""))
	if rid != "" and not Research.has(rid):
		return rid
	return ""


## Craftable here (craft, research and set sources).
static func craftable(id: String) -> bool:
	return source_kind(id) in ["craft", "research", "set"]


## Index into GameState.parts of the cheapest stored part of a type at min_rarity or better
## (spares cores a Mk tier still needs where it can).
static func _part_to_use(type_id: String, min_rarity: int) -> int:
	var idx: int = Fleet.part_index(type_id)
	var best: int = -1
	for i: int in GameState.parts.size():
		var p: Dictionary = GameState.parts[i]
		if int(p["type"]) != idx or int(p["rarity"]) < min_rarity:
			continue
		if best < 0 or int(p["rarity"]) < int(GameState.parts[best]["rarity"]):
			best = i
	return best


static func craft_block_reason(id: String) -> String:
	var p: Dictionary = part(id)
	if p.is_empty() or not craftable(id):
		return TranslationServer.translate("Can't be crafted")
	var src: Dictionary = p["source"]
	var lr: String = locked_research(id)
	if lr != "":
		return TranslationServer.translate("Research %s") % TranslationServer.translate(str(Research.def(lr).get("name", lr)))
	var ptype: String = str(src.get("part", ""))
	if ptype != "" and _part_to_use(ptype, int(src.get("min_rarity", 0))) < 0:
		var pname: String = TranslationServer.translate(str(Economy.part_type(Fleet.part_index(ptype)).get("name", ptype)))
		var mr: int = int(src.get("min_rarity", 0))
		return TranslationServer.translate("Needs a %s%s") % ["%s+ " % TranslationServer.translate(str(Economy.rarity(mr).get("name", ""))) if mr > 0 else "", pname]
	if not GameState.can_afford("parts", BigNum.from_float(float(src.get("parts", 0)))):  # [money]
		return TranslationServer.translate("Needs %s") % L10nFmt.amount("parts", float(src.get("parts", 0)))
	if not GameState.can_afford("cubes", BigNum.from_float(float(src.get("cubes", 0)))):
		return TranslationServer.translate("Not enough cubes")
	return ""


## Short cost line, e.g. "40 parts + Drive Wheel Assembly".
static func cost_text(id: String) -> String:
	var src: Dictionary = part(id).get("source", {})
	var bits: Array[String] = []
	match str(src.get("kind", "")):
		"haggle":
			return TranslationServer.translate("Haggle's stall · %s") % Currencies.cost_text({"cubes": src.get("cubes", 0), "parts": src.get("parts", 0)})  # [money]
		"request":
			return TranslationServer.translate("Requests reward · %d requests") % int(src.get("requests", 0))
		"drop":
			return TranslationServer.translate(str(src.get("hint", "Rare find")))
	if int(src.get("parts", 0)) > 0:  # [money]
		bits.append(L10nFmt.amount("parts", float(src["parts"])))
	var ptype: String = str(src.get("part", ""))
	if ptype != "":
		var mr: int = int(src.get("min_rarity", 0))
		bits.append("%s%s" % ["%s+ " % TranslationServer.translate(str(Economy.rarity(mr).get("name", ""))) if mr > 0 else "", TranslationServer.translate(str(Economy.part_type(Fleet.part_index(ptype)).get("name", ptype)))])
	if int(src.get("cubes", 0)) > 0:
		bits.append(TranslationServer.translate("%s cubes") % Settings.fmt(BigNum.from_float(float(src["cubes"]))))
	return TranslationServer.translate("Craft · %s") % " + ".join(bits)


static func craft(id: String) -> bool:
	if craft_block_reason(id) != "":
		return false
	var src: Dictionary = part(id)["source"]
	var ptype: String = str(src.get("part", ""))
	if ptype != "":
		GameState.parts.remove_at(_part_to_use(ptype, int(src.get("min_rarity", 0))))
	GameState.spend("parts", BigNum.from_float(float(src.get("parts", 0))))  # [money]
	GameState.spend("cubes", BigNum.from_float(float(src.get("cubes", 0))))
	add_part(id)
	GameState.inc_stat("builder_crafted")
	Audio.play("hydraulic", 1.2, -8.0)
	Audio.play("buy", 1.1, -4.0)
	return true


## Haggle's builder stall: a few haggle-source parts, reshuffled every rotate_s of play time.
static func haggle_offers(play_time: float = -1.0) -> Array[String]:
	if play_time < 0.0:
		play_time = float(GameState.stats.get("time_played", 0.0))
	var hc: Dictionary = cfg().get("haggle", {})
	var pool: Array[String] = []
	for p: Dictionary in all_parts():
		if str(p.get("source", {}).get("kind", "")) == "haggle":
			pool.append(str(p["id"]))
	var r := RandomNumberGenerator.new()
	r.seed = int(play_time / maxf(float(hc.get("rotate_s", 480)), 1.0)) * 7919 + 17
	var out: Array[String] = []
	while out.size() < mini(int(hc.get("offers", 3)), pool.size()):
		var id: String = pool[r.randi() % pool.size()]
		if not (id in out):
			out.append(id)
	return out


static func haggle_seconds_left(play_time: float = -1.0) -> float:
	if play_time < 0.0:
		play_time = float(GameState.stats.get("time_played", 0.0))
	var rot: float = maxf(float(cfg().get("haggle", {}).get("rotate_s", 480)), 1.0)
	return rot - fmod(play_time, rot)


static func haggle_block_reason(id: String) -> String:
	if not (id in haggle_offers()):
		return TranslationServer.translate("Not in Haggle's stall right now")
	var src: Dictionary = part(id).get("source", {})
	if not GameState.can_afford("cubes", BigNum.from_float(float(src.get("cubes", 0)))):
		return TranslationServer.translate("Not enough cubes")
	if not GameState.can_afford("parts", BigNum.from_float(float(src.get("parts", 0)))):  # [money]
		return TranslationServer.translate("Needs %s") % L10nFmt.amount("parts", float(src.get("parts", 0)))
	return ""


static func buy_haggle(id: String) -> String:
	var why: String = haggle_block_reason(id)
	if why != "":
		return why
	var src: Dictionary = part(id)["source"]
	GameState.spend("cubes", BigNum.from_float(float(src.get("cubes", 0))))
	GameState.spend("parts", BigNum.from_float(float(src.get("parts", 0))))  # [money]
	add_part(id)
	Audio.play("buy", 1.0, -3.0)
	return ""


## Why a part can't be had right now from the builder tab ("" = it can, via craft or Haggle).
static func get_block_reason(id: String) -> String:
	match source_kind(id):
		"haggle":
			return haggle_block_reason(id)
		"request":
			return TranslationServer.translate("Requests reward (%d of %d requests)") % [mini(Contracts.done_total(), int(part(id).get("source", {}).get("requests", 0))), int(part(id).get("source", {}).get("requests", 0))]  # [money]
		"drop":
			return TranslationServer.translate(str(part(id).get("source", {}).get("hint", "Rare find")))
	return craft_block_reason(id)


## Craft it or buy it from Haggle, whichever its source is.
static func obtain(id: String) -> String:
	if source_kind(id) == "haggle":
		return buy_haggle(id)
	var why: String = get_block_reason(id)
	if why != "":
		return why
	craft(id)
	return ""


## A random builder part the player doesn't own yet (token crate), else any non-set part.
static func roll_unowned(r: RandomNumberGenerator) -> String:
	var pool: Array[String] = []
	var any: Array[String] = []
	for p: Dictionary in all_parts():
		var k: String = str(p.get("source", {}).get("kind", ""))
		if k == "set":
			continue
		any.append(str(p["id"]))
		if count(str(p["id"])) == 0:
			pool.append(str(p["id"]))
	var src: Array[String] = pool if not pool.is_empty() else any
	return src[r.randi() % src.size()]


# --- Crew presets --------------------------------------------------------------------------

static func preset(crew: String) -> Dictionary:
	return (st()["presets"] as Dictionary).get(crew, {})


static func save_preset(crew: String, build: Dictionary) -> void:
	(st()["presets"] as Dictionary)[crew] = build.duplicate()
	GameState.inc_stat("builder_presets")
	Audio.play("ding", 1.2, -6.0)


## Fit the crew's preset on every robot of the crew, as far as the bin allows. Returns the
## number of parts fitted.
static func apply_preset(fleet: Fleet, crew: String) -> int:
	var pre: Dictionary = preset(crew)
	if fleet == null or pre.is_empty():
		return 0
	var n: int = 0
	for r: Robot in fleet.robots_with_role(crew):
		for s: String in SLOTS:
			var want: String = str(pre.get(s, ""))
			if want == str(r.build.get(s, "")) or (want != "" and (not fits(want, r.type_id) or count(want) <= 0)):
				continue
			if equip(r, s, want) == "" and want != "":
				n += 1
	return n


## Scan multiplier (1.0 = stock) from parts and trait.
static func scan_of(r: Robot) -> float:
	return float(r.build_mods.get("scan", 1.0))


# --- World hooks (instance) ----------------------------------------------------------------

func _ready() -> void:
	rng.randomize()
	cfg()
	EventBus.robot_built.connect(_on_robot_built)
	EventBus.part_found.connect(_on_part_found)
	if DevHooks.has("builder-sample"):
		sample_inventory()


## Dev / screenshots: a stocked parts bin.
static func sample_inventory() -> void:
	for p: Dictionary in all_parts():
		add_part(str(p["id"]), 2)
	GameState.add_currency("parts", BigNum.from_float(600))  # [money]


## Haggle's welcome gift with the first robot: treads and a bobble plant.
func _on_robot_built(_n: String) -> void:
	if st().get("starter", false):
		return
	st()["starter"] = true
	add_part("treads")
	add_part("bobble_plant")
	EventBus.toast.emit(tr("Haggle: \"First bot? Treads on the house. And a plant, bots like plants.\" (Workbench > Builder)"), "story")


## Dug-up parts sometimes come with a Maker Fragment (much likelier on Vintage/Legendary finds).
func _on_part_found(_t: int, r: int) -> void:
	if _quiet:
		return
	var ch: Array = cfg().get("salvage", {}).get("dig_fragment_chance", [0.02])
	if rng.randf() < float(ch[clampi(r, 0, ch.size() - 1)]):
		add_fragments(1)
		EventBus.toast.emit(tr("A Maker Fragment was tucked inside it: +%d parts.") % int(FRAGMENT_PARTS), "hint")  # [money]


func _process(delta: float) -> void:
	if world == null or get_tree().paused:
		return
	if DevHooks.has("builder-demo") and not _demo_done:
		_demo_done = true
		demo_builds()
		print("[builder] demo builds on %d robots" % (world.fleet.robots().size() if world.get("fleet") else -1))
		if DevHooks.has("builder-shot"):
			_shot_camera()
	_tick += delta
	if _tick < 2.0:
		return
	var dt: float = _tick
	_tick = 0.0
	var fl: Fleet = world.get("fleet")
	if fl == null:
		return
	var sc: Dictionary = cfg().get("salvage", {})
	for r: Robot in fl.robots():
		if r.visual == null or r._idling:
			continue
		if rng.randf() < float(sc.get("base_per_s", 0.001)) * scan_of(r) * dt:
			_salvage_find(r, sc)


func _salvage_find(r: Robot, sc: Dictionary) -> void:
	GameState.inc_stat("builder_salvage_finds")
	if rng.randi() % maxi(int(sc.get("clover_one_in", 40)), 1) == 0:
		add_part("lucky_clover")
		EventBus.toast.emit(tr("%s spotted something green and lucky: a Lucky Clover!") % r.robot_name, "story")
	elif rng.randi() % maxi(int(sc.get("fragment_one_in", 10)), 1) == 0:
		add_fragments(1)
		EventBus.toast.emit(tr("%s spotted a Maker Fragment glinting in the junk: +%d parts.") % [r.robot_name, int(FRAGMENT_PARTS)], "story")  # [money]
	else:
		var t: int = rng.randi() % maxi(Economy.parts.get("types", [1]).size(), 1)
		var rar: int = 0 if rng.randf() < 0.7 else 1
		GameState.parts.append({"type": t, "rarity": rar})
		_quiet = true
		EventBus.part_found.emit(t, rar)
		_quiet = false
		EventBus.toast.emit(tr("%s spotted a %s.") % [r.robot_name, L10nFmt.part_name(rar, t)], "hint")
	Audio.play("detector", 1.4, -10.0)


## --builder-shot: a fixed camera for screenshots. --bshot-cam=x,y,z camera position,
## --bshot-at=x,y,z look-at point; Lumi steps aside (--bshot-lumi keeps her), --bshot-nohud hides HUDs.
func _shot_camera() -> void:
	var cp: PackedStringArray = DevHooks.get_s("bshot-cam", "0,1.4,4.2").split(",")
	var ap: PackedStringArray = DevHooks.get_s("bshot-at", "0,0.5,0.6").split(",")
	var cam := Camera3D.new()
	cam.fov = DevHooks.get_f("bshot-fov", 50.0)
	world.add_child(cam)
	cam.global_position = Vector3(float(cp[0]), float(cp[1]), float(cp[2]))
	cam.look_at(Vector3(float(ap[0]), float(ap[1]), float(ap[2])), Vector3.UP)
	cam.make_current()
	if world.get("patch") and not DevHooks.has("bshot-lumi"):
		world.patch.global_position = Vector3(float(cp[0]), 0.2, float(cp[2]) + 6.0)
	if DevHooks.has("bshot-nohud"):
		for c: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
			if not (c is UpgradesScreen):
				(c as CanvasLayer).visible = false


## --builder-demo: give the robots in the scene distinct showcase builds (screenshots).
func demo_builds() -> void:
	var fl: Fleet = world.get("fleet") if world else null
	if fl == null:
		return
	var looks: Array[Dictionary] = [
		{"chassis": "cargo_hull", "head": "big_eye", "mobility": "treads", "tool": "wide_scoop", "topper": "bobble_plant"},
		{"chassis": "light_frame", "head": "focus_visor", "mobility": "rotor", "tool": "tow_hook", "topper": "crew_flag"},
		{"chassis": "maker_shell", "head": "maker_optic", "mobility": "maker_glider", "tool": "mist_sprayer", "topper": "maker_crest"},
		{"chassis": "sealed_shell", "head": "chatter_dome", "mobility": "legs", "tool": "seed_drill", "topper": "top_hat"},
		{"chassis": "light_frame", "head": "periscope", "mobility": "hover_skirt", "tool": "fine_sieve", "topper": "propeller_cap"},
		{"head": "big_eye", "mobility": "legs", "tool": "long_forks", "topper": "traffic_cone"},
	]
	var i: int = 0
	for r: Robot in fl.robots():
		var b: Dictionary = looks[i % looks.size()].duplicate()
		for s: String in b.keys():
			if not fits(str(b[s]), r.type_id):
				b.erase(s)
		set_build(r, b)
		i += 1
