class_name Research
extends Node
## Research tree (the planet's research table). Static helpers own the rules; state lives in
## GameState.flags["research"] = {done: [ids], active: {id}, paid: [ids], progress: {id: data},
## bank: data}. A node costs stock (cubes, and Parts where it says), paid once when it is first
## started, and field data (systems/field_data.gd), which only work earns: the active node's bar
## fills as Lumi works. One node is active at a time; switching keeps every node's bar. Nothing
## runs on a clock, so time away adds no research (design spec section 6).
## Other systems gate on `Research.has(id)`; stat effects reach the game through Economy.stat
## (see `stat_mod`). An instance of this node (added by the slice) turns work into field data.

const TABLE: String = "research"
const CURRENCY: String = "cubes"

static var _cfg: Dictionary = {}
static var _defs: Dictionary = {}
static var _order: Array[String] = []
static var _story: Array[String] = []  # [v4bots] story unlocks: in _defs, never in the tree (_order)
static var _mods: Dictionary = {}  # stat id -> Vector2(add, mul)
static var _mods_done: Array = []
static var _mods_size: int = -1

var world: Node
var _tick: float = 0.0
var _seen: Dictionary = {}  # stat id -> last value, for "work happened" deltas
var _garden_applied: int = -1


# --- Data ------------------------------------------------------------------------

static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_cfg = Economy.planet_table(TABLE)
	Economy.drop_on_planet_change(_drop_planet_cache)
	for n: Dictionary in _cfg.get("nodes", []):
		_defs[str(n["id"])] = n
		_order.append(str(n["id"]))
	for n: Dictionary in _cfg.get("story_unlocks", []):
		n["story"] = true
		_defs[str(n["id"])] = n
		_story.append(str(n["id"]))


static func reload() -> void:
	_defs.clear()
	_order.clear()
	_story.clear()
	_mods_size = -1
	_ensure()


## Forgets the tree without reloading it: the next reader loads the new planet's table.
static func _drop_planet_cache() -> void:
	_cfg = {}
	_defs.clear()
	_order.clear()
	_story.clear()
	_mods_size = -1


## The planet's research table.
static func config() -> Dictionary:
	_ensure()
	return _cfg


static func ids() -> Array[String]:
	_ensure()
	return _order


static func def(id: String) -> Dictionary:
	_ensure()
	return _defs.get(id, {})


static func exists(id: String) -> bool:
	_ensure()
	return _defs.has(id)


static func branches() -> Array:
	_ensure()
	return _cfg.get("branches", [])


## Field data one kind of work pays, before bonuses (FieldData.reward).
static func reward(kind: String) -> float:
	return FieldData.reward(kind)


# --- State -----------------------------------------------------------------------

static func state() -> Dictionary:
	var s: Variant = GameState.flags.get("research")
	if not (s is Dictionary):
		s = {}
		GameState.flags["research"] = s
	var d: Dictionary = s
	if not d.has("done"):
		d["done"] = []
	var a: Variant = d.get("active", {})
	if d.has("queue") or (a is Dictionary and (a as Dictionary).has("start")):
		FieldData.migrate(d, Time.get_unix_time_from_system())
	if not d.has("active"):
		d["active"] = {}
	if not d.has("paid"):
		d["paid"] = []
	if not d.has("progress"):
		d["progress"] = {}
	if not d.has("bank"):
		d["bank"] = 0.0
	return d


static func done_list() -> Array:
	return state()["done"]


static func active() -> Dictionary:
	return state()["active"]


static func active_id() -> String:
	return str(active().get("id", ""))


## True once a node is researched. The one call other systems need.
static func has(id: String) -> bool:
	var s: Variant = GameState.flags.get("research")
	return s is Dictionary and id in ((s as Dictionary).get("done", []) as Array)


static func is_active(id: String) -> bool:
	return active_id() == id


## True when the node's stock is paid (it was started once): starting it again is free.
static func is_paid(id: String) -> bool:
	return id in (state()["paid"] as Array)


