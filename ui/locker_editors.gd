class_name LockerEditors
extends RefCounted
## [ui7] The Locker's Bots and Rocket sections, both in the workbench's list + detail pattern
## (ui/list_detail.gd), with a turning 3D preview in the detail panel.
##   Bots:   pick a robot type (chips on top); its design (systems/robot_design.gd): Builder parts,
##           fleet marks and light colour. Every robot of the type wears it, new ones too. Every
##           look is a found piece (CrewLooks): found ones are worn, unfound ones this planet hides
##           show as "???" with their hint, the rest are counted.
##   Rocket: the ship's hull paint, trim and engine glow (systems/ship_style.gd).
## Rocket looks are still bought (ShipStyle).

# l10n:begin
const BOT_CATS: Array = [["parts", "Parts"], ["paint", "Fleet mark"], ["glow", "Light colour"]]
const SHIP_CATS: Array = [["paints", "Paint"], ["trims", "Trim"], ["glows", "Glow"]]
# l10n:end


static func _tr(s: String) -> String:
	return TranslationServer.translate(s)


## Robot types you can design: researched or already built.
static func bot_types(fleet: Fleet) -> Array[String]:
	var out: Array[String] = []
	for rid: String in Economy.robot_order:
		if Research.robot_unlocked(rid) or (fleet and fleet.count(rid) > 0):
			out.append(rid)
	return out


# --- Bots -----------------------------------------------------------------------------------

