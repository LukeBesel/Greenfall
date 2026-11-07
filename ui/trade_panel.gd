class_name TradePanel
extends VBoxContainer
## Haggle's Parts Trade (kiosk at the hub). Buy parts at a premium, swap three spares for one of
## your choice, scrap spares for Bolts. Pity offer: a part a recipe has needed for a long time is
## offered at half price.

const BUY_PRICE: Array[float] = [80.0, 220.0, 700.0, 2600.0, 12000.0]
const PITY_AFTER_S: float = 600.0

var fleet: Fleet
var _list: VBoxContainer
var _bolts: Label
var _pity: Label
var _rows: Array[Dictionary] = []
var _scrap_btn: Button
var _pity_type: int = -1
var _bits_label: Label  # [drones] Haggle's builder stall
var _bits: HBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := UITheme.label(tr("HAGGLE'S PARTS TRADE"), 20, UITheme.CREAM)
	add_child(head)
	var blurb := UITheme.label(tr("\"Everything's original. Mostly. Three of yours for one of mine, no questions, some questions.\""), 14, UITheme.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(blurb)
	_bolts = UITheme.label("", 15, UITheme.GOLD)
	add_child(_bolts)
	_pity = UITheme.label("", 15, UITheme.GREEN)
	_pity.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_pity)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	add_child(_list)
	# [drones] Haggle's builder stall: a few robot builder parts, new stock every few minutes.
	_bits_label = UITheme.label("", 15, UITheme.CREAM)
	add_child(_bits_label)
	_bits = HBoxContainer.new()
	_bits.add_theme_constant_override("separation", 8)
	add_child(_bits)
	refresh()


func _owned(t: int, rarity: int = -1) -> Array[int]:
	var out: Array[int] = []
	for i: int in GameState.parts.size():
		var p: Dictionary = GameState.parts[i]
		if int(p["type"]) == t and (rarity < 0 or int(p["rarity"]) == rarity):
			out.append(i)
	return out


func _needed_types() -> Array[int]:
	var need: Array[int] = []
	if fleet == null:
		return need
	for rid: String in Economy.robot_order:
		for r: Dictionary in fleet.recipe_status(rid):
			if not r["have"]:
				var idx: int = Fleet.part_index(str(r["part_id"]))
				if not (idx in need):
					need.append(idx)
	return need


func refresh() -> void:
	var types: Array = Economy.parts.get("types", [])
	if _rows.size() != types.size() or not is_instance_valid(_scrap_btn):
		_build_rows(types.size())
	_bolts.text = tr("Bolts  %s      Parts in storage  %d") % [Settings.fmt(GameState.get_currency("bolts")), GameState.parts.size()]
	var need: Array[int] = _needed_types()
	# Pity: track how long each needed type has been missing.
	var t_now: float = float(GameState.stats.get("time_played", 0.0))
	var pity_type: int = -1
	for t: int in need:
		var key: String = "missing_since_%d" % t
		if not GameState.flags.has(key):
			GameState.flags[key] = t_now
		elif t_now - float(GameState.flags[key]) > PITY_AFTER_S:
			pity_type = t
	_pity_type = pity_type
	_pity.text = (tr("Haggle: \"Funny thing, I just happened to find a %s. For you, half price.\"") % tr(str(types[pity_type]["name"]))) if pity_type >= 0 else ""
	var take: Array[int] = swap_take()
	var swap_tip: String = ""
	if take.size() >= 3:
		var names: Array[String] = []
		for i: int in take:
			var p: Dictionary = GameState.parts[i]
			names.append(L10nFmt.part_label(tr(str(Economy.rarity(int(p["rarity"])).get("name", "?"))), tr(str(types[int(p["type"])]["name"]))))  # [i18n2]
		swap_tip = tr("Trades away: %s") % ", ".join(names)
	else:
		swap_tip = tr("Needs 3 spare parts (Control Cores needed for a Mk tier are never traded).")
	for t: int in types.size():
		var row: Dictionary = _rows[t]
		var needed: bool = t in need
		var name_l: Label = row["name"]
		name_l.text = "%s%s" % [tr(str(types[t]["name"])), tr("   (needed)") if needed else ""]
		name_l.add_theme_color_override("font_color", UITheme.GOLD if needed else UITheme.CREAM)
		(row["own"] as Label).text = tr("own %d") % _owned(t).size()
		var price: float = _price(t, 0)
		var buy: Button = row["buy"]
		buy.text = tr("Buy Rusty  %s") % Settings.fmt(BigNum.from_float(price))
		buy.disabled = not GameState.can_afford("cubes", BigNum.from_float(price))
		var buy2: Button = row["buy2"]
		buy2.text = tr("Buy Worn  %s") % Settings.fmt(BigNum.from_float(BUY_PRICE[1]))
		buy2.disabled = not GameState.can_afford("cubes", BigNum.from_float(BUY_PRICE[1]))
		var swap: Button = row["swap"]
		swap.disabled = take.size() < 3
		swap.tooltip_text = swap_tip
	var rusty: int = _rusty_spares().size()
	_scrap_btn.text = tr("Scrap %d spare Rusty parts  ->  +%d bolts") % [rusty, rusty * 2]
	_scrap_btn.disabled = rusty == 0
	_refresh_bits()