## "researched" | "active" | "paused" (started before, its bar kept) | "available" | "locked"
static func status(id: String) -> String:
	if has(id):
		return "researched"
	if is_story(id):  # [v4bots] arrives by itself, never started
		return "locked"
	if is_active(id):
		return "active"
	if not prereqs_met(id):
		return "locked"
	return "paused" if is_paid(id) else "available"


static func requires(id: String) -> Array:
	return def(id).get("requires", [])


static func prereqs_met(id: String) -> bool:
	for r: String in requires(id):
		if not has(r):
			return false
	return true


## The cube part of a node's stock.
static func cost(id: String) -> BigNum:
	return BigNum.from_float(float(def(id).get("cost", 0)))


## Everything a node's stock costs: {currency: amount} (cubes, and Parts where the node asks).
static func stock(id: String) -> Dictionary:
	var out: Dictionary = {CURRENCY: float(def(id).get("cost", 0))}
	if float(def(id).get("parts", 0)) > 0.0:
		out[Currencies.PARTS] = float(def(id).get("parts", 0))
	return out


## Field data the node needs in all.
static func data_cost(id: String) -> float:
	return FieldData.need(id)


## 0..1 of a node's field data put in (1 once researched).
static func progress(id: String) -> float:
	return FieldData.fraction(id)


static func can_start(id: String) -> bool:
	return reason(id) == ""


## Why a node can't be started right now ("" = it can).
static func reason(id: String) -> String:
	if not exists(id):
		return TranslationServer.translate("Unknown research")
	if is_story(id) and not has(id):  # [v4bots]
		return TranslationServer.translate(str(def(id).get("hint", "Comes later")))
	match status(id):
		"researched":
			return TranslationServer.translate("Already researched")
		"active":
			return TranslationServer.translate("Researching now")
		"paused":
			return ""
		"locked":
			var names: Array[String] = []
			for r: String in requires(id):
				if not has(r):
					names.append(TranslationServer.translate(str(def(r).get("name", r))))
			return TranslationServer.translate("Needs %s") % ", ".join(names)
	# [beat] Garden robots wait for a proper base (the ~1 h garden ramp): min_base_level in data.
	var mb: int = int(def(id).get("min_base_level", 0))
	if mb > 0 and int(GameState.world.get("hub_level", 1)) < mb and Frontiers.bases_at_level(mb) == 0:
		return TranslationServer.translate("Needs base level %d") % mb
	if not GameState.can_afford(CURRENCY, cost(id)):
		return TranslationServer.translate("Not enough cubes")
	if not GameState.can_afford_all(stock(id)):
		return TranslationServer.translate("Not enough Parts")
	return ""


## Makes a node the active one: pays its stock the first time, keeps the bar of the node it
## replaces and draws banked field data into it. Returns true on success.
static func start(id: String) -> bool:
	if not can_start(id):
		return false
	if not is_paid(id):
		GameState.spend_all(stock(id))
		(state()["paid"] as Array).append(id)
	state()["active"] = {"id": id}
	EventBus.research_started.emit(id)
	FieldData.feed_active()
	return true


## Leaves the active node (its bar is kept); field data banks until a node is started.
static func pause() -> void:
	state()["active"] = {}


## The active node's bar is full: it is researched and nothing is active.
static func finish_active() -> void:
	var id: String = active_id()
	if id == "":
		return
	var s: Dictionary = state()
	s["active"] = {}
	(s["progress"] as Dictionary).erase(id)
	(s["paid"] as Array).erase(id)
	_complete(id)


static func _complete(id: String) -> void:
	if not has(id):
		done_list().append(id)
	_mods_size = -1
	GameState.inc_stat("research_done")
	EventBus.research_completed.emit(id)


## Test/dev helper: mark researched immediately (no cost).
static func grant(id: String) -> void:
	if exists(id) and not has(id):
		if is_active(id):
			state()["active"] = {}
		_complete(id)


