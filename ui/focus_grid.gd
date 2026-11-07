class_name FocusGrid
extends RefCounted
## [deck] Explicit D-pad neighbours for a grid of cards inside a ScrollContainer. Godot's own
## geometric search misses buttons in other cards of a scrolled grid (the workbench Bots and Hub
## tabs were unreachable with a pad). wire() links every visible, enabled, focusable control
## under `root` to its nearest neighbour in each direction (on-axis distance plus twice the
## off-axis distance), using their laid-out rectangles.


## Signature of the focusable set (rewire only when buttons appear, vanish or enable).
static func signature(root: Control) -> String:
	var parts: PackedStringArray = []
	for c: Control in _focusables(root):
		parts.append("%d" % c.get_instance_id())
	return ",".join(parts)


static func _focusables(root: Control) -> Array[Control]:
	var out: Array[Control] = []
	for n: Node in root.find_children("*", "Control", true, false):
		var c: Control = n as Control
		if c.focus_mode != Control.FOCUS_ALL or not c.is_visible_in_tree() or c.is_queued_for_deletion():
			continue
		if c is BaseButton and (c as BaseButton).disabled:
			continue
		out.append(c)
	return out


## `top_exit` (e.g. a Close button) is the up-neighbour of the top row.
static func wire(root: Control, top_exit: Control = null) -> int:
	var cs: Array[Control] = _focusables(root)
	var dirs: Array = [[SIDE_LEFT, Vector2.LEFT], [SIDE_RIGHT, Vector2.RIGHT], [SIDE_TOP, Vector2.UP], [SIDE_BOTTOM, Vector2.DOWN]]
	for c: Control in cs:
		var rc: Rect2 = c.get_global_rect()
		var p: Vector2 = rc.get_center()
		for d: Array in dirs:
			var dv: Vector2 = d[1]
			var best: Control = null
			var best_s: float = INF
			for o: Control in cs:
				if o == c:
					continue
				var q: Vector2 = o.get_global_rect().get_center() - p
				var along: float = q.dot(dv)
				if along <= 2.0:
					continue
				var off: float = absf(q.dot(Vector2(dv.y, dv.x)))
				var s: float = along + off * 2.0
				if s < best_s:
					best_s = s
					best = o
			if best == null and int(d[0]) == SIDE_TOP and top_exit:
				best = top_exit
			c.set("focus_neighbor_" + ["left", "top", "right", "bottom"][int(d[0])], c.get_path_to(best) if best else NodePath())
	return cs.size()
