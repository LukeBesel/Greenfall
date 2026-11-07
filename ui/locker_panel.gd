class_name LockerPanel
extends HBoxContainer
## [ui2] Workbench "Locker" tab: one place to style any bot. It opens once the hub reaches
## HUB_LEVEL (before that the tab shows what opens it). Left: who you are editing (Lumi first,
## then every robot) and the fleet paint (liveries won from Requests). Right: that bot's editor.
##
## Editors are pluggable, so the Lumi character builder (wt/style) drops in without touching
## this file:
##   LockerPanel.add_editor("lumi", func(world: Node) -> Control: ...)   # a factory (preferred)
##   LockerPanel.add_editor("lumi", some_control)                         # or a ready Control
## Without a registered "lumi" editor the Locker embeds ui/lumi_builder.gd when it exists
## (LumiBuilder.new(), world set, embedded mode), else the design picker (CosmeticsPanel).
## Robots use the cosmetic robot builder (BuilderPanel in locker_mode: parts, name, personality).
## The editor gets `world`, and `fleet` / select_robot(r) when it has them.

signal editing_changed(who: String)

const HUB_LEVEL: int = 3
const LUMI_BUILDER_PATH: String = "res://ui/lumi_builder.gd"

static var _editors: Dictionary = {}  # id -> Callable(world) -> Control, or a Control

var world: Node
var fleet: Fleet
var _who: String = "lumi"  # "lumi" or a robot name
var _list: VBoxContainer
var _who_btns: Array[Button] = []
var _host: VBoxContainer
var _editor: Control
var _editor_kind: String = ""
var _robot_editor: BuilderPanel
var _paint: HBoxContainer
var _bots_sig: String = ""
var _t: float = 0.0


## Registers the editor for a kind of bot ("lumi", or "robot" to replace the robot editor).
static func add_editor(id: String, editor: Variant) -> void:
	_editors[id] = editor


static func remove_editor(id: String) -> void:
	_editors.erase(id)


## The Locker is open from hub level HUB_LEVEL (any district), or when a dev flag opens it.
static func is_open_for(w: Node) -> bool:
	if DevHooks.has("locker") or bool(GameState.flags.get("locker_open", false)):
		return true
	var lv: int = int(GameState.world.get("hub_level", 1))
	if w and w.get("hub") != null:
		lv = maxi(lv, int(w.hub.level))
	return lv >= HUB_LEVEL or Achievements.best_hub_level() >= HUB_LEVEL


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not is_open_for(world):
		_build_locked()
		return
	GameState.flags["locker_open"] = true
	var lc: Array = BenchKit.card(Color(1, 1, 1, 0.1), 250)
	var left: PanelContainer = lc[0]
	left.size_flags_horizontal = Control.SIZE_FILL
	add_child(left)
	var lv: VBoxContainer = lc[1]
	lv.add_child(BenchKit.caps(tr("Editing")))
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(0, 300)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.follow_focus = true
	lv.add_child(sc)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	sc.add_child(_list)
	lv.add_child(BenchKit.caps(tr("Fleet paint")))
	_paint = HBoxContainer.new()
	_paint.add_theme_constant_override("separation", 6)
	lv.add_child(_paint)
	_host = VBoxContainer.new()
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_host)
	_rebuild_list()
	_rebuild_paint()
	_show_editor()


func _build_locked() -> void:
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
	tv.add_child(BenchKit.body(tr("Style Lumi and every robot: colours, eyes, head pieces, toppers, fleet paint. New pieces unlock as you play.")))
	var lv: int = int(GameState.world.get("hub_level", 1))
	if world and world.get("hub") != null:
		lv = int(world.hub.level)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 12)
	vb.add_child(pr)
	var pips := BenchKit.Pips.new(HUB_LEVEL, true, UITheme.GOLD)
	pips.set_counts(mini(lv, HUB_LEVEL), HUB_LEVEL)
	pr.add_child(pips)
	pr.add_child(UITheme.label(tr("Opens at hub level %d (now %d). Upgrade the hub in the Hub tab.") % [HUB_LEVEL, lv], BenchKit.BODY_SIZE, UITheme.CREAM))


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
	_add_who("lumi", tr("Lumi"), tr("You"), UITheme.GOLD)
	for r: Robot in _bots():
		var sub: String = "%s  ·  %s" % [tr(str(Economy.robots.get(r.type_id, {}).get("name", r.type_id))), Economy.tier_name(r.tier)]
		_add_who(r.robot_name, r.robot_name, sub, RobotBuilder.CREW_COLORS.get(r.role(), UITheme.GOLD))
	if _who != "lumi" and _find_robot(_who) == null:
		_who = "lumi"
	_style_list()


