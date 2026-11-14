class_name ObjectiveCard
extends PanelContainer
## [onboard] The current story objective (story/objectives.gd) as a compact HUD card, top-right.
## [v9d] Owner, 13 Nov: "It all needs to be visual and easy to understand". Picture first, few words:
##   picture   a large drawing of the thing the step is about (ui/step_icons.gd)
##   title     what to do, big (a step's "short" text when it has one)
##   progress  ONE element: pips for a small count ("2 / 3"), else a bar with its number
##   costs     while the step's price is short: an icon chip per currency, "240 / 600", filling as
##             you earn, green when met (no "Need 600 more cubes..." sentence)
##   hint      the one thing blocking the step (full chest, carry the bale, too heavy, lost), held
##             at least HINT_HOLD_S so it never flips between two messages
##   why       the reason, small: shown for WHY_S at the start of a step, then folded away; the
##             goals key (toggle_goals) unfolds it with the full title
## A finished objective ticks green for a beat, then the next one slides in.

const W: float = 300.0
const PIC: float = 56.0
const ACCENT := Color(0.55, 0.9, 1.0)
const WHY := Color(0.78, 0.8, 0.79)
const HINT := Color(1.0, 0.82, 0.45)  # [v3clear] a situation hint (amber)
const WHY_S: float = 8.0
const HINT_HOLD_S: float = 3.5
const PIPS_MAX: int = 8