## One robot type's page (the Locker gives each type its own tab): its parts, fleet mark and light
## colour, worn by every robot of the type.
class BotEditor extends VBoxContainer:
	var world: Node
	var fleet: Fleet
	## The robot type this page dresses (the Locker sets it; "" = the first type there is).
	var type_id: String = ""
	var _ld: ListDetail
	var modules: bool = false  # [ui7] floating glass modules (ui/holo_frame.gd)

	func _ready() -> void:
		add_theme_constant_override("separation", HoloFrame.GAP if modules else 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		if fleet == null and world:
			fleet = world.get("fleet") as Fleet
		if type_id == "":
			var types: Array[String] = LockerEditors.bot_types(fleet)
			type_id = types[0] if not types.is_empty() else ""
		_ld = ListDetail.new()
		_ld.world = world
		_ld.modules = modules
		_ld.categories = LockerEditors.BOT_CATS
		_ld.provider = func() -> Array: return LockerEditors.bot_rows(fleet, type_id)
		_ld.counter = func() -> String: return TranslationServer.translate("Every %s wears this") % TranslationServer.translate(str(Economy.robots.get(type_id, {}).get("name", type_id))) if type_id != "" else ""
		add_child(_ld)

	func first_button() -> Button:
		return _ld.first_button() if _ld else null


static func _bot_preview(type_id: String, parts: Dictionary, tier: int) -> Control:
	var pv := ModelPreview.new(Vector2i(300, 170))
	pv.frame(3.0, 0.6)
	var v := RobotVisual.new()
	pv.set_model(v)
	v.build(type_id, str(Economy.robot_tiers[clampi(tier, 0, Economy.robot_tiers.size() - 1)].get("look", "salvage")))
	RobotKit.fit(v, parts, str(Economy.robots.get(type_id, {}).get("role", "clean")))
	return pv


## The rows of a robot type's page: per slot the stock look, the found pieces (press to wear),
## the pieces this planet hides as "???" with their hint, and a count of those on other worlds.
## Nothing here is bought.
static func bot_rows(fleet: Fleet, type_id: String) -> Array:
	var out: Array = []
	if type_id == "":
		return out
	var tier: int = fleet.tier_of(type_id) if fleet else 0
	var cur: Dictionary = RobotDesign.parts(type_id)
	var def: PlanetDefinition = Planets.current()
	for slot: String in RobotBuilder.SLOTS:
		var worn_id: String = str(cur.get(slot, ""))
		var stock: Dictionary = cur.duplicate()
		stock.erase(slot)
		out.append(_wear_row("part_%s_" % slot, "parts", "%s: %s" % [RobotBuilder.slot_name(slot), _tr("Stock")], "", worn_id == "",
			func() -> bool: return RobotDesign.set_part(fleet, type_id, slot, "") == "",
			func(_w: Node) -> Control: return LockerEditors._bot_preview(type_id, stock, tier)))
		var list: Dictionary = CrewLooks.listing(CrewLooks.CREW, slot, def)
		for piece: String in list["found"]:
			var id: String = CrewLooks.option_of(piece)
			if not RobotBuilder.fits(id, type_id):
				continue
			var p: Dictionary = RobotBuilder.part(id)
			var cand: Dictionary = cur.duplicate()
			cand[slot] = id
			out.append(_wear_row("part_" + id, "parts", "%s: %s" % [RobotBuilder.slot_name(slot), _tr(str(p.get("name", id)))], _tr(str(p.get("desc", ""))),
				worn_id == id, func() -> bool: return RobotDesign.set_part(fleet, type_id, slot, id) == "",
				func(_w: Node) -> Control: return LockerEditors._bot_preview(type_id, cand, tier)))
		out.append_array(_unfound_rows("parts", slot, list, def))
	for key: String in [CrewLooks.LIVERY, CrewLooks.GLOW]:
		var cat: String = "paint" if key == CrewLooks.LIVERY else "glow"
		var cur_v: String = RobotDesign.livery_for(type_id) if key == CrewLooks.LIVERY else str(RobotDesign.of(type_id).get(CrewLooks.GLOW, ""))
		out.append(_wear_row("%s_" % cat, cat, _tr("Plain") if key == CrewLooks.LIVERY else _tr("Stock"), "", cur_v == "",
			func() -> bool: return RobotDesign.set_look(fleet, type_id, key, ""), Callable()))
		var list: Dictionary = CrewLooks.listing(CrewLooks.CREW, key, def)
		for piece: String in list["found"]:
			var id: String = CrewLooks.option_of(piece)
			out.append(_wear_row("%s_%s" % [cat, id], cat, _tr(Looks.name_of(piece)), _tr(str(Looks.def(piece).get("desc", ""))), cur_v == id,
				func() -> bool: return RobotDesign.set_look(fleet, type_id, key, id), Callable()))
		out.append_array(_unfound_rows(cat, key, list, def))
	return out


## One row of a look the player holds: WORN, or "Wear it".
static func _wear_row(id: String, cat: String, title: String, desc: String, worn: bool, act: Callable, preview: Callable) -> Dictionary:
	var it: Dictionary = {"id": id, "cat": cat, "icon": "star", "name": title, "desc": desc, "state": "ready", "price": {}, "table": [],
		"requires": "", "tag": _tr("WORN") if worn else _tr("FOUND"), "action": "" if worn else _tr("Wear it"), "act": act,
		"note": _tr("Every robot of this type wears it.") if worn else _tr("Found. Wear it on every robot of this type.")}
	if preview.is_valid():
		it["custom"] = preview
	return it


## The pieces of a slot still in the ground: "???" with the hint of where this planet hides each,
## and one line counting the ones on other worlds.
static func _unfound_rows(cat: String, key: String, list: Dictionary, def: PlanetDefinition) -> Array:
	var out: Array = []
	for piece: String in list["hidden"]:
		out.append({"id": "unfound_" + piece, "cat": cat, "icon": "star", "name": _tr(Looks.UNFOUND_NAME), "desc": "", "state": "locked",
			"price": {}, "table": [], "requires": "", "action": "", "note": _tr(Finds.hint_for(def, piece))})
	var n: int = int(list["elsewhere"])
	if n > 0:
		out.append({"id": "elsewhere_%s_%s" % [cat, key], "cat": cat, "icon": "star", "name": _tr("%d more lie on other worlds.") % n, "desc": "",
			"state": "locked", "price": {}, "table": [], "requires": "", "action": "", "note": ""})
	return out


# --- Rocket ---------------------------------------------------------------------------------

static func _ship_preview(slot: String, id: String) -> Control:
	var pv := ModelPreview.new(Vector2i(300, 170))
	pv.frame(9.0, 1.2)
	pv.spin = 0.3
	# Build the preview with the candidate look, then put the worn one back.
	var before: Variant = ShipStyle.st().get(ShipStyle.KEY[slot], null)
	ShipStyle.st()[ShipStyle.KEY[slot]] = id
	pv.set_model(ShipModel.for_display())
	if before == null:
		ShipStyle.st().erase(ShipStyle.KEY[slot])
	else:
		ShipStyle.st()[ShipStyle.KEY[slot]] = before
	return pv


static func ship_rows(world: Node) -> Array:
	var out: Array = []
	for slot: String in ShipStyle.SLOTS:
		for it: Dictionary in ShipStyle.items(slot):
			var id: String = str(it["id"])
			if not ShipStyle.listed(slot, id):
				continue  # tier-locked looks stay hidden
			var unl: bool = ShipStyle.unlocked(slot, id)
			var worn: bool = ShipStyle.worn(slot) == id
			var price: Dictionary = ShipStyle.price(slot, id)
			out.append({"id": "%s_%s" % [slot, id], "cat": slot, "icon": "star", "name": _tr(str(it.get("name", id))), "desc": "",
				"state": "ready" if unl or GameState.can_afford_all(price) else "short", "tag": _tr("WORN") if worn else (_tr("OWNED") if unl else ""),
				"price": price, "table": [], "action": "" if worn else (_tr("Wear it") if unl else _tr("Unlock and wear")),
				"custom": func(_w: Node) -> Control: return LockerEditors._ship_preview(slot, id),
				"act": func() -> bool:
					if not unl and not ShipStyle.buy(slot, id):
						return false
					var ok: bool = ShipStyle.wear(slot, id)
					if ok and world and world.has_method("refresh_rocket"):
						world.refresh_rocket()
					return ok})
	return out


class ShipEditor extends VBoxContainer:
	var world: Node
	var _ld: ListDetail
	var modules: bool = false  # [ui7]

	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		_ld = ListDetail.new()
		_ld.world = world
		_ld.modules = modules
		_ld.categories = LockerEditors.SHIP_CATS
		_ld.provider = func() -> Array: return LockerEditors.ship_rows(world)
		_ld.counter = func() -> String: return TranslationServer.translate("Ship looks: the tiers keep their shape")
		add_child(_ld)

	func first_button() -> Button:
		return _ld.first_button() if _ld else null
