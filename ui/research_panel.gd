class_name ResearchPanel
extends VBoxContainer
## Workbench "Research" tab: Data balance, the active research with a progress ring and the
## queue, a detail box for the focused node, and the node graph (5 branches x 6 tiers).

var _graph: Graph
var _data_lbl: Label
var _active_ring: Ring
var _active_name: Label
var _active_time: Label
var _queue_lbl: Label
var _d_name: Label
var _d_desc: Label
var _d_fx: Label
var _d_cost: Label
var _d_hint: Label
var _focus_id: String = ""
var _t: float = 0.0


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	# Data balance.
	var dbox := _glass()
	dbox.custom_minimum_size = Vector2(230, 100)
	top.add_child(dbox)
	var dvb := VBoxContainer.new()
	dvb.add_theme_constant_override("separation", 2)
	dbox.add_child(dvb)
	dvb.add_child(UITheme.label("FIELD DATA", 12, UITheme.MUTED))
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 8)
	dvb.add_child(drow)
	drow.add_child(ResearchIcons.IconView.new("data", 34, Color(0.45, 0.8, 1.0)))
	_data_lbl = UITheme.label("0", 30, Color(0.6, 0.86, 1.0))
	drow.add_child(_data_lbl)
	var earn := UITheme.label("Clean hexes, grow blooms, read shards and let robots work.", 12, UITheme.MUTED)
	earn.autowrap_mode = TextServer.AUTOWRAP_WORD
	earn.custom_minimum_size = Vector2(200, 0)
	dvb.add_child(earn)
	# Active research.
	var abox := _glass()
	abox.custom_minimum_size = Vector2(300, 100)
	top.add_child(abox)
	var ahb := HBoxContainer.new()
	ahb.add_theme_constant_override("separation", 12)
	abox.add_child(ahb)
	_active_ring = Ring.new()
	_active_ring.custom_minimum_size = Vector2(76, 76)
	_active_ring.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ahb.add_child(_active_ring)
	var avb := VBoxContainer.new()
	avb.add_theme_constant_override("separation", 2)
	avb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ahb.add_child(avb)
	avb.add_child(UITheme.label("RESEARCHING", 12, UITheme.MUTED))
	_active_name = UITheme.label("", 18, UITheme.CREAM)
	avb.add_child(_active_name)
	_active_time = UITheme.label("", 14, UITheme.GOLD)
	avb.add_child(_active_time)
	_queue_lbl = UITheme.label("", 12, UITheme.MUTED)
	_queue_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	_queue_lbl.custom_minimum_size = Vector2(190, 0)
	avb.add_child(_queue_lbl)
	# Details of the focused / hovered node.
	var det := _glass()
	det.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	det.custom_minimum_size = Vector2(0, 100)
	top.add_child(det)
	var dt := VBoxContainer.new()
	dt.add_theme_constant_override("separation", 2)
	det.add_child(dt)
	_d_name = UITheme.label("", 18, Color.WHITE)
	dt.add_child(_d_name)
	_d_desc = UITheme.label("", 13, UITheme.MUTED)
	_d_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	dt.add_child(_d_desc)
	_d_fx = UITheme.label("", 13, UITheme.GREEN)
	_d_fx.autowrap_mode = TextServer.AUTOWRAP_WORD
	dt.add_child(_d_fx)
	var crow := HBoxContainer.new()
	dt.add_child(crow)
	_d_cost = UITheme.label("", 13, UITheme.GOLD)
	_d_cost.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_d_cost)
	_d_hint = UITheme.label("", 12, UITheme.MUTED)
	crow.add_child(_d_hint)
	_graph = Graph.new()
	_graph.panel = self
	add_child(_graph)
	EventBus.research_completed.connect(_on_completed)
	_set_focus(Research.ids()[0] if _first_available() == "" else _first_available())
	refresh()
	(func() -> void:
		var sc: ScrollContainer = _find_scroll()
		if sc:
			sc.follow_focus = true
		focus_first()).call_deferred()


func _find_scroll() -> ScrollContainer:
	var n: Node = get_parent()
	while n:
		if n is ScrollContainer:
			return n
		n = n.get_parent()
	return null


