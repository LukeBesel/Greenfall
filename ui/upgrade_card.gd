class_name UpgradeCard
extends PanelContainer
## A chunky upgrade card: icon, level, before → after numbers, cost with an affordability bar and
## time estimate, x1 / x10 / Max buttons, best-value tag, and a buy flourish (click, flash, shine,
## sparkle burst, level tick).

signal bought(id: String, count: int)

var upgrade_id: String
var is_best_value: bool = false

var _icon: UIIcon
var _name: Label
var _level: Label
var _desc: Label
var _change: Label
var _cost: Label
var _bar: ProgressBar
var _eta: Label
var _btn1: Button
var _btn10: Button
var _btnmax: Button
var _tag: Label
var _breakdown: Label
var _flash: ColorRect
var _shine: ColorRect
var _particles: CPUParticles2D
var _bounce_t: float = 0.0
var _affordable: bool = false


func _init(id: String) -> void:
	upgrade_id = id


func _ready() -> void:
	custom_minimum_size = Vector2(330, 0)
	clip_contents = true
	var def: Dictionary = Economy.upgrade_defs[upgrade_id]
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	_icon = UIIcon.new(str(def.get("icon", "cube")), 56, UITheme.GOLD)
	top.add_child(_icon)
	var tvb := VBoxContainer.new()
	tvb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tvb.add_theme_constant_override("separation", -2)
	top.add_child(tvb)
	_name = UITheme.label(tr(str(def["name"])), 23)
	tvb.add_child(_name)
	_level = UITheme.label(tr("Lv 0"), 16, UITheme.MUTED)
	tvb.add_child(_level)
	_tag = UITheme.label(tr("BEST VALUE"), 13, Color(0.15, 0.1, 0.05))
	_tag.add_theme_stylebox_override("normal", UITheme.box(UITheme.GOLD, Color(0, 0, 0, 0), 0, 8, 4))
	_tag.add_theme_constant_override("outline_size", 0)
	_tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_tag.visible = false
	top.add_child(_tag)
	_desc = UITheme.label(tr(str(def.get("desc", ""))), 16, UITheme.MUTED)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	vb.add_child(_desc)
	_change = UITheme.label("", 21, UITheme.GREEN)
	vb.add_child(_change)
	var cost_row := HBoxContainer.new()
	vb.add_child(cost_row)
	cost_row.add_child(UIIcon.new("cube", 26, UITheme.GOLD))
	_cost = UITheme.label("", 21, UITheme.GOLD)
	cost_row.add_child(_cost)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cost_row.add_child(sp)
	_eta = UITheme.label("", 14, UITheme.MUTED)
	cost_row.add_child(_eta)
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 10)
	_bar.show_percentage = false
	_bar.max_value = 1.0
	vb.add_child(_bar)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	vb.add_child(btns)
	_btn1 = _make_btn(tr("Buy"), 1, btns)
	_btn10 = _make_btn("x10", 10, btns)
	_btnmax = _make_btn(tr("Max"), 0, btns)
	_breakdown = UITheme.label("", 13, UITheme.MUTED)
	_breakdown.autowrap_mode = TextServer.AUTOWRAP_WORD
	_breakdown.visible = false
	vb.add_child(_breakdown)
	# Overlays for the buy flourish.
	_flash = ColorRect.new()
	_flash.color = Color(1, 1, 0.8, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_flash)
	_shine = ColorRect.new()
	_shine.color = Color(1, 1, 1, 0.0)
	_shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine.size = Vector2(50, 600)
	_shine.rotation = 0.35
	add_child(_shine)
	_particles = CPUParticles2D.new()
	_particles.emitting = false
	_particles.one_shot = true
	_particles.amount = 26
	_particles.lifetime = 0.8
	_particles.explosiveness = 1.0
	_particles.spread = 180.0
	_particles.initial_velocity_min = 120.0
	_particles.initial_velocity_max = 320.0
	_particles.gravity = Vector2(0, 500)
	_particles.scale_amount_min = 3.0
	_particles.scale_amount_max = 6.0
	_particles.color = UITheme.GOLD
	add_child(_particles)
	mouse_entered.connect(func() -> void: _breakdown.visible = true)
	mouse_exited.connect(func() -> void: _breakdown.visible = false)
	refresh()


func _make_btn(text: String, n: int, parent: Control) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(80, 48)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_on_buy.bind(n))
	b.focus_entered.connect(func() -> void: _breakdown.visible = true)
	b.focus_exited.connect(func() -> void: _breakdown.visible = false)
	parent.add_child(b)
	return b


func first_button() -> Button:
	return _btn1


func _on_buy(n: int) -> void:
	var got: int = Economy.buy_upgrade(upgrade_id, n)
	if got <= 0:
		Audio.play("buzz", 1.3, -8.0)
		var tw := create_tween()
		tw.tween_property(self, "position:x", position.x + 8, 0.04)
		tw.tween_property(self, "position:x", position.x - 8, 0.06)
		tw.tween_property(self, "position:x", position.x, 0.04)
		return
	Audio.play("buy", 1.0, -2.0)
	Audio.play("coin", 1.0 + minf(got, 10) * 0.03, -6.0)
	Audio.play("confirm", 1.0 + minf(got - 1, 6) * 0.025, -6.0)  # [first] two-note confirm
	_flash.color.a = 0.55
	var tw2 := create_tween().set_parallel(true)
	tw2.tween_property(_flash, "color:a", 0.0, 0.35)
	_shine.position = Vector2(-80, -60)
	_shine.color.a = 0.45
	tw2.tween_property(_shine, "position:x", size.x + 80, 0.4).set_trans(Tween.TRANS_QUAD)
	tw2.tween_property(_shine, "color:a", 0.0, 0.4)
	pivot_offset = size * 0.5
	scale = Vector2(1.06, 1.06)
	tw2.tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	_particles.position = size * 0.5
	_particles.restart()
	_level.add_theme_color_override("font_color", UITheme.GOLD)
	var tw3 := create_tween()
	tw3.tween_interval(0.4)
	tw3.tween_callback(func() -> void: _level.add_theme_color_override("font_color", UITheme.MUTED))
	bought.emit(upgrade_id, got)
	refresh()


