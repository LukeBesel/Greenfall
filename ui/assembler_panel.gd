class_name AssemblerPanel
extends VBoxContainer
## The Assembler's panel (the workbench Bots tab, once the building stands): one status line, the
## build mix as one row per robot type (share number with - and +, the share in percent, the
## Parts for one robot), the next robots off the line, and Pause / Resume. It reads and sets the
## chain through RobotChain (systems/crew/robot_chain.gd) and nothing else.
##
## Use: var p := AssemblerPanel.new(); p.rc = RobotChain.of(world); parent.add_child(p)

const REFRESH_S: float = 0.5
const PREVIEW_N: int = 6
const STEP_W: float = 44.0
const COUNT_W: float = 32.0
const SHARE_W: float = 56.0

var rc: RobotChain
var _status: Label
var _next: Label
var _rows: VBoxContainer
var _pause: Button
var _counts: Dictionary[String, Label] = {}
var _shares: Dictionary[String, Label] = {}
var _row_types: Array[String] = []
var _t: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	add_child(BenchKit.caps(tr("Assembler")))
	_status = BenchKit.body("", UITheme.CREAM)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_status)
	var help: Label = BenchKit.body(tr("Build mix: how many of each type the line builds in turn. A type joins the line after you build the first one by hand. Paint where Scroungers search in Command view."),
		UITheme.MUTED, BenchKit.SMALL_SIZE)
	help.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(help)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	add_child(_rows)
	_next = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
	_next.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_next)
	_pause = BenchKit.soft_button("")
	_pause.pressed.connect(_on_pause)
	add_child(_pause)
	refresh()


func _process(delta: float) -> void:
	_t += delta
	if _t >= REFRESH_S:
		_t = 0.0
		refresh()


## The line's state in words.
static func status_text(rc_: RobotChain) -> String:
	var c: CrewChain = rc_.chain
	match c.status:
		CrewChain.PART:
			return TranslationServer.translate("Building a part for Lumi. Robots wait until it is done.")
		CrewChain.PAUSED:
			return TranslationServer.translate("Paused.")
		CrewChain.NO_MIX:
			return TranslationServer.translate("Nothing to build: give a type a share.")
		CrewChain.CREW_FULL:
			return TranslationServer.translate("Crew full: the line waits for room.")
		CrewChain.NEED_PARTS:
			return TranslationServer.translate("Waiting for Parts.")
		CrewChain.BUILDING:
			return TranslationServer.translate("Building a %s, %d%%") % [_type_name(c.current), int(c.progress() * 100.0)]
	return TranslationServer.translate("Starting up.")


func refresh() -> void:
	if rc == null or _status == null:
		return
	var types: Array[String] = rc.mix_types()
	if types != _row_types:
		_build_rows(types)
	_status.text = status_text(rc)
	var allowed: Array[String] = rc.allowed_types()
	for t: String in _counts:
		_counts[t].text = str(rc.chain.weight(t))
		_shares[t].text = ("%d%%" % roundi(rc.chain.share(t, allowed) * 100.0)) if t in allowed else tr("by hand first")
	var names: PackedStringArray = []
	for t: String in rc.chain.upcoming(PREVIEW_N, allowed):
		names.append(_type_name(t))
	_next.text = tr("Next: %s") % ", ".join(names) if not names.is_empty() else ""
	_pause.text = tr("Resume") if rc.chain.paused else tr("Pause")


func _build_rows(types: Array[String]) -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_counts.clear()
	_shares.clear()
	_row_types = types.duplicate()
	for t: String in types:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_rows.add_child(row)
		var nm: Label = BenchKit.body(_type_name(t), UITheme.CREAM)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(nm)
		var price: Label = BenchKit.body(L10nFmt.amount("parts", rc.price_of(t)), UITheme.MUTED, BenchKit.SMALL_SIZE)
		row.add_child(price)
		var share: Label = BenchKit.body("", UITheme.MUTED, BenchKit.SMALL_SIZE)
		share.custom_minimum_size.x = SHARE_W
		share.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(share)
		_shares[t] = share
		row.add_child(_step_button("-", t, -1))
		var n: Label = BenchKit.body("0", Color.WHITE)
		n.custom_minimum_size.x = COUNT_W
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		row.add_child(n)
		_counts[t] = n
		row.add_child(_step_button("+", t, 1))


func _step_button(text: String, type_id: String, step: int) -> Button:
	var b: Button = BenchKit.soft_button(text)
	b.size_flags_horizontal = Control.SIZE_SHRINK_END
	b.custom_minimum_size.x = STEP_W
	b.tooltip_text = tr("More %s") % _type_name(type_id) if step > 0 else tr("Fewer %s") % _type_name(type_id)
	b.pressed.connect(_on_step.bind(type_id, step))
	return b


func _on_step(type_id: String, step: int) -> void:
	if rc == null:
		return
	rc.set_weight(type_id, rc.chain.weight(type_id) + step)
	Audio.play("click", 1.1 if step > 0 else 0.9, -8.0)
	refresh()


func _on_pause() -> void:
	if rc == null:
		return
	rc.set_paused(not rc.chain.paused)
	Audio.play("click", 1.0, -8.0)
	refresh()


static func _type_name(type_id: String) -> String:
	return TranslationServer.translate(str((Economy.robots.get(type_id, {}) as Dictionary).get("name", type_id)))
