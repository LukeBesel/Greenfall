class_name KeyHints
extends PanelContainer
## [onboard] The key-hint strip: a soft dark pill with key caps ("M  map   B  command ..."), large
## enough to read over any scene. In the HUD (bottom-right) it shows for the first minutes of play,
## while the restart checklist runs, in Full HUD mode, and on demand: hold Tab away from the
## workbench for the full list. The pause menu shows the full list too (mode PAUSE).

enum Mode { HUD, PAUSE }

## Shown for this much play time in the Minimal HUD (seconds).
const FIRST_S: float = 600.0
const KEY_COLOR := Color(1.0, 0.76, 0.4)
const NAME_COLOR := Color(0.93, 0.93, 0.9)
const NAME_PX: int = 14
const KEY_PX: int = 13

# l10n:begin
# [v8bot] The first-minutes strip leaves out B (command): robots work on their own and the game
# does not push the Command view (owner); it stays in the full list (Tab, pause menu).
const SHORT: Array = [["open_globe", "map"], ["lens_view", "lens"], ["toggle_goals", "goals"]]
const FULL: Array = [
	["scoop", "scoop"], ["cube", "press bale"], ["interact", "use"], ["drop", "drop"],
	["tool_scoop", "tools"], ["open_upgrades", "workbench"], ["open_globe", "map"],
	["open_command", "command"], ["lens_view", "lens"], ["toggle_goals", "goals"], ["photo_mode", "photo"],
]
# l10n:end


## [v5text] One-word lowercase names look like ids to tools/extract_strings.py and were skipped,
## so the HUD key strip stayed English. Naming them in tr() calls puts them in the catalog.
func _catalog_names() -> Array:
	return [tr("map"), tr("command"), tr("lens"), tr("goals"), tr("scoop"), tr("use"), tr("drop"),
		tr("workbench"), tr("photo")]

var mode: int = Mode.HUD
var world: Node
var _flow: HFlowContainer
var _sig: String = ""
var _alpha: float = 0.0
var _peek: float = 0.0
var _full: bool = false
var _sig_t: float = 0.0
## [v7look] The HUD strip is always ONE row. When it is wider than `cap_w` (the room beside the
## hotbar's right readouts on a small screen) it first gets smaller text and tighter gaps, then
## drops the words and keeps the key caps (`compact` 0 / 1 / 2). The HUD sets cap_w every frame.
var cap_w: float = 380.0:
	set(v):
		if absf(v - cap_w) > 0.5:
			cap_w = v
			_pick_compact()
var compact: int = 0
## Per compact level: [key px, name px, gap between items, show names].
const COMPACT: Array = [[13, 14, 12, true], [11, 12, 8, true], [12, 0, 6, false]]


func _init(p_mode: int = Mode.HUD) -> void:
	mode = p_mode


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = HudReadable.theme()
	add_theme_stylebox_override("panel", HudReadable.pill(0.72 if mode == Mode.PAUSE else 0.62))
	_flow = HFlowContainer.new()
	_flow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flow.add_theme_constant_override("h_separation", 12)
	_flow.add_theme_constant_override("v_separation", 6)
	_flow.alignment = FlowContainer.ALIGNMENT_CENTER if mode == Mode.PAUSE else FlowContainer.ALIGNMENT_END
	add_child(_flow)
	_full = mode == Mode.PAUSE
	_rebuild()
	if mode == Mode.HUD:
		modulate.a = 0.0
		visible = false


## Show the full list for a few seconds (Tab tapped away from the workbench).
func peek(seconds: float = 3.0) -> void:
	_peek = maxf(_peek, seconds)


## Pure: should the HUD strip show?
static func want_shown(hud_mode: int, played_s: float, tutorial_on: bool, peeking: bool) -> bool:
	if peeking:
		return true
	match hud_mode:
		Settings.HudMode.FULL:
			return true
		Settings.HudMode.HIDDEN:
			return false
	return tutorial_on or played_s < FIRST_S


func _items() -> Array:
	return items_for(_full, Pace.baler_unlocked())


## [onboard2] QA P2: "press bale" only once Lumi has the Baler.
static func items_for(full: bool, baler: bool) -> Array:
	if not full:
		return SHORT
	return FULL.filter(func(it: Array) -> bool: return (baler or str(it[0]) != "cube") and (str(it[0]) != "photo_mode" or CameraBot.available()))  # [camp3]


func _signature() -> String:
	var s: String = str(_full) + str(Pace.baler_unlocked()) + str(CameraBot.available()) + TranslationServer.get_locale()
	for it: Array in _items():
		s += Settings.glyph(str(it[0])) + ","
	return s


