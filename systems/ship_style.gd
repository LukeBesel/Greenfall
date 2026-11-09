class_name ShipStyle
extends RefCounted
## [ui7] The ship's looks (data/ship_style.json): hull paint, trim and engine glow, changed only at
## the Locker (Rocket section). ShipModel reads paint_color(), trim_color() and glow_color() when
## it builds its materials. State: GameState.flags["ship_style"] = {paint, trim, glow, owned: []}.

const PATH: String = "res://data/ship_style.json"
const SLOTS: Array[String] = ["paints", "trims", "glows"]
const KEY: Dictionary = {"paints": "paint", "trims": "trim", "glows": "glow"}
## The ship's own colours (ShipModel's PEARL / ACCENT / GLOW) when nothing is chosen.
const DEFAULTS: Dictionary = {"paints": Color(0.93, 0.93, 0.91), "trims": Color(1.0, 0.5, 0.16), "glows": Color(0.3, 0.88, 1.0)}

static var _cfg: Dictionary = {}


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func st() -> Dictionary:
	var v: Variant = GameState.flags.get("ship_style")
	if not (v is Dictionary):
		v = {}
		GameState.flags["ship_style"] = v
	return v


static func items(slot: String) -> Array:
	return cfg().get(slot, [])


static func item(slot: String, id: String) -> Dictionary:
	for it: Dictionary in items(slot):
		if str(it["id"]) == id:
			return it
	return {}


static func worn(slot: String) -> String:
	var id: String = str(st().get(KEY[slot], ""))
	if id == "" and not items(slot).is_empty():
		id = str(items(slot)[0]["id"])
	return id


static func _owned() -> Array:
	var v: Variant = st().get("owned")
	if not (v is Array):
		v = []
		st()["owned"] = v
	return v


## Unlocked: free, the ship's Mk reached, or bought.
static func unlocked(slot: String, id: String) -> bool:
	var u: Dictionary = item(slot, id).get("unlock", {})
	if u.is_empty() or ("%s:%s" % [slot, id]) in _owned():
		return true
	if u.has("tier"):
		return RocketTiers.tier() >= int(u["tier"])
	return false


## Shown in the Locker: unlocked, or buyable right now (parts). Tier locks stay hidden.
static func listed(slot: String, id: String) -> bool:
	return unlocked(slot, id) or item(slot, id).get("unlock", {}).has("parts")


static func price(slot: String, id: String) -> Dictionary:
	var u: Dictionary = item(slot, id).get("unlock", {})
	return {"parts": float(u["parts"])} if u.has("parts") and not unlocked(slot, id) else {}


static func buy(slot: String, id: String) -> bool:
	var p: Dictionary = price(slot, id)
	if p.is_empty() or not GameState.spend_all(p):
		return false
	_owned().append("%s:%s" % [slot, id])
	return true


static func wear(slot: String, id: String) -> bool:
	if not unlocked(slot, id):
		return false
	st()[KEY[slot]] = id
	return true


static func color(slot: String) -> Color:
	var it: Dictionary = item(slot, worn(slot))
	return Color.html(str(it["color"])) if it.has("color") else DEFAULTS[slot]


static func paint_color() -> Color:
	return color("paints")


static func trim_color() -> Color:
	return color("trims")


static func glow_color() -> Color:
	return color("glows")
