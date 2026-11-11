class_name WelcomeBack
extends CanvasLayer
## [extras] The "welcome back" card after a break. core/offline.gd computes what the fleet baled
## (capped at Offline.cap_s(), and by the junk the district has left, so closing and reopening the
## game never pays twice); this adds the garden (planted slots keep growing while watered, at
## Offline.rate(); every plant blooms once, so it can't be farmed) and shows it all on one
## small card in the minimal-HUD style: away time, the robots and what they did, cubes, plants,
## air. A / B / Esc / Enter closes it. scenes/slice.gd hands the payout over with `offer()`.

const MIN_AWAY_S: float = 120.0

## The offline result waiting for the district to finish building (set by scenes/slice.gd).
static var pending: Dictionary = {}

var world: Node
var summary: Dictionary = {}
var _root: Control
var _btn: Button
var is_open: bool = false


static func offer(res: Dictionary, away_s: float, robots: Array = []) -> void:
	pending = res.duplicate()
	pending["away_raw"] = away_s
	if not robots.is_empty():
		pending["robots"] = robots.duplicate(true)


## Offline garden growth (the maths lives in core/offline.gd, Offline.grow_garden).
static func grow_garden(g: Garden, seconds: float, has_waterer: bool, grow_mult: float = 1.0, seed_mult: float = 1.0) -> Dictionary:
	return Offline.grow_garden(g, seconds, has_waterer, grow_mult, seed_mult)


static func fleet_has_waterer(robots: Array) -> bool:
	return Offline.has_waterer(robots)


## "3 Scoopies, 1 Haul Bug" from the saved robot list.
static func fleet_text(robots: Array) -> String:
	var counts: Dictionary = {}
	var order: Array[String] = []
	for r: Dictionary in robots:
		var t: String = str(r.get("type", ""))
		if not counts.has(t):
			order.append(t)
		counts[t] = int(counts.get(t, 0)) + 1
	var bits: Array[String] = []
	for t: String in order:
		bits.append("%s ×%d" % [TranslationServer.translate(str(Economy.robots.get(t, {}).get("name", t))), int(counts[t])])
	return ", ".join(bits)


static func away_text(s: float) -> String:
	var m: int = int(s / 60.0)
	if m < 60:
		return TranslationServer.translate("%d min") % maxi(m, 1)
	return TranslationServer.translate("%d h %d min") % [m / 60, m % 60]


## Builds the card's rows from an offline result + garden result (pure).
static func build_summary(res: Dictionary, garden: Dictionary, robots: Array) -> Dictionary:
	var cubes: float = float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0))
	var units: float = float(res.get("units", 0.0))
	var cap: float = maxf(Economy.robot_stat("scoopie", "capacity", 0), 1.0) if Economy.robots.has("scoopie") else 10.0
	var rows: Array = []
	if not robots.is_empty():
		var did: String
		if units > 0.0:
			did = TranslationServer.translate("baled about %d bales") % maxi(1, int(round(units / cap)))
		else:
			did = TranslationServer.translate("kept the base tidy")
		rows.append({"kind": "robots", "label": fleet_text(robots), "value": did})
	if cubes > 0.0:
		rows.append({"kind": "cubes", "label": TranslationServer.translate("Cubes earned"), "value": "+" + Settings.fmt(BigNum.from_float(cubes))})
		if float(res.get("waiting_value", 0.0)) > 0.0:
			rows.append({"kind": "tip", "label": TranslationServer.translate("No hauler: Lumi cashed the stacked bales. A Haul Bug keeps them moving."), "value": ""})
	if int(garden.get("grew", 0)) > 0:
		rows.append({"kind": "plants", "label": TranslationServer.translate("Plants grew"), "value": str(int(garden["grew"]))})
	if int(garden.get("bloomed", 0)) > 0:
		rows.append({"kind": "seeds", "label": TranslationServer.translate("Bloomed (seeds)"), "value": "%d  (+%s)" % [int(garden["bloomed"]), Settings.fmt(BigNum.from_float(float(garden.get("seeds", 0.0))))]})
	if float(res.get("air", 0.0)) > 0.0:
		rows.append({"kind": "air", "label": TranslationServer.translate("Scrubbers cleaned the air"), "value": ""})
	var raw: float = float(res.get("away_raw", res.get("seconds", 0.0)))
	return {"away": float(res.get("seconds", 0.0)), "capped": raw > Offline.cap_s() + 1.0, "rows": rows,
		"cubes": cubes, "grew": int(garden.get("grew", 0)), "bloomed": int(garden.get("bloomed", 0))}


