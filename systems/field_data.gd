class_name FieldData
extends RefCounted
## Field data: what Lumi learns by working (design spec section 6). Every reward comes from play
## (a cleaned hex, a hex stage, a mastery level, a find, a source step), never from a clock, so
## time away adds none. Data goes into the active research node's bar; with no node active, or
## past what the node still needs, it waits in the bank, and the next node started draws on the
## bank first. Amounts and their sources are in the planet's research table (`data_rewards`).
## State lives in Research.state(): `bank` and `progress` {node id: data put in}.


## Data one event pays before bonuses ("hex_cleaned", "mastery_level", ...). `hex_stage` is a list
## by stage; read it with stage_reward.
static func reward(kind: String) -> float:
	var v: Variant = Research.config().get("data_rewards", {}).get(kind, 0.0)
	return float(v) if (v is float or v is int) else 0.0


## Data a hex pays on reaching `stage` (the regrowth stage, 1 clean .. 5 thriving).
static func stage_reward(stage: int) -> float:
	var arr: Variant = Research.config().get("data_rewards", {}).get("hex_stage", [])
	if arr is Array and stage >= 0 and stage < (arr as Array).size():
		return float((arr as Array)[stage])
	return 0.0


## Multiplier on every reward: research bonuses (data_gain, research_speed) and a worn set's buff.
static func gain_mult() -> float:
	var speed: float = Designs.apply("research_speed", Research.stat_mod("research_speed", 1.0))
	return maxf(Research.stat_mod("data_gain", 1.0) * speed, 0.0)


static func bank() -> float:
	return float(Research.state().get("bank", 0.0))


## Data already put into a node (kept when the player switches away from it).
static func put_in(id: String) -> float:
	return float((Research.state()["progress"] as Dictionary).get(id, 0.0))


## Data a node needs in all.
static func need(id: String) -> float:
	return maxf(float(Research.def(id).get("data", 0.0)), 0.0)


## Data a node still needs.
static func left(id: String) -> float:
	return maxf(0.0, need(id) - put_in(id))


## 0..1 share of a node's data put in (1 once researched).
static func fraction(id: String) -> float:
	if Research.has(id):
		return 1.0
	var n: float = need(id)
	return 1.0 if n <= 0.0 else clampf(put_in(id) / n, 0.0, 1.0)


## Adds `base` data from `kind` of work (after bonuses): into the active node first, the rest to
## the bank. Completes the node when its bar is full. Returns the data added.
static func award(base: float, kind: String = "") -> float:
	if base <= 0.0:
		return 0.0
	var amt: float = base * gain_mult()
	if amt <= 0.0:
		return 0.0
	GameState.inc_stat("data_earned", amt)
	var s: Dictionary = Research.state()
	s["bank"] = float(s.get("bank", 0.0)) + amt
	feed_active()
	EventBus.field_data_gained.emit(amt, kind)
	return amt


## Moves banked data into the active node, up to what it needs; finishes it when full.
static func feed_active() -> void:
	var id: String = Research.active_id()
	if id == "":
		return
	var s: Dictionary = Research.state()
	var take: float = minf(float(s.get("bank", 0.0)), left(id))
	if take > 0.0:
		(s["progress"] as Dictionary)[id] = put_in(id) + take
		s["bank"] = float(s.get("bank", 0.0)) - take
	if left(id) <= 0.0:
		Research.finish_active()


## Old saves ran research on a clock with a queue: {active: {id, start, dur}, queue: [ids]}. The
## running node keeps its share of the clock as field data put in (a node whose time was up is
## researched, as the old rules would have done on load); queued nodes were paid for, so they stay
## paid with an empty bar. `now` is the unix time of the load.
static func migrate(s: Dictionary, now: float) -> void:
	var paid: Array = s.get("paid", [])
	var prog: Dictionary = s.get("progress", {})
	var a: Variant = s.get("active", {})
	var new_active: Dictionary = {}
	if a is Dictionary and (a as Dictionary).has("start"):
		var ad: Dictionary = a
		var id: String = str(ad.get("id", ""))
		var dur: float = maxf(float(ad.get("dur", 1.0)), 0.001)
		var share: float = clampf((now - float(ad.get("start", now))) / dur, 0.0, 1.0)
		if Research.exists(id) and not (id in (s["done"] as Array)):
			if share >= 1.0:
				(s["done"] as Array).append(id)
			else:
				prog[id] = share * need(id)
				paid.append(id)
				new_active = {"id": id}
	elif a is Dictionary and (a as Dictionary).has("id"):
		new_active = a
	for q: Variant in s.get("queue", []):
		if Research.exists(str(q)) and not (str(q) in paid):
			paid.append(str(q))
	s.erase("queue")
	s["active"] = new_active
	s["paid"] = paid
	s["progress"] = prog
	if not s.has("bank"):
		s["bank"] = 0.0
