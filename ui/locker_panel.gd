class_name LockerPanel
extends VBoxContainer
## The Locker's panel (design spec section 13): the one place looks are edited. It opens from the
## Locker in the yard (systems/camp/locker_cabinet.gd: press E at it) and sits on the right of
## the screen as a field-instrument plate, leaving the left free for Lumi on the turntable
## (systems/camp/locker_stage.gd). A bar on top picks who is being dressed: Lumi first, then the
## other cosmetic targets (Glim, ...) from CosmeticTargets, the crew's robots (one look per robot
## type) and the rocket; under it, that one's editor.
##
## Editors are pluggable:
##   LockerPanel.add_editor("lumi", func(world: Node) -> Control: ...)   # a factory (preferred)
##   LockerPanel.add_editor("lumi", some_control)                         # or a ready Control
## Lumi's page is ui/lumi_builder.gd (through CosmeticTargets). Robots use the cosmetic robot
## builder (BuilderPanel in locker_mode: parts, name, personality).
## The editor gets `world`, `stage` (the turntable), and `fleet` / select_robot(r) when it has them.

signal editing_changed(who: String)

const LUMI: String = "target:lumi"
## The docked panel's share of the screen width while Lumi is on the turntable, and its limits.
const DOCK_SHARE: float = 0.46
const DOCK_MIN_W: float = 540.0
const DOCK_MAX_W: float = 680.0
## Safe margin: this share of the screen's short side (docs/STYLE.md section 10).
const SAFE_SHARE: float = 0.04

static var _editors: Dictionary = {}  # id -> Callable(world) -> Control, or a Control

var world: Node
var fleet: Fleet
## The turntable beside the Locker (null when the panel is shown without one: tools, tests).
var stage: LockerStage
var _who: String = LUMI  # "target:<id>", "bots" or "rocket"
var _list: HBoxContainer  # [ui3] the slim bot bar
var _who_btns: Array[Button] = []
var _host: VBoxContainer
var _editor: Control
var _editor_kind: String = ""
var _robot_editor: BuilderPanel
var _paint: HBoxContainer
var _bots_sig: String = ""
var _t: float = 0.0
## Over the game (open_overlay): the section bar and the editor page each sit on their own plate;
## list + detail editors (Bots, Rocket) bring their own.
var modules: bool = false
## Over the game: the bar starts with this title and ends with this control (the Close key).
var bar_title: String = ""
var bar_tail: Control
var _page: PanelContainer


## Registers the editor for a kind of bot ("lumi", or "robot" to replace the robot editor).
static func add_editor(id: String, editor: Variant) -> void:
	_editors[id] = editor


static func remove_editor(id: String) -> void:
	_editors.erase(id)


## The panel has something to show once the Locker stands in the yard (or a dev flag opens it).
static func is_open_for(_w: Node) -> bool:
	return DevHooks.has("locker") or YardBuilds.built("locker")


