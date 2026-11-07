class_name ContractsPanel
extends VBoxContainer
## Workbench "Contracts" tab: the three contract slots (accept / pass / claim), the token shop
## (fleet liveries, blueprint parts, seed crates, Curio Capsules) and a Collection summary.
## Rebuilds itself when a slot changes state; labels tick every half second.

const TOKEN_COLOR := Color(0.55, 0.95, 0.85)

var world: Node
var _tokens: Label
var _slots_row: HBoxContainer
var _shop_grid: GridContainer
var _collection: Label
var _sig: String = ""
var _t: float = 0.0
var _slot_labels: Array[Dictionary] = []


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	add_child(head)
	head.add_child(UITheme.label(tr("CONTRACTS"), 20, UITheme.CREAM))
	# [vqa] The blurb wraps instead of setting the workbench's minimum width (it pushed the panel
	# off a 1280x720 screen, more so in German).
	var blurb: Label = UITheme.label(tr("Optional jobs with a timer. Finish in time for tokens; nothing is lost if one runs out."), 13, UITheme.MUTED)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	blurb.custom_minimum_size.x = 200
	head.add_child(blurb)
	_tokens = UITheme.label("", 22, TOKEN_COLOR)
	head.add_child(_tokens)
	_slots_row = HBoxContainer.new()
	_slots_row.add_theme_constant_override("separation", 14)
	add_child(_slots_row)
	add_child(HSeparator.new())
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 14)
	add_child(sh)
	sh.add_child(UITheme.label(tr("TOKEN SHOP"), 20, UITheme.CREAM))
	_collection = UITheme.label("", 13, UITheme.MUTED)
	_collection.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sh.add_child(_collection)
	_shop_grid = GridContainer.new()
	_shop_grid.columns = 4
	_shop_grid.add_theme_constant_override("h_separation", 10)
	_shop_grid.add_theme_constant_override("v_separation", 10)
	add_child(_shop_grid)
	refresh(true)


func _contracts() -> Contracts:
	return world.get("contracts") as Contracts if world else null


func _process(delta: float) -> void:
	# Rebuild as soon as anything changes; the timers/labels tick twice a second.
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
	bits.append(str(Contracts.tokens()))
	bits.append(str(Contracts.owned()))
	bits.append(Liveries.equipped())
	bits.append(str(Collection.count()))
	return "|".join(bits)


func refresh(force: bool = false) -> void:
	_tokens.text = tr("◆  %d tokens") % Contracts.tokens()
	_collection.text = tr("Collection  %d / %d   ·   see the Codex (K)") % [Collection.count(), Collection.total()]
	var sig: String = _signature()
	if force or sig != _sig:
		_sig = sig
		_rebuild_slots()
		_rebuild_shop()
	_tick_labels()


static func _clock(s: float) -> String:
	var t: int = maxi(int(ceil(s)), 0)
	@warning_ignore("integer_division")
	return "%d:%02d" % [t / 60, t % 60]


func _card(col: Color) -> Array:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(300, 190)
	pc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pc.add_theme_stylebox_override("panel", UITheme.box(Color(0.06, 0.065, 0.075, 0.95), Color(col, 0.5), 1, 10, 14))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	return [pc, vb]


func _rebuild_slots() -> void:
	for c: Node in _slots_row.get_children():
		_slots_row.remove_child(c)
		c.queue_free()
	_slot_labels.clear()
	var arr: Array = Contracts.slots()
	var want: int = int(Contracts.cfg().get("slots", 3))
	for i: int in want:
		var s: Dictionary = arr[i] if i < arr.size() else Contracts.wait_slot(0.0)
		var st: String = str(s.get("state", "wait"))
		var col: Color = UITheme.MUTED
		match st:
			"offer": col = UITheme.GOLD
			"active": col = Color(0.45, 0.85, 1.0)
			"done": col = UITheme.GREEN
		var parts: Array = _card(col)
		_slots_row.add_child(parts[0])
		var vb: VBoxContainer = parts[1]
		var refs: Dictionary = {"i": i}
		var tag: String = {"offer": "N E W   O F F E R", "active": "I N   P R O G R E S S", "done": "C O M P L E T E", "wait": "P O S T I N G   S O O N"}.get(st, "")
		vb.add_child(UITheme.label(tag, 11, col))
		if st == "wait":
			var l := UITheme.label(tr("A new contract is being posted."), 16, UITheme.MUTED)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			vb.add_child(l)
			refs["timer"] = UITheme.label("", 14, UITheme.MUTED)
			vb.add_child(refs["timer"])
			_wrap_card(vb)
			_slot_labels.append(refs)
			continue
		var title := UITheme.label(Contracts.text_of(s), 19, UITheme.CREAM)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		vb.add_child(title)
		vb.add_child(UITheme.label(tr("Reward  ◆ %d tokens  +  cubes") % int(s.get("tokens", 0)), 14, TOKEN_COLOR))
		if st == "active" or st == "done":
			var bar := ProgressBar.new()
			bar.show_percentage = false
			bar.max_value = float(s.get("n", 1))
			bar.custom_minimum_size = Vector2(0, 6)
			bar.modulate = col
			vb.add_child(bar)
			refs["bar"] = bar
			refs["count"] = UITheme.label("", 13, UITheme.CREAM)
			vb.add_child(refs["count"])
		refs["timer"] = UITheme.label("", 13, UITheme.MUTED)
		vb.add_child(refs["timer"])
		var sp := Control.new()
		sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vb.add_child(sp)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vb.add_child(row)
		match st:
			"offer":
				var acc := Button.new()
				acc.text = tr("Accept  (%s)") % _clock(float(s.get("time_s", 600)))
				acc.custom_minimum_size = Vector2(170, 40)
				UITheme.orange_button(acc)
				acc.pressed.connect(func() -> void:
					var c: Contracts = _contracts()
					if c and c.accept(i):
						refresh(true))
				row.add_child(acc)
				var pass_b := Button.new()
				pass_b.text = tr("Pass")
				pass_b.custom_minimum_size = Vector2(80, 40)
				pass_b.pressed.connect(func() -> void:
					var c: Contracts = _contracts()
					if c:
						c.decline(i)
						refresh(true))
				row.add_child(pass_b)
			"active":
				var b := Button.new()
				b.text = tr("Working on it")
				b.disabled = true
				b.custom_minimum_size = Vector2(170, 40)
				row.add_child(b)
			"done":
				var cl := Button.new()
				cl.text = tr("Claim  ◆ %d") % int(s.get("tokens", 0))
				cl.custom_minimum_size = Vector2(170, 40)
				UITheme.orange_button(cl)
				cl.pressed.connect(func() -> void:
					var c: Contracts = _contracts()
					if c and c.claim(i) > 0:
						if world and world.get("patch") != null:
							Vfx.burst("confetti", world.patch.global_position + Vector3(0, 1.5, 0), Color.WHITE, 0.5)
						refresh(true))
				row.add_child(cl)
		_wrap_card(vb)
		_slot_labels.append(refs)


