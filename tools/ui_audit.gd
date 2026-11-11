class_name UIAudit
extends RefCounted
## [v6screens] Layout and gamepad audit of 2D screens, by numbers (no rendering needed).
## The checks are static and take any Control tree, so tests and other tools can use them:
##   UIAudit.layout(roots, view)   -> issues: off-screen, clipped text, overlaps
##   UIAudit.focus(roots, vp)      -> issues: no focus, focus outside the screen, unreachable
##                                    controls, focus with no visible ring
## The driver that opens every screen of the round game at every size is tools/ui_audit_run.gd
## (`--ui-audit`, see docs/UI_AUDIT.md).
##
## An issue is {kind, node, text, rect, note}. Kinds:
##   offscreen   a text or button reaches past the visible area
##   clipped     text is cut (ellipsis, or more lines than fit), or runs past a clipping parent
##   overlap     two texts / buttons cover each other and neither contains the other
##   overflow    a child is larger than the container that should hold it
##   nofocus     a modal screen is open and nothing has the focus
##   focus_out   the focus sits on a control outside the open screen, or on a hidden one
##   unreachable a focusable control no chain of d-pad presses reaches from the focused one
##   noring      a focusable control whose focus style draws nothing

const TOL: float = 1.5
## Overlaps smaller than this (px on the short side) are ignored: shadows and 1 px seams.
const OVERLAP_MIN: float = 4.0


## The visible area of a viewport in canvas units (what Controls are laid out in).
static func view_of(vp: Viewport) -> Rect2:
	return vp.get_visible_rect()


static func _shown(c: CanvasItem) -> bool:
	if not c.is_visible_in_tree():
		return false
	var a: float = 1.0
	var n: Node = c
	while n:
		if n is CanvasItem:
			a *= (n as CanvasItem).modulate.a
		elif n is CanvasLayer and not (n as CanvasLayer).visible:
			return false
		n = n.get_parent()
	return a * c.self_modulate.a > 0.05 or (a > 0.05 and c is Control and (c as Control).get_child_count() > 0)


## Where the control is laid out on screen. Its own scale is left out: a button that grows a
## little while it has the focus (UITheme.juice) is not off its row.
static func rect_of(c: Control) -> Rect2:
	var xf: Transform2D = c.get_global_transform_with_canvas()
	if c.scale != Vector2.ONE and c.scale.x != 0.0 and c.scale.y != 0.0:
		var p: Vector2 = c.pivot_offset
		xf = xf * Transform2D(0.0, p) * Transform2D.IDENTITY.scaled(Vector2.ONE / c.scale) * Transform2D(0.0, -p)
	return (xf * Rect2(Vector2.ZERO, c.size)).abs()


static func text_of(c: Control) -> String:
	if c is Label:
		return (c as Label).text
	if c is Button:
		return (c as Button).text
	if c is RichTextLabel:
		return (c as RichTextLabel).get_parsed_text()
	if c is LineEdit:
		return (c as LineEdit).text if (c as LineEdit).text != "" else (c as LineEdit).placeholder_text
	return ""


## Is this a thing the player reads or presses (as opposed to a box that holds other things)?
static func is_content(c: Control) -> bool:
	if c.has_meta("ui_audit_skip"):
		return false
	if c is Label or c is RichTextLabel:
		return text_of(c).strip_edges() != ""
	if c is BaseButton or c is LineEdit or c is Slider or c is SpinBox:
		return true
	if c is TextureRect:
		var t: TextureRect = c
		return t.texture != null and t.size.x <= 96.0 and t.size.y <= 96.0 and t.size.x > 2.0
	return false


## The part of the control's rect its clipping ancestors let through (scroll areas, clip_contents).
static func clip_rect(c: Control, r: Rect2) -> Rect2:
	var p: Node = c.get_parent()
	while p and p is Control:
		var pc: Control = p
		if pc.clip_contents or pc is ScrollContainer:
			r = r.intersection(rect_of(pc))
		p = p.get_parent()
	return r


static func _scroll_parent(c: Control) -> ScrollContainer:
	var p: Node = c.get_parent()
	while p and p is Control:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


static func _clip_parent(c: Control) -> Control:
	var p: Node = c.get_parent()
	while p and p is Control:
		if (p as Control).clip_contents and not p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


