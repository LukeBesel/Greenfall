class_name LumiLevel
extends Node
## Lumi Level: a light, always-on progression earned from everything Lumi does (scoops, bales,
## parts, hexes cleaned and levelled, goals, world events, achievements, research, robots).
## Each level pays a small reward (cubes scaled to progress, seeds, now and then a robot part,
## tokens or a Lumi keepsake for the Collection). The curve is smooth: early levels come every
## couple of minutes, later ones slow down (data/lumi_level.json, docs/BALANCE.md).
## State: GameState.flags["lumi"] = {level, xp (into this level), total (lifetime XP)}.
## The HUD draws it as the thin level bar above the hotbar (ui/hotbar.gd).
## Dev: --lumi-level=N starts at level N; --lumi-xp=N grants N XP; --lumi-levelup=S levels up
## S wall-clock seconds after start (screenshots).

signal xp_gained(amount: int, source: String)
signal leveled(level: int, reward_text: String)

const PATH: String = "res://data/lumi_level.json"
const POLL_S: float = 1.0

static var _cfg: Dictionary = {}

var world: Node
var _poll: float = 0.0
var _seen_planted: float = -1.0
var _seen_bloomed: float = -1.0
var _dev_levelup_done: bool = false
var _start_ms: int = 0
var _granting: bool = false


# --- Pure helpers (tests) ----------------------------------------------------------------

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


## XP needed to go from `level` to `level + 1`.
static func need(level_: int, c: Dictionary = {}) -> int:
	var cv: Dictionary = (c if not c.is_empty() else cfg()).get("curve", {})
	var base: float = float(cv.get("base", 90.0))
	var pw: float = float(cv.get("power", 1.6))
	return maxi(1, int(round(base * pow(float(maxi(level_, 1)), pw))))


## Lifetime XP needed to reach `level` from level 1.
static func total_to(level_: int, c: Dictionary = {}) -> int:
	var t: int = 0
	for l: int in range(1, maxi(level_, 1)):
		t += need(l, c)
	return t


## XP points for a source ("scoop", "goal", ...), 0 if unknown.
static func xp_for(source: String, c: Dictionary = {}) -> int:
	return int((c if not c.is_empty() else cfg()).get("xp", {}).get(source, 0))


## Adds XP to a state {level, xp, total}. Returns the levels reached (in order; empty if none).
static func apply_xp(st: Dictionary, amount: int, c: Dictionary = {}) -> Array[int]:
	var out: Array[int] = []
	if amount <= 0:
		return out
	var cap: int = int((c if not c.is_empty() else cfg()).get("max_level", 999))
	st["total"] = int(st.get("total", 0)) + amount
	var lv: int = int(st.get("level", 1))
	var xp: int = int(st.get("xp", 0)) + amount
	while lv < cap and xp >= need(lv, c):
		xp -= need(lv, c)
		lv += 1
		out.append(lv)
	st["level"] = lv
	st["xp"] = xp if lv < cap else 0
	return out


