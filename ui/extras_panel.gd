class_name ExtrasPanel
extends CanvasLayer
## [extras] Keepsakes: the radio, the photo album, the robot nursery and the Seed of the Week in
## one small panel (Pause > Keepsakes; the base radio opens it on the Radio tab).
## Pad: LB / RB switch tabs, the d-pad moves focus, A presses, left / right moves the album's
## before/after slider, B (or Esc) closes.

const TABS: Array[String] = ["radio", "album", "nursery", "weekly"]
const TAB_NAMES: Dictionary = {"radio": "Radio", "album": "Album", "nursery": "Nursery", "weekly": "Seed of the Week"}  # l10n
const VIEW_SIZE := Vector2(560, 315)

var world: Node
var is_open: bool = false
var tab: String = "radio"
var _root: Control
var _tab_btns: Dictionary = {}
var _body: HBoxContainer
var _first: Control
var _album_hub: int = -1
var _album_kind: String = ""
var _album_photo: int = -1
var _view: BeforeAfterView
var _slider: HSlider
var _tex_cache: Dictionary = {}
var _confirm: String = ""


static func open_for(slice: Node, p_tab: String = "radio") -> void:
	var p: ExtrasPanel = slice.get_node_or_null("ExtrasPanel") as ExtrasPanel if slice else null
	if p:
		p.open_panel(p_tab)


func _ready() -> void:
	layer = 31
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = UITheme.get_theme()
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.035, 0.04, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(cc)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(980, 560)
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.07, 0.92), Color(1, 1, 1, 0.1), 1, 10, 20))
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	vb.add_child(head)
	var title: Label = UITheme.label(tr("KEEPSAKES"), 24, Color.WHITE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	for t: String in TABS:
		var b := Button.new()
		b.text = tr(str(TAB_NAMES[t]))
		b.custom_minimum_size = Vector2(0, 38)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func() -> void: _set_tab(t))
		head.add_child(b)
		_tab_btns[t] = b
	var hint: Label = UITheme.label("", 12, UITheme.MUTED)
	Settings.bind_text(hint, func() -> String: return tr("%s / %s  switch tabs") % [Settings.glyph("ui_tab_prev"), Settings.glyph("ui_tab_next")])
	head.add_child(hint)
	_body = HBoxContainer.new()
	_body.add_theme_constant_override("separation", 16)
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_body)
	_root.visible = false


func open_panel(p_tab: String = "") -> void:
	if p_tab in TABS:
		tab = p_tab
	if not is_open:
		is_open = true
		_root.visible = true
		_root.modulate.a = 0.0
		create_tween().tween_property(_root, "modulate:a", 1.0, 0.15)
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		EventBus.ui_modal_changed.emit(true)
		GameState.inc_stat("keepsakes_opened")
	_set_tab(tab)


func close_panel() -> void:
	if not is_open:
		return
	is_open = false
	_root.visible = false
	_tex_cache.clear()
	get_tree().paused = false
	EventBus.ui_modal_changed.emit(false)
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _set_tab(t: String) -> void:
	tab = t
	_confirm = ""
	for k: String in _tab_btns:
		var b: Button = _tab_btns[k]
		var on: bool = k == t
		b.add_theme_stylebox_override("normal", UITheme.box(Color(0.2, 0.15, 0.07, 0.9) if on else UITheme.TEAL, UITheme.GOLD if on else Color(1, 1, 1, 0.08), 1, 6, 10))
		b.add_theme_color_override("font_color", UITheme.GOLD if on else UITheme.CREAM)
	_rebuild()


func _rebuild() -> void:
	for c: Node in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_view = null
	_slider = null
	_first = null
	match tab:
		"radio": _build_radio()
		"album": _build_album()
		"nursery": _build_nursery()
		"weekly": _build_weekly()
	if _first:
		_first.call_deferred("grab_focus")


# --- Shared bits -------------------------------------------------------------------------

