class_name RangeBoost
extends RefCounted
## [vqa] Overhead views (Command view) look at the whole district from up to ~240 m, past the
## visibility ranges tuned for the play camera (junk 110 m, plants 120 m, props 160 m...), so whole
## junk chunks and gardens vanished as the player zoomed out. While such a view is open the ranges
## are lifted to `min_end`; closing restores them. Ground litter (tiny items, 150k instances) and
## Label3D tags keep their ranges: they are sub-pixel from up there.

var _saved: Dictionary = {}  # GeometryInstance3D -> original visibility_range_end


func boost(root: Node, min_end: float) -> void:
	restore()
	if root == null:
		return
	for n: Node in root.find_children("*", "GeometryInstance3D", true, false):
		var g: GeometryInstance3D = n as GeometryInstance3D
		if g is Label3D or g.visibility_range_end <= 0.0 or g.visibility_range_end >= min_end or _skip(g):
			continue
		_saved[g] = g.visibility_range_end
		g.visibility_range_end = min_end


func restore() -> void:
	for g: Variant in _saved:
		if is_instance_valid(g):
			(g as GeometryInstance3D).visibility_range_end = float(_saved[g])
	_saved.clear()


static func _skip(g: Node) -> bool:
	var p: Node = g.get_parent()
	while p:
		if p is LitterView:
			return true
		p = p.get_parent()
	return false