## [drones] Builder stall rows (buttons are rebuilt only when the stock rotates, so focus survives).
func _refresh_bits() -> void:
	if _bits == null:
		return
	var offers: Array[String] = RobotBuilder.haggle_offers()
	_bits_label.text = tr("BUILDER BITS  ·  new stock in %d min  ·  fit them in the Builder tab") % ceili(RobotBuilder.haggle_seconds_left() / 60.0)
	if str(_bits.get_meta("ids", [])) != str(offers):
		_bits.set_meta("ids", offers)
		for c: Node in _bits.get_children():
			_bits.remove_child(c)
			c.queue_free()
		for id: String in offers:
			var b := Button.new()
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.custom_minimum_size = Vector2(0, 52)
			b.pressed.connect(func() -> void:
				var why: String = RobotBuilder.buy_haggle(id)
				if why != "":
					Audio.play("buzz", 1.2, -8.0)
				else:
					EventBus.toast.emit(tr("Haggle: \"%s. Treat it nicely.\"") % tr(str(RobotBuilder.part(id).get("name", id))), "hint")
				refresh())
			_bits.add_child(b)
	for i: int in mini(offers.size(), _bits.get_child_count()):
		var id: String = offers[i]
		var p: Dictionary = RobotBuilder.part(id)
		var src: Dictionary = p.get("source", {})
		var b: Button = _bits.get_child(i) as Button
		b.text = tr("%s  (own %d)\n%s cubes + %d bolts") % [tr(str(p.get("name", id))), RobotBuilder.count(id), Settings.fmt(BigNum.from_float(float(src.get("cubes", 0)))), int(src.get("bolts", 0))]
		b.tooltip_text = tr(str(p.get("desc", "")))
		b.disabled = RobotBuilder.haggle_block_reason(id) != ""


## Rows are created once; refresh() only updates their text and disabled state so focus survives.
func _build_rows(n: int) -> void:
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_rows.clear()
	for t: int in n:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label("", 15, UITheme.CREAM)
		name_l.custom_minimum_size = Vector2(250, 0)
		row.add_child(name_l)
		var own_l := UITheme.label("", 14, UITheme.MUTED)
		row.add_child(own_l)
		var buy := Button.new()
		buy.pressed.connect(func() -> void: _buy(t, 0, _price(t, 0)))
		row.add_child(buy)
		var buy2 := Button.new()
		buy2.pressed.connect(func() -> void: _buy(t, 1, _price(t, 1)))
		row.add_child(buy2)
		var swap := Button.new()
		swap.text = tr("Swap 3 spares")
		swap.pressed.connect(_swap.bind(t))
		row.add_child(swap)
		_list.add_child(row)
		_rows.append({"name": name_l, "own": own_l, "buy": buy, "buy2": buy2, "swap": swap})
	_scrap_btn = Button.new()
	_scrap_btn.pressed.connect(_scrap)
	_list.add_child(_scrap_btn)


