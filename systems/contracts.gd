class_name Contracts
extends Node
## [money] The Requests board (workbench "Requests" tab, data/events.json "contracts"): contracts
## and world events on one board. Three optional, timed requests are offered; accept one and its
## timer starts; finish it in time and claim Cubes or Parts (each template says which). A world
## event in progress shows on the board too, and every claimed request or handled world event
## counts toward the reward track (liveries, Builder parts, Curio Capsules, rare robot parts),
## which replaced the token shop. Nothing is lost on failure: the slot just cools down and a new
## offer arrives. State lives in GameState.flags["contracts"]:
##   {"slots": [slot, ...], "done_total": int, "events_seen": float, "track_done": int}
##   slot = {state: offer|active|done|wait, tpl, n, time_s, pay, parts, income_s, tier, offer_left, left, base, peak, wait}
## Timers count play time (they only tick while the game runs). The static helpers are pure on
## the state dictionary so the tests can drive them.

const PATH: String = "res://data/events.json"

static var _cfg: Dictionary = {}
## [ui2] Simple board: a new request starts right away (no Accept / Pass) and never runs out of
## time; the player only claims it. Tests of the old offer flow turn this off.
static var auto_accept: bool = true
static var _shop: Array = []

var world: Node
var rng := RandomNumberGenerator.new()
var _t: float = 0.0


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH).get("contracts", {})
	return _cfg


## Fleet liveries (data/events.json "liveries"; unlocked by the reward track).
static func shop() -> Array:
	if _shop.is_empty():
		_shop = Economy.read_json(PATH).get("liveries", [])
	return _shop


static func track() -> Array:
	return cfg().get("track", [])


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
		"pay": str(tpl.get("pay", "cubes")),  # [money] cubes or parts
		"parts": int(_at(tpl.get("parts", [40]), tier)),
		"income_s": float(_at(tpl.get("income_s", [90]), tier)),
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
		return TranslationServer.translate(str(t["text_1"]))
	return TranslationServer.translate(str(t.get("text", "%d"))) % int(slot.get("n", 1))


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
		if auto_accept and str(s.get("state", "")) == "offer":
			accept_slot(s, float(value_fn.call(s)))  # [ui2]
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
				elif not auto_accept:  # [ui2] auto-accepted requests have no time limit
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
					if auto_accept and str((arr[i] as Dictionary).get("state", "")) == "offer":
						accept_slot(arr[i], float(value_fn.call(arr[i])))  # [ui2]
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


## Requests finished so far (claimed requests + handled world events): the reward track's counter.
static func done_total() -> int:
	return int(state().get("done_total", 0))


## "+120 parts" / "+1.4K cubes" for a slot (cubes scale with income, so the shown value is a guess).
static func pay_text(slot: Dictionary) -> String:
	if str(slot.get("pay", "cubes")) == "parts":
		return L10nFmt.amount("parts", float(slot.get("parts", 0)), true)
	return L10nFmt.amount("cubes", WorldEvents.progress_cubes(float(slot.get("income_s", 90.0))), true)


## The next reward-track step not reached yet ({} after the last), for the board's header.
static func next_track_step(done: int) -> Dictionary:
	for t: Dictionary in track():
		if int(t.get("n", 0)) > done:
			return t
	return {}


## Display name of a track step.
static func track_name(t: Dictionary) -> String:
	match str(t.get("kind", "")):
		"livery":
			return TranslationServer.translate(str(shop_item(str(t.get("id", ""))).get("name", "")))
		"builder":
			return TranslationServer.translate("%s (robot style)") % TranslationServer.translate(str(RobotBuilder.part(str(t.get("id", ""))).get("name", "")))  # [ui2]
		"builder_crate":
			return TranslationServer.translate("Builder Crate")
		"capsule":
			return TranslationServer.translate("Curio Capsule")
		"part":
			return L10nFmt.amount("parts", RobotParts.value(int(t.get("rarity", 3))), true)  # [ui2] pays Parts
	return "?"


static func owned() -> Array:
	var v: Variant = GameState.flags.get("shop_owned")
	if not (v is Array):
		v = []
		GameState.flags["shop_owned"] = v
	return v


# --- Live node --------------------------------------------------------------------------------

