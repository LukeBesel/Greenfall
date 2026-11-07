class_name ArkBridge
extends CanvasLayer
## [late] The Ark Bridge: Cradle Mode's world select and Heirloom shop (systems/cradle_mode.gd).
## Opens from Pause > Ark Bridge once a Cradle finale has played (dev: --open=ark). Opening it
## banks the Starseeds this world has earned since the last visit.
##   Left: every world in the profile (travel to any of them; Verdance is always there) and
##   "Seed a new world" with a preview of where the Cradle would go next.
##   Right: Heirlooms, bought with Starseeds, kept on every world.
## Pad: D-pad / stick moves focus, A presses, B (or Esc) closes.

signal closed

const PLANET_COLORS: Dictionary = {
	"verdance": [Color(0.24, 0.52, 0.3), Color(0.2, 0.42, 0.62), Color(0.55, 0.5, 0.4)],
	"ice_moon": [Color(0.86, 0.9, 0.96), Color(0.55, 0.7, 0.85), Color(0.4, 0.5, 0.62)],
	"desert_world": [Color(0.8, 0.64, 0.42), Color(0.68, 0.5, 0.32), Color(0.3, 0.5, 0.62)],
	"ocean_world": [Color(0.16, 0.36, 0.6), Color(0.22, 0.5, 0.7), Color(0.4, 0.58, 0.36)],
	"fungal_world": [Color(0.32, 0.42, 0.34), Color(0.5, 0.42, 0.55), Color(0.26, 0.4, 0.5)],
	"rust_world": [Color(0.55, 0.36, 0.24), Color(0.42, 0.4, 0.38), Color(0.3, 0.45, 0.55)],
}

var world: Node
var is_open: bool = false
var _root: Control
var _worlds_box: VBoxContainer
var _heir_box: VBoxContainer
var _seeds_label: Label
var _banked_label: Label
var _first: Control


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_root.visible = false


func open_bridge() -> void:
	if is_open:
		return
	is_open = true
	var gain: int = CradleMode.bank()
	_rebuild(gain)
	_root.visible = true
	_root.modulate.a = 0.0
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.2)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if world and world.get("hud") != null:
		world.hud.visible = false
	EventBus.ui_modal_changed.emit(true)
	GameState.inc_stat("ark_bridge_opened")
	if _first:
		_first.call_deferred("grab_focus")
	Audio.play("whoosh", 0.8, -8.0)


func close_bridge() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	get_tree().paused = false
	if world and world.get("hud") != null:
		world.hud.visible = true
	EventBus.ui_modal_changed.emit(false)
	closed.emit()
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _rebuild(gain: int = 0) -> void:
	for c: Node in _root.get_children():
		c.queue_free()
	_first = null
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.035, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 48)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	_root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	margin.add_child(outer)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	outer.add_child(head)
	var tb := VBoxContainer.new()
	tb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tb)
	tb.add_child(UITheme.label(tr("THE CRADLE  ·  SEED VAULT DECK"), 11, Color(0.4, 0.75, 1.0)))
	tb.add_child(UITheme.label(tr("ARK BRIDGE"), 30, Color.WHITE))
	var intro := UITheme.label(tr("The vault holds seeds for every world in the system. Take what Lumi learned somewhere new; nothing here is ever undone."), 13, UITheme.MUTED)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tb.add_child(intro)
	var seeds := VBoxContainer.new()
	head.add_child(seeds)
	_seeds_label = UITheme.label(tr("%d Starseeds") % int(CradleMode.starseeds()), 24, UITheme.GOLD)
	_seeds_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seeds.add_child(_seeds_label)
	_banked_label = UITheme.label(tr("+%d banked from %s") % [gain, CradleMode.world_name()] if gain > 0 else tr("Earn more from Seed Ark waves and restoration"), 12, UITheme.GREEN if gain > 0 else UITheme.MUTED)
	_banked_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	seeds.add_child(_banked_label)
	outer.add_child(UITheme.hazard_strip(5))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(cols)
	# Worlds
	var wl := VBoxContainer.new()
	wl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wl.size_flags_stretch_ratio = 1.25
	wl.custom_minimum_size = Vector2(420, 0)
	wl.add_theme_constant_override("separation", 8)
	cols.add_child(wl)
	wl.add_child(UITheme.label(tr("WORLDS"), 13, UITheme.MUTED))
	var ws := ScrollContainer.new()
	ws.size_flags_vertical = Control.SIZE_EXPAND_FILL
	ws.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	wl.add_child(ws)
	_worlds_box = VBoxContainer.new()
	_worlds_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_worlds_box.add_theme_constant_override("separation", 8)
	ws.add_child(_worlds_box)
	_worlds_box.add_child(_new_world_row())
	for i: int in CradleMode.worlds().size():
		_worlds_box.add_child(_world_row(i))
	# Heirlooms
	var hl := VBoxContainer.new()
	hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hl.custom_minimum_size = Vector2(340, 0)
	hl.add_theme_constant_override("separation", 8)
	cols.add_child(hl)
	hl.add_child(UITheme.label(tr("HEIRLOOMS  ·  KEPT ON EVERY WORLD"), 13, UITheme.MUTED))
	var hs := ScrollContainer.new()
	hs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hs.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hl.add_child(hs)
	_heir_box = VBoxContainer.new()
	_heir_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heir_box.add_theme_constant_override("separation", 6)
	hs.add_child(_heir_box)
	for h: Dictionary in CradleMode.heirloom_defs():
		_heir_box.add_child(_heirloom_row(h))
	var foot := HBoxContainer.new()
	outer.add_child(foot)
	var hint := UITheme.label(tr("Enter / A  choose      Esc / B  back"), 12, UITheme.MUTED)
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(hint)
	var back := Button.new()
	back.text = tr("Back to %s") % CradleMode.world_name()
	back.custom_minimum_size = Vector2(220, 42)
	back.pressed.connect(close_bridge)
	UITheme.juice(back, 1.02)
	foot.add_child(back)
	if _first == null:
		_first = back