## The Locker over the game: the panel docked on the right, the turntable in view on the left.
## Close / Esc / B shuts it. Pauses the world while open. Returns the layer (it frees itself on
## close). `p_stage` is the turntable Lumi stands on (may be null).
static func open_overlay(w: Node, p_stage: LockerStage = null) -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 40
	cl.process_mode = Node.PROCESS_MODE_ALWAYS
	var root := _StageView.new()
	root.stage = p_stage
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = UITheme.get_theme()
	cl.add_child(root)
	var frame := MarginContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(frame)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(row)
	var view := Control.new()  # the part of the screen left to the turntable
	view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(view)
	var dock := VBoxContainer.new()
	dock.add_theme_constant_override("separation", 8)
	row.add_child(dock)
	var close := Button.new()
	close.text = TranslationServer.translate("Close")
	close.custom_minimum_size = Vector2(96, FieldPlate.TOUCH_PX)
	FieldPlate.key(close, FieldPlate.AMBER)
	var lp := LockerPanel.new()
	lp.bar_title = TranslationServer.translate("Locker")
	lp.bar_tail = close
	lp.world = w
	lp.fleet = w.get("fleet") as Fleet if w else null
	lp.stage = p_stage
	lp.modules = true
	lp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(lp)
	# Lumi's page leaves the turntable in view; the wider editors (crew, rocket) take the screen.
	var fit := func() -> void:
		var pad: int = int(minf(root.size.x, root.size.y) * SAFE_SHARE)
		for side: String in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
			frame.add_theme_constant_override(side, pad)
		var lumi: bool = lp.editing() == LUMI
		view.visible = lumi
		dock.size_flags_horizontal = Control.SIZE_SHRINK_END if lumi else Control.SIZE_EXPAND_FILL
		dock.custom_minimum_size.x = clampf(root.size.x * DOCK_SHARE, DOCK_MIN_W, DOCK_MAX_W) if lumi else 0.0
	root.resized.connect(fit)
	lp.editing_changed.connect(func(_section: String) -> void: fit.call())
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var was_paused: bool = tree.paused
	var hidden: Array[CanvasLayer] = HoloFrame.hide_hud(tree, cl.layer)  # no HUD text behind the plates
	var shut := func() -> void:
		if not is_instance_valid(cl) or cl.has_meta("closing"):
			return
		tree.paused = was_paused
		HoloFrame.show_hud(hidden)
		EventBus.ui_modal_changed.emit(false)
		cl.set_meta("closing", true)
		cl.queue_free()
	close.pressed.connect(shut)
	cl.set_meta("shut", shut)
	var catcher := _OverlayInput.new()
	catcher.on_close = shut
	cl.add_child(catcher)
	(w if w and w.is_inside_tree() else tree.root).add_child(cl)
	tree.paused = true
	EventBus.ui_modal_changed.emit(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(func() -> void:
		fit.call()
		_slide_in(dock)
		var f: Button = lp.first_button()
		(f if f else close).grab_focus()).call_deferred()
	return cl


## The dock slides in from the edge: one short mechanical ease, none with reduced motion.
static func _slide_in(dock: Control) -> void:
	if Settings.reduced_motion:
		return
	dock.modulate.a = 0.0
	var tw: Tween = dock.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(dock, "modulate:a", 1.0, FieldPlate.EASE_S).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


## The screen behind the dock: a drag on it turns the turntable, the wheel moves the camera.
class _StageView extends Control:
	var stage: LockerStage
	var _drag: bool = false

	func _gui_input(event: InputEvent) -> void:
		if stage == null:
			return
		if event is InputEventMouseButton:
			var mb: InputEventMouseButton = event
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_drag = mb.pressed
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				stage.zoom(1.0)
			elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				stage.zoom(-1.0)
		elif event is InputEventMouseMotion and _drag:
			stage.turn((event as InputEventMouseMotion).relative.x)


class _OverlayInput extends Node:
	var on_close: Callable

	func _ready() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _unhandled_input(event: InputEvent) -> void:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			on_close.call()
			get_viewport().set_input_as_handled()


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_open_for(world):
		_build_locked()
		return
	GameState.flags["locker_open"] = true
	# [ui3] One slim bar on top (who you edit, then the fleet paint), so the editor gets the full
	# width (the Lumi builder needs it at 1280x720 and 125% UI scale).
	add_theme_constant_override("separation", 10)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	if modules:
		add_theme_constant_override("separation", 8)
		var bm := FieldPlate.new(8, 12.0)
		add_child(bm)
		bm.add_child(bar)
	else:
		add_child(bar)
	if bar_title != "":
		bar.add_child(FieldPlate.stencil(bar_title, FieldPlate.INK, 20))
	var sc := ScrollContainer.new()
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 52)
	sc.follow_focus = true
	bar.add_child(sc)
	_list = HBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 2)
	bar.add_child(pv)
	_paint = HBoxContainer.new()  # [ui7] fleet paint moved into the Bots section (per robot type)
	_paint.visible = false
	pv.add_child(_paint)
	if bar_tail:
		bar.add_child(bar_tail)
	# The editor scrolls sideways if a wide one (the Lumi builder) meets a small screen at a big
	# UI scale, instead of pushing the workbench off the screen.
	var hsc := ScrollContainer.new()
	hsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	hsc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsc.follow_focus = true
	if modules:
		hsc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO  # a tall editor scrolls inside its plate
		_page = FieldPlate.new(14)
		_page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		add_child(_page)
		_page.add_child(hsc)
	else:
		add_child(hsc)
	_host = VBoxContainer.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hsc.add_child(_host)
	_rebuild_list()
	_show_editor()


