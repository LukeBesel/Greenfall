class_name Research
extends Node
## Research tree (data/research.json). Static helpers own the rules; state lives in
## GameState.flags["research"] = {done: [ids], active: {id, start, dur}, queue: [ids]}.
## Research runs on wall-clock unix time, so it keeps going while paused, in menus and offline.
## Other systems gate on `Research.has(id)`; stat effects reach the game through Economy.stat
## (see `stat_mod`). An instance of this node (added by the slice) awards Data and finishes
## research while playing.

const PATH: String = "res://data/research.json"
const CURRENCY: String = "cubes"  # [money] research costs cubes (was Data) plus real time

static var _cfg: Dictionary = {}
static var _defs: Dictionary = {}
static var _order: Array[String] = []
static var _story: Array[String] = []  # [v4bots] story unlocks: in _defs, never in the tree (_order)
static var _mods: Dictionary = {}  # stat id -> Vector2(add, mul)
static var _mods_done: Array = []
static var _mods_size: int = -1
## Tests set this to drive time; < 0 means use the system clock.
static var now_override: float = -1.0

var world: Node
var _tick: float = 0.0
var _seen: Dictionary = {}  # stat id -> last value, for "work happened" deltas
var _garden_applied: int = -1


# --- Data ------------------------------------------------------------------------

static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_cfg = Economy.read_json(PATH)
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


static func max_queue() -> int:
	_ensure()
	return int(_cfg.get("max_queue", 3))


static func reward(kind: String) -> float:
	_ensure()
	return float(_cfg.get("data_rewards", {}).get(kind, 0.0))


static func now() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


# --- State -----------------------------------------------------------------------

static func state() -> Dictionary:
	var s: Variant = GameState.flags.get("research")
	if not (s is Dictionary):
		s = {}
		GameState.flags["research"] = s
	var d: Dictionary = s
	if not d.has("done"):
		d["done"] = []
	if not d.has("queue"):
		d["queue"] = []
	if not d.has("active"):
		d["active"] = {}
	return d


static func done_list() -> Array:
	return state()["done"]


static func queue() -> Array:
	return state()["queue"]


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


static func is_queued(id: String) -> bool:
	return id in queue()


static func queue_position(id: String) -> int:
	return queue().find(id)


## "researched" | "active" | "queued" | "available" | "locked"
static func status(id: String) -> String:
	if has(id):
		return "researched"
	if is_story(id):  # [v4bots] arrives by itself, never started
		return "locked"
	if is_active(id):
		return "active"
	if is_queued(id):
		return "queued"
	var rt: String = str(def(id).get("requires_tech", ""))  # [pace2]
	if rt != "" and not Homeward.has_tech(rt):
		return "locked"
	return "available" if prereqs_met(id, true) else "locked"


static func requires(id: String) -> Array:
	return def(id).get("requires", [])


## Prerequisites researched (or, with allow_pending, already running/queued ahead of this).
static func prereqs_met(id: String, allow_pending: bool = false) -> bool:
	for r: String in requires(id):
		if has(r):
			continue
		if allow_pending and (is_active(r) or is_queued(r)):
			continue
		return false
	return true


static func cost(id: String) -> BigNum:
	return BigNum.from_float(float(def(id).get("cost", 0)))


## Real seconds to research, after research-speed bonuses.
static func duration(id: String) -> float:
	return float(def(id).get("time_s", 60)) / maxf(Designs.apply("research_speed", stat_mod("research_speed", 1.0)), 0.1)  # [skins] design buff


static func can_start(id: String) -> bool:
	return reason(id) == ""


## Why a node can't be started right now ("" = it can).
static func reason(id: String) -> String:
	if not exists(id):
		return TranslationServer.translate("Unknown research")
	if is_story(id) and not has(id):  # [v4bots]
		return TranslationServer.translate(str(def(id).get("hint", "Comes later")))
	var rt: String = str(def(id).get("requires_tech", ""))  # [pace2] tools from later planets
	if rt != "" and not Homeward.has_tech(rt) and not has(id):
		return Homeward.tech_hint(rt)
	match status(id):
		"researched":
			return TranslationServer.translate("Already researched")
		"active":
			return TranslationServer.translate("Researching now")
		"queued":
			return TranslationServer.translate("Already queued")
		"locked":
			var names: Array[String] = []
			for r: String in requires(id):
				if not has(r) and not is_active(r) and not is_queued(r):
					names.append(TranslationServer.translate(str(def(r).get("name", r))))
			return TranslationServer.translate("Needs %s") % ", ".join(names)
	# [beat] Garden robots wait for a proper base (the ~1 h garden ramp): min_base_level in data.
	var mb: int = int(def(id).get("min_base_level", 0))
	if mb > 0 and int(GameState.world.get("hub_level", 1)) < mb and Frontiers.bases_at_level(mb) == 0:
		return TranslationServer.translate("Needs base level %d") % mb
	if not active().is_empty() and queue().size() >= max_queue():
		return TranslationServer.translate("Queue is full")
	if not GameState.can_afford(CURRENCY, cost(id)):
		return TranslationServer.translate("Not enough cubes")
	return ""