## [onboard] The board opens later (owner: "you should not unlock contracts for a while"): at base
## level unlock_hub_level, or after unlock_play_s of play, whichever comes first. A save that
## already used the board keeps it. Dev: --requests-unlocked (and --contracts-sample / --tab=contracts).
static func unlocked() -> bool:
	if GameState.flags.get("requests_unlocked", false):
		return true
	if DevHooks.has("requests-unlocked") or DevHooks.has("contracts-sample") or DevHooks.get_s("tab", "") == "contracts":
		return true
	return unlock_due(int(GameState.world.get("hub_level", 1)), float(GameState.stats.get("time_played", 0.0)), state())


## Pure: does this state open the board?
static func unlock_due(hub_level: int, played_s: float, st: Dictionary) -> bool:
	if int(st.get("done_total", 0)) > 0:
		return true
	for s: Variant in st.get("slots", []):
		if s is Dictionary and str((s as Dictionary).get("state", "")) in ["active", "done"]:
			return true
	return hub_level >= int(cfg().get("unlock_hub_level", 3)) or played_s >= float(cfg().get("unlock_play_s", 2700))


func _ready() -> void:
	rng.randomize()
	if unlocked() and (BenchTiers.tab_open("contracts") or GameState.flags.get("requests_unlocked", false)):  # [onboard] [v9b] once the bench has the board
		GameState.flags["requests_unlocked"] = true
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
	if not GameState.flags.get("requests_unlocked", false):  # [onboard] closed until a later milestone
		if not unlocked():
			return
		if not BenchTiers.tab_open("contracts"):  # [v9b] the board needs the bench's Request Board first
			_bench_hint()
			return
		_announce_unlock()
	_count_events()
	for e: Dictionary in step(state(), dt, live_value, new_offer):
		var s: Dictionary = slots()[int(e["i"])]
		match str(e["kind"]):
			"done":
				EventBus.toast.emit(tr("Request complete: %s. Claim it at the workbench.") % text_of(s), "info")
				Audio.play("chime", 1.2, -4.0)
				Audio.play("coin", 1.3, -8.0)
				if world.get("wren") != null:
					world.wren.say("contract_done", 0.6)
			"failed":
				EventBus.toast.emit(tr("A request ran out of time. No harm done; a new one will be posted soon."), "info")


## [v9b] The board is due but the bench has no Request Board yet (its tab stays hidden): the toast
## said "New at the workbench" and there was nothing there. Once the Request Board can be bought,
## one line says where it is; the board itself opens when it's installed.
func _bench_hint() -> void:
	if GameState.flags.get("requests_bench_hint", false):
		return
	if BenchTiers.tier() + 1 != BenchTiers.tier_for_tab("contracts") or BenchTiers.block_reason(world) != "":
		return
	GameState.flags["requests_bench_hint"] = true
	EventBus.toast.emit(tr("The Requests board is ready to build: workbench, Upgrades tab, Request Board."), "story")
	Audio.play("chime", 1.1, -6.0)


## [onboard] The board opens: one WREN line and a toast, then the first offers.
func _announce_unlock() -> void:
	GameState.flags["requests_unlocked"] = true
	st_events_baseline()
	step(state(), 0.0, live_value, new_offer)
	EventBus.toast.emit(tr("New at the workbench: the Requests board. Small jobs, real rewards."), "story")
	Audio.play("chime", 1.1, -6.0)
	if world.get("wren") != null:
		(world.wren as Wren).speak(tr("The relay's strong enough now to hear the Cradle's old work orders. They're on the Requests board at the workbench."), 1)


## [onboard] World events handled before the board opened don't count toward its reward track.
func st_events_baseline() -> void:
	state()["events_seen"] = float(GameState.stats.get("ev_events_done", 0.0))


## [money] Handled world events count as finished requests (the board shows them live).
func _count_events() -> void:
	var st: Dictionary = state()
	var ev: float = float(GameState.stats.get("ev_events_done", 0.0))
	if not st.has("events_seen"):
		st["events_seen"] = ev
	var n: int = int(ev - float(st["events_seen"]))
	if n > 0:
		st["events_seen"] = ev
		count_done(n)


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