static func content_of(roots: Array) -> Array[Control]:
	var out: Array[Control] = []
	for r: Variant in roots:
		if r == null or not is_instance_valid(r):
			continue
		var stack: Array[Node] = [r as Node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CanvasLayer and not (n as CanvasLayer).visible:
				continue
			if n is Control:
				if not (n as Control).visible:
					continue
				if is_content(n) and _shown(n):
					out.append(n)
			elif n is Node3D or n is Viewport:
				continue
			for ch: Node in n.get_children():
				stack.append(ch)
	return out


static func _issue(kind: String, c: Control, r: Rect2, note: String = "") -> Dictionary:
	return {"kind": kind, "node": short_path(c), "text": text_of(c).replace("\n", " / ").left(48), "rect": r, "note": note}


## A stable, short name for a node: the last named steps of its path (generated @names dropped).
static func short_path(n: Node) -> String:
	var parts: PackedStringArray = []
	var p: Node = n
	while p and parts.size() < 5:
		var nm: String = str(p.name)
		if nm.begins_with("@"):
			nm = p.get_class()
			var sc: Script = p.get_script()
			if sc and sc.get_global_name() != "":
				nm = sc.get_global_name()
		parts.insert(0, nm)
		p = p.get_parent()
	return "/".join(parts)


## Width the text wants on one line, or (0, lines that do not fit) for a wrapped label.
static func label_clipped(l: Label) -> String:
	if l.text.strip_edges() == "":
		return ""
	var font: Font = l.get_theme_font("font")
	var fs: int = l.get_theme_font_size("font_size")
	var text: String = l.text.to_upper() if l.uppercase else l.text
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		if not l.clip_text and l.text_overrun_behavior == TextServer.OVERRUN_NO_TRIMMING:
			return ""
		var want: float = 0.0
		for line: String in text.split("\n"):
			want = maxf(want, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
		if want > l.size.x + TOL:
			return "wants %d px, has %d" % [roundi(want), roundi(l.size.x)]
		return ""
	var lines: int = l.get_line_count()
	var vis: int = l.get_visible_line_count()
	if l.max_lines_visible > 0:
		vis = mini(vis, l.max_lines_visible)
	if lines > vis:
		return "%d lines, %d shown" % [lines, vis]
	var need: float = lines * l.get_line_height() + maxi(0, lines - 1) * l.get_theme_constant("line_spacing")
	if need > l.size.y + 3.0:
		return "wants %d px tall, has %d" % [roundi(need), roundi(l.size.y)]
	return ""


static func button_clipped(b: Button) -> String:
	if b.text == "" or not (b.clip_text or b.text_overrun_behavior != TextServer.OVERRUN_NO_TRIMMING):
		return ""
	var font: Font = b.get_theme_font("font")
	var fs: int = b.get_theme_font_size("font_size")
	var sb: StyleBox = b.get_theme_stylebox("normal")
	var want: float = font.get_string_size(b.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + (sb.get_minimum_size().x if sb else 0.0)
	if b.icon:
		want += b.icon.get_width() + b.get_theme_constant("h_separation")
	if want > b.size.x + TOL:
		return "wants %d px, has %d" % [roundi(want), roundi(b.size.x)]
	return ""


static func _is_anc(a: Node, b: Node) -> bool:
	return a == b or a.is_ancestor_of(b)


## Layout issues of everything shown under `roots`, against the visible area `view`.
## `ignore_overlap`: Callable(a: Control, b: Control) -> bool for pairs that overlap on purpose.
static func layout(roots: Array, view: Rect2, ignore_overlap: Callable = Callable()) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var items: Array[Control] = content_of(roots)
	var rects: Array[Rect2] = []
	for c: Control in items:
		var r: Rect2 = rect_of(c)
		var seen: Rect2 = clip_rect(c, r)
		rects.append(seen)
		if seen.size.x <= 0.5 or seen.size.y <= 0.5:
			continue  # scrolled out of sight: fine
		var sp: ScrollContainer = _scroll_parent(c)
		if sp:
			var sr: Rect2 = rect_of(sp)
			if sp.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED and (r.position.x < sr.position.x - TOL or r.end.x > sr.end.x + TOL):
				out.append(_issue("clipped", c, r, "wider than its scroll area (%d..%d, area %d..%d)" % [roundi(r.position.x), roundi(r.end.x), roundi(sr.position.x), roundi(sr.end.x)]))
		else:
			var cp: Control = _clip_parent(c)
			if cp and not rect_of(cp).grow(TOL).encloses(r):
				out.append(_issue("clipped", c, r, "cut by " + short_path(cp)))
		if not view.grow(TOL).encloses(seen):
			out.append(_issue("offscreen", c, seen, "view %dx%d" % [roundi(view.size.x), roundi(view.size.y)]))
		var why: String = ""
		if c is Label:
			why = label_clipped(c)
		elif c is Button:
			why = button_clipped(c)
		elif c is RichTextLabel:
			var rt: RichTextLabel = c
			if not rt.fit_content and not rt.scroll_active and rt.get_content_height() > rt.size.y + 3.0:
				why = "wants %d px tall, has %d" % [rt.get_content_height(), roundi(rt.size.y)]
		if why != "":
			out.append(_issue("clipped", c, r, why))
		var par: Control = c.get_parent() as Control
		if par is Container and not par is ScrollContainer and sp == null:
			# Own sizes, not screen rects: a button that grows a little on focus (UITheme.juice) is fine.
			if c.size.x > par.size.x + TOL or c.size.y > par.size.y + TOL:
				out.append(_issue("overflow", c, r, "%dx%d in a %dx%d %s" % [roundi(c.size.x), roundi(c.size.y), roundi(par.size.x), roundi(par.size.y), par.get_class()]))
	for i: int in items.size():
		var a: Control = items[i]
		var ra: Rect2 = rects[i]
		if ra.size.x <= 0.5 or ra.size.y <= 0.5:
			continue
		for j: int in range(i + 1, items.size()):
			var b: Control = items[j]
			var rb: Rect2 = rects[j]
			if rb.size.x <= 0.5 or rb.size.y <= 0.5 or not ra.intersects(rb):
				continue
			if _is_anc(a, b) or _is_anc(b, a):
				continue
			var x: Rect2 = ra.intersection(rb)
			if minf(x.size.x, x.size.y) < OVERLAP_MIN:
				continue
			if ignore_overlap.is_valid() and bool(ignore_overlap.call(a, b)):
				continue
			var d: Dictionary = _issue("overlap", a, ra, "with %s \"%s\" by %dx%d" % [short_path(b), text_of(b).left(32), roundi(x.size.x), roundi(x.size.y)])
			out.append(d)
	return out


## Every visible control that can take the focus.
static func focusables(roots: Array) -> Array[Control]:
	var out: Array[Control] = []
	for r: Variant in roots:
		if r == null or not is_instance_valid(r):
			continue
		var stack: Array[Node] = [r as Node]
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			if n is CanvasLayer and not (n as CanvasLayer).visible:
				continue
			if n is Control:
				var c: Control = n
				if not c.visible:
					continue
				if c.focus_mode == Control.FOCUS_ALL and _shown(c) and not (c is BaseButton and (c as BaseButton).disabled and false):
					out.append(c)
			for ch: Node in n.get_children():
				stack.append(ch)
	return out


static func _under(roots: Array, c: Node) -> bool:
	for r: Variant in roots:
		if r != null and is_instance_valid(r) and _is_anc(r as Node, c):
			return true
	return false


## The controls the d-pad can reach from `start` (the engine's own neighbour search).
static func reachable(start: Control) -> Array[Control]:
	var seen: Array[Control] = [start]
	var todo: Array[Control] = [start]
	while not todo.is_empty():
		var c: Control = todo.pop_back()
		for side: int in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			var n: Control = c.find_valid_focus_neighbor(side)
			if n and not (n in seen):
				seen.append(n)
				todo.append(n)
	return seen


## Gamepad issues of an open modal screen: the focus must be on a shown control of the screen,
## every focusable control must be reachable with the d-pad, and the focus must be drawn.
## `tab_reach`: controls reached another way on purpose (tab buttons on LB / RB) are passed in.
static func focus(roots: Array, vp: Viewport, other_ways: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Array[Control] = focusables(roots)
	if all.is_empty():
		return out
	var cur: Control = vp.gui_get_focus_owner()
	if cur == null:
		out.append({"kind": "nofocus", "node": short_path(roots[0] as Node), "text": "", "rect": Rect2(), "note": "%d focusable controls, none focused" % all.size()})
		return out
	if not _under(roots, cur) or not _shown(cur):
		out.append(_issue("focus_out", cur, rect_of(cur), "focus is outside the open screen" if _shown(cur) else "focus is on a hidden control"))
		return out
	var got: Array[Control] = reachable(cur)
	for g: Control in got:
		if not _under(roots, g):
			out.append(_issue("focus_out", g, rect_of(g), "the d-pad can leave the screen to here"))
		elif not _shown(g):
			out.append(_issue("focus_out", g, rect_of(g), "the d-pad can land on a hidden control"))
	for c: Control in all:
		if not (c in got) and not (c in other_ways):
			var seen: Rect2 = clip_rect(c, rect_of(c))
			out.append(_issue("unreachable", c, seen, "no d-pad path from " + short_path(cur)))
		if not draws_focus(c):
			out.append(_issue("noring", c, rect_of(c), "focus style draws nothing"))
	return out


## Does the control show that it has the focus? A focus stylebox that draws, or a script that
## draws its own (it sets the meta "own_focus_ring").
static func draws_focus(c: Control) -> bool:
	if c.has_meta("own_focus_ring"):
		return true
	if not c.has_theme_stylebox("focus"):
		return false
	var sb: StyleBox = c.get_theme_stylebox("focus")
	if sb == null or sb is StyleBoxEmpty:
		return false
	if sb is StyleBoxFlat:
		var f: StyleBoxFlat = sb
		var border: bool = f.border_color.a > 0.2 and (f.border_width_left + f.border_width_top + f.border_width_right + f.border_width_bottom) > 0
		return border or (f.draw_center and f.bg_color.a > 0.2)
	return true


static func line(scn: String, cfg: String, d: Dictionary) -> String:
	var r: Rect2 = d["rect"]
	return "[ui-audit] %s %s %s %s \"%s\" at %d,%d %dx%d  %s" % [str(d["kind"]).to_upper(), scn, cfg, d["node"], d["text"], roundi(r.position.x), roundi(r.position.y), roundi(r.size.x), roundi(r.size.y), d["note"]]