func _add_who(id: String, title: String, sub: String, col: Color) -> void:
	var b := Button.new()
	b.text = "%s\n%s" % [title, sub]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size = Vector2(0, 58)
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 16)
	b.set_meta("who", id)
	b.set_meta("col", col)
	b.pressed.connect(func() -> void: set_editing(id))
	_list.add_child(b)
	_who_btns.append(b)


func _style_list() -> void:
	for b: Button in _who_btns:
		var on: bool = str(b.get_meta("who")) == _who
		var col: Color = b.get_meta("col")
		b.add_theme_stylebox_override("normal", UITheme.box(Color(col.r * 0.16 + 0.03, col.g * 0.16 + 0.03, col.b * 0.16 + 0.03, 0.95) if on else UITheme.TEAL, col if on else Color(col, 0.22), 2 if on else 1, 8, 10))
		b.add_theme_color_override("font_color", Color.WHITE if on else UITheme.CREAM)


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
	var kind: String = "lumi" if _who == "lumi" else "robot"
	if kind == "robot" and _editor_kind == "robot" and is_instance_valid(_robot_editor):
		_robot_editor.select_robot(_find_robot(_who))
		return
	_clear_editor()
	_editor_kind = kind
	var ed: Control = _make_editor(kind)
	if ed == null:
		return
	_editor = ed
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
	var reg: Variant = _editors.get(kind)
	var ed: Control = null
	if reg is Callable and (reg as Callable).is_valid():
		ed = (reg as Callable).call(world) as Control
	elif reg is Control and is_instance_valid(reg):
		ed = reg
		if ed.get_parent():
			ed.get_parent().remove_child(ed)
	elif kind == "lumi":
		if ResourceLoader.exists(LUMI_BUILDER_PATH):
			var scr: Script = load(LUMI_BUILDER_PATH)
			if scr:
				ed = scr.new() as Control
		if ed == null:
			ed = CosmeticsPanel.new()
	else:
		var bp := BuilderPanel.new()
		bp.locker_mode = true
		ed = bp
	if ed == null:
		return null
	if "world" in ed:
		ed.set("world", world)
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
		var col: Color = Color.html(str(it.get("color", "#8fe8d8")))
		var b := Button.new()
		b.custom_minimum_size = Vector2(40, 40)
		b.tooltip_text = "%s\n%s" % [tr(str(it.get("name", id))), tr(str(it.get("desc", ""))) if have else Contracts.block_reason(id)]
		var on: bool = Liveries.equipped() == id
		b.add_theme_stylebox_override("normal", UITheme.box(Color(col, 0.85) if have else Color(col, 0.12), Color.WHITE if on else Color(col, 0.4), 3 if on else 1, 20, 4))
		b.add_theme_stylebox_override("hover", UITheme.box(Color(col, 1.0) if have else Color(col, 0.18), Color.WHITE, 2, 20, 4))
		b.disabled = not have
		if not have:
			b.text = "?"
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
		_rebuild_list()
		if _who != "lumi" and _find_robot(_who) == null:
			set_editing("lumi")


func _exit_tree() -> void:
	# A registered Control editor outlives the panel: detach it so the next Locker can reuse it.
	if _editor != null and is_instance_valid(_editor) and _editors.get(_editor_kind) is Control and _editors[_editor_kind] == _editor:
		_host.remove_child(_editor)