var objectives: Objectives
var _cap: Label
var _pic: StepIcons.Picture
var _count: Label
var _title: Label
var _why: Label
var _hint: Label
var _hint_row: HBoxContainer
var _hint_pic: StepIcons.Picture
var _bar: Control
var _pips: Control
var _chips: HFlowContainer
var _chip_sig: String = ""
var _shown: float = 0.0
var _progress: float = -1.0
var _flash: float = 0.0
var _busy: bool = false
var _index: int = -1
var _step_t: float = 0.0
var _hint_now: String = ""
var _hint_t: float = 0.0
var _hint_clear_t: float = 0.0
var _price: Dictionary = {}
var _pip_n: int = 0
var _pip_have: int = 0
var _plabel: String = ""  # the progress number, also while chips stand in for it
## [v2guide] Owner playtest 2 #33: one card. A sub-step (the restart checklist's "Empty your chest
## into the trash bin", the first seed's "water it") replaces the card's text while it lasts.
var substep: String = ""
var substep_progress: Array = [-1.0, ""]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(W, 0)
	size_flags_horizontal = Control.SIZE_SHRINK_END
	var sb := UITheme.box(Color(0.025, 0.035, 0.045, 0.72), Color(0.55, 0.9, 1.0, 0.24), 1, 12, 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	_pic = StepIcons.Picture.new("star", PIC, ACCENT)
	row.add_child(_pic)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(vb)
	var tw: float = W - 24.0 - PIC - 10.0
	_title = UITheme.label("", 20, UITheme.CREAM)
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.custom_minimum_size = Vector2(tw, 0)
	_title.max_lines_visible = 2
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	vb.add_child(_title)
	var prow := HBoxContainer.new()  # the one progress element and its number
	prow.add_theme_constant_override("separation", 8)
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(prow)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(0, 14)
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	prow.add_child(_bar)
	_pips = Control.new()
	_pips.custom_minimum_size = Vector2(0, 16)
	_pips.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.draw.connect(_draw_pips)
	_pips.visible = false
	prow.add_child(_pips)
	_count = UITheme.label("", 14, UITheme.CREAM)
	prow.add_child(_count)
	_chips = HFlowContainer.new()  # the step's price, one chip per currency
	_chips.add_theme_constant_override("h_separation", 8)
	_chips.add_theme_constant_override("v_separation", 4)
	_chips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chips.visible = false
	vb.add_child(_chips)
	_hint = UITheme.label("", 14, HINT)  # [v6story] the situation line
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(tw, 0)
	_hint.max_lines_visible = 2
	_hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hint.visible = false
	_hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint.custom_minimum_size.x = tw - 24.0
	_hint_row = HBoxContainer.new()  # [v9d] a small picture by the hint (lock = too heavy, chest, bale...)
	_hint_row.add_theme_constant_override("separation", 6)
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_pic = StepIcons.Picture.new("star", 20.0, HINT)
	_hint_row.add_child(_hint_pic)
	_hint_row.add_child(_hint)
	vb.add_child(_hint_row)
	_why = UITheme.label("", 13, WHY)
	_why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_why.custom_minimum_size = Vector2(tw, 0)
	vb.add_child(_why)
	_cap = _why  # (the old "OBJECTIVE" caption is gone: the picture says it)
	visible = false
	modulate.a = 0.0


func bind(o: Objectives) -> void:
	objectives = o
	o.changed.connect(func(_i: int) -> void: refresh(true))
	o.completed.connect(_on_completed)
	refresh(false)


## Shows the current objective (fading it in), or fades the card out when there is none.
func refresh(animate: bool) -> void:
	if objectives == null or _busy:
		return
	var def: Dictionary = objectives.current()
	if def.is_empty():
		_index = -1
		if visible:
			var tw := create_tween().set_ignore_time_scale(true)
			tw.tween_property(self, "modulate:a", 0.0, 0.6)
			tw.tween_callback(func() -> void:
				if _index < 0:
					visible = false)
		return
	if objectives.position() == _index and visible:  # [v1guide] goal steps keep step: use the timeline position
		return
	_index = objectives.position()
	_flash = 0.0
	_step_t = 0.0
	_hint_now = ""
	_hint_t = 0.0
	_title.add_theme_color_override("font_color", UITheme.CREAM)
	_set_texts(def)
	_shown = maxf(0.0, float(objectives.progress()[0]))
	visible = true
	if animate:
		modulate.a = 0.0
	create_tween().set_ignore_time_scale(true).tween_property(self, "modulate:a", 1.0, 0.45)


## The goals key unfolds the card (the why and the full title).
func expanded() -> bool:
	var gp: Node = get_parent()
	return gp != null and gp.get("expanded") == true


## The card's title for a step: its "short" text (at most ~5 words) when it has one.
static func title_of(def: Dictionary, full: bool = false) -> String:
	var t: String = str(def.get("text", ""))
	if not full and def.has("short"):
		t = str(def["short"])
	return Objectives.glyphs(TranslationServer.translate(t))


func _set_texts(def: Dictionary) -> void:
	var raw: String = objectives.situation if objectives else ""
	_price = {}
	if substep != "":  # [v2guide]
		# [v9b] A one-off instruction (water the seed) is the one thing on the card: the step's own
		# price line ("Need 292 more cubes") has nothing to do with it, so it stays off.
		if raw != "" and objectives and (objectives.situation_price or raw == ListDetail.short_text(objectives.call("_step_price"))):
			raw = ""
		_title.text = substep
		_why.text = raw
		_why.add_theme_color_override("font_color", HINT)
		_why.visible = raw != ""
		_hint.visible = false
		_hint_row.visible = false
		_chips.visible = false
		return
	_why.add_theme_color_override("font_color", WHY)
	var t: Array[String] = Objectives.texts(def)
	var big: bool = expanded()
	_title.text = title_of(def, big)
	_pic.set_kind(picture_of(def))
	_why.text = t[1]
	_why.visible = _why.text != "" and (big or _step_t < WHY_S)
	# The price of the step, when it is short: chips (the sentence it used to say is dropped).
	if objectives and objectives.has_method("step_price"):
		var pr: Dictionary = objectives.step_price()
		if not pr.is_empty() and not GameState.can_afford_all(pr):
			var fp: Dictionary = Currencies.fold(pr)
			for cid: String in Currencies.IDS:
				if float(fp.get(cid, 0.0)) > 0.0:
					_price[cid] = float(fp[cid])
			if raw == ListDetail.short_text(pr) or objectives.situation_price:
				raw = ""
	_hint.text = _hint_now
	_hint.visible = _hint.text != ""
	_hint_row.visible = _hint.visible
	var hk: String = objectives.situation_kind if objectives and "situation_kind" in objectives else ""
	_hint_pic.visible = hk != ""
	if hk != "":
		_hint_pic.set_kind(hk)


## The hint keeps one message at least HINT_HOLD_S, and goes away only once it has been gone a moment.
func _hold_hint(raw: String, delta: float) -> void:
	_hint_t += delta
	if raw == _hint_now:
		_hint_clear_t = 0.0
		return
	if raw == "":
		_hint_clear_t += delta
		if _hint_clear_t >= 1.5 and _hint_t >= HINT_HOLD_S:
			_hint_now = ""
			_hint_t = 0.0
		return
	if _hint_now == "" or _hint_t >= HINT_HOLD_S:
		_hint_now = raw
		_hint_t = 0.0
		_hint_clear_t = 0.0


## What the card shows, as text (tools and tests): [title, why (even folded), hint or costs, count].
func read() -> Array[String]:
	var hint: String = _hint.text if _hint.visible else ""
	if _chips.visible:
		var cs: PackedStringArray = []
		for k: String in _price:
			cs.append("%s %s / %s" % [k, Settings.fmt(BigNum.from_float(minf(GameState.get_currency(k).to_float(), float(_price[k])))), Settings.fmt(BigNum.from_float(float(_price[k])))])
		hint = (hint + "  " if hint != "" else "") + "  ".join(cs)
	return [_title.text, _why.text, hint, _count.text if _count.text != "" else _plabel]


## [v9d] The picture for a step (ui/step_icons.gd kinds): the thing it is about.
const STEP_PICS: Dictionary = {
	"dump3": "bin", "compartment": "chest", "scoop_size": "scoop", "baler": "press", "power": "bale",
	"tower": "tower", "tower2": "tower", "glim": "lantern", "bench2": "gear", "robot": "bot",
	"seed": "seed", "haul": "haulbug", "research1": "book", "requests": "check",
}
const KEY_PICS: Dictionary = {
	"hexes_cleaned": "hex", "junk_scooped": "scoop", "junk_dumps": "bin", "cubes_cashed": "bale",
	"robot_bales": "bale", "cubes_made": "press", "perfect_cubes": "press", "plants_planted": "seed",
	"seeds_unlocked": "seed", "plants_bloomed": "flower", "garden_stipend": "sprout", "hexes_restored": "sprout",
	"research_done": "book", "upgrades_bought": "gear", "robots_built": "bot", "shards_found": "book",
	"eggs_found": "star", "parts_found": "part", "hubs_seen": "rocket", "hubs_woken": "flag",
	"rocket_tier": "rocket", "drive_tier": "rocket", "cats_petted": "heart", "seen_deer": "heart",
	"bales_recycled": "recycle", "air_filtered": "recycle", "decor_placed": "flower", "decor_kinds": "flower",
	"decor_charm_best": "flower", "builder_parts_fitted": "bot", "builder_full_custom": "bot",
	"robots_retired": "bot", "radio_plays": "star", "water_tanks": "drop",
}
const ROBOT_PICS: Dictionary = {"haulbug": "haulbug", "seedling": "sprout", "drip": "drop", "skimmer": "wave"}
const UPGRADE_PICS: Dictionary = {"compartment_size": "chest", "baler": "press", "scoop_width": "scoop", "scoop_speed": "scoop"}


static func picture_of(def: Dictionary) -> String:
	var id: String = str(def.get("id", ""))
	var typ: String = str(def.get("type", "stat"))
	var key: String = str(def.get("key", ""))
	if STEP_PICS.has(id):
		return str(STEP_PICS[id])
	if id.begins_with("hub_fly") or id.begins_with("rocket_tier"):
		return "rocket"
	if id.begins_with("hub_wake"):
		return "flag"
	if id.begins_with("base") or typ == "hub_level":
		return "house"
	if id.begins_with("hex") and not def.has("_goal"):
		return "hex"
	match typ:
		"upgrade":
			return str(UPGRADE_PICS.get(key, "gear"))
		"robot":
			return str(ROBOT_PICS.get(key, "bot"))
		"tier":
			return "bot"
		"research":
			return "book"
		"districts":
			return "rocket"
		"hex_level":
			return "sprout"
		"earned":
			return "cube"
	return str(KEY_PICS.get(key, "star"))


## [v9d] Kept for callers: the step's picture kind.
static func icon_of(def: Dictionary) -> String:
	return picture_of(def)


## [v2guide] Sets (or clears, with "") the sub-step shown in place of the objective; plain text.
func set_substep(text: String, pr: Array = [-1.0, ""]) -> void:
	substep_progress = pr
	if text == substep:
		return
	substep = text
	if visible and not _busy:
		_title.modulate.a = 0.0
		create_tween().set_ignore_time_scale(true).tween_property(_title, "modulate:a", 1.0, 0.3)


func _on_completed(_i: int) -> void:
	_busy = true
	_title.add_theme_color_override("font_color", UITheme.GREEN)
	_count.text = tr("DONE")
	_count.visible = true
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_method(func(t: float) -> void:
		_flash = t
		_pips.queue_redraw()
		_bar.queue_redraw(), 0.0, 1.0, 0.25)
	tw.tween_interval(Objectives.NEXT_DELAY_S - 0.75)
	tw.tween_property(self, "modulate:a", 0.0, 0.3)
	tw.tween_callback(func() -> void:
		_busy = false
		_index = -1
		visible = false
		refresh(true))


func _process(delta: float) -> void:
	if not visible or _busy or objectives == null:
		return
	var def: Dictionary = objectives.current()
	if def.is_empty():
		return
	_step_t += delta
	var raw: String = objectives.situation
	if objectives.situation_price:  # [v9d] a price is shown as cost chips, never as a sentence
		raw = ""
	_hold_hint(raw if substep == "" else "", delta)
	_set_texts(def)  # the why can change (a wait flag), and the language
	var pr: Array = objectives.progress() if substep == "" else substep_progress  # [v2guide]
	_progress = float(pr[0])
	var label: String = str(pr[1])
	_plabel = label
	_shown = lerpf(_shown, maxf(_progress, 0.0), clampf(delta * 6.0, 0.0, 1.0))
	# Costs as chips while the price is short: they ARE the progress then (no second bar).
	_chips.visible = not _price.is_empty()
	if _chips.visible:
		_fill_chips()
	# A small count is pips ("2 / 3" as two lit of three); else a bar and its number.
	_pip_n = 0
	var m: PackedStringArray = label.split(" / ")
	if not _chips.visible and m.size() == 2 and m[0].is_valid_int() and m[1].is_valid_int() and int(m[1]) <= PIPS_MAX and int(m[1]) > 1:
		_pip_n = int(m[1])
		_pip_have = int(m[0])
	_pips.visible = _pip_n > 0
	_bar.visible = not _chips.visible and _pip_n == 0 and _progress >= 0.0
	_count.text = "" if _chips.visible else label
	_count.visible = _count.text != ""
	_bar.queue_redraw()
	_pips.queue_redraw()


func _fill_chips() -> void:
	var sig: String = ",".join(PackedStringArray(_price.keys()))
	if sig != _chip_sig:
		_chip_sig = sig
		for c: Node in _chips.get_children():
			c.queue_free()
		for k: String in _price:
			_chips.add_child(CostChip.new(k))
	for c: Node in _chips.get_children():
		if c is CostChip and not c.is_queued_for_deletion():
			(c as CostChip).set_need(float(_price.get((c as CostChip).currency, 0.0)))


func _draw_pips() -> void:
	var h: float = _pips.size.y
	var r: float = minf(h * 0.36, 6.0)
	var gap: float = r * 2.0 + 6.0
	for i: int in _pip_n:
		var c := Vector2(r + 1.0 + float(i) * gap, h * 0.5)
		if i < _pip_have or _flash > 0.0:
			_pips.draw_circle(c, r, ACCENT.lerp(UITheme.GREEN, _flash if _flash > 0.0 else 0.0))
		else:
			_pips.draw_arc(c, r - 0.5, 0.0, TAU, 16, Color(1, 1, 1, 0.45), 1.5, true)


func _draw_bar() -> void:
	var w: float = _bar.size.x
	var y: float = _bar.size.y * 0.5 - 3.0
	_bar.draw_rect(Rect2(0, y, w, 6.0), Color(1, 1, 1, 0.16))
	_bar.draw_rect(Rect2(0, y, w * clampf(_shown if _flash <= 0.0 else 1.0, 0.0, 1.0), 6.0), ACCENT.lerp(UITheme.GREEN, _flash))


## [v9d] One currency of a step's price: its icon, "have / need", a thin fill line; amber while
## short, green once met.
class CostChip extends HBoxContainer:
	var currency: String = "cubes"
	var need: float = 0.0
	var _l: Label
	var _line: Control

	func _init(cur: String) -> void:
		currency = cur
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_constant_override("separation", 4)
		add_child(CurrencyIcon.new(cur, 18.0))
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 1)
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(vb)
		_l = UITheme.label("", 14, HINT)
		vb.add_child(_l)
		_line = Control.new()
		_line.custom_minimum_size = Vector2(0, 3)
		_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_line.draw.connect(func() -> void:
			var have: float = GameState.get_currency(currency).to_float()
			var f: float = clampf(have / maxf(need, 0.001), 0.0, 1.0)
			_line.draw_rect(Rect2(0, 0, _line.size.x, 3), Color(1, 1, 1, 0.16))
			_line.draw_rect(Rect2(0, 0, _line.size.x * f, 3), UITheme.GREEN if f >= 1.0 else HINT))
		vb.add_child(_line)

	func set_need(n: float) -> void:
		need = n
		var have: float = GameState.get_currency(currency).to_float()
		_l.text = "%s / %s" % [Settings.fmt(BigNum.from_float(minf(have, need))), Settings.fmt(BigNum.from_float(need))]
		_l.add_theme_color_override("font_color", UITheme.GREEN if have >= need else HINT)
		_line.queue_redraw()
