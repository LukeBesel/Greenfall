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


func _ready() -> void:
	add_theme_constant_override("separation", 8)
	var head := UITheme.label("HAGGLE'S PARTS TRADE", 20, UITheme.CREAM)
	add_child(head)
	var blurb := UITheme.label("\"Everything's original. Mostly. Three of yours for one of mine, no questions, some questions.\"", 14, UITheme.MUTED)
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
	for c: Node in _list.get_children():
		c.queue_free()
	_bolts.text = "Bolts  %s      Parts in storage  %d" % [Settings.fmt(GameState.get_currency("bolts")), GameState.parts.size()]
	var types: Array = Economy.parts.get("types", [])
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
	_pity.text = ("Haggle: \"Funny thing, I just happened to find a %s. For you, half price.\"" % types[pity_type]["name"]) if pity_type >= 0 else ""
	for t: int in types.size():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name_l := UITheme.label("%s%s" % [types[t]["name"], "   (needed)" if t in need else ""], 15, UITheme.GOLD if t in need else UITheme.CREAM)
		name_l.custom_minimum_size = Vector2(250, 0)
		row.add_child(name_l)
		row.add_child(UITheme.label("own %d" % _owned(t).size(), 14, UITheme.MUTED))
		var price: float = BUY_PRICE[0] * (0.5 if t == pity_type else 1.0)
		var buy := Button.new()
		buy.text = "Buy Rusty  %s" % Settings.fmt(BigNum.from_float(price))
		buy.disabled = not GameState.can_afford("cubes", BigNum.from_float(price))
		buy.pressed.connect(_buy.bind(t, 0, price))
		row.add_child(buy)
		var buy2 := Button.new()
		buy2.text = "Buy Worn  %s" % Settings.fmt(BigNum.from_float(BUY_PRICE[1]))
		buy2.disabled = not GameState.can_afford("cubes", BigNum.from_float(BUY_PRICE[1]))
		buy2.pressed.connect(_buy.bind(t, 1, BUY_PRICE[1]))
		row.add_child(buy2)
		var swap := Button.new()
		swap.text = "Swap 3 spares"
		swap.disabled = _spares().size() < 3
		swap.pressed.connect(_swap.bind(t))
		row.add_child(swap)
		_list.add_child(row)
	var scrap := Button.new()
	var spares: Array[int] = _spares()
	scrap.text = "Scrap %d spare Rusty parts  ->  +%d bolts" % [_rusty_spares().size(), _rusty_spares().size() * 2]
	scrap.disabled = _rusty_spares().is_empty()
	scrap.pressed.connect(_scrap)
	_list.add_child(scrap)


## Parts not needed by any recipe slot (keeps one of each needed type).
func _spares() -> Array[int]:
	var keep: Dictionary = {}
	for rid: String in Economy.robot_order:
		for part_id: String in Economy.robots[rid].get("recipe", []):
			keep[Fleet.part_index(part_id)] = int(keep.get(Fleet.part_index(part_id), 0)) + 1
	var counts: Dictionary = {}
	var out: Array[int] = []
	for i: int in GameState.parts.size():
		var t: int = int(GameState.parts[i]["type"])
		counts[t] = int(counts.get(t, 0)) + 1
		if int(counts[t]) > int(keep.get(t, 0)):
			out.append(i)
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
	var sp: Array[int] = _spares()
	if sp.size() < 3:
		return
	var take: Array[int] = [sp[0], sp[1], sp[2]]
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