## The reward plan for reaching `level` (no side effects): {cubes, seeds, parts, part_rarity,
## tokens, trinket(bool)}. `income_cubes` is the progress-scaled cube amount for one level
## (about cube_secs of income); `earned` is lifetime cubes earned (lifts the cap late game).
static func reward_plan(level_: int, income_cubes: float, earned: float, seeds_unlocked: bool, c: Dictionary = {}) -> Dictionary:
	var rw: Dictionary = (c if not c.is_empty() else cfg()).get("reward", {})
	# Progress-scaled cubes, floored per level and capped so early income spikes don't flood.
	var floor_c: float = float(rw.get("min_cubes_per_level", 15)) * level_
	var cap_c: float = maxf(float(rw.get("cap_cubes_base", 30)) * pow(float(level_), 1.5), earned * float(rw.get("cap_earned_frac", 0.004)))
	var out: Dictionary = {"cubes": round(clampf(income_cubes, floor_c, maxf(cap_c, floor_c))),
		"seeds": 0, "parts": 0, "part_rarity": 0, "tokens": 0, "trinket": false}
	var se: int = int(rw.get("seeds_every", 2))
	if seeds_unlocked and se > 0 and level_ % se == 0:
		@warning_ignore("integer_division")
		out["seeds"] = int(rw.get("seeds", 4)) + level_ / 10
	var pe: int = int(rw.get("part_every", 5))
	if pe > 0 and level_ % pe == 0:
		out["parts"] = 1
		# Common early, then Uncommon/Rare/Vintage as Lumi grows (rarity index into parts.json).
		@warning_ignore("integer_division")
		out["part_rarity"] = clampi(level_ / 15, 0, 3)
	var te: int = int(rw.get("token_every", 5))
	if te > 0 and level_ % te == 0:
		@warning_ignore("integer_division")
		out["tokens"] = int(rw.get("tokens", 1)) + int(rw.get("tokens_per_10_levels", 1)) * (level_ / 10)
	var ke: int = int(rw.get("trinket_every", 10))
	if ke > 0 and level_ % ke == 0:
		out["trinket"] = true
	return out


## Persistent state dictionary (created on first use).
static func state() -> Dictionary:
	var v: Variant = GameState.flags.get("lumi")
	if not (v is Dictionary):
		v = {"level": 1, "xp": 0, "total": 0}
		GameState.flags["lumi"] = v
	return v


static func level() -> int:
	return int(state().get("level", 1))


## 0..1 progress inside the current level.
static func progress() -> float:
	var st: Dictionary = state()
	return clampf(float(st.get("xp", 0)) / float(need(int(st.get("level", 1)))), 0.0, 1.0)


# --- Live node ----------------------------------------------------------------------------

func _ready() -> void:
	_start_ms = Time.get_ticks_msec()
	state()
	if DevHooks.has("lumi-level"):
		var st: Dictionary = state()
		st["level"] = maxi(1, int(DevHooks.get_f("lumi-level", 1.0)))
		st["xp"] = int(need(int(st["level"])) * 0.62)
		st["total"] = total_to(int(st["level"])) + int(st["xp"])
	EventBus.junk_scooped.connect(func(_t: String, _p: Vector3) -> void: add("scoop"))
	EventBus.cube_made.connect(func(_i: Dictionary) -> void: add("bale_made"))
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void: add("bale_sold"))
	EventBus.part_found.connect(func(_t: int, _r: int) -> void: add("part_found"))
	EventBus.hex_cleaned.connect(func(_h: int, _p: Vector3, _b: BigNum) -> void: add("hex_cleaned"))
	EventBus.hex_level_changed.connect(func(_h: int, lv: int) -> void: add("hex_level", xp_for("hex_level") * maxi(lv - 1, 1)))
	EventBus.achievement_unlocked.connect(func(_id: String) -> void: add("achievement"))
	EventBus.research_completed.connect(func(_id: String) -> void: add("research"))
	EventBus.upgrade_bought.connect(func(_id: String, _l: int) -> void: add("upgrade"))
	EventBus.robot_built.connect(func(_n: String) -> void: add("robot_built"))
	_hook_late.call_deferred()
	if DevHooks.has("lumi-xp"):
		add.call_deferred("dev", int(DevHooks.get_f("lumi-xp", 0.0)))


## Goals and world events live on the slice; connect once they exist.
func _hook_late() -> void:
	if world == null:
		return
	var g: Variant = world.get("goals")
	if g is Goals:
		(g as Goals).completed.connect(func(i: int) -> void: add("goal", xp_for("goal") + xp_for("goal_per_index") * i))
	var ev: Variant = world.get("events")
	if ev is WorldEvents:
		(ev as WorldEvents).event_ended.connect(func(_id: String, handled: bool) -> void: add("event_handled" if handled else "event_missed"))


