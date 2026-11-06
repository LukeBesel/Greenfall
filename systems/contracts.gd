class_name Contracts
extends Node
## Contracts board (data/events.json "contracts"): three optional, timed jobs offered at the
## workbench ("Contracts" tab). Accept one and its timer starts; finish it in time and claim
## tokens (plus a cube bonus scaled to progress). Tokens buy liveries, blueprint parts, seed
## crates and Curio Capsules in the token shop. Nothing is lost on failure: the slot just cools
## down and a new offer arrives. State lives in GameState.flags["contracts"]:
##   {"slots": [slot, ...], "done_total": int}
##   slot = {state: offer|active|done|wait, tpl, n, time_s, tokens, tier, offer_left, left, base, peak, wait}
## Timers count play time (they only tick while the game runs). The static helpers are pure on
## the state dictionary so the tests can drive them.

const CURRENCY: String = "tokens"
const PATH: String = "res://data/events.json"

static var _cfg: Dictionary = {}
static var _shop: Array = []

var world: Node
var rng := RandomNumberGenerator.new()
var _t: float = 0.0


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH).get("contracts", {})
	return _cfg


static func shop() -> Array:
	if _shop.is_empty():
		_shop = Economy.read_json(PATH).get("shop", [])
	return _shop


static func shop_item(id: String) -> Dictionary:
	for s: Dictionary in shop():
		if str(s["id"]) == id:
			return s
	return {}


static func templates() -> Array:
	return cfg().get("templates", [])


static func template(id: String) -> Dictionary:
	for t: Dictionary in templates():
		if str(t["id"]) == id:
			return t
	return {}


## 0..3 from lifetime hexes cleaned: bigger asks (and slightly bigger pay) later on.
static func tier_for(hexes: float) -> int:
	var th: Array = cfg().get("tier_hexes", [12, 40, 100])
	var t: int = 0
	for v: Variant in th:
		if hexes >= float(v):
			t += 1
	return t


static func state() -> Dictionary:
	var v: Variant = GameState.flags.get("contracts")
	if not (v is Dictionary):
		v = {"slots": [], "done_total": 0}
		GameState.flags["contracts"] = v
	var st: Dictionary = v
	if not (st.get("slots") is Array):
		st["slots"] = []
	return st


static func slots() -> Array:
	return state()["slots"]


static func _at(arr: Array, i: int) -> Variant:
	return arr[clampi(i, 0, arr.size() - 1)]


## Templates whose requirement flag is met and that aren't already on the board.
static func available_templates(flags: Dictionary, exclude: Array) -> Array:
	var out: Array = []
	for t: Dictionary in templates():
		var req: String = str(t.get("requires", ""))
		if req != "" and not bool(flags.get(req, false)):
			continue
		if str(t["id"]) in exclude:
			continue
		out.append(t)
	return out


static func make_offer(tpl: Dictionary, tier: int) -> Dictionary:
	return {
		"state": "offer", "tpl": str(tpl["id"]), "tier": tier,
		"n": int(_at(tpl.get("n", [1]), tier)), "time_s": float(_at(tpl.get("time_s", [600]), tier)),
		"tokens": int(tpl.get("tokens", 3)) + tier,
		"offer_left": float(cfg().get("offer_life_s", 1200)),
		"left": 0.0, "base": 0.0, "peak": 0.0, "wait": 0.0,
	}


static func wait_slot(seconds: float) -> Dictionary:
	return {"state": "wait", "wait": seconds}


static func text_of(slot: Dictionary) -> String:
	var t: Dictionary = template(str(slot.get("tpl", "")))
	if t.is_empty():
		return "?"
	if int(slot.get("n", 1)) == 1 and t.has("text_1"):
		return str(t["text_1"])
	return str(t.get("text", "%d")) % int(slot.get("n", 1))


## Raw counter a contract watches (a lifetime stat, a peak since accepting, or a hex-level count).
static func value_of(slot: Dictionary, stats: Dictionary, sustained: int) -> float:
	var t: Dictionary = template(str(slot.get("tpl", "")))
	if t.has("peak"):
		return float(slot.get("peak", 0.0))
	if t.has("hex_level"):
		return float(sustained)
	var v: Variant = stats.get(str(t.get("stat", "")), 0.0)
	return float(v) if (v is float or v is int) else 0.0


## Progress toward n (0..n) given the counter's current value.
static func count_of(slot: Dictionary, value: float) -> float:
	var t: Dictionary = template(str(slot.get("tpl", "")))
	var got: float = value if t.has("peak") else value - float(slot.get("base", 0.0))
	return clampf(got, 0.0, float(slot.get("n", 1)))


