class_name CurrencyCluster
extends VBoxContainer
## Top-left currency readout: the main currency (Cubes) with a thin cube icon, a smooth count-up
## and its income rate in small muted text. [money] The only other currencies, Parts and Seeds
## (core/currencies.gd), appear only when they change, as a small chip that fades in and out.
## No panel: text with a soft shadow, hairline icons.

const CHIP_LIFE: float = 3.5
## [money] Chips only for these (cubes are the big readout).
const CHIP_IDS: Array[String] = ["parts", "seeds"]

var _count: Label
var _rate: Label
var _icon: Control
var _chips: VBoxContainer
var _chip_map: Dictionary = {}  # id -> {node, label, delta_label, delta, left, age}
var _prev: Dictionary = {}
var _shown: float = 0.0
var _bump: float = 0.0
var _since_cash: float = 99.0
var _warm: float = 1.5
## [first] Cubes still flying into the counter (ui/coin_flight.gd); the readout counts up as they land.
var in_flight: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_icon = Control.new()
	_icon.custom_minimum_size = Vector2(24, 24)
	_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon.draw.connect(func() -> void: HudIcons.draw(_icon, "cube", _icon.size * 0.5, 11.0, UITheme.CREAM.lerp(UITheme.GOLD, 0.35 + 0.65 * _bump), 1.5))
	row.add_child(_icon)
	_count = UITheme.label("0", 28, UITheme.CREAM)
	_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_count)
	_rate = UITheme.label("", 13, UITheme.MUTED)
	_rate.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_rate)
	_chips = VBoxContainer.new()
	_chips.add_theme_constant_override("separation", 3)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chips)
	for id: Variant in GameState.currencies:
		_prev[str(id)] = (GameState.currencies[id] as BigNum).to_float()
	_shown = GameState.get_currency("cubes").to_float()
	EventBus.currency_changed.connect(_on_currency)
	EventBus.cube_cashed.connect(func(_v: BigNum, _p: Vector3) -> void:
		_bump = 1.0
		_since_cash = 0.0)


func _on_currency(id: String, amount: BigNum) -> void:
	var v: float = amount.to_float()
	var before: float = float(_prev.get(id, 0.0))
	_prev[id] = v
	if not (id in CHIP_IDS) or _warm > 0.0:
		return
	var d: float = v - before
	if absf(d) < 0.001 or (id == "seeds" and d < 0.0):  # planting: the hotbar's Plant slot counts seeds
		return
	_chip(id, Settings.fmt(amount), d)


func _chip(id: String, amount_text: String, delta: float, note: String = "") -> void:
	var c: Dictionary = _chip_map.get(id, {})
	if c.is_empty() or not is_instance_valid(c["node"]):
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := Control.new()
		ic.custom_minimum_size = Vector2(16, 16)
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var kind: String = Currencies.icon(id)
		var tint: Color = CurrencyIcon.tint(id)
		ic.draw.connect(func() -> void: HudIcons.draw(ic, kind, ic.size * 0.5, 7.5, Color(tint, 0.9), 1.2))
		hb.add_child(ic)
		var l := UITheme.label("", 13, UITheme.CREAM)
		hb.add_child(l)
		var dl := UITheme.label("", 13, UITheme.GREEN)
		hb.add_child(dl)
		hb.modulate.a = 0.0
		_chips.add_child(hb)
		c = {"node": hb, "label": l, "delta_label": dl, "delta": 0.0, "left": CHIP_LIFE, "age": 0.0}
		_chip_map[id] = c
	c["delta"] = float(c["delta"]) + delta
	c["left"] = CHIP_LIFE
	(c["label"] as Label).text = "%s  %s" % [Currencies.short_name(id), amount_text]
	var dv: float = float(c["delta"])
	var dl2: Label = c["delta_label"]
	dl2.text = ("%s%s" % ["+" if dv > 0.0 else "-", Settings.fmt(BigNum.from_float(absf(dv)))]) + (("  " + note) if note != "" else "")
	dl2.add_theme_color_override("font_color", UITheme.GREEN if dv > 0.0 else UITheme.MUTED)


var _demo_t: float = 0.0


func _process(delta: float) -> void:
	_warm = maxf(0.0, _warm - delta)
	if DevHooks.has("money-chips") and _warm <= 0.0:  # [money] screenshots: keep the Parts/Seeds chips up
		_demo_t -= delta
		if _demo_t <= 0.0:
			_demo_t = 2.5
			GameState.add_currency("parts", BigNum.from_float(24))
			GameState.add_currency("seeds", BigNum.from_float(2))
		for c: Dictionary in _chip_map.values():  # software rendering runs at ~1 fps: keep them up
			c["left"] = CHIP_LIFE + 30.0
	var cubes: BigNum = GameState.get_currency("cubes")
	var target: float = cubes.to_float()
	if in_flight > 0.0:  # [first]
		target = maxf(_shown if _shown < target else 0.0, target - in_flight)
	if target < 1.0e9:
		_shown = lerpf(_shown, target, clampf(delta * 8.0, 0.0, 1.0))
		if absf(_shown - target) < 0.5:
			_shown = target
		_count.text = Settings.fmt(BigNum.from_float(round(_shown)))
	else:
		_count.text = Settings.fmt(cubes)
	_bump = maxf(0.0, _bump - delta * 2.5)
	_since_cash += delta
	_count.add_theme_color_override("font_color", UITheme.CREAM.lerp(UITheme.GOLD, _bump))
	_icon.queue_redraw()
	var rate: float = GameState.income_rate()
	_rate.text = ("+%s/s" % Settings.fmt(BigNum.from_float(rate))) if rate > 0.0 else ""
	var full: bool = Settings.hud_mode == Settings.HudMode.FULL
	var want: float = 1.0 if full or _since_cash < 6.0 else 0.0
	_rate.modulate.a = move_toward(_rate.modulate.a, want, delta * (4.0 if want > 0.0 else 0.6))
	for id: Variant in _chip_map.keys():
		var c: Dictionary = _chip_map[id]
		var n: Control = c["node"]
		if not is_instance_valid(n):
			_chip_map.erase(id)
			continue
		c["age"] = float(c["age"]) + delta
		c["left"] = float(c["left"]) - delta
		n.modulate.a = minf(clampf(float(c["age"]) / 0.25, 0.0, 1.0), clampf(float(c["left"]) / 0.7, 0.0, 1.0))
		if float(c["left"]) <= 0.0:
			n.queue_free()
			_chip_map.erase(id)


## Number of visible chips (tests).
func chip_count() -> int:
	return _chip_map.size()


## [first] Screen point the flying coins aim at (the cube icon).
func icon_center() -> Vector2:
	return _icon.get_global_rect().get_center()


## [first] One flying coin arrived: release its share and give the icon a pop.
func land(amount: float) -> void:
	in_flight = maxf(0.0, in_flight - amount)
	_bump = 1.0
	_since_cash = 0.0