func _build_locked() -> void:
	if bar_tail:
		add_child(bar_tail)
	var c: Array = BenchKit.card(Color(1, 1, 1, 0.12))
	add_child(c[0])
	var vb: VBoxContainer = c[1]
	vb.add_theme_constant_override("separation", 14)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	vb.add_child(top)
	top.add_child(BenchKit.Glyph.new("lock", 56, UITheme.MUTED))
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(tv)
	tv.add_child(BenchKit.title(tr("The Locker")))
	tv.add_child(BenchKit.body(tr("Find a piece of a look in the world. Then build the Locker in the Build tab and open it in the yard."), UITheme.CREAM))
	tv.add_child(BenchKit.body(tr("Lumi wears what she finds: paint tins, lens chips and the pieces of old robots. Glim and your robots are dressed here too.")))


func first_button() -> Button:
	return _who_btns[0] if not _who_btns.is_empty() else null


func editing() -> String:
	return _who


func _bots() -> Array[Robot]:
	var out: Array[Robot] = []
	if fleet:
		out = fleet.robots()
	out.sort_custom(func(a: Robot, b: Robot) -> bool:
		var ra: int = Fleet.ROLES.find(a.role())
		var rb: int = Fleet.ROLES.find(b.role())
		return ra < rb if ra != rb else a.robot_name < b.robot_name)
	return out


func _bots_signature() -> String:
	var bits: Array[String] = []
	for r: Robot in _bots():
		bits.append("%s/%d" % [r.robot_name, r.tier])
	return ",".join(bits)


func _rebuild_list() -> void:
	_bots_sig = _bots_signature()
	for c: Node in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	_who_btns.clear()
	for t: Dictionary in CosmeticTargets.all():  # [ui6] Lumi, Glim, ... (locked ones aren't shown)
		var tid: String = str(t.get("id", ""))
		if CosmeticTargets.is_unlocked(tid):
			_add_who("target:" + tid, CosmeticTargets.display_name(tid), "", FieldPlate.CYAN)
	# [ui7] Four sections: Lumi, Glim (CosmeticTargets), Bots (one design per robot type), Rocket.
	if not LockerEditors.bot_types(fleet).is_empty():
		_add_who("bots", tr("Crew"), "", FieldPlate.CYAN)
	if _rocket_open():
		_add_who("rocket", tr("Rocket"), "", FieldPlate.CYAN)
	var ok: bool = false
	for b: Button in _who_btns:
		ok = ok or str(b.get_meta("who")) == _who
	if not ok:
		_who = LUMI
	_style_list()


func _rocket_open() -> bool:
	return UpgradesScreen.tab_visible("rockets", world) or int(GameState.flags.get("rocket_tier", 1)) > 1


func _add_who(id: String, title: String, sub: String, col: Color) -> void:
	var b := Button.new()
	b.text = title
	b.tooltip_text = sub
	b.custom_minimum_size = Vector2(110, FieldPlate.TOUCH_PX)
	b.clip_text = true
	b.set_meta("who", id)
	b.set_meta("col", col)
	b.pressed.connect(func() -> void: set_editing(id))
	_list.add_child(b)
	_who_btns.append(b)


func _style_list() -> void:
	for b: Button in _who_btns:
		FieldPlate.key(b, b.get_meta("col") as Color, str(b.get_meta("who")) == _who)


func _find_robot(rname: String) -> Robot:
	for r: Robot in _bots():
		if r.robot_name == rname:
			return r
	return null


## Switches the editor to Lumi ("lumi") or a robot (its name).
func set_editing(who: String) -> void:
	if who == _who and _editor != null:
		return
	_who = who
	Audio.play("click", 1.1, -8.0)
	_style_list()
	_show_editor()
	editing_changed.emit(who)