## A project that comes with something else the player bought (the Bot Bay brings Salvage Logic):
## researched at once, but not a project the player ran, so it is not counted in research_done and
## not announced as finished research.
static func gift(id: String) -> void:
	if exists(id) and not has(id):
		done_list().append(id)
		if is_active(id):
			state()["active"] = {}
		_mods_size = -1


# --- Effects ---------------------------------------------------------------------

static func _rebuild_mods() -> void:
	var done: Array = done_list()
	if _mods_size == done.size() and is_same(_mods_done, done):
		return
	_mods.clear()
	for id: String in done:
		for e: Dictionary in def(id).get("effects", []):
			if not e.has("stat"):
				continue
			var m: Vector2 = _mods.get(str(e["stat"]), Vector2(0.0, 1.0))
			if str(e.get("mode", "add")) == "add":
				m.x += float(e["amount"])
			else:
				m.y *= 1.0 + float(e["amount"])
			_mods[str(e["stat"])] = m
	_mods_done = done
	_mods_size = done.size()


## Applies researched bonuses to a stat value. Economy.stat calls this for every stat.
static func stat_mod(stat_id: String, value: float) -> float:
	var s: Variant = GameState.flags.get("research")
	if not (s is Dictionary) or ((s as Dictionary).get("done", []) as Array).is_empty():
		return value
	_rebuild_mods()
	if not _mods.has(stat_id):
		return value
	var m: Vector2 = _mods[stat_id]
	return (value + m.x) * m.y