## [vqa] Card labels wrap (timer and reward lines in long languages set the card, and so the
## workbench, wider than the screen) and its buttons shrink with ellipses.
static func _wrap_card(vb: Control) -> void:
	for n: Node in vb.find_children("*", "Label", true, false):
		(n as Label).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		(n as Label).custom_minimum_size.x = 0
	for n: Node in vb.find_children("*", "Button", true, false):
		var bt: Button = n
		bt.clip_text = true
		bt.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		bt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bt.custom_minimum_size.x = minf(bt.custom_minimum_size.x, 80.0)


func _tick_labels() -> void:
	var arr: Array = Contracts.slots()
	var c: Contracts = _contracts()
	for refs: Dictionary in _slot_labels:
		var i: int = int(refs["i"])
		if i >= arr.size():
			continue
		var s: Dictionary = arr[i]
		var st: String = str(s.get("state", "wait"))
		var timer: Label = refs.get("timer")
		match st:
			"wait":
				timer.text = tr("Next posting in %s") % _clock(float(s.get("wait", 0.0)))
			"offer":
				timer.text = tr("Time limit %s once accepted   ·   offer open %s") % [_clock(float(s.get("time_s", 600))), _clock(float(s.get("offer_left", 0.0)))]
			"active", "done":
				var have: float = Contracts.count_of(s, c.live_value(s)) if c else 0.0
				if st == "done":
					have = float(s.get("n", 1))
				var bar: ProgressBar = refs.get("bar")
				if bar:
					bar.value = have
				var cnt: Label = refs.get("count")
				if cnt:
					cnt.text = "%d / %d" % [int(have), int(s.get("n", 1))]
				timer.text = (tr("Time left %s") % _clock(float(s.get("left", 0.0)))) if st == "active" else tr("Finished. Claim your tokens!")
				timer.add_theme_color_override("font_color", Color(1.0, 0.55, 0.35) if st == "active" and float(s.get("left", 0.0)) < 60.0 else UITheme.MUTED)


func _rebuild_shop() -> void:
	for ch: Node in _shop_grid.get_children():
		_shop_grid.remove_child(ch)
		ch.queue_free()
	var owned: Array = Contracts.owned()
	for it: Dictionary in Contracts.shop():
		var id: String = str(it["id"])
		var col: Color = Color.html(str(it.get("color", "#8fe8d8"))) if it.has("color") else TOKEN_COLOR
		var kind: String = str(it.get("kind", ""))
		var b := Button.new()
		b.custom_minimum_size = Vector2(240, 92)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD
		b.add_theme_font_size_override("font_size", 14)
		var have: bool = id in owned
		var price: String = "◆ %d" % int(it.get("cost", 0))
		var status: String = price
		if kind == "livery" and have:
			status = tr("Equipped  (press to remove)") if Liveries.equipped() == id else tr("Owned  ·  press to equip")
		var why: String = Contracts.block_reason(id)
		if why != "" and not (kind == "livery" and have):
			status = "%s   ·   %s" % [price, why]
		b.text = "%s\n%s\n%s" % [tr(str(it.get("name", id))), tr(str(it.get("desc", ""))), status]
		b.disabled = why != "" and not (kind == "livery" and have)
		b.add_theme_color_override("font_color", col.lightened(0.25))
		b.add_theme_stylebox_override("normal", UITheme.box(Color(col.r * 0.12 + 0.04, col.g * 0.12 + 0.04, col.b * 0.12 + 0.04, 0.92), Color(col, 0.6 if Liveries.equipped() == id else 0.25), 2 if Liveries.equipped() == id else 1, 8, 10))
		b.pressed.connect(func() -> void:
			var c: Contracts = _contracts()
			if c == null:
				return
			var err: String = c.buy(id)
			if err != "":
				Audio.play("buzz", 1.2, -8.0)
				EventBus.toast.emit(err, "info")
			refresh(true))
		_shop_grid.add_child(b)