func _process(delta: float) -> void:
	_poll += delta
	if _poll >= POLL_S:
		_poll = 0.0
		_poll_stats()
	if DevHooks.has("lumi-levelup") and not _dev_levelup_done:
		if (Time.get_ticks_msec() - _start_ms) / 1000.0 >= DevHooks.get_f("lumi-levelup", 5.0):
			_dev_levelup_done = true
			var st: Dictionary = state()
			add("dev", need(int(st.get("level", 1))) - int(st.get("xp", 0)))


## Planting and blooms have no signal; count their stat deltas.
func _poll_stats() -> void:
	var p: float = float(GameState.stats.get("plants_planted", 0.0))
	var b: float = float(GameState.stats.get("plants_bloomed", 0.0))
	if _seen_planted >= 0.0 and p > _seen_planted:
		add("planted", xp_for("planted") * int(p - _seen_planted))
	if _seen_bloomed >= 0.0 and b > _seen_bloomed:
		add("bloomed", xp_for("bloomed") * int(b - _seen_bloomed))
	_seen_planted = p
	_seen_bloomed = b


## Grants XP from a source (amount defaults to the source's table value).
func add(source: String, amount: int = -1) -> void:
	var n: int = amount if amount >= 0 else xp_for(source)
	if n <= 0 or _granting:
		return
	var ups: Array[int] = apply_xp(state(), n)
	xp_gained.emit(n, source)
	for lv: int in ups:
		_granting = true
		var text: String = _grant(lv)
		_granting = false
		GameState.inc_stat("lumi_levels")
		if DevHooks.has("autoplay"):
			print("[lumi] level %d at %.1f min (%s)" % [lv, float(GameState.stats.get("time_played", 0.0)) / 60.0, text])
		leveled.emit(lv, text)


## Pays the reward for reaching `lv`; returns a short summary ("+340 cubes  +1 Rare Coil").
func _grant(lv: int) -> String:
	var seeds_on: bool = bool(GameState.flags.get("seeds_unlocked", false))
	var rw: Dictionary = cfg().get("reward", {})
	var earned: float = BigNum.from_serialized(GameState.stats.get("cubes_earned_total", [0.0, 0])).to_float()
	var income: float = maxf(WorldEvents.progress_cubes(float(rw.get("cube_secs", 30))), 0.0)
	var plan: Dictionary = reward_plan(lv, income, earned, seeds_on)
	var bits: Array[String] = []
	var cubes: float = float(plan["cubes"])
	if cubes > 0.0:
		GameState.add_currency("cubes", BigNum.from_float(cubes))
		bits.append(tr("+%s cubes") % Settings.fmt(BigNum.from_float(cubes)))
	if int(plan["seeds"]) > 0:
		GameState.add_currency("seeds", BigNum.from_float(int(plan["seeds"])))
		bits.append(tr("+%d seeds") % int(plan["seeds"]))
	if int(plan["parts"]) > 0:
		var types: Array = Economy.parts.get("types", [])
		var t: int = randi() % maxi(types.size(), 1)
		var r: int = int(plan["part_rarity"])
		GameState.parts.append({"type": t, "rarity": r})
		EventBus.part_found.emit(t, r)
		bits.append("+" + L10nFmt.part_name(r, t))  # [i18n2]
	var tokens: int = int(plan["tokens"])
	if bool(plan["trinket"]):
		var left: Array[String] = Collection.unfound("lumi_level")  # in order: L10, L20, ...
		var tid: String = left[0] if not left.is_empty() else ""
		if tid != "" and Collection.grant(tid, true):
			bits.append(tr(str(Collection.def(tid).get("name", tid))))
		else:
			tokens += int(rw.get("trinket_tokens", 3))
	if tokens > 0:
		GameState.add_currency(Contracts.CURRENCY, BigNum.from_float(tokens))
		bits.append(tr_n("+%d token", "+%d tokens", tokens) % tokens)
	return "  ".join(bits)