func _rebuild() -> void:
	_sig = _signature()
	for c: Node in _flow.get_children():
		c.queue_free()
	_flow.custom_minimum_size.x = 400.0  # a flow box needs a width or it stacks; _fit() sets the real one
	for it: Array in _items():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 7)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cap := PanelContainer.new()
		cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := UITheme.box(Color(1, 1, 1, 0.07), Color(KEY_COLOR, 0.45), 1, 5, 0)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 2
		cap.add_theme_stylebox_override("panel", sb)
		var g: String = Settings.glyph(str(it[0]))
		if str(it[0]) == "tool_scoop":
			g = "%s %s %s" % [g, Settings.glyph("tool_plant"), Settings.glyph("tool_water")]
		var lv: Array = COMPACT[compact] if mode == Mode.HUD else COMPACT[0]
		cap.add_child(UITheme.label(g, int(lv[0]), KEY_COLOR))
		row.add_child(cap)
		var name_: String = tr("tools") if str(it[0]) == "tool_scoop" else tr(str(it[1]))
		var l: Label = UITheme.label(name_, int(lv[1]) if bool(lv[3]) else NAME_PX, NAME_COLOR)
		l.visible = bool(lv[3])
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(l)
		_flow.add_child(row)
	_fit.call_deferred()


## One row when it fits (the HUD's short list), else wrap at the cap.
## [v7look] The widest row of each compact level, measured with the theme font (for _pick_compact).
func row_width(level: int) -> float:
	var f: Font = get_theme_default_font() if is_inside_tree() else ThemeDB.fallback_font
	var lv: Array = COMPACT[level]
	var w: float = 0.0
	var items: Array = _items()
	for it: Array in items:
		var g: String = Settings.glyph(str(it[0]))
		w += f.get_string_size(g, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv[0])).x + 14.0
		if bool(lv[3]):
			var nm: String = tr("tools") if str(it[0]) == "tool_scoop" else tr(str(it[1]))
			w += 7.0 + f.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, int(lv[1])).x
	return w + float(lv[2]) * maxf(0.0, items.size() - 1) + 22.0  # + the pill's padding


func _pick_compact() -> void:
	if mode != Mode.HUD:
		return
	var want: int = 2
	for lvl: int in 3:
		if row_width(lvl) <= cap_w:
			want = lvl
			break
	if want != compact:
		compact = want
		if is_inside_tree():
			_rebuild()


func _fit() -> void:
	var w: float = 0.0
	var rows: Array[Node] = _flow.get_children().filter(func(c: Node) -> bool: return not c.is_queued_for_deletion())
	for c: Node in rows:
		w += (c as Control).get_combined_minimum_size().x
	w += 12.0 * maxf(0.0, rows.size() - 1) + 2.0
	if mode == Mode.HUD:  # [v7look] one row, never wrapped
		_flow.add_theme_constant_override("h_separation", int(COMPACT[compact][2]))
		_flow.custom_minimum_size.x = w + 2.0
		return
	var cap: float = 1180.0
	_flow.custom_minimum_size.x = minf(w, cap)


func _process(delta: float) -> void:
	_sig_t -= delta
	if _sig_t <= 0.0:
		_sig_t = 0.5
		if _signature() != _sig:
			_rebuild()
	if mode == Mode.PAUSE:
		return
	if get_tree().paused:  # [ui5] the pause menu has its own legend: never both on screen
		_alpha = 0.0
		visible = false
		return
	_peek = maxf(0.0, _peek - delta)
	if DevHooks.has("hints-full"):  # dev: the held-Tab list (shots)
		_peek = 1.0
	if Input.is_action_pressed("open_upgrades") and not _bench_or_modal():
		_peek = maxf(_peek, 0.3)
	var peeking: bool = _peek > 0.0
	if peeking != _full:
		_full = peeking
		_rebuild()
	var tutorial_on: bool = int(GameState.flags.get("tutorial_step", 0)) < Tutorial.STEPS.size()
	var want: bool = want_shown(Settings.hud_mode, float(GameState.stats.get("time_played", 0.0)), tutorial_on, peeking)
	_alpha = move_toward(_alpha, 1.0 if want else 0.0, delta * (5.0 if want else 1.5))
	modulate.a = _alpha
	visible = _alpha > 0.0


## [ui5] Hidden at once when the game pauses (also when this node itself stops processing).
func _notification(what: int) -> void:
	if what == NOTIFICATION_PAUSED and mode == Mode.HUD:
		_alpha = 0.0
		visible = false


func _bench_or_modal() -> bool:
	if world == null:
		return true
	if world.has_method("any_modal_open") and bool(world.call("any_modal_open")):
		return true
	return world.has_method("near_bench") and bool(world.call("near_bench"))