## Pays and starts (or queues) a node. Returns true on success.
static func start(id: String, t: float = -1.0) -> bool:
	if not can_start(id):
		return false
	var at: float = now() if t < 0.0 else t
	GameState.spend(CURRENCY, cost(id))
	if active().is_empty():
		_activate(id, at)
	else:
		queue().append(id)
	return true


static func _activate(id: String, at: float) -> void:
	state()["active"] = {"id": id, "start": at, "dur": duration(id)}


## Cancels a running or queued node with a full refund; queued nodes that depended on it go too.
static func cancel(id: String, t: float = -1.0) -> bool:
	var at: float = now() if t < 0.0 else t
	var removed: Array[String] = []
	if is_active(id):
		state()["active"] = {}
		removed.append(id)
	elif is_queued(id):
		queue().erase(id)
		removed.append(id)
	else:
		return false
	# Cascade: drop queued nodes whose prerequisites are no longer pending or done.
	var changed: bool = true
	while changed:
		changed = false
		for q: String in queue().duplicate():
			if not _prereqs_before(q):
				queue().erase(q)
				removed.append(q)
				changed = true
	for r: String in removed:
		GameState.add_currency(CURRENCY, cost(r))
	if active().is_empty():
		_start_next(at)
	return true


## Prereqs are done, active, or earlier in the queue than `id`.
static func _prereqs_before(id: String) -> bool:
	var pos: int = queue_position(id)
	for r: String in requires(id):
		if has(r) or is_active(r):
			continue
		var rp: int = queue_position(r)
		if rp < 0 or (pos >= 0 and rp > pos):
			return false
	return true


static func _start_next(at: float) -> void:
	while not queue().is_empty():
		var nxt: String = str(queue().pop_front())
		if prereqs_met(nxt):
			_activate(nxt, at)
			return
		GameState.add_currency(CURRENCY, cost(nxt))  # shouldn't happen; refund to be safe


static func progress(id: String = "", t: float = -1.0) -> float:
	var a: Dictionary = active()
	if a.is_empty() or (id != "" and str(a["id"]) != id):
		return 1.0 if id != "" and has(id) else 0.0
	var at: float = now() if t < 0.0 else t
	return clampf((at - float(a["start"])) / maxf(float(a["dur"]), 0.001), 0.0, 1.0)


static func remaining(t: float = -1.0) -> float:
	var a: Dictionary = active()
	if a.is_empty():
		return 0.0
	var at: float = now() if t < 0.0 else t
	return maxf(0.0, float(a["start"]) + float(a["dur"]) - at)


## Finishes everything that is due by time t (chains through the queue, so offline time
## completes several nodes). Returns the ids completed, in order.
static func update(t: float = -1.0) -> Array[String]:
	var at: float = now() if t < 0.0 else t
	var out: Array[String] = []
	var guard: int = 0
	while guard < 64:
		guard += 1
		var a: Dictionary = active()
		if a.is_empty():
			if queue().is_empty():
				break
			_start_next(at)
			continue
		var end: float = float(a["start"]) + float(a["dur"])
		if at < end:
			break
		var id: String = str(a["id"])
		state()["active"] = {}
		_complete(id)
		out.append(id)
		_start_next(end)
	return out


static func _complete(id: String, counted: bool = true) -> void:
	if not has(id):
		done_list().append(id)
	_mods_size = -1
	if counted:
		GameState.inc_stat("research_done")
	EventBus.research_completed.emit(id)


## Test/dev helper: mark researched immediately (no cost).
## [v9b] A grant (the Bot Bay's Salvage Logic, rewards) is not a research project the player
## finished: it no longer counts in research_done, so "Finish a research project" can't complete
## itself the moment the Bot Bay is bought (it did, before the Research tab even existed).
static func grant(id: String) -> void:
	if exists(id) and not has(id):
		_complete(id, false)


