class_name Goals
extends Node
## The planet's goals in tiers (its `goals` table; design spec section 10): short (the next
## concrete thing, minutes), medium (a city milestone) and long (the planet's arc). One goal of
## each tier is active at a time; when it completes the next of its tier takes its place.
##
## A tier's active goal is its first authored goal, in table order, that is on offer and not done.
## When none is left the tier falls back on its repeating goals ("Clean 3 more hexes"). From that
## moment all of them count side by side, and the row shows the one nearest done: whatever the
## player is doing, the next small win is the one on show. So a tier never stands empty.
##
## A tier may set a patience: an authored goal that has held the tier's row that long with no
## progress steps aside for good, so a goal the player is not after (an optional build, a skill)
## never blocks the row. It still pays when it is finished.
##
## An authored goal pays the moment its condition holds, wherever it stands in its tier and
## whatever the story card shows (design spec section 14: rewards never wait and never land in a
## burst): one per beat. So does a repeating goal, once its tier has fallen back on them.
## Saved in GameState.flags: FLAG_DONE (ids of finished authored goals), FLAG_REPEAT (how often
## each repeating goal was finished, where its count started and which one a tier is on) and
## FLAG_ASIDE (ids of goals that stepped aside).

signal completed(index: int)
## A tier has a new active goal (-1: the tier has nothing left).
signal tier_changed(tier: String, index: int)

const BEAT_S: float = 0.7
## How much further along (0..1) another repeating goal must be to take the row from the one on it.
const LEAD: float = 0.25
const FLAG_DONE: String = "goals_done"
const FLAG_REPEAT: String = "goals_repeat"
const FLAG_ASIDE: String = "goals_aside"
## Set once a save has been through the tier chain (see _catch_up_old_save).
const FLAG_TIERS: String = "goals_tiers"
const STAT_DONE: String = "goals_completed"

var world: Node
var cfg: Dictionary
var chain: Array = []
## The index the story card is showing and will complete itself (-1: none).
var card_goal: int = -1
var _tiers: Array[Dictionary] = []
var _done: Dictionary = {}
var _counts: Dictionary = {}
var _bases: Dictionary = {}
var _on: Dictionary = {}
var _shown: Dictionary = {}
var _active: Dictionary = {}
var _aside: Dictionary = {}
## Per tier: the goal holding the row, its best value so far and when that was reached.
var _held: Dictionary = {}
var _old_save: bool = false
var _tick: float = 0.0


func _ready() -> void:
	load_chain()
	EventBus.junk_scooped.connect(_on_junk_scooped)  # a method: the engine drops it with this node


func _process(delta: float) -> void:
	_tick += delta
	if _tick >= BEAT_S:
		_tick = 0.0
		check()


func load_chain() -> void:
	cfg = Economy.planet_table("goals")
	chain = cfg.get("goals", [])
	_tiers.clear()
	for t: Variant in cfg.get("tiers", []):
		if t is Dictionary:
			_tiers.append(t)
	_done.clear()
	for id: Variant in GameState.flags.get(FLAG_DONE, []):
		_done[str(id)] = true
	var rep: Dictionary = GameState.flags.get(FLAG_REPEAT, {})
	_counts = (rep.get("n", {}) as Dictionary).duplicate()
	_bases = (rep.get("base", {}) as Dictionary).duplicate()
	_on = (rep.get("on", {}) as Dictionary).duplicate()
	_aside.clear()
	for id: Variant in GameState.flags.get(FLAG_ASIDE, []):
		_aside[str(id)] = true
	_shown.clear()
	_active.clear()
	_held.clear()
	_old_save = not GameState.flags.has(FLAG_TIERS) and not _done.is_empty()
	GameState.flags[FLAG_TIERS] = true


# --- Tiers ------------------------------------------------------------------------------------

## Tier ids in the table's order (the order the HUD lists them).
func tier_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in _tiers:
		out.append(str(t.get("id", "")))
	return out


## The tier's label, in English (translated where it is shown).
func tier_name(tier: String) -> String:
	for t: Dictionary in _tiers:
		if str(t.get("id", "")) == tier:
			return str(t.get("name", tier))
	return tier


## A goal with no tier belongs to the first one.
func tier_of(i: int) -> String:
	return str(chain[i].get("tier", _tiers[0].get("id", "") if not _tiers.is_empty() else ""))


func is_repeat(i: int) -> bool:
	return chain[i].has("repeat")


## The tier's active goal (-1 when it has none), as of the last beat: check() and complete() bring
## it up to date, and refresh() does on demand. The HUD asks every frame, so it is not worked out
## on each call.
func active(tier: String) -> int:
	if _active.is_empty():
		refresh()
	return int(_active.get(tier, -1))


## Works out each tier's active goal from the state of the game now.
func refresh() -> void:
	for tier: String in tier_ids():
		var i: int = _pick(tier)
		if i >= 0 and not is_repeat(i) and _out_of_patience(tier, i):
			step_aside(i)
			i = _pick(tier)
		_active[tier] = i


