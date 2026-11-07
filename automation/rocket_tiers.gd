class_name RocketTiers
extends RefCounted
## Rocket upgrades (data/rockets.json): Mk I comes with a level 5 base; Mk II-IV are bought in the
## workbench Rockets tab. Each tier looks cooler (automation/rocket_model.gd) and travels better:
## a shorter launch, a faster flight, energy cells that refill faster between launches, bigger and
## more frequent cargo pods, and at Mk IV instant warp hops. Global (flies with you): stored in
## GameState.flags "rocket_tier" and "rocket_ready_unix" (when the cells are full again).

static var _data: Dictionary = {}
## [beat] The autoplay bot drives this from the game clock so a time-scaled run recharges at
## game speed (like Research.now_override); < 0 means the system clock.
static var now_override: float = -1.0


static func _clock() -> float:
	return now_override if now_override >= 0.0 else Time.get_unix_time_from_system()


static func data() -> Dictionary:
	if _data.is_empty():
		_data = Economy.read_json("res://data/rockets.json")
	return _data


static func tier() -> int:
	if DevHooks.has("rocket-tier"):
		return clampi(int(DevHooks.get_f("rocket-tier", 1.0)), 1, max_tier())
	return clampi(int(GameState.flags.get("rocket_tier", 1)), 1, max_tier())


static func max_tier() -> int:
	return maxi(1, (data().get("tiers", []) as Array).size())


static func def(t: int = -1) -> Dictionary:
	var want: int = tier() if t < 0 else t
	for d: Dictionary in data().get("tiers", []):
		if int(d["tier"]) == want:
			return d
	return {}


static func next_def() -> Dictionary:
	return def(tier() + 1) if tier() < max_tier() else {}


## "" if the next tier can be bought now, else the reason it can't.
static func blocker() -> String:
	var nd: Dictionary = next_def()
	if nd.is_empty():
		return TranslationServer.translate("Top tier")
	var rq: String = str(nd.get("requires_research", ""))
	if rq != "" and not Research.has(rq):
		return TranslationServer.translate("Needs the Rocket Cargo research")
	if not Hub.can_pay(nd.get("cost", {})):
		return TranslationServer.translate("Not enough materials")
	return ""


static func upgrade() -> bool:
	if blocker() != "":
		return false
	var nd: Dictionary = next_def()
	if not Hub.pay(nd.get("cost", {})):
		return false
	GameState.flags["rocket_tier"] = int(nd["tier"])
	# A new rocket comes with full cells.
	GameState.flags.erase("rocket_ready_unix")
	EventBus.toast.emit(TranslationServer.translate("Rocket upgraded: %s.") % TranslationServer.translate(str(nd["name"])), "story")
	return true


## Seconds until the energy cells are full again (0 = ready).
static func recharge_left() -> float:
	if DevHooks.has("auto-launch"):
		return 0.0
	var at: float = float(GameState.flags.get("rocket_ready_unix", 0.0))
	# [beat] Never more than a full recharge (clock changed, or a save from another clock).
	return clampf(at - _clock(), 0.0, float(def().get("recharge_s", 0.0)))


static func mark_launched() -> void:
	var r: float = float(def().get("recharge_s", 0.0))
	if r > 0.0:
		GameState.flags["rocket_ready_unix"] = _clock() + r
	else:
		GameState.flags.erase("rocket_ready_unix")


static func fmt_time(s: float) -> String:
	var n: int = int(ceil(s))
	return "%d:%02d" % [n / 60, n % 60]