func _col(width: float, title: String = "") -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", UITheme.box(UITheme.CARD_BG, Color(1, 1, 1, 0.06), 1, 8, 12))
	pc.custom_minimum_size = Vector2(width, 0)
	if width <= 0.0:
		pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(pc)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.follow_focus = true
	pc.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 6)
	sc.add_child(vb)
	if title != "":
		vb.add_child(UITheme.label(title, 12, Color(0.4, 0.75, 1.0)))
	return vb


func _btn(parent: Control, text: String, cb: Callable, h: float = 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.clip_text = true
	b.custom_minimum_size = Vector2(0, h)
	b.add_theme_font_size_override("font_size", 14)
	b.pressed.connect(func() -> void:
		Audio.play("click", 1.0, -6.0)
		cb.call())
	parent.add_child(b)
	if _first == null:
		_first = b
	return b


func _wrap(text: String, size: int, col: Color) -> Label:
	var l: Label = UITheme.label(text, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _tex(path: String) -> Texture2D:
	if not _tex_cache.has(path):
		_tex_cache[path] = PhotoAlbum.load_texture(path)
	return _tex_cache[path]


# --- Radio -------------------------------------------------------------------------------

func _build_radio() -> void:
	var left: VBoxContainer = _col(420, tr("SONGS  ·  %d / %d") % [Radio.unlocked_count(), Radio.songs().size()])
	var cur: String = Radio.playing()
	for s: Dictionary in Radio.songs():
		var id: String = str(s["id"])
		var ok: bool = Radio.is_unlocked(id)
		var txt: String = ("%s%s\n%s" % ["▶  " if id == cur else "", tr(Radio.title(id)), tr(str(s.get("desc", "")))]) if ok \
			else ("? ? ?\n%s" % (tr("Unlocks: %s") % tr(str(s.get("hint", "")))))
		var b: Button = _btn(left, txt, func() -> void:
			if Radio.play(id):
				EventBus.toast.emit(tr("Now playing: %s") % tr(Radio.title(id)), "info")
			_rebuild(), 56)
		b.add_theme_color_override("font_color", UITheme.GOLD if id == cur else (UITheme.CREAM if ok else UITheme.MUTED))
		if id == cur:
			_first = b
	var right: VBoxContainer = _col(0, tr("NOW PLAYING"))
	if cur != "":
		right.add_child(UITheme.label(tr(Radio.title(cur)), 26, Color.WHITE))
		right.add_child(_wrap(tr(str(Radio.song(cur).get("desc", ""))), 15, UITheme.MUTED))
		right.add_child(_wrap(tr("Your pick loops everywhere until you switch back to the mood music. A restored planet plays its restored version."), 13, UITheme.MUTED))
		var back: Button = _btn(right, tr("Back to mood music"), func() -> void:
			Radio.play("")
			EventBus.toast.emit(tr("The radio hands the music back to the day."), "info")
			_rebuild())
		UITheme.orange_button(back)
	else:
		right.add_child(UITheme.label(tr("Mood music"), 26, Color.WHITE))
		right.add_child(_wrap(tr("The music follows the day: the yard, the streets, the night. Pick a song to play it instead."), 15, UITheme.MUTED))
	right.add_child(_wrap(tr("New songs come in as districts and planets are restored."), 13, UITheme.GREEN))


# --- Album -------------------------------------------------------------------------------

func _build_album() -> void:
	var hubs: Array[int] = PhotoAlbum.districts()
	var photos: Array = PhotoAlbum.st()["photos"]
	if _album_hub < 0 and _album_photo < 0:
		if hubs.has(GameState.current_hub):
			_album_hub = GameState.current_hub
		elif not hubs.is_empty():
			_album_hub = hubs[0]
	var left: VBoxContainer = _col(250, tr("DISTRICTS"))
	if hubs.is_empty():
		left.add_child(_wrap(tr("Lumi takes a picture of each district on arrival, and \"after\" pictures as it is restored."), 13, UITheme.MUTED))
	for h: int in hubs:
		var e: Dictionary = PhotoAlbum.entry(h)
		var after: String = PhotoAlbum.latest_after(h)
		var b: Button = _btn(left, "%s\n%s" % [tr(str(e.get("name", "?"))), PhotoAlbum.milestone_name(after) if after != "" else tr("Before only")], func() -> void:
			_album_hub = h
			_album_photo = -1
			_album_kind = ""
			_rebuild(), 52)
		if h == _album_hub and _album_photo < 0:
			b.add_theme_color_override("font_color", UITheme.GOLD)
			_first = b
	left.add_child(UITheme.label(tr("PHOTOS  ·  %d") % photos.size(), 12, Color(0.4, 0.75, 1.0)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	left.add_child(grid)
	for i: int in range(photos.size() - 1, maxi(-1, photos.size() - 13), -1):
		var p: Dictionary = photos[i]
		var tb := Button.new()
		tb.custom_minimum_size = Vector2(108, 61)
		tb.icon = _tex(str(p.get("thumb", "")))
		tb.expand_icon = true
		tb.text = "" if tb.icon else tr("Photo")
		var idx: int = i
		tb.pressed.connect(func() -> void:
			_album_photo = idx
			_rebuild())
		grid.add_child(tb)
		if idx == _album_photo:
			_first = tb
	if photos.is_empty():
		left.add_child(_wrap(tr("Photos you take in photo mode show up here."), 13, UITheme.MUTED))
	var right: VBoxContainer = _col(0)
	if _album_photo >= 0 and _album_photo < photos.size():
		var p2: Dictionary = photos[_album_photo]
		right.add_child(UITheme.label(tr("PHOTO MODE"), 12, Color(0.4, 0.75, 1.0)))
		var tr_ := TextureRect.new()
		tr_.custom_minimum_size = VIEW_SIZE
		tr_.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr_.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr_.texture = _tex(str(p2.get("src", ""))) if _tex(str(p2.get("src", ""))) else _tex(str(p2.get("thumb", "")))
		right.add_child(tr_)
		right.add_child(UITheme.label(Time.get_datetime_string_from_unix_time(int(float(p2.get("unix", 0.0))), true), 13, UITheme.MUTED))
		return
	if _album_hub < 0:
		right.add_child(_wrap(tr("No pictures yet."), 15, UITheme.MUTED))
		return
	var e2: Dictionary = PhotoAlbum.entry(_album_hub)
	if _album_kind == "" or not PhotoAlbum.has_shot(_album_hub, _album_kind):
		_album_kind = PhotoAlbum.latest_after(_album_hub)
	right.add_child(UITheme.label(tr(str(e2.get("name", ""))).to_upper(), 12, Color(0.4, 0.75, 1.0)))
	_view = BeforeAfterView.new()
	_view.custom_minimum_size = VIEW_SIZE
	_view.before = _tex(str(e2.get("before", "")))
	_view.after = _tex(str(e2.get(_album_kind, ""))) if _album_kind != "" else null
	_view.after_label = PhotoAlbum.milestone_name(_album_kind).to_upper() if _album_kind != "" else ""
	_view.before_label = tr("BEFORE")
	right.add_child(_view)
	_slider = HSlider.new()
	_slider.min_value = 0.0
	_slider.max_value = 1.0
	_slider.step = 0.01
	_slider.value = 0.5
	_slider.custom_minimum_size = Vector2(VIEW_SIZE.x, 24)
	_slider.value_changed.connect(func(v: float) -> void: _view.split = v)
	_slider.editable = _album_kind != ""
	right.add_child(_slider)
	if _album_kind != "":
		_first = _slider
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	right.add_child(row)
	for m: String in PhotoAlbum.MILESTONES:
		var mb := Button.new()
		var has: bool = PhotoAlbum.has_shot(_album_hub, m)
		mb.text = PhotoAlbum.milestone_name(m) if has else "%s  ·  %s" % [PhotoAlbum.milestone_name(m), tr("not yet")]
		mb.disabled = not has
		mb.custom_minimum_size = Vector2(0, 36)
		mb.add_theme_color_override("font_color", UITheme.GOLD if m == _album_kind else UITheme.CREAM)
		var mm: String = m
		mb.pressed.connect(func() -> void:
			_album_kind = mm
			_rebuild())
		row.add_child(mb)
	if _album_kind == "":
		right.add_child(_wrap(tr("The \"after\" picture comes when the district is half clean."), 13, UITheme.MUTED))


# --- Nursery -----------------------------------------------------------------------------

func _build_nursery() -> void:
	var left: VBoxContainer = _col(440, tr("CARETAKERS  ·  %d") % Nursery.count())
	left.add_child(_wrap(tr("Garden bonus: plants grow %d%% faster (up to %d%%).") % [int(round(Nursery.garden_bonus() * 100.0)), int(round(Nursery.BONUS_CAP * 100.0))], 14, UITheme.GREEN))
	var recs: Array = Nursery.list()
	if recs.is_empty():
		left.add_child(_wrap(tr("No one has retired yet. Old or Mk I-II robots can retire here or in the workbench Builder; they'll look after the nursery garden at the base."), 14, UITheme.MUTED))
	for i: int in range(recs.size() - 1, -1, -1):
		var r: Dictionary = recs[i]
		var tdef: Dictionary = RobotBuilder.trait_def(str(r.get("trait", "")))
		var tier: int = int(r.get("tier", 0))
		var row: HBoxContainer = UITheme.stat_row(RobotBuilder.CREW_COLORS.get(str(Economy.robots.get(str(r.get("type", "")), {}).get("role", "clean")), UITheme.GOLD),
			"%s  ·  %s %s" % [str(r.get("name", "")), tr(str(Economy.robots.get(str(r.get("type", "")), {}).get("name", ""))), Economy.tier_name(tier)],
			tr(str(tdef.get("name", ""))))
		left.add_child(row)
	var right: VBoxContainer = _col(0, tr("RETIRE A ROBOT"))
	var fl: Fleet = world.get("fleet") as Fleet if world else null
	right.add_child(_wrap(tr("Retiring gives a few parts back, and the robot keeps its name and personality in the nursery."), 13, UITheme.MUTED))
	if fl == null or fl.robots().is_empty():
		right.add_child(_wrap(tr("No robots in this district."), 14, UITheme.MUTED))
		return
	for rb: Robot in fl.robots():
		var why: String = Nursery.retire_block_reason(rb)
		var key: String = rb.robot_name
		var label: String = "%s  ·  %s %s" % [rb.robot_name, tr(str(Economy.robots.get(rb.type_id, {}).get("name", ""))), Economy.tier_name(rb.tier)]
		if why == "":
			label += "\n" + (tr("Press again to retire (+%d parts)") % Nursery.refund_for(rb.tier) if _confirm == key else tr("Retire  (+%d parts)") % Nursery.refund_for(rb.tier))
		else:
			label += "\n" + why
		var robot: Robot = rb
		var b: Button = _btn(right, label, func() -> void:
			if Nursery.retire_block_reason(robot) != "":
				return
			if _confirm != key:
				_confirm = key
				_rebuild()
				return
			_confirm = ""
			Nursery.retire(fl, robot)
			_rebuild(), 52)
		b.add_theme_color_override("font_color", UITheme.GOLD if _confirm == key else (UITheme.CREAM if why == "" else UITheme.MUTED))
		if _confirm == key:
			_first = b


# --- Seed of the Week --------------------------------------------------------------------

func _build_weekly() -> void:
	var w: Vector2i = WeeklyChallenge.iso_week(WeeklyChallenge.now())
	var tw: Dictionary = WeeklyChallenge.twist()
	var wr: Dictionary = WeeklyChallenge.week_rec()
	var left: VBoxContainer = _col(520, tr("WEEK %d, %d") % [w.y, w.x])
	left.add_child(UITheme.label(tr("Seed of the Week"), 26, Color.WHITE))
	left.add_child(_wrap(tr("The same seed and twist for everyone this week. Clean %d hexes as fast as you can. It has its own save, so your world is untouched.") % WeeklyChallenge.goal_hexes(), 14, UITheme.MUTED))
	left.add_child(UITheme.stat_row(UITheme.GOLD, tr("Twist: %s") % tr(str(tw.get("name", ""))), ""))
	left.add_child(_wrap(tr(str(tw.get("desc", ""))), 13, UITheme.MUTED))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Seed"), str(WeeklyChallenge.current_seed())))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Best time"), WeeklyChallenge.clock_text(float(wr["best_time"])) if float(wr.get("best_time", 0.0)) > 0.0 else "--"))
	left.add_child(UITheme.stat_row(UITheme.CREAM, tr("Best score"), str(int(wr.get("best_score", 0))) if int(wr.get("best_score", 0)) > 0 else "--"))
	if WeeklyChallenge.active:
		var home: Button = _btn(left, tr("Return home"), func() -> void:
			close_panel()
			WeeklyChallenge.leave(get_tree()))
		UITheme.orange_button(home)
		_btn(left, tr("Restart this week's run"), func() -> void:
			close_panel()
			WeeklyChallenge.restart(get_tree()))
	else:
		var go: Button = _btn(left, tr("Resume this week's run") if WeeklyChallenge.has_run() else tr("Start the challenge"), func() -> void:
			close_panel()
			WeeklyChallenge.start(get_tree()))
		UITheme.orange_button(go)
	var right: VBoxContainer = _col(0, tr("PAINT CHIPS  ·  %d") % WeeklyChallenge.chip_count())
	right.add_child(_wrap(tr("Finish a week's challenge for its paint chip. Chips unlock the weekly decorations in Garden Mode and paint them."), 13, UITheme.MUTED))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	right.add_child(grid)
	for c: Variant in WeeklyChallenge.chips():
		var chip := Panel.new()
		chip.custom_minimum_size = Vector2(44, 56)
		chip.tooltip_text = str((c as Dictionary).get("week", ""))
		chip.add_theme_stylebox_override("panel", UITheme.box(Color.html(str((c as Dictionary).get("color", "#e8a33d"))), Color(1, 1, 1, 0.5), 1, 4, 0))
		grid.add_child(chip)
	if WeeklyChallenge.chips().is_empty():
		right.add_child(_wrap(tr("No chips yet."), 14, UITheme.MUTED))


func _unhandled_input(event: InputEvent) -> void:
	if not is_open:
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		close_panel()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_tab_next") or event.is_action_pressed("ui_tab_prev"):
		var i: int = TABS.find(tab)
		_set_tab(TABS[(i + (1 if event.is_action_pressed("ui_tab_next") else TABS.size() - 1)) % TABS.size()])
		get_viewport().set_input_as_handled()


## Before / after: the "after" picture fills the frame and the "before" one is revealed to the
## left of the split line (0..1), with a thin handle.
class BeforeAfterView extends Control:
	var before: Texture2D
	var after: Texture2D
	var before_label: String = "BEFORE"
	var after_label: String = ""
	var split: float = 0.5:
		set(v):
			split = clampf(v, 0.0, 1.0)
			queue_redraw()

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.03, 0.035, 0.04))
		var font: Font = UITheme.font()
		if before == null:
			draw_string(font, Vector2(16, size.y * 0.5), TranslationServer.translate("No picture yet"), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, UITheme.MUTED)
			return
		if after == null:
			draw_texture_rect(before, r, false)
		else:
			draw_texture_rect(after, r, false)
			var ts: Vector2 = before.get_size()
			var w: float = size.x * split
			draw_texture_rect_region(before, Rect2(0, 0, w, size.y), Rect2(0, 0, ts.x * split, ts.y))
			draw_rect(Rect2(w - 1.0, 0, 2.0, size.y), Color(1, 1, 1, 0.85))
			draw_circle(Vector2(w, size.y * 0.5), 9.0, Color(1, 1, 1, 0.9))
			draw_circle(Vector2(w, size.y * 0.5), 6.0, Color(0.1, 0.11, 0.12, 0.9))
			_tag(font, after_label, Vector2(size.x - 10.0, 22.0), true)
		_tag(font, before_label, Vector2(10.0, 22.0), false)

	func _tag(font: Font, text: String, at: Vector2, right: bool) -> void:
		if text == "":
			return
		var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		var x: float = at.x - tw - 12.0 if right else at.x
		draw_rect(Rect2(x, at.y - 15.0, tw + 12.0, 20.0), Color(0, 0, 0, 0.55))
		draw_string(font, Vector2(x + 6.0, at.y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