## Breakdown rows for the stat tooltip: [{source, text}].
static func breakdown(stat_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var s: Variant = GameState.flags.get("research")
	if not (s is Dictionary):
		return out
	for id: String in done_list():
		for e: Dictionary in def(id).get("effects", []):
			if str(e.get("stat", "")) != stat_id:
				continue
			var txt: String = ("+%s" % _num(float(e["amount"]))) if str(e.get("mode", "add")) == "add" else "x%.2f" % (1.0 + float(e["amount"]))
			out.append({"source": TranslationServer.translate("Research: %s") % TranslationServer.translate(str(def(id).get("name", id))), "text": txt})
	return out


static func _num(v: float) -> String:
	return str(int(round(v))) if is_equal_approx(v, round(v)) else "%.2f" % v


# l10n:begin
const STAT_NAMES: Dictionary = {
	"scoop_reach": "scoop reach", "scoop_width": "scoop width", "capacity": "compartment size",
	"cube_value_mult": "bale value", "magnet_radius": "magnet radius", "scoop_rate": "scoop speed",
	"data_gain": "field data", "research_speed": "research speed", "lake_clarity": "lake clarity",
	"speed": "speed", "work_rate": "work rate", "tank": "tank", "range": "range",
	"efficiency": "bale quality", "carry": "carry",
	"plant_growth": "plant growth", "seed_yield": "seeds per bloom",
}
# l10n:end


## Human lines for a node's effects ("+20% scoop width", "Unlocks Seedling").
static func effect_lines(id: String) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in def(id).get("effects", []):
		if e.has("stat"):
			var sid: String = str(e["stat"])
			var who: String = ""
			if "." in sid:
				who = TranslationServer.translate(str(Economy.robots.get(sid.get_slice(".", 0), {}).get("name", sid.get_slice(".", 0))))
				sid = sid.get_slice(".", 1)
			var nm: String = TranslationServer.translate(str(STAT_NAMES.get(sid, sid.replace("_", " "))))
			if str(e.get("mode", "add")) == "add":
				out.append(L10nFmt.stat_effect(_num(float(e["amount"])), false, who, nm))  # [i18n2]
			else:
				out.append(L10nFmt.stat_effect(str(int(round(float(e["amount"]) * 100.0))), true, who, nm))
		elif e.has("unlock_robot"):
			out.append(TranslationServer.translate("Unlocks the %s robot") % TranslationServer.translate(str(Economy.robots.get(str(e["unlock_robot"]), {}).get("name", e["unlock_robot"]))))
		elif e.has("unlock_plant"):
			out.append(TranslationServer.translate("Unlocks %s seeds") % str(e["unlock_plant"]).capitalize())
		elif e.has("flag"):
			out.append(TranslationServer.translate("Unlocks: %s") % TranslationServer.translate(str(def(id).get("name", id))))
	return out


# --- Gates -----------------------------------------------------------------------

## Robot types with `requires_research` in data/robots.json stay unbuildable until researched.
static func robot_unlocked(type_id: String) -> bool:
	var req: String = str(Economy.robots.get(type_id, {}).get("requires_research", ""))
	return req == "" or has(req)


static func robot_requirement(type_id: String) -> String:
	return str(Economy.robots.get(type_id, {}).get("requires_research", ""))


## [v4bots] What a locked robot card says: the research to do, or a story unlock's hint.
static func robot_lock_text(type_id: String) -> String:
	var req: String = robot_requirement(type_id)
	if is_story(req):
		return TranslationServer.translate(str(def(req).get("hint", "Comes later")))
	return TranslationServer.translate("Research: %s") % TranslationServer.translate(str(def(req).get("name", "?")))


# --- Story unlocks ([v4bots]) ------------------------------------------------------------
# Owner 2026-11-09: the Scoopie comes alone, the Haul Bug a while later, the Skimmer later still.
# They are not tree cards: they arrive by themselves (data/research.json story_unlocks).

static func is_story(id: String) -> bool:
	return bool(def(id).get("story", false))


static func story_ids() -> Array[String]:
	_ensure()
	return _story


## One story condition: the workbench.json ones, plus since_first_robot and owned.
static func story_cond(c: Array, w: Node = null) -> bool:
	match str(c[0]):
		"cities_open":  # this many of the planet's cities are unlocked
			return Economy.tiers_open() >= int(c[1])
		"since_first_robot":
			if not GameState.flags.has("first_robot_t"):
				return false
			return float(GameState.stats.get("time_played", 0.0)) - float(GameState.flags["first_robot_t"]) >= float(c[1])
		"owned":
			var f: Variant = w.get("fleet") if w != null and is_instance_valid(w) else null
			return f != null and is_instance_valid(f) and (f as Object).has_method("count") and int((f as Object).call("count", str(c[1]))) >= int(c[2])
	return UpgradesScreen.cond_ok(c, w)


static func story_ready(id: String, w: Node = null) -> bool:
	if has(id) or not is_story(id):
		return false
	var d: Dictionary = def(id)
	for r: String in d.get("requires", []):
		if not has(r):
			return false
	for c: Variant in d.get("any", []):
		if c is Array and story_cond(c, w):
			return true
	var when: Array = d.get("when", [])
	if when.is_empty():
		return false
	for c: Variant in when:
		if not (c is Array and story_cond(c, w)):
			return false
	return true


## Marks the first robot's time, then grants every story unlock that is due (quietly: no
## research_done stat, no research toast). Sets flags[id] for the objectives' wait_flag.
static func check_story(w: Node = null) -> Array[String]:
	var out: Array[String] = []
	if not GameState.flags.has("first_robot_t") and float(GameState.stats.get("robots_built", 0.0)) >= 1.0:
		GameState.flags["first_robot_t"] = float(GameState.stats.get("time_played", 0.0))
	for id: String in story_ids():
		if story_ready(id, w):
			unlock_story(id)
			out.append(id)
	return out


static func unlock_story(id: String) -> void:
	if not exists(id) or has(id):
		return
	done_list().append(id)
	_mods_size = -1
	GameState.flags[id] = true


static func plant_unlocked(species: Dictionary) -> bool:
	var req: String = str(species.get("requires_research", ""))
	return req == "" or has(req)


## Zeroes the pick weight of locked species in a Garden (restores it once researched).
## New species sit at the end of plants.json, so a roll that lands on a locked one falls back
## to the first species.
static func apply_garden(garden: Node) -> void:
	if garden == null or not ("species" in garden):
		return
	for sp: Dictionary in garden.get("species"):
		if not sp.has("_base_weight"):
			sp["_base_weight"] = float(sp.get("weight", 1.0))
		sp["weight"] = float(sp["_base_weight"]) if plant_unlocked(sp) else 0.0


# --- Field data ------------------------------------------------------------------------

## [money] Cubes one old Data unit was worth (parked systems still count in it).
static func note_cubes() -> float:
	_ensure()
	return float(_cfg.get("note_cubes", 10.0))


## Adds field data from work (after bonuses): see FieldData.award. Returns the data added.
static func award_data(base: float, kind: String = "") -> float:
	return FieldData.award(base, kind)


# --- Live node -------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Methods, not lambdas: a lambda that calls only static functions is not tied to this node, so
	# its connection would outlive the node and every world built would pay the data once more.
	EventBus.hex_cleaned.connect(_on_hex_cleaned)
	EventBus.hex_level_changed.connect(_on_hex_level)
	EventBus.mastery_gained.connect(_on_mastery)
	EventBus.piece_found.connect(_on_piece_found)
	EventBus.source_step_done.connect(_on_source_step)
	EventBus.source_shut_down.connect(_on_source_shut)
	EventBus.research_completed.connect(_on_completed)
	_seen["shards_found"] = float(GameState.stats.get("shards_found", 0.0))


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	for sid: String in check_story(world):  # [v4bots] the Haul Bug / Skimmer plans arrive
		_announce_story(sid)
	var v: float = float(GameState.stats.get("shards_found", 0.0))
	var d: float = v - float(_seen.get("shards_found", v))
	_seen["shards_found"] = v
	if d > 0.0:
		award_data(d * reward("shard_read"), "shard_read")
	if world and "garden" in world and world.get("garden") != null and _garden_applied != done_list().size():
		_garden_applied = done_list().size()
		apply_garden(world.get("garden"))


## [v4bots] One message for a story unlock: WREN says it, or (while she is silent) a toast.
func _announce_story(id: String) -> void:
	Audio.play("chime", 1.2, -3.0)
	var line: String = tr(str(def(id).get("line", "")))
	var w: Variant = world.get("wren") if world != null and is_instance_valid(world) else null
	if w != null and is_instance_valid(w) and w is Wren and (w as Wren).awake() and line != "":
		(w as Wren).speak(line, (w as Wren).stage())
	else:
		EventBus.toast.emit(tr("New robot plans: %s. %s") % [tr(str(def(id).get("name", id))), ". ".join(effect_lines(id))], "story")


func _on_hex_cleaned(_hex_id: int, _pos: Vector3, _bonus: BigNum) -> void:
	award_data(reward("hex_cleaned"), "hex_cleaned")


## A hex reached a regrowth stage (stage 1, clean, is paid by hex_cleaned).
func _on_hex_level(_hex_id: int, level: int) -> void:
	if level >= 2:
		award_data(FieldData.stage_reward(level), "hex_stage")


func _on_mastery(_kind: String, _level: int) -> void:
	award_data(reward("mastery_level"), "mastery_level")


func _on_piece_found(_piece_id: String, _source: String) -> void:
	award_data(reward("piece_found"), "piece_found")


func _on_source_step(_district_id: String, _step: int) -> void:
	award_data(reward("source_step"), "source_step")


func _on_source_shut(_district_id: String) -> void:
	award_data(reward("source_shut"), "source_shut")


func _on_completed(id: String) -> void:
	Audio.play("chime", 1.2, -3.0)
	EventBus.toast.emit(tr("Research complete: %s.") % tr(str(def(id).get("name", id))), "goal" if Once.take("toast_first_research") else "reward")  # [v4calm] no stat list; the first one only
	_garden_applied = -1
