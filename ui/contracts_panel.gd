class_name ContractsPanel
extends VBoxContainer
## [ui2] Workbench "Requests" tab, kept short: the live world event (when one is on), then the
## requests, one line each ("Press 5 Perfect bales   3 / 5   +1.2K cubes   [Claim]"), and one
## line for the next unlock on the reward track. Requests start on their own and never run out
## (Contracts.auto_accept); fleet liveries won from them are worn in the Locker.

var world: Node
var _live_card: PanelContainer
var _live: Label
var _rows: VBoxContainer
var _next: Label
var _done: Label
var _sig: String = ""
var _t: float = 0.0
var _row_refs: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	var t: Label = BenchKit.title(tr("Requests"))
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	_done = UITheme.label("", BenchKit.BODY_SIZE, UITheme.MUTED)
	_done.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_done)
	var lc: Array = BenchKit.card(Color(UITheme.GOLD, 0.7))
	_live_card = lc[0]
	add_child(_live_card)
	_live = BenchKit.body("", UITheme.GOLD, 19)
	(lc[1] as VBoxContainer).add_child(_live)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	add_child(_rows)
	_next = BenchKit.body("", UITheme.CREAM)
	add_child(_next)
	refresh(true)


func _contracts() -> Contracts:
	return world.get("contracts") as Contracts if world else null


func first_button() -> Button:
	for r: Dictionary in _row_refs:
		var b: Button = r.get("btn")
		if b and not b.disabled:
			return b
	return null


func _process(delta: float) -> void:
	if _signature() != _sig:
		refresh(false)
	_t += delta
	if _t < 0.5:
		return
	_t = 0.0
	refresh(false)


func _signature() -> String:
	var bits: Array[String] = []
	for s: Dictionary in Contracts.slots():
		bits.append("%s:%s" % [str(s.get("state", "")), str(s.get("tpl", ""))])
	bits.append(str(Contracts.done_total()))
	return "|".join(bits)


func refresh(force: bool = false) -> void:
	_done.text = tr_n("%d done", "%d done", Contracts.done_total()) % Contracts.done_total()
	var ev: WorldEvents = world.get("events") as WorldEvents if world else null
	var live: bool = ev != null and not ev.active.is_empty()
	_live_card.visible = live
	if live:
		_live.text = tr("Live now:  %s  ·  %s  ·  %s left") % [tr(str(ev.active.get("name", ""))), str(ev.active.get("hint", "")), _clock(float(ev.active.get("left", 0.0)))]
	var nt: Dictionary = Contracts.next_track_step(Contracts.done_total())
	if nt.is_empty():
		_next.text = tr("Every reward unlocked. Each %d more requests pay a Vintage part's worth of parts.") % int(Contracts.cfg().get("repeat_every", 5))
	else:
		var left: int = int(nt.get("n", 0)) - Contracts.done_total()
		_next.text = tr_n("Next unlock in %d request:  %s", "Next unlock in %d requests:  %s", left) % [left, Contracts.track_name(nt)]
	var sig: String = _signature()
	if force or sig != _sig:
		_sig = sig
		_rebuild()
	_tick()


static func _clock(s: float) -> String:
	var t: int = maxi(int(ceil(s)), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [t / 60, t % 60]


func _rebuild() -> void:
	for c: Node in _rows.get_children():
		_rows.remove_child(c)
		c.queue_free()
	_row_refs.clear()
	var arr: Array = Contracts.slots()
	for i: int in arr.size():
		var s: Dictionary = arr[i]
		var st: String = str(s.get("state", "wait"))
		var done: bool = st == "done"
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", UITheme.box(BenchKit.CARD_BG, Color(UITheme.GREEN, 0.7) if done else Color(1, 1, 1, 0.1), 2 if done else 1, 10, 14))
		_rows.add_child(pc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		pc.add_child(row)
		var refs: Dictionary = {"i": i}
		var text: String = tr("A new request is on its way") if st == "wait" else Contracts.text_of(s)
		var tl: Label = UITheme.label(text, 21, UITheme.CREAM if st != "wait" else UITheme.MUTED)
		tl.add_theme_constant_override("outline_size", 0)
		tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tl.clip_text = true
		tl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tl)
		var cnt: Label = UITheme.label("", 20, UITheme.MUTED)
		cnt.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		cnt.custom_minimum_size = Vector2(90, 0)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(cnt)
		refs["count"] = cnt
		if st != "wait":
			var pay := BenchKit.CostRow.new(22, 20)
			pay.custom_minimum_size = Vector2(110, 0)
			pay.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			var pid: String = "parts" if str(s.get("pay", "cubes")) == "parts" else "cubes"
			var amt: float = float(s.get("parts", 0)) if pid == "parts" else WorldEvents.progress_cubes(float(s.get("income_s", 90.0)))
			pay.add_child(UITheme.label("+", 20, UITheme.GREEN))
			pay.add_child(CurrencyIcon.new(pid, 22.0))
			var al: Label = UITheme.label(Settings.fmt(BigNum.from_float(ceilf(amt))), 20, UITheme.GREEN)
			al.add_theme_constant_override("outline_size", 0)
			pay.add_child(al)
			row.add_child(pay)
		var b := BenchKit.big_button(tr("Claim"))
		b.custom_minimum_size = Vector2(150, 48)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.disabled = not done
		b.visible = st != "wait"
		b.pressed.connect(func() -> void:
			var c: Contracts = _contracts()
			if c and c.claim(i) > 0.0:
				if world and world.get("patch") != null:
					Vfx.burst("confetti", world.patch.global_position + Vector3(0, 1.5, 0), Color.WHITE, 0.5)
				refresh(true))
		row.add_child(b)
		refs["btn"] = b
		_row_refs.append(refs)


func _tick() -> void:
	var arr: Array = Contracts.slots()
	var c: Contracts = _contracts()
	for refs: Dictionary in _row_refs:
		var i: int = int(refs["i"])
		if i >= arr.size():
			continue
		var s: Dictionary = arr[i]
		var cnt: Label = refs["count"]
		match str(s.get("state", "wait")):
			"wait":
				cnt.text = _clock(float(s.get("wait", 0.0)))
			"done":
				cnt.text = "%d / %d" % [int(s.get("n", 1)), int(s.get("n", 1))]
				cnt.add_theme_color_override("font_color", UITheme.GREEN)
			_:
				var have: float = Contracts.count_of(s, c.live_value(s)) if c else 0.0
				cnt.text = "%d / %d" % [int(have), int(s.get("n", 1))]
				cnt.add_theme_color_override("font_color", UITheme.CREAM)