func _first_available() -> String:
	if Research.active_id() != "":
		return Research.active_id()
	for id: String in Research.ids():
		if Research.status(id) == "available":
			return id
	return ""


func focus_first() -> void:
	var id: String = _first_available()
	var c: ResearchNodeCard = _graph.cards.get(id if id != "" else Research.ids()[0])
	if c and is_inside_tree():
		c.grab_focus()
		# Keep the header (data, active research) in view when the focused card is near the top.
		var sc: ScrollContainer = _find_scroll()
		if sc and int(Research.def(c.node_id).get("tier", 0)) <= 2:
			(func() -> void: sc.scroll_vertical = 0).call_deferred()


func _glass() -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UITheme.box(Color(0.05, 0.055, 0.065, 0.85), Color(1, 1, 1, 0.08), 1, 12, 12))
	return p


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_t += delta
	if _t >= 0.25:
		_t = 0.0
		refresh()
	else:
		_update_active()


func refresh() -> void:
	_data_lbl.text = Settings.fmt(GameState.get_currency(Research.CURRENCY))
	for c: ResearchNodeCard in _graph.cards.values():
		c.refresh()
	_update_active()
	_update_detail()
	_graph.queue_redraw()


func _update_active() -> void:
	var aid: String = Research.active_id()
	if aid == "":
		_active_name.text = "Nothing yet"
		_active_time.text = "Pick a glowing card below"
		_active_ring.progress = 0.0
		_active_ring.kind = "data"
	else:
		_active_name.text = str(Research.def(aid).get("name", aid))
		_active_time.text = "%s left  ·  %d%%" % [Research.time_text(Research.remaining()), int(Research.progress(aid) * 100.0)]
		_active_ring.progress = Research.progress(aid)
		_active_ring.kind = str(Research.def(aid).get("icon", "data"))
	var q: Array[String] = []
	for id: String in Research.queue():
		q.append(str(Research.def(id).get("name", id)))
	_queue_lbl.text = ("Next: " + ", ".join(q)) if not q.is_empty() else "Queue: empty  (%d slots)" % Research.max_queue()
	_active_ring.queue_redraw()


func _set_focus(id: String) -> void:
	_focus_id = id
	_update_detail()


func _update_detail() -> void:
	if _focus_id == "":
		return
	var d: Dictionary = Research.def(_focus_id)
	_d_name.text = str(d.get("name", _focus_id))
	_d_desc.text = str(d.get("desc", ""))
	_d_fx.text = "  ·  ".join(Research.effect_lines(_focus_id))
	var st: String = Research.status(_focus_id)
	match st:
		"researched":
			_d_cost.text = "Researched"
			_d_hint.text = ""
		"active":
			_d_cost.text = "%s left" % Research.time_text(Research.remaining())
			_d_hint.text = "Press again to cancel (refund)"
		"queued":
			_d_cost.text = "Queued #%d" % (Research.queue_position(_focus_id) + 1)
			_d_hint.text = "Press again to cancel (refund)"
		_:
			_d_cost.text = "%s data  ·  %s" % [Settings.fmt(Research.cost(_focus_id)), Research.time_text(Research.duration(_focus_id))]
			var why: String = Research.reason(_focus_id)
			_d_hint.text = why if why != "" else ("Press to research" if Research.active().is_empty() else "Press to queue")


func _on_card_pressed(id: String) -> void:
	var c: ResearchNodeCard = _graph.cards[id]
	var st: String = Research.status(id)
	if st == "active" or st == "queued":
		Research.cancel(id)
		Audio.play("click", 0.8, -6.0)
		EventBus.toast.emit("%s cancelled. Data refunded." % Research.def(id).get("name", id), "info")
	elif Research.start(id):
		Audio.play("buy", 1.1, -3.0)
		c.pop()
	else:
		Audio.play("buzz", 1.2, -8.0)
		c.shake()
	refresh()


func _on_completed(id: String) -> void:
	if not is_inside_tree():
		return
	var c: ResearchNodeCard = _graph.cards.get(id)
	if c:
		c.celebrate()
	refresh()


