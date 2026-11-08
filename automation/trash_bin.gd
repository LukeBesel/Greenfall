class_name TrashBin
extends RefCounted
## [camp] The upgradeable trash bin at each base: the Depot (automation/depot.gd) is its body and
## weigh plate. Rules here are static so the economy (pace), the Hub tab, tests and the save round
## trip can use them without a scene. Data: data/trash_bin.json.
## State (per district): GameState.world["trash_bin"] = {"level": n}  (1-based, 1 = Dented Bin).
##
## API
##   TrashBin.level() -> int                 current level here (1..max_level())
##   TrashBin.max_level() -> int
##   TrashBin.level_def(l) -> Dictionary      {name, desc, cost, requires_level, value_mult, feed_interval}
##   TrashBin.next_def() -> Dictionary        the next level's def ({} when maxed)
##   TrashBin.next_cost() -> Dictionary       its cost ({} when maxed)
##   TrashBin.block_reason(hub_level) -> String   "" when the next level can be bought now
##   TrashBin.upgrade(hub_level) -> bool      pays and raises the level; emits TrashBin.changed
##   TrashBin.value_mult() -> float           sale multiplier for bales cashed here
##   TrashBin.feed_interval() -> float        seconds between bales hopping into the bin
##   TrashBin.changed (Signal on TrashBin.events)   (level: int) after an upgrade or a set_level

const PATH: String = "res://data/trash_bin.json"

static var _cfg: Dictionary = {}
## Static signal holder: TrashBin.events.changed.connect(...)
static var events: TrashBinEvents = TrashBinEvents.new()


class TrashBinEvents:
	extends RefCounted
	@warning_ignore("unused_signal")
	signal changed(level: int)


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func levels() -> Array:
	return cfg().get("levels", [])


static func max_level() -> int:
	return maxi(1, levels().size())


static func state() -> Dictionary:
	var v: Variant = GameState.world.get("trash_bin")
	if not (v is Dictionary):
		v = {"level": 1}
		GameState.world["trash_bin"] = v
	return v


static func level() -> int:
	return clampi(int(state().get("level", 1)), 1, max_level())


static func set_level(l: int) -> void:
	state()["level"] = clampi(l, 1, max_level())
	events.changed.emit(level())


static func level_def(l: int) -> Dictionary:
	var ls: Array = levels()
	if l < 1 or l > ls.size():
		return {}
	return ls[l - 1]


static func next_def() -> Dictionary:
	return level_def(level() + 1)


static func next_cost() -> Dictionary:
	return next_def().get("cost", {})


static func block_reason(hub_level: int) -> String:
	var nd: Dictionary = next_def()
	if nd.is_empty():
		return TranslationServer.translate("Fully upgraded.")
	var req: int = int(nd.get("requires_level", 1))
	if hub_level < req:
		return TranslationServer.translate("Requires hub level %d.") % req
	if not Hub.can_pay(nd.get("cost", {})):
		return TranslationServer.translate("Not enough materials.")
	return ""


static func upgrade(hub_level: int) -> bool:
	if block_reason(hub_level) != "" or not Hub.pay(next_cost()):
		return false
	state()["level"] = level() + 1
	GameState.inc_stat("trash_bin_upgrades")
	events.changed.emit(level())
	return true


static func value_mult() -> float:
	return float(level_def(level()).get("value_mult", 1.0))


static func feed_interval() -> float:
	return float(level_def(level()).get("feed_interval", 0.16))


static func name_of(l: int = -1) -> String:
	return str(level_def(level() if l < 0 else l).get("name", "Trash Bin"))