func _world_row(i: int) -> Control:
	var w: Dictionary = CradleMode.worlds()[i]
	var here: bool = i == CradleMode.current_index()
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.07, 0.08, 0.92), UITheme.GOLD if here else Color(1, 1, 1, 0.07), 1, 6, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	hb.add_child(PlanetDisc.new(str(w.get("type", "verdance")), int(w.get("seed", 0)), 30.0))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	var title: String = "%s   %s" % [tr("WORLD %d") % (i + 1), str(w.get("name", "?")).to_upper()]
	vb.add_child(UITheme.label(title, 17, Color.WHITE))
	var wd := UITheme.label(WorldGen.describe(w), 12, Color(0.4, 0.75, 1.0))
	wd.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(wd)
	var st: Dictionary = w.get("stats", {})
	var line: String = tr("Not visited yet")
	if not st.is_empty():
		line = tr("%s  ·  %d hexes  ·  %d ark waves  ·  %d curiosities") % [_hours(float(st.get("time_played", 0.0))), int(st.get("hexes_cleaned", 0)), int(st.get("ark_waves", 0)), int(st.get("eggs", 0))]
		if bool(w.get("finale", false)):
			line += "  ·  " + tr("restored")
	var stl := UITheme.label(line, 12, UITheme.MUTED)
	stl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(stl)
	var b := Button.new()
	b.custom_minimum_size = Vector2(150, 40)
	if here:
		b.text = tr("You are here")
		b.disabled = true
	else:
		b.text = tr("Travel")
		b.pressed.connect(func() -> void:
			Audio.play("click", 1.0, -6.0)
			_travel(i))
		UITheme.juice(b, 1.03)
		if _first == null:
			_first = b
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(b)
	return pc


func _new_world_row() -> Control:
	var idx: int = CradleMode.worlds().size()
	var w: Dictionary = WorldGen.make(idx, WorldGen.seed_for(idx, int(CradleMode.profile.get("starseeds_total", 0.0))))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.07, 0.06, 0.04, 0.92), Color(1.0, 0.7, 0.26, 0.35), 1, 6, 10))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	pc.add_child(hb)
	hb.add_child(PlanetDisc.new(str(w["type"]), int(w["seed"]), 30.0, true))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 2)
	hb.add_child(vb)
	vb.add_child(UITheme.label(tr("SEED A NEW WORLD"), 17, UITheme.GOLD))
	if not CradleMode.unlocked():
		vb.add_child(UITheme.label(tr("The Cradle has to come home first."), 12, UITheme.MUTED))
		return pc
	var dl := UITheme.label("%s  ·  %s" % [str(w["name"]), WorldGen.describe(w)], 12, Color(0.4, 0.75, 1.0))
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(dl)
	var mods: Array[String] = []
	for id: Variant in w["modifiers"]:
		mods.append(tr(str(WorldGen.modifier(str(id)).get("desc", ""))))
	var l := UITheme.label(" ".join(mods), 12, UITheme.MUTED)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(l)
	var kit: Dictionary = CradleMode.start_kit(CradleMode.profile.get("heirlooms", {}))
	var kl := UITheme.label(_kit_text(kit), 12, UITheme.GREEN)
	kl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(kl)
	var b := Button.new()
	b.text = tr("Launch")
	b.custom_minimum_size = Vector2(150, 40)
	UITheme.orange_button(b)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func() -> void:
		Audio.play("fanfare", 0.8, -8.0)
		_launch_new())
	UITheme.juice(b, 1.03)
	hb.add_child(b)
	if _first == null or (_first is Button and (_first as Button).text == tr("Back to %s") % CradleMode.world_name()):
		_first = b
	return pc