static func accept_slot(slot: Dictionary, value: float) -> void:
	slot["state"] = "active"
	slot["left"] = float(slot.get("time_s", 600))
	slot["base"] = value
	slot["peak"] = 0.0


## Advances every slot by dt. value_fn(slot) -> current counter; offer_fn(i) -> a new offer
## Dictionary. Returns what happened: [{"kind": "done"|"failed"|"offer", "i": int}].
static func step(st: Dictionary, dt: float, value_fn: Callable, offer_fn: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var arr: Array = st["slots"]
	var want: int = int(cfg().get("slots", 3))
	while arr.size() < want:
		arr.append(wait_slot(0.0))
	for i: int in arr.size():
		var s: Dictionary = arr[i]
		match str(s.get("state", "wait")):
			"offer":
				s["offer_left"] = float(s.get("offer_left", 0.0)) - dt
				if float(s["offer_left"]) <= 0.0:
					arr[i] = offer_fn.call(i)
					out.append({"kind": "offer", "i": i})
			"active":
				if count_of(s, float(value_fn.call(s))) >= float(s.get("n", 1)):
					s["state"] = "done"
					out.append({"kind": "done", "i": i})
				else:
					s["left"] = float(s.get("left", 0.0)) - dt
					if float(s["left"]) <= 0.0:
						arr[i] = wait_slot(float(cfg().get("fail_cooldown_s", 120)))
						out.append({"kind": "failed", "i": i})
			"done":
				pass
			_:
				s["wait"] = float(s.get("wait", 0.0)) - dt
				if float(s["wait"]) <= 0.0:
					arr[i] = offer_fn.call(i)
					out.append({"kind": "offer", "i": i})
	return out


## Records a peak value (e.g. the streak tier) for active contracts that track it.
static func note_peak(kind: String, v: float) -> void:
	for s: Dictionary in slots():
		if str(s.get("state", "")) != "active":
			continue
		if str(template(str(s.get("tpl", ""))).get("peak", "")) == kind:
			s["peak"] = maxf(float(s.get("peak", 0.0)), v)


static func count_state(kind: String) -> int:
	var n: int = 0
	for s: Dictionary in slots():
		if str(s.get("state", "")) == kind:
			n += 1
	return n


static func tokens() -> int:
	return int(round(GameState.get_currency(CURRENCY).to_float()))


static func owned() -> Array:
	var v: Variant = GameState.flags.get("shop_owned")
	if not (v is Array):
		v = []
		GameState.flags["shop_owned"] = v
	return v


# --- Live node --------------------------------------------------------------------------------

func _ready() -> void:
	rng.randomize()
	step(state(), 0.0, live_value, new_offer)  # a fresh board is filled right away
	if DevHooks.has("contracts-sample"):
		_sample.call_deferred()


## --contracts-sample: a board mid-game (one in progress, one ready to claim, one fresh offer).
func _sample() -> void:
	GameState.flags["seeds_unlocked"] = true
	GameState.flags["first_sprout"] = true
	var st: Dictionary = state()
	st["slots"] = [make_offer(template("metal_bales"), 1), make_offer(template("sustain"), 1), make_offer(template("plant"), 1)]
	accept_slot(st["slots"][0], live_value(st["slots"][0]))
	GameState.stats["ev_metal_bales"] = float(GameState.stats.get("ev_metal_bales", 0.0)) + 6.0
	st["slots"][0]["left"] = 431.0
	st["slots"][1]["state"] = "done"


func _process(delta: float) -> void:
	if world == null or (world.has_method("any_modal_open") and bool(world.call("any_modal_open")) and not _board_open()):
		return
	_t += delta
	if _t < 0.5:
		return
	var dt: float = _t
	_t = 0.0
	for e: Dictionary in step(state(), dt, live_value, new_offer):
		var s: Dictionary = slots()[int(e["i"])]
		match str(e["kind"]):
			"done":
				EventBus.toast.emit("Contract complete: %s. Claim %d tokens at the workbench." % [text_of(s), int(s.get("tokens", 0))], "story")
				Audio.play("chime", 1.2, -4.0)
				Audio.play("coin", 1.3, -8.0)
				if world.get("wren") != null:
					world.wren.say("contract_done", 0.6)
			"failed":
				EventBus.toast.emit("A contract ran out of time. No harm done; a new one will be posted soon.", "info")


## The board is open in the workbench: keep timers running so the panel stays live.
func _board_open() -> bool:
	return world.get("upgrades") != null and world.upgrades.is_open


func sustained_count() -> int:
	var hl: Variant = world.get("hex_levels") if world else null
	return (hl as HexLevels).count_at_least(4) if hl is HexLevels else 0


func live_value(slot: Dictionary) -> float:
	return value_of(slot, GameState.stats, sustained_count())


func new_offer(_i: int) -> Dictionary:
	var exclude: Array = []
	for s: Dictionary in slots():
		if s.has("tpl") and str(s.get("state", "")) != "wait":
			exclude.append(str(s["tpl"]))
	var opts: Array = available_templates(GameState.flags, exclude)
	if opts.is_empty():
		opts = available_templates(GameState.flags, [])
	if opts.is_empty():
		return wait_slot(60.0)
	var tpl: Dictionary = opts[rng.randi() % opts.size()]
	return make_offer(tpl, tier_for(float(GameState.stats.get("hexes_cleaned", 0))))


func accept(i: int) -> bool:
	var arr: Array = slots()
	if i < 0 or i >= arr.size() or str(arr[i].get("state", "")) != "offer":
		return false
	accept_slot(arr[i], live_value(arr[i]))
	Audio.play("buy", 1.1, -4.0)
	return true


func decline(i: int) -> void:
	var arr: Array = slots()
	if i < 0 or i >= arr.size():
		return
	arr[i] = wait_slot(float(cfg().get("decline_cooldown_s", 90)))
	Audio.play("click", 0.9, -6.0)


## Pays out a finished contract. Returns the tokens paid (0 if not claimable).
func claim(i: int) -> int:
	var arr: Array = slots()
	if i < 0 or i >= arr.size() or str(arr[i].get("state", "")) != "done":
		return 0
	var s: Dictionary = arr[i]
	var tok: int = int(s.get("tokens", 0))
	GameState.add_currency(CURRENCY, BigNum.from_float(tok))
	var cubes: float = WorldEvents.progress_cubes(60.0 + 20.0 * int(s.get("tier", 0)))
	GameState.add_currency("cubes", BigNum.from_float(cubes))
	var st: Dictionary = state()
	st["done_total"] = int(st.get("done_total", 0)) + 1
	GameState.inc_stat("contracts_done")
	var cd: Array = cfg().get("cooldown_s", [60, 120])
	arr[i] = wait_slot(rng.randf_range(float(cd[0]), float(cd[1])))
	Audio.play("fanfare", 1.1, -6.0)
	Audio.play("coin", 1.0, -4.0)
	EventBus.toast.emit("Contract paid: +%d tokens, +%s cubes." % [tok, Settings.fmt(BigNum.from_float(cubes))], "story")
	for t: Dictionary in Collection.defs():
		if str(t.get("source", "")) == "contracts" and int(st["done_total"]) >= int(t.get("milestone", 999)):
			Collection.grant(str(t["id"]))
	return tok


## Token shop. Returns "" on success or a short reason.
func buy(item_id: String) -> String:
	var it: Dictionary = shop_item(item_id)
	if it.is_empty():
		return "Unknown item"
	var kind: String = str(it.get("kind", ""))
	var have: Array = owned()
	if kind == "livery" and item_id in have:
		GameState.flags["livery"] = "" if str(GameState.flags.get("livery", "")) == item_id else item_id
		Audio.play("click", 1.2, -6.0)
		return ""
	var why: String = block_reason(item_id)
	if why != "":
		return why
	GameState.spend(CURRENCY, BigNum.from_float(float(it.get("cost", 0))))
	match kind:
		"livery":
			have.append(item_id)
			GameState.flags["livery"] = item_id
			EventBus.toast.emit("%s fitted to the whole fleet." % str(it["name"]), "story")
		"part":
			var t: int = rng.randi() % maxi(Economy.parts.get("types", [1]).size(), 1)
			var r: int = int(it.get("rarity", 3))
			GameState.parts.append({"type": t, "rarity": r})
			EventBus.part_found.emit(t, r)
			EventBus.toast.emit("Printed: %s %s." % [Economy.rarity(r).get("name", ""), Economy.part_type(t).get("name", "part")], "story")
		"seeds":
			GameState.add_currency("seeds", BigNum.from_float(float(it.get("amount", 20))))
			EventBus.toast.emit("+%d seeds." % int(it.get("amount", 20)), "hint")
		"capsule":
			Collection.grant(Collection.roll("capsule", rng.randf()))
	GameState.inc_stat("tokens_spent", float(it.get("cost", 0)))
	Audio.play("buy", 1.0, -2.0)
	return ""


static func block_reason(item_id: String) -> String:
	var it: Dictionary = shop_item(item_id)
	var kind: String = str(it.get("kind", ""))
	if kind == "seeds" and not GameState.flags.get("seeds_unlocked", false):
		return "Unlocks with planting"
	if kind == "capsule" and Collection.unfound("capsule").is_empty():
		return "Collection complete"
	if kind == "livery" and item_id in owned():
		return ""
	if tokens() < int(it.get("cost", 0)):
		return "Needs %d tokens" % int(it.get("cost", 0))
	return ""
