class_name LockerEditors
extends RefCounted
## [ui7] The Locker's Bots and Rocket sections, both in the workbench's list + detail pattern
## (ui/list_detail.gd), with a turning 3D preview in the detail panel.
##   Bots:   pick a robot type (chips on top); its design (systems/robot_design.gd): Builder parts,
##           paint (fleet liveries) and glow. Every robot of the type wears it, new ones too.
##   Rocket: the ship's hull paint, trim and engine glow (systems/ship_style.gd).
## Locked looks are hidden; only what you own or can buy now is listed.

# l10n:begin
const BOT_CATS: Array = [["parts", "Parts"], ["paint", "Paint"], ["glow", "Glow"]]
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

class BotEditor extends VBoxContainer:
	var world: Node
	var fleet: Fleet
	var _type: String = ""
	var _chips: HBoxContainer
	var _ld: ListDetail
	var modules: bool = false  # [ui7] floating glass modules (ui/holo_frame.gd)

	func _ready() -> void:
		add_theme_constant_override("separation", HoloFrame.GAP if modules else 8)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		if fleet == null and world:
			fleet = world.get("fleet") as Fleet
		var types: Array[String] = LockerEditors.bot_types(fleet)
		_type = types[0] if not types.is_empty() else ""
		_chips = HBoxContainer.new()
		_chips.add_theme_constant_override("separation", 6)
		if modules:
			var cm: PanelContainer = HoloFrame.module(6)
			add_child(cm)
			cm.add_child(_chips)
		else:
			add_child(_chips)
		for rid: String in types:
			var b := Button.new()
			b.text = TranslationServer.translate(str(Economy.robots[rid].get("name", rid)))
			b.custom_minimum_size = Vector2(110, 36)
			b.set_meta("type", rid)
			b.pressed.connect(func() -> void: set_type(rid))
			_chips.add_child(b)
		_ld = ListDetail.new()
		_ld.world = world
		_ld.modules = modules
		_ld.categories = LockerEditors.BOT_CATS
		_ld.provider = func() -> Array: return LockerEditors.bot_rows(fleet, _type)
		_ld.counter = func() -> String: return TranslationServer.translate("Every %s wears this") % TranslationServer.translate(str(Economy.robots.get(_type, {}).get("name", _type))) if _type != "" else ""
		add_child(_ld)
		_style_chips()

	func set_type(rid: String) -> void:
		if rid == _type:
			return
		_type = rid
		Audio.play("click", 1.1, -8.0)
		_style_chips()
		_ld.refresh(true)

	func _style_chips() -> void:
		for b: Node in _chips.get_children():
			var on: bool = str(b.get_meta("type")) == _type
			BenchKit.style_action(b as Button, ListDetail.TAG_OK if on else BenchKit.HOLO)

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


static func bot_rows(fleet: Fleet, type_id: String) -> Array:
	var out: Array = []
	if type_id == "":
		return out
	var tier: int = fleet.tier_of(type_id) if fleet else 0
	var cur: Dictionary = RobotDesign.parts(type_id)
	# Parts: what you own, plus what you can unlock now (cost only); locked ones stay hidden.
	for slot: String in RobotBuilder.SLOTS:
		for p: Dictionary in RobotBuilder.parts_for_slot(slot):
			var id: String = str(p["id"])
			if not RobotBuilder.fits(id, type_id):
				continue
			var owned: bool = RobotBuilder.count(id) > 0
			var why: String = "" if owned else RobotBuilder.get_block_reason(id)
			var buyable: bool = not owned and RobotBuilder.source_kind(id) in ["craft", "haggle", "research", "set"] and RobotBuilder.locked_research(id) == ""
			if not owned and not buyable:
				continue
			var worn: bool = str(cur.get(slot, "")) == id
			var src: Dictionary = p.get("source", {})
			var price: Dictionary = {} if owned else {"cubes": float(src.get("cubes", 0)), "parts": RobotBuilder.craft_parts(id) if RobotBuilder.source_kind(id) != "haggle" else float(src.get("parts", 0))}
			var cand: Dictionary = cur.duplicate()
			cand[slot] = id
			var it: Dictionary = {"id": "part_" + id, "cat": "parts", "icon": "star", "name": "%s: %s" % [RobotBuilder.slot_name(slot), _tr(str(p.get("name", id)))],
				"desc": _tr(str(p.get("desc", ""))), "price": price, "table": [], "requires": "",
				"custom": func(_w: Node) -> Control: return LockerEditors._bot_preview(type_id, cand, tier)}
			if worn:
				it["state"] = "ready"
				it["tag"] = _tr("WORN")
				it["action"] = _tr("Take it off")
				it["act"] = func() -> bool: return RobotDesign.set_part(fleet, type_id, slot, "") == ""
			elif owned:
				it["state"] = "ready"
				it["tag"] = _tr("OWNED")
				it["action"] = _tr("Wear it")
				it["act"] = func() -> bool: return RobotDesign.set_part(fleet, type_id, slot, id) == ""
			else:
				it["state"] = "ready" if why == "" else "short"
				it["action"] = _tr("Unlock and wear")
				it["act"] = func() -> bool: return RobotBuilder.obtain(id) == "" and RobotDesign.set_part(fleet, type_id, slot, id) == ""
			out.append(it)
	# Paint: the fleet liveries you've won (none = plain).
	var cur_l: String = RobotDesign.livery_for(type_id)
	var paints: Array = [["", _tr("Plain"), ""]]
	for l: Dictionary in Contracts.shop():
		if str(l.get("id", "")) in Contracts.owned():
			paints.append([str(l["id"]), _tr(str(l.get("name", ""))), _tr(str(l.get("desc", "")))])
	for pnt: Array in paints:
		var lid: String = str(pnt[0])
		out.append({"id": "paint_" + lid, "cat": "paint", "icon": "star", "name": str(pnt[1]), "desc": str(pnt[2]),
			"state": "ready", "tag": _tr("WORN") if lid == cur_l else "", "price": {}, "table": [],
			"action": "" if lid == cur_l else _tr("Wear it"),
			"act": func() -> bool:
				RobotDesign.set_field(fleet, type_id, "livery", lid)
				return true})
	# Glow: the light strips' colour.
	var cur_g: String = str(RobotDesign.of(type_id).get("glow", ""))
	var glows: Array = [["", _tr("Stock")]]
	for g: Array in RobotDesign.GLOWS:
		glows.append([str(g[0]), _tr(str(g[1]))])
	for g: Array in glows:
		var gid: String = str(g[0])
		out.append({"id": "glow_" + gid, "cat": "glow", "icon": "star", "name": str(g[1]), "desc": "",
			"state": "ready", "tag": _tr("WORN") if gid == cur_g else "", "price": {}, "table": [],
			"action": "" if gid == cur_g else _tr("Wear it"),
			"act": func() -> bool:
				RobotDesign.set_field(fleet, type_id, "glow", gid)
				return true})
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