static func _kit_text(kit: Dictionary) -> String:
	var bits: Array[String] = []
	if float(kit["cubes"]) > 0.0:
		bits.append(TranslationServer.translate("%s cubes") % Settings.fmt(BigNum.from_float(float(kit["cubes"]))))
	if float(kit["data"]) > 0.0:
		bits.append(TranslationServer.translate("%d Data") % int(kit["data"]))
	if float(kit["seeds"]) > 0.0:
		bits.append(TranslationServer.translate("%d seeds") % int(kit["seeds"]))
	if not (kit["robots"] as Array).is_empty():
		bits.append(TranslationServer.translate("robots waiting: %d") % (kit["robots"] as Array).size())
	if int(kit["research_tier"]) > 0:
		bits.append(TranslationServer.translate("research tier %d known") % int(kit["research_tier"]))
	if bits.is_empty():
		return TranslationServer.translate("Starting kit: just Lumi. Heirlooms add to it.")
	return TranslationServer.translate("Starting kit: %s") % ", ".join(bits)


func _heirloom_row(h: Dictionary) -> Control:
	var id: String = str(h["id"])
	var lv: int = CradleMode.heirloom_level(id)
	var mx: int = int(h.get("max", 5))
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.row_box())
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	pc.add_child(hb)
	hb.add_child(ResearchIcons.IconView.new(str(h.get("icon", "star")), 30, UITheme.GOLD if lv > 0 else UITheme.MUTED))
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 1)
	hb.add_child(vb)
	var pips: String = ""
	for k: int in mx:
		pips += "●" if k < lv else "○"
	vb.add_child(UITheme.label("%s   %s" % [tr(str(h.get("name", id))), pips], 15, Color.WHITE))
	var d := UITheme.label(tr(str(h.get("desc", ""))), 12, UITheme.MUTED)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(d)
	var b := Button.new()
	b.custom_minimum_size = Vector2(120, 36)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if lv >= mx:
		b.text = tr("Full")
		b.disabled = true
	else:
		b.text = tr("%d Starseeds") % CradleMode.heirloom_cost(h, lv)
		b.disabled = CradleMode.buy_block_reason(id) != ""
		b.pressed.connect(func() -> void:
			if CradleMode.buy(id):
				Audio.play("buy", 1.0, -4.0)
				_rebuild()
				_refocus_heirloom(id))
		UITheme.juice(b, 1.03)
	hb.add_child(b)
	return pc


func _refocus_heirloom(id: String) -> void:
	var i: int = 0
	for h: Dictionary in CradleMode.heirloom_defs():
		if str(h["id"]) == id:
			break
		i += 1
	(func() -> void:
		if _heir_box and i < _heir_box.get_child_count():
			for b: Node in _heir_box.get_child(i).find_children("*", "Button", true, false):
				if not (b as Button).disabled:
					(b as Button).grab_focus()
					return
			if _first:
				_first.grab_focus()).call_deferred()


static func _hours(s: float) -> String:
	var m: int = int(s / 60.0)
	return "%d:%02d h" % [m / 60, m % 60]


func _travel(i: int) -> void:
	is_open = false
	EventBus.ui_modal_changed.emit(false)
	CradleMode.switch_world(i, get_tree())


func _launch_new() -> void:
	is_open = false
	EventBus.ui_modal_changed.emit(false)
	CradleMode.launch_new_world(get_tree())


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close_bridge()
		get_viewport().set_input_as_handled()


## A little planet: the world type's colours in soft blotches, seeded, with a lit rim.
class PlanetDisc extends Control:
	var kind: String
	var seed_v: int
	var radius: float
	var ghost: bool

	func _init(p_kind: String, p_seed: int, p_radius: float, p_ghost: bool = false) -> void:
		kind = p_kind
		seed_v = p_seed
		radius = p_radius
		ghost = p_ghost
		custom_minimum_size = Vector2(radius * 2.0 + 8.0, radius * 2.0 + 8.0)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var cols: Array = ArkBridge.PLANET_COLORS.get(kind, ArkBridge.PLANET_COLORS["rust_world"])
		var a: float = 0.55 if ghost else 1.0
		draw_circle(c, radius, Color(cols[0], a))
		var r := RandomNumberGenerator.new()
		r.seed = seed_v
		for k: int in 14:
			var ang: float = r.randf() * TAU
			var d: float = sqrt(r.randf()) * radius * 0.78
			var br: float = r.randf_range(0.12, 0.34) * radius
			var col: Color = cols[1 + (k % 2)]
			draw_circle(c + Vector2(cos(ang), sin(ang)) * d, br, Color(col, 0.85 * a))
		# Night side and a thin lit rim.
		draw_arc(c + Vector2(radius * 0.18, radius * 0.12), radius * 0.86, -PI * 0.1, PI * 0.75, 32, Color(0, 0, 0, 0.32 * a), radius * 0.3, true)
		draw_arc(c, radius, PI * 0.6, PI * 1.9, 40, Color(0.75, 0.9, 1.0, 0.55 * a), 1.5, true)
		draw_arc(c, radius + 3.0, 0, TAU, 48, Color(1, 1, 1, 0.06), 1.0, true)
