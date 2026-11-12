# Snippet cut from ui/locker_editors.gd in task M3-13: the Locker's Rocket section (ship paint, trim
# and glow, bought or tier-unlocked). Put it back with the SHIP_CATS constant
# [["paints", "Paint"], ["trims", "Trim"], ["glows", "Glow"]] (l10n block), the "rocket" entry in
# LockerPanel (_add_who, _rocket_open, _make_editor) and ShipStyle colours in ShipModel._make_mats.

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