func _price(t: int, rarity: int) -> float:
	return BUY_PRICE[rarity] * (0.5 if rarity == 0 and t == _pity_type else 1.0)


func first_button() -> Button:
	if _rows.is_empty():
		return null
	return _rows[0]["buy"]


## Lowest Control Core rarity any robot type still needs for its next Mk tier (99 if none).
func _protected_core_rarity() -> int:
	var lowest: int = 99
	if fleet == null:
		return lowest
	for rid: String in Economy.robot_order:
		var req: Dictionary = fleet.tier_requirements(rid)
		if not req.get("maxed", false):
			lowest = mini(lowest, int(req.get("core_rarity", 99)))
	return lowest


## Parts not needed by any recipe slot. For each type the highest-rarity parts are kept (as many
## as all recipes use); Control Cores good enough for a pending Mk tier are never spares.
func _spares() -> Array[int]:
	var keep: Dictionary = {}
	for rid: String in Economy.robot_order:
		for part_id: String in Economy.robots[rid].get("recipe", []):
			keep[Fleet.part_index(part_id)] = int(keep.get(Fleet.part_index(part_id), 0)) + 1
	var by_type: Dictionary = {}
	for i: int in GameState.parts.size():
		var t: int = int(GameState.parts[i]["type"])
		if not by_type.has(t):
			by_type[t] = []
		(by_type[t] as Array).append(i)
	var core_t: int = Fleet.part_index("core")
	var core_min: int = _protected_core_rarity()
	var out: Array[int] = []
	for t: int in by_type:
		var idx: Array = by_type[t]
		idx.sort_custom(func(a: int, b: int) -> bool:
			var ra: int = int(GameState.parts[a]["rarity"])
			var rb: int = int(GameState.parts[b]["rarity"])
			return ra > rb if ra != rb else a < b)
		for k: int in idx.size():
			var i: int = idx[k]
			if k < int(keep.get(t, 0)):
				continue
			if t == core_t and int(GameState.parts[i]["rarity"]) >= core_min:
				continue
			out.append(i)
	out.sort()
	return out


## The three spares a swap consumes: lowest rarity first.
func swap_take() -> Array[int]:
	var sp: Array[int] = _spares()
	sp.sort_custom(func(a: int, b: int) -> bool:
		var ra: int = int(GameState.parts[a]["rarity"])
		var rb: int = int(GameState.parts[b]["rarity"])
		return ra < rb if ra != rb else a < b)
	var out: Array[int] = []
	if sp.size() >= 3:
		out = [sp[0], sp[1], sp[2]]
	return out


func _rusty_spares() -> Array[int]:
	var out: Array[int] = []
	for i: int in _spares():
		if int(GameState.parts[i]["rarity"]) == 0:
			out.append(i)
	return out


func _remove(indices: Array[int]) -> void:
	indices.sort()
	indices.reverse()
	for i: int in indices:
		GameState.parts.remove_at(i)


func _buy(t: int, rarity: int, price: float) -> void:
	if not GameState.spend("cubes", BigNum.from_float(price)):
		Audio.play("buzz", 1.2, -8.0)
		return
	GameState.parts.append({"type": t, "rarity": rarity})
	GameState.flags.erase("missing_since_%d" % t)
	EventBus.part_found.emit(t, rarity)
	Audio.play("buy", 1.0, -3.0)
	refresh()


func _swap(t: int) -> void:
	var take: Array[int] = swap_take()
	if take.size() < 3:
		return
	var r: int = 4
	for i: int in take:
		r = mini(r, int(GameState.parts[i]["rarity"]))
	_remove(take)
	GameState.parts.append({"type": t, "rarity": r})
	GameState.flags.erase("missing_since_%d" % t)
	Audio.play("buy", 1.1, -3.0)
	refresh()


func _scrap() -> void:
	var rs: Array[int] = _rusty_spares()
	GameState.add_currency("bolts", BigNum.from_float(rs.size() * 2.0))
	_remove(rs)
	Audio.play("crunch", 1.2, -6.0)
	refresh()