func _show_editor() -> void:
	var kind: String = _who
	_clear_editor()
	_editor_kind = kind
	var ed: Control = _make_editor(kind)
	if ed == null:
		return
	_editor = ed
	if _page:  # list + detail editors bring their own modules; the rest sit on the page's plate
		var own: bool = ed is LockerEditors.BotEditor or ed is LockerEditors.ShipEditor
		(_page as FieldPlate).fill = Color(0, 0, 0, 0) if own else FieldPlate.SLATE
		_page.queue_redraw()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_host.add_child(ed)
	if kind == "robot":
		if ed.has_method("select_robot"):
			ed.call("select_robot", _find_robot(_who))
		if ed is BuilderPanel:
			_robot_editor = ed


func _clear_editor() -> void:
	if _editor != null and is_instance_valid(_editor):
		_host.remove_child(_editor)
		var reg: Variant = _editors.get(_editor_kind)
		if not (reg is Control and reg == _editor):  # a registered Control is reused, not freed
			_editor.queue_free()
	_editor = null
	_robot_editor = null


func _make_editor(kind: String) -> Control:
	var reg: Variant = _editors.get(kind, _editors.get(kind.trim_prefix("target:")))
	var ed: Control = null
	if reg is Callable and (reg as Callable).is_valid():
		ed = (reg as Callable).call(world) as Control
	elif reg is Control and is_instance_valid(reg):
		ed = reg
		if ed.get_parent():
			ed.get_parent().remove_child(ed)
	elif kind == "bots":  # [ui7] per-type robot designs
		var be := LockerEditors.BotEditor.new()
		be.fleet = fleet
		be.modules = modules
		ed = be
	elif kind == "rocket":  # [ui7] ship paint, trim, glow
		var se := LockerEditors.ShipEditor.new()
		se.modules = modules
		ed = se
	elif kind.begins_with("target:"):  # [ui6] CosmeticTargets editors (Lumi's builder, Glim's looks, ...)
		ed = CosmeticTargets.make_editor(kind.substr(7), world)
	else:
		var bp := BuilderPanel.new()
		bp.locker_mode = true
		ed = bp
	if ed == null:
		return null
	if "world" in ed:
		ed.set("world", world)
	if "stage" in ed:
		ed.set("stage", stage)
	if "fleet" in ed:
		ed.set("fleet", fleet)
	return ed


## Fleet paint: the liveries won from Requests (press to wear, again to take off).
func _rebuild_paint() -> void:
	for c: Node in _paint.get_children():
		_paint.remove_child(c)
		c.queue_free()
	var owned: Array = Contracts.owned()
	var any: bool = false
	for it: Dictionary in Contracts.shop():
		var id: String = str(it.get("id", ""))
		var have: bool = id in owned
		if not have:
			continue  # [ui3] only the paints you own (nothing shown before it's unlocked)
		var col: Color = Color.html(str(it.get("color", "#8fe8d8")))
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.tooltip_text = "%s\n%s" % [tr(str(it.get("name", id))), tr(str(it.get("desc", ""))) if have else Contracts.block_reason(id)]
		var on: bool = Liveries.equipped() == id
		b.add_theme_stylebox_override("normal", UITheme.box(Color(col, 0.85) if have else Color(col, 0.12), Color.WHITE if on else Color(col, 0.4), 3 if on else 1, 20, 4))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(col, 1.0) if have else Color(col, 0.18), Color.WHITE, 2, 20, 4))
		b.disabled = not have
		if not have:
			b.focus_mode = Control.FOCUS_NONE  # [ui3] locked chips aren't stops for the D-pad
			b.custom_minimum_size = Vector2(28, 28)
		b.pressed.connect(func() -> void:
			if GameState.flags.get("livery", "") == id:
				GameState.flags["livery"] = ""
			else:
				GameState.flags["livery"] = id
			Audio.play("click", 1.2, -6.0)
			_rebuild_paint())
		_paint.add_child(b)
		any = true
	_paint.get_parent().get_child(_paint.get_index() - 1).visible = any
	_paint.visible = any


func _process(delta: float) -> void:
	if _list == null:
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	if _bots_signature() != _bots_sig:
		_rebuild_list()  # [ui7] keeps the section when it's still there


func _exit_tree() -> void:
	# A registered Control editor outlives the panel: detach it so the next Locker can reuse it.
	if _editor != null and is_instance_valid(_editor) and _editors.get(_editor_kind) is Control and _editors[_editor_kind] == _editor:
		_host.remove_child(_editor)