static func time_text(s: float) -> String:
	var n: int = int(ceil(s))
	if n >= 60:
		@warning_ignore("integer_division")
		return "%d:%02d" % [n / 60, n % 60]
	return TranslationServer.translate("%ds") % n


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
	"data_gain": "field-note cubes", "research_speed": "research speed", "lake_clarity": "lake clarity",
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


## [v9b] How far a story unlock's timed conditions are (0..1), for the card's bar while it waits:
## the slowest of its `when` conditions (time since the first robot, a stat), or 1 when any `any`
## condition already holds. -1 when it has no `when` list.
static func story_progress(id: String, w: Node = null) -> float:
	if has(id):
		return 1.0
	var d: Dictionary = def(id)
	for c: Variant in d.get("any", []):
		if c is Array and story_cond(c, w):
			return 1.0
	var when: Array = d.get("when", [])
	if when.is_empty():
		return -1.0
	var f: float = 1.0
	for c: Variant in when:
		if not c is Array:
			continue
		var ca: Array = c
		match str(ca[0]):
			"since_first_robot":
				var t0: float = float(GameState.flags.get("first_robot_t", 0.0))
				f = minf(f, 0.0 if not GameState.flags.has("first_robot_t") else clampf((float(GameState.stats.get("time_played", 0.0)) - t0) / maxf(float(ca[1]), 1.0), 0.0, 1.0))
			"stat":
				f = minf(f, clampf(float(GameState.stats.get(str(ca[1]), 0.0)) / maxf(float(ca[2]), 1.0), 0.0, 1.0))
			_:
				f = minf(f, 1.0 if story_cond(ca, w) else 0.0)
	return f


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


# --- Field notes ----------------------------------------------------------------------

## [money] Cubes per field note (data/research.json note_cubes; the old Data's worth).
static func note_cubes() -> float:
	_ensure()
	return float(_cfg.get("note_cubes", 10.0))


## Logs field notes (after research bonuses): they pay cubes (note_cubes each), so the old Data
## income is still there and research, which costs cubes now, paces as before. Returns the notes
## logged; stats.data_earned counts notes (achievements), stats.notes_cubes the cubes paid.
static func award_data(base: float) -> float:
	if base <= 0.0:
		return 0.0
	var amt: float = stat_mod("data_gain", 1.0) * base
	var c: float = amt * note_cubes()
	GameState.add_currency("cubes", BigNum.from_float(c))
	GameState.inc_stat("data_earned", amt)
	GameState.inc_stat("notes_cubes", c)
	return amt


# --- Live node -------------------------------------------------------------------

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: award_data(reward("hex_cleaned")))
	EventBus.hex_restored.connect(func(_h: int) -> void: award_data(reward("hex_restored")))
	for k: String in ["plants_bloomed", "shards_found", "robot_bales"]:
		_seen[k] = float(GameState.stats.get(k, 0.0))
	# Finish whatever completed while we were away (quietly, then one summary toast).
	var finished: Array[String] = update()
	EventBus.research_completed.connect(_on_completed)
	if not finished.is_empty():
		var names: Array[String] = []
		for id: String in finished:
			names.append(tr(str(def(id).get("name", id))))
		(func() -> void: EventBus.toast.emit(tr("While you were away, research finished: %s.") % ", ".join(names), "story")).call_deferred()


func _process(delta: float) -> void:
	_tick += delta
	if _tick < 0.5:
		return
	_tick = 0.0
	update()
	for sid: String in check_story(world):  # [v4bots] the Haul Bug / Skimmer plans arrive
		_announce_story(sid)
	var rewards: Dictionary = {"plants_bloomed": "plant_bloomed", "shards_found": "shard_read", "robot_bales": "robot_bale"}
	for k: String in rewards:
		var v: float = float(GameState.stats.get(k, 0.0))
		var d: float = v - float(_seen.get(k, v))
		_seen[k] = v
		if d > 0.0:
			award_data(d * reward(rewards[k]))
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


func _on_completed(id: String) -> void:
	Audio.play("chime", 1.2, -3.0)
	EventBus.toast.emit(tr("Research complete: %s.") % tr(str(def(id).get("name", id))), "goal" if Once.take("toast_first_research") else "reward")  # [v4calm] no stat list; the first one only
	_garden_applied = -1
