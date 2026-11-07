class_name Currencies
extends RefCounted
## [money] The single source of truth for currencies (data/currencies.json): exactly Cubes, Parts
## and Seeds. Everything else is a legacy id that maps onto one of them at a fixed rate, so
## `GameState.add_currency("bolts", x)` from older code (or another branch mid-merge) still works:
## it becomes Parts at the table's rate and warns once per id in debug builds. Saves use the same
## table (SaveManager.migrate, version 2).

const PATH: String = "res://data/currencies.json"
const CUBES: String = "cubes"
const PARTS: String = "parts"
const SEEDS: String = "seeds"
const IDS: Array[String] = [CUBES, PARTS, SEEDS]

static var _cfg: Dictionary = {}
static var _warned: Dictionary = {}
## Tests turn the debug warning off so expected alias calls don't spam the log.
static var warn_legacy: bool = true


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f:
			var v: Variant = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_cfg = v
	return _cfg


static func ids() -> Array[String]:
	return IDS


static func is_currency(id: String) -> bool:
	return id in IDS


static func is_legacy(id: String) -> bool:
	return (cfg().get("legacy", {}) as Dictionary).has(id)


static func def(id: String) -> Dictionary:
	for c: Dictionary in cfg().get("currencies", []):
		if str(c["id"]) == id:
			return c
	return {}


## Player-facing name (translated at display time).
static func display_name(id: String) -> String:
	return TranslationServer.translate(str(def(canonical(id)).get("name", id.capitalize())))


static func short_name(id: String) -> String:
	return TranslationServer.translate(str(def(canonical(id)).get("short", id.to_upper())))


## HudIcons kind for a currency (legacy ids get their new currency's icon).
static func icon(id: String) -> String:
	return str(def(canonical(id)).get("icon", "part"))


## The currency an id is paid in now ("bolts" -> "parts"). Unknown ids pass through unchanged.
static func canonical(id: String) -> String:
	if id in IDS:
		return id
	var l: Dictionary = (cfg().get("legacy", {}) as Dictionary).get(id, {})
	return str(l.get("to", id)) if not l.is_empty() else id


## New units per old unit (1 for the three currencies and unknown ids).
static func rate(id: String, for_save: bool = false) -> float:
	if id in IDS:
		return 1.0
	var l: Dictionary = (cfg().get("legacy", {}) as Dictionary).get(id, {})
	if l.is_empty():
		return 1.0
	if for_save and l.has("save"):
		return float(l["save"])
	return float(l.get("rate", 1.0))


## Resolves a (possibly legacy) id + amount to [currency id, amount in that currency].
static func resolve(id: String, amount: float) -> Array:
	if id in IDS:
		return [id, amount]
	if is_legacy(id):
		_warn(id)
		return [canonical(id), amount * rate(id)]
	return [id, amount]


static func _warn(id: String) -> void:
	if not warn_legacy or not OS.is_debug_build() or _warned.has(id):
		return
	_warned[id] = true
	push_warning("[money] legacy currency '%s' is now '%s' (x%s); update the caller" % [id, canonical(id), str(rate(id))])


## A cost/reward dictionary with legacy keys folded into the three currencies
## ({"cubes": 100, "sheet_metal": 20, "bolts": 4} -> {"cubes": 100, "parts": 40}).
## Keys that aren't currencies at all (e.g. "research_tier") are kept as they are.
static func fold(d: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for k: Variant in d:
		var id: String = str(k)
		var v: Variant = d[k]
		if not (v is float or v is int) or not (id in IDS or is_legacy(id)):
			out[id] = v
			continue
		var c: String = canonical(id)
		out[c] = float(out.get(c, 0.0)) + float(v) * rate(id)
	return out


## Short cost line in the three currencies, fixed order, consistent glyphs: "1.2K cubes · 40 parts".
static func cost_text(cost: Dictionary, mult: float = 1.0) -> String:
	var f: Dictionary = fold(cost)
	var bits: Array[String] = []
	for id: String in IDS:
		var v: float = float(f.get(id, 0.0)) * mult
		if v <= 0.0:
			continue
		bits.append(amount_text(id, v))
	return "  ·  ".join(bits)


## "1.2K cubes" / "40 parts" / "3 seeds" (whole units, rounded up so a cost is never under-read).
static func amount_text(id: String, v: float) -> String:
	return L10nFmt.amount(id, ceilf(v - 0.0001))


## Save migration: folds a serialized currencies dict ({id: [mantissa, exp]}) into the three.
## Returns {currencies: {...}, into: {target: amount}} where `into` holds balances that have a
## non-currency home (old compost -> the compost press hopper).
static func migrate_serialized(cur: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	var into: Dictionary = {}
	for k: Variant in cur:
		var id: String = str(k)
		var amt: BigNum = BigNum.from_serialized(cur[k]) if cur[k] is Array else BigNum.from_float(float(cur[k]))
		if id in IDS:
			out[id] = (BigNum.from_serialized(out[id]) if out.has(id) else BigNum.zero()).add(amt).serialize()
			continue
		var l: Dictionary = (cfg().get("legacy", {}) as Dictionary).get(id, {})
		if l.is_empty():
			continue  # unknown ids are dropped (nothing reads them)
		if l.has("into"):
			var t: String = str(l["into"])
			into[t] = float(into.get(t, 0.0)) + amt.to_float()
			continue
		var c: String = str(l.get("to", CUBES))
		var conv: BigNum = amt.mul_f(rate(id, true))
		out[c] = (BigNum.from_serialized(out[c]) if out.has(c) else BigNum.zero()).add(conv).serialize()
	return {"currencies": out, "into": into}