## How long an authored goal may hold the tier's row without progress (0 = as long as it takes).
func patience_s(tier: String) -> float:
	for t: Dictionary in _tiers:
		if str(t.get("id", "")) == tier:
			return float(t.get("patience_s", 0.0))
	return 0.0


## Whether a goal has stepped aside: it no longer holds its tier's row, and still pays when done.
func is_aside(i: int) -> bool:
	return _aside.has(str(chain[i]["id"]))


func step_aside(i: int) -> void:
	_aside[str(chain[i]["id"])] = true
	GameState.flags[FLAG_ASIDE] = _aside.keys()


## True once goal `i` has held its tier's row for the tier's patience with its count standing
## still. Progress starts the wait again.
func _out_of_patience(tier: String, i: int) -> bool:
	var limit: float = patience_s(tier)
	if limit <= 0.0:
		return false
	var now: float = float(GameState.stats.get("time_played", 0.0))
	var value: float = value_of(i)
	var held: Dictionary = _held.get(tier, {})
	if int(held.get("goal", -1)) != i or value > float(held.get("value", 0.0)) or now < float(held.get("since", 0.0)):
		_held[tier] = {"goal": i, "value": value, "since": now}
		return false
	return now - float(held["since"]) >= limit


## Goals offered by a flag come first, so what the player just came across is the next step.
func _pick(tier: String) -> int:
	for flagged: bool in [true, false]:
		for i: int in chain.size():
			if tier_of(i) != tier or chain[i].has("after_flag") != flagged or is_repeat(i) or is_done(i) or is_aside(i):
				continue
			if is_offered(i):
				return i
	return _active_repeat(tier)


## Chain indices of the active goals, one per tier, in tier order.
func current() -> Array[int]:
	var out: Array[int] = []
	for tier: String in tier_ids():
		var i: int = active(tier)
		if i >= 0:
			out.append(i)
	return out


## The repeating goal on a tier's row: the one nearest done. The one already on the row keeps it
## until another is clearly further along (LEAD), so the row does not flicker between two jobs.
func _active_repeat(tier: String) -> int:
	var best: int = -1
	var best_share: float = -1.0
	var kept: int = -1
	var kept_id: String = str(_on.get(tier, ""))
	for i: int in chain.size():
		if tier_of(i) != tier or not is_repeat(i) or not is_offered(i):
			continue
		var share: float = progress(i)
		if str(chain[i]["id"]) == kept_id:
			kept = i
		if share > best_share:
			best = i
			best_share = share
	return kept if kept >= 0 and best_share < progress(kept) + LEAD else best


# --- One goal ---------------------------------------------------------------------------------

## A repeating goal is never done for good.
func is_done(i: int) -> bool:
	return not is_repeat(i) and _done.has(str(chain[i]["id"]))


## How often a repeating goal was finished.
func times_done(i: int) -> int:
	return int(_counts.get(str(chain[i]["id"]), 0))


## Goals finished so far, repeats included.
func done_count() -> int:
	var n: int = 0
	for i: int in chain.size():
		n += times_done(i) if is_repeat(i) else (1 if is_done(i) else 0)
	return n


## Authored goals in the chain (the repeating ones have no end to count).
func authored_count() -> int:
	var n: int = 0
	for i: int in chain.size():
		n += 0 if is_repeat(i) else 1
	return n


## A goal is on offer when its `after_flag` is set and its `when` condition holds: it belongs to
## something the player has reached (a found piece, an opened city, a first robot).
func is_offered(i: int) -> bool:
	var g: Dictionary = chain[i]
	var flag: String = str(g.get("after_flag", ""))
	if flag != "" and not bool(GameState.flags.get(flag, false)):
		return false
	var when: Variant = g.get("when", null)
	return not when is Dictionary or GoalMeasures.value(world, when) >= float((when as Dictionary).get("target", 1))


func value_of(i: int) -> float:
	return GoalMeasures.value(world, chain[i])


## What value_of must reach. A repeating goal asks for repeat_amount more than its count stood at
## when it came up.
func target_of(i: int) -> float:
	if not is_repeat(i):
		return float(chain[i].get("target", 1))
	return _base_of(i) + float(repeat_amount(i))


## How much a repeating goal asks for this time: `repeat`, plus `repeat_grow` for each time it was
## finished, up to `repeat_max`. So the job grows with the player instead of turning into noise.
func repeat_amount(i: int) -> int:
	var g: Dictionary = chain[i]
	var amount: int = int(g.get("repeat", 1)) + int(g.get("repeat_grow", 0)) * times_done(i)
	return mini(amount, int(g["repeat_max"])) if g.has("repeat_max") else amount


## [have, need] as the HUD counts them: a repeating goal from zero.
func counts(i: int) -> Array[float]:
	var base: float = _base_of(i) if is_repeat(i) else 0.0
	var need: float = target_of(i) - base
	return [clampf(value_of(i) - base, 0.0, need), need]