## Runs once the district is built (systems/extras/extras_director.gd): garden growth, payout card.
static func resolve(slice: Node) -> WelcomeBack:
	if pending.is_empty():
		return null
	var res: Dictionary = pending
	pending = {}
	var robots: Array = res.get("robots", GameState.world.get("robots", []))
	var g: Garden = slice.get("garden") as Garden
	var gr: Dictionary = res.get("garden", {})
	if not bool(res.get("garden_grown", false)) and g != null:
		gr = grow_garden(g, float(res.get("seconds", 0.0)), fleet_has_waterer(robots), maxf(Economy.stat("plant_growth"), 0.1), maxf(Economy.stat("seed_yield"), 0.1))
		res["garden"] = gr
	Offline.apply(res)  # cubes, stacked bales, air, and the garden's seeds: credited once, here
	if g:
		for s: int in g.slot_species.size():
			if g.slot_species[s] >= 0:
				g._update_inst(s)
		for h: Variant in (gr.get("hexes", {}) as Dictionary):
			g._recount(int(h))
	var sm_d: Dictionary = build_summary(res, gr, robots)
	GameState.inc_stat("welcome_backs")
	GameState.stats["offline_best_s"] = maxf(float(GameState.stats.get("offline_best_s", 0.0)), float(res.get("seconds", 0.0)))
	if (sm_d["rows"] as Array).is_empty():
		return null
	var wb := WelcomeBack.new()
	wb.world = slice
	wb.summary = sm_d
	slice.add_child(wb)
	return wb


func _ready() -> void:
	layer = 32
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.35)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(430, 0)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.9), Color(1, 1, 1, 0.1), 1, 10, 20))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	pc.add_child(vb)
	vb.add_child(UITheme.label(tr("WELCOME BACK"), 13, UITheme.MUTED))
	var away: Label = UITheme.label(tr("Away %s") % away_text(float(summary.get("away", 0.0))), 26, Color.WHITE)
	vb.add_child(away)
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(0, 1)
	line.color = Color(1, 1, 1, 0.08)
	vb.add_child(line)
	var cols: Dictionary = {"robots": UITheme.GOLD, "cubes": Color(1.0, 0.85, 0.45), "plants": UITheme.GREEN,
		"seeds": Color(0.75, 0.95, 0.55), "air": Color(0.55, 0.85, 1.0), "tip": UITheme.MUTED}
	for r: Dictionary in summary.get("rows", []):
		if str(r["kind"]) == "tip":
			var tip: Label = UITheme.label(str(r["label"]), 13, UITheme.MUTED)
			tip.autowrap_mode = TextServer.AUTOWRAP_WORD
			tip.custom_minimum_size = Vector2(390, 0)
			vb.add_child(tip)
			continue
		var row: HBoxContainer = UITheme.stat_row(cols.get(str(r["kind"]), UITheme.CREAM), str(r["label"]), str(r["value"]))
		var lab: Label = row.get_child(1) as Label
		lab.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		lab.clip_text = true
		vb.add_child(row)
	if bool(summary.get("capped", false)):
		var cap: Label = UITheme.label(tr("Robots work up to %d h while you're away.") % int(Offline.cap_s() / 3600.0), 12, UITheme.MUTED)
		vb.add_child(cap)
	_btn = Button.new()
	_btn.text = tr("Back to work")
	_btn.custom_minimum_size = Vector2(0, 44)
	_btn.pressed.connect(close)
	UITheme.juice(_btn, 1.02)
	vb.add_child(_btn)
	_root.modulate.a = 0.0
	(func() -> void: open()).call_deferred()


func open() -> void:
	is_open = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	EventBus.ui_modal_changed.emit(true)
	create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)
	Audio.play("chime", 1.1, -8.0)
	_btn.grab_focus()
	# Autoplay / headless runs have nobody to press the button.
	if DisplayServer.get_name() == "headless" or (world and world.get("bot") != null and not DevHooks.has("extras")):
		get_tree().create_timer(2.0, true).timeout.connect(close)


func close() -> void:
	if not is_open:
		return
	is_open = false
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if is_open and (event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()