## Progress ring for the active research.
class Ring extends Control:
	var progress: float = 0.0
	var kind: String = "data"

	func _draw() -> void:
		var c: Vector2 = size * 0.5
		var r: float = minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r - 4.0, Color(1, 1, 1, 0.04))
		draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.1), 5.0, true)
		if progress > 0.0:
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * progress, 48, UITheme.GOLD, 5.0, true)
			var tip: Vector2 = c + Vector2(cos(-PI * 0.5 + TAU * progress), sin(-PI * 0.5 + TAU * progress)) * r
			draw_circle(tip, 4.0, Color(1.0, 0.9, 0.6))
		ResearchIcons.draw(self, kind, c, r * 0.5, UITheme.GOLD if progress > 0.0 else UITheme.MUTED, 2.0)


## The node graph: branch headers, connector lines (orthogonal, routed through the gaps),
## flowing dots toward running research, and one ResearchNodeCard per node.
class Graph extends Control:
	const HEADER: float = 44.0
	const ROW: float = 104.0
	var panel: ResearchPanel
	var cards: Dictionary = {}  # id -> ResearchNodeCard
	var _branch_idx: Dictionary = {}
	var _tiers: int = 1
	var _t: float = 0.0

	func _ready() -> void:
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mouse_filter = Control.MOUSE_FILTER_PASS
		var br: Array = Research.branches()
		for i: int in br.size():
			_branch_idx[str(br[i]["id"])] = i
		for id: String in Research.ids():
			var d: Dictionary = Research.def(id)
			_tiers = maxi(_tiers, int(d.get("tier", 0)) + 1)
			var bi: int = int(_branch_idx.get(str(d.get("branch", "")), 0))
			var c := ResearchNodeCard.new(id, Color.html(str(br[bi].get("color", "#ffb342"))))
			add_child(c)
			cards[id] = c
			c.pressed.connect(func() -> void: panel._on_card_pressed(id))
			c.focus_entered.connect(func() -> void: panel._set_focus(id))
			c.mouse_entered.connect(func() -> void: panel._set_focus(id))
		custom_minimum_size = Vector2(br.size() * (ResearchNodeCard.W + 24.0), HEADER + _tiers * ROW)
		resized.connect(_layout)
		_layout()
		_link_focus()

	func _col_w() -> float:
		return size.x / maxf(float(_branch_idx.size()), 1.0)

	func _layout() -> void:
		var cw: float = _col_w()
		for id: String in cards:
			var d: Dictionary = Research.def(id)
			var c: ResearchNodeCard = cards[id]
			var bi: int = int(_branch_idx.get(str(d.get("branch", "")), 0))
			c.position = Vector2(bi * cw + (cw - ResearchNodeCard.W) * 0.5, HEADER + int(d.get("tier", 0)) * ROW)
			c.pivot_offset = c.size * 0.5
		queue_redraw()

	func _link_focus() -> void:
		var grid: Dictionary = {}
		for id: String in cards:
			var d: Dictionary = Research.def(id)
			grid[Vector2i(int(_branch_idx.get(str(d.get("branch", "")), 0)), int(d.get("tier", 0)))] = cards[id]
		for k: Vector2i in grid:
			var c: ResearchNodeCard = grid[k]
			for pair: Array in [[Vector2i(-1, 0), SIDE_LEFT], [Vector2i(1, 0), SIDE_RIGHT], [Vector2i(0, -1), SIDE_TOP], [Vector2i(0, 1), SIDE_BOTTOM]]:
				var n: Variant = grid.get(k + (pair[0] as Vector2i))
				if n != null:
					c.set_focus_neighbor(pair[1], c.get_path_to(n as Control))

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _route(a: ResearchNodeCard, b: ResearchNodeCard, lane: int) -> PackedVector2Array:
		var p0 := Vector2(a.position.x + a.size.x * 0.5, a.position.y + a.size.y)
		var p1 := Vector2(b.position.x + b.size.x * 0.5, b.position.y)
		if absf(p0.x - p1.x) < 1.0:
			return PackedVector2Array([p0, p1])
		var gap: float = ROW - ResearchNodeCard.H
		var gy1: float = p0.y + gap * 0.5 + lane * 5.0
		var gy2: float = p1.y - gap * 0.5 + lane * 5.0
		if gy2 - gy1 < 6.0:
			return PackedVector2Array([p0, Vector2(p0.x, gy1), Vector2(p1.x, gy1), p1])
		var cw: float = _col_w()
		var ca: int = int(a.position.x / cw)
		var gx: float = (ca + 1) * cw if p1.x > p0.x else ca * cw
		gx += lane * 6.0
		return PackedVector2Array([p0, Vector2(p0.x, gy1), Vector2(gx, gy1), Vector2(gx, gy2), Vector2(p1.x, gy2), p1])

	func _draw() -> void:
		var f: Font = UITheme.font()
		var br: Array = Research.branches()
		var cw: float = _col_w()
		for i: int in br.size():
			var col := Color.html(str(br[i].get("color", "#ffb342")))
			var done: int = 0
			var total: int = 0
			for id: String in cards:
				if str(Research.def(id).get("branch", "")) == str(br[i]["id"]):
					total += 1
					done += 1 if Research.has(id) else 0
			var x0: float = i * cw + (cw - ResearchNodeCard.W) * 0.5
			draw_string(f, Vector2(x0, 20), str(br[i]["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, ResearchNodeCard.W, 15, col)
			draw_string(f, Vector2(x0, 20), "%d/%d" % [done, total], HORIZONTAL_ALIGNMENT_RIGHT, ResearchNodeCard.W, 12, UITheme.MUTED)
			draw_rect(Rect2(x0, 28, ResearchNodeCard.W, 2), Color(1, 1, 1, 0.07))
			draw_rect(Rect2(x0, 28, ResearchNodeCard.W * done / maxf(total, 1.0), 2), col)
		# Connectors behind the cards.
		var aid: String = Research.active_id()
		for id: String in cards:
			var lane: int = 0
			for r: String in Research.requires(id):
				if not cards.has(r):
					continue
				var pts: PackedVector2Array = _route(cards[r], cards[id], lane)
				if absf(pts[0].x - pts[pts.size() - 1].x) >= 1.0:
					lane += 1
				var c_from: ResearchNodeCard = cards[r]
				var c_to: ResearchNodeCard = cards[id]
				var col: Color = Color(1, 1, 1, 0.1)
				var w: float = 1.5
				if Research.has(r) and Research.has(id):
					col = Color(c_to.accent, 0.75)
					w = 3.0
				elif Research.has(r) or Research.is_active(r) or Research.is_queued(r):
					col = Color(c_from.accent, 0.45)
					w = 2.0
				draw_polyline(pts, col, w, true)
				if id == aid or (Research.has(r) and not Research.has(id) and Research.status(id) == "available"):
					_flow(pts, UITheme.GOLD if id == aid else Color(c_from.accent, 0.6), 1.0 if id == aid else 0.35)
				for k: int in range(1, pts.size() - 1):
					draw_circle(pts[k], w * 0.5, col)
				# Arrow nub into the target.
				var end: Vector2 = pts[pts.size() - 1]
				draw_colored_polygon(PackedVector2Array([end, end + Vector2(-5, -7), end + Vector2(5, -7)]), col)

	## Little dots running along a connector toward its target.
	func _flow(pts: PackedVector2Array, col: Color, speed: float) -> void:
		var total: float = 0.0
		for i: int in range(1, pts.size()):
			total += pts[i].distance_to(pts[i - 1])
		if total <= 1.0:
			return
		var spacing: float = 26.0
		var off: float = fmod(_t * 40.0 * speed, spacing)
		var d: float = off
		while d < total:
			var acc: float = 0.0
			for i: int in range(1, pts.size()):
				var seg: float = pts[i].distance_to(pts[i - 1])
				if acc + seg >= d:
					draw_circle(pts[i - 1].lerp(pts[i], (d - acc) / maxf(seg, 0.001)), 2.2, col)
					break
				acc += seg
			d += spacing