## Pays out a finished request (Cubes or Parts). Returns the amount paid (0 if not claimable).
func claim(i: int) -> float:
	var arr: Array = slots()
	if i < 0 or i >= arr.size() or str(arr[i].get("state", "")) != "done":
		return 0.0
	var s: Dictionary = arr[i]
	var paid: float
	var txt: String
	if str(s.get("pay", "cubes")) == "parts":
		paid = float(s.get("parts", 40))
		GameState.add_currency("parts", BigNum.from_float(paid))
		txt = L10nFmt.amount("parts", paid, true)
	else:
		paid = WorldEvents.progress_cubes(float(s.get("income_s", 60.0 + 20.0 * int(s.get("tier", 0)))))
		GameState.add_currency("cubes", BigNum.from_float(paid))
		txt = L10nFmt.amount("cubes", paid, true)
	GameState.inc_stat("contracts_done")
	var cd: Array = cfg().get("cooldown_s", [60, 120])
	arr[i] = wait_slot(rng.randf_range(float(cd[0]), float(cd[1])))
	Audio.play("coin", 1.0, -4.0)
	EventBus.toast.emit(tr("Request done: %s.") % txt, "info")
	count_done(1)
	return paid


## One more finished request (a claimed contract or a handled world event): Collection milestones
## and the reward track.
func count_done(n: int) -> void:
	var st: Dictionary = state()
	st["done_total"] = int(st.get("done_total", 0)) + n
	for t: Dictionary in Collection.defs():
		if str(t.get("source", "")) == "contracts" and int(st["done_total"]) >= int(t.get("milestone", 999)):
			Collection.grant(str(t["id"]))
	grant_track(st)


## Grants every reward-track step reached and not granted yet (and the repeat Vintage part).
func grant_track(st: Dictionary) -> void:
	var done: int = int(st.get("done_total", 0))
	var granted: int = int(st.get("track_done", 0))
	var last_n: int = 0
	for t: Dictionary in track():
		var n: int = int(t.get("n", 0))
		last_n = maxi(last_n, n)
		if n > granted and n <= done:
			_grant_step(t)
	var every: int = maxi(int(cfg().get("repeat_every", 5)), 1)
	@warning_ignore("integer_division")
	var reps_before: int = maxi(0, granted - last_n) / every
	@warning_ignore("integer_division")
	var reps_now: int = maxi(0, done - last_n) / every
	for k: int in reps_now - reps_before:
		_grant_step({"kind": "part", "rarity": 3})
	st["track_done"] = maxi(granted, done)


func _grant_step(t: Dictionary) -> void:
	match str(t.get("kind", "")):
		"livery":
			var id: String = str(t.get("id", ""))
			if not (id in owned()):
				owned().append(id)
			EventBus.toast.emit(tr("Requests reward: %s. Paint your fleet with it in the Locker.") % track_name(t), "story")  # [ui2]
		"builder":
			RobotBuilder.add_part(str(t.get("id", "")))
			EventBus.toast.emit(tr("Requests reward: %s. Fit it in the Locker.") % track_name(t), "story")  # [ui2]
		"builder_crate":
			var pid: String = RobotBuilder.roll_unowned(rng)
			RobotBuilder.add_part(pid)
			EventBus.toast.emit(tr("Requests reward: %s.") % tr(str(RobotBuilder.part(pid).get("name", pid))), "story")
		"capsule":
			var cid: String = Collection.roll("capsule", rng.randf())
			if cid != "":
				Collection.grant(cid)
		"part":
			var ty: int = rng.randi() % maxi(Economy.parts.get("types", [1]).size(), 1)
			var r: int = int(t.get("rarity", 3))
			RobotParts.salvage(ty, r)  # [ui2] pays Parts
			EventBus.toast.emit(tr("Requests reward: %s.") % RobotParts.gain_text(r), "story")
	Audio.play("fanfare", 1.1, -8.0)


## Equips (or takes off) an unlocked livery. Returns "" on success or a short reason.
func buy(item_id: String) -> String:
	var it: Dictionary = shop_item(item_id)
	if it.is_empty():
		return tr("Unknown item")
	if not (item_id in owned()):
		return block_reason(item_id)
	GameState.flags["livery"] = "" if str(GameState.flags.get("livery", "")) == item_id else item_id
	Audio.play("click", 1.2, -6.0)
	return ""


static func block_reason(item_id: String) -> String:
	if item_id in owned():
		return ""
	for t: Dictionary in track():
		if str(t.get("id", "")) == item_id:
			return TranslationServer.translate("Unlocks after %d requests") % int(t.get("n", 0))
	return TranslationServer.translate("Locked")