func refresh() -> void:
	var def: Dictionary = Economy.upgrade_defs[upgrade_id]
	var lv: int = GameState.level_of(upgrade_id)
	var maxed: bool = Economy.is_maxed(upgrade_id)
	var unlocked: bool = Economy.is_unlocked(upgrade_id)
	var mx: int = Economy.upgrade_max(upgrade_id)
	_level.text = tr("Lv %d%s") % [lv, (" / %d" % mx) if mx > 0 else ""]
	var unit: String = tr(str(def.get("unit", "")))
	var before: float = Economy.stat_with_upgrade_level(upgrade_id, lv)
	var after: float = Economy.stat_with_upgrade_level(upgrade_id, lv + 1)
	if not unlocked and def.has("requires_station") and not Stations.built_in_state(str(def["requires_station"])):
		_change.text = tr("Build the %s first (Hub tab)") % tr(str(Economy.read_json("res://data/stations.json").get(str(def["requires_station"]), {}).get("name", def["requires_station"])))  # [camp]
		_change.add_theme_color_override("font_color", UITheme.MUTED)
	elif not unlocked:
		var req: Dictionary = def.get("requires", {})
		var parts: Array[String] = []
		for rid: String in req:
			parts.append(tr("%s Lv %d") % [tr(str(Economy.upgrade_defs[rid]["name"])), int(req[rid])])
		_change.text = tr("Requires %s") % ", ".join(parts)
		_change.add_theme_color_override("font_color", UITheme.MUTED)
	elif maxed:
		_change.text = tr("%s%s  (max)") % [_fmt(before), unit]
		_change.add_theme_color_override("font_color", UITheme.GOLD)
	elif str(def["stat"]) == "auto_compactor":
		_change.text = tr("Off  →  On")
		_change.add_theme_color_override("font_color", UITheme.GREEN)
	else:
		_change.text = "%s%s  →  %s%s" % [_fmt(before), unit, _fmt(after), unit]
		_change.add_theme_color_override("font_color", UITheme.GREEN)
	var money: BigNum = GameState.get_currency("cubes")
	var cost: BigNum = Economy.upgrade_cost(upgrade_id)
	_cost.text = tr("MAX") if maxed else Settings.fmt(cost)
	var ratio: float = 1.0 if maxed else clampf(money.ratio_to(cost), 0.0, 1.0)
	_bar.value = ratio
	_affordable = unlocked and not maxed and ratio >= 1.0
	var can10: int = Economy.max_affordable(upgrade_id)
	_btn1.disabled = not _affordable
	_btn10.disabled = not unlocked or maxed or can10 < 2
	_btn10.text = "x%d" % mini(10, maxi(can10, 2)) if can10 >= 2 else "x10"
	_btnmax.disabled = not unlocked or maxed or can10 < 1
	_btnmax.text = tr("Max (%d)") % can10 if can10 > 1 else tr("Max")
	if _affordable or maxed:
		_eta.text = ""
	else:
		var rate: float = GameState.income_rate()
		var need: float = cost.sub(money).to_float()
		_eta.text = (tr("in about %s") % _fmt_time(need / rate)) if rate > 0.01 else tr("earn more cubes")
	_tag.visible = is_best_value and _affordable and Settings.best_value_tags
	var lines: Array[String] = []
	for b: Dictionary in Economy.stat_breakdown(def["stat"]):
		lines.append("%s %s" % [b["source"], tr(str(b["text"]))])
	_breakdown.text = tr("Where it comes from:  %s") % "  ·  ".join(lines)
	var style: StyleBoxFlat = UITheme.box(UITheme.PLUM_LIGHT if _affordable else UITheme.PLUM,
		UITheme.GOLD if _affordable else UITheme.RUST, 4 if _affordable else 3, 16, 12)
	add_theme_stylebox_override("panel", style)
	modulate = Color(1, 1, 1, 0.6) if not unlocked else Color.WHITE


## Relative stat gain per cube spent (for the Best Value tag).
func value_score() -> float:
	if not Economy.is_unlocked(upgrade_id) or Economy.is_maxed(upgrade_id):
		return -1.0
	var lv: int = GameState.level_of(upgrade_id)
	var before: float = Economy.stat_with_upgrade_level(upgrade_id, lv)
	var after: float = Economy.stat_with_upgrade_level(upgrade_id, lv + 1)
	var gain: float = (after - before) / maxf(absf(before), 0.5)
	return gain / maxf(Economy.upgrade_cost(upgrade_id).to_float(), 1.0)


func _process(delta: float) -> void:
	if _affordable:
		_bounce_t += delta
		pivot_offset = size * 0.5
		if scale.x <= 1.0001:
			rotation = sin(_bounce_t * 3.0) * 0.006
	else:
		rotation = 0.0


func _fmt(v: float) -> String:
	if absf(v - round(v)) < 0.005:
		return str(int(round(v)))
	return "%.2f" % v


func _fmt_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%d s" % int(ceil(seconds))
	if seconds < 3600.0:
		return tr("%d min") % int(ceil(seconds / 60.0))
	return "%.1f h" % (seconds / 3600.0)