func progress(i: int) -> float:
	var c: Array[float] = counts(i)
	return clampf(c[0] / maxf(c[1], 0.0001), 0.0, 1.0)


## The goal's title, translated; a repeating goal's "%d" is its amount.
func text_of(i: int) -> String:
	var text: String = tr(str(chain[i].get("text", "")))
	return (text % repeat_amount(i)) if is_repeat(i) and text.contains("%d") else text


func reward_of(i: int) -> Dictionary:
	return chain[i].get("reward", {})


func _base_of(i: int) -> float:
	var id: String = str(chain[i]["id"])
	return float(_bases[id]) if _bases.has(id) else value_of(i)


# --- Completing -------------------------------------------------------------------------------

## Completes at most one goal whose condition holds, anywhere in the chain (the card's own goal is
## left to the card). Returns its index or -1.
func check() -> int:
	if _old_save:
		_catch_up_old_save()
	refresh()
	_arm_repeats()
	for i: int in chain.size():
		if i == card_goal or is_done(i) or not is_offered(i):
			continue
		if is_repeat(i) and not _bases.has(str(chain[i]["id"])):
			continue  # its tier has not fallen back on its repeating goals yet
		if value_of(i) >= target_of(i):
			complete(i)
			return i
	_announce()
	return -1


func complete(i: int) -> void:
	if is_done(i):
		return
	var id: String = str(chain[i]["id"])
	if is_repeat(i):
		_counts[id] = times_done(i) + 1
		_bases.erase(id)
		if str(_on.get(tier_of(i), "")) == id:
			_on.erase(tier_of(i))
		_store_repeats()
	else:
		_done[id] = true
		var arr: Array = GameState.flags.get(FLAG_DONE, [])
		arr.append(id)
		GameState.flags[FLAG_DONE] = arr
	var r: Dictionary = reward_of(i)
	for k: String in r:
		if float(r[k]) > 0.0:
			GameState.add_currency(k, BigNum.from_float(float(r[k])))
	GameState.inc_stat(STAT_DONE)
	Audio.play("coin", 1.15, -6.0)
	Audio.play("chime", 1.3, -10.0)
	refresh()
	completed.emit(i)
	_arm_repeats()
	_announce()


## Once a tier has fallen back on its repeating goals, every one of them on offer counts from
## where its stat stands, and the one on the row is remembered.
func _arm_repeats() -> void:
	var changed: bool = false
	for tier: String in tier_ids():
		var i: int = active(tier)
		if i >= 0 and is_repeat(i) and str(_on.get(tier, "")) != str(chain[i]["id"]):
			_on[tier] = str(chain[i]["id"])
			changed = true
		if not _fallen_back(tier) and (i < 0 or not is_repeat(i)):
			continue
		for k: int in chain.size():
			if tier_of(k) == tier and is_repeat(k) and not _bases.has(str(chain[k]["id"])) and is_offered(k):
				_bases[str(chain[k]["id"])] = value_of(k)
				changed = true
	if changed:
		_store_repeats()


## Whether a tier's repeating goals are running: one of them counts or has been finished.
func _fallen_back(tier: String) -> bool:
	for k: int in chain.size():
		if tier_of(k) == tier and is_repeat(k) and (_bases.has(str(chain[k]["id"])) or times_done(k) > 0):
			return true
	return false


func _store_repeats() -> void:
	GameState.flags[FLAG_REPEAT] = {"n": _counts.duplicate(), "base": _bases.duplicate(), "on": _on.duplicate()}


## Tells listeners when a tier's active goal is a different one from last time.
func _announce() -> void:
	for tier: String in tier_ids():
		var i: int = active(tier)
		var key: String = "" if i < 0 else "%s#%d" % [str(chain[i]["id"]), times_done(i)]
		if str(_shown.get(tier, "")) != key:
			var first: bool = not _shown.has(tier)
			_shown[tier] = key
			if not first:
				tier_changed.emit(tier, i)


## A save from before the tiers: its finished goals stay finished (their ids are kept), and the
## goals that are new to it and already hold are marked done without a payout or a notice, so
## loading it does not set off a long run of rewards for work done long ago.
func _catch_up_old_save() -> void:
	_old_save = false
	var arr: Array = GameState.flags.get(FLAG_DONE, [])
	for i: int in chain.size():
		if is_repeat(i) or is_done(i) or not is_offered(i) or value_of(i) < target_of(i):
			continue
		_done[str(chain[i]["id"])] = true
		arr.append(str(chain[i]["id"]))
	GameState.flags[FLAG_DONE] = arr


func _on_junk_scooped(_type_id: String, _pos: Vector3) -> void:
	GameState.inc_stat("junk_scooped")


## Distinct hexes painted into any Command zone (crew or single robot) in this district.
static func zone_hex_count() -> int:
	return GoalMeasures.zone_hex_count()
