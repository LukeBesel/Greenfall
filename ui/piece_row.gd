class_name PieceRow
extends Button
## One piece of a look in the Locker's list (ui/lumi_builder.gd). A found piece shows its mark in
## its own colour and its name; pressing it wears it. An unfound piece is a dark silhouette of the
## same mark, named "???" with one hint line: it cannot be pressed into a look (design spec
## section 13). The worn piece carries a stamped bar on its left edge and the word WORN, so
## colour is never the only signal.

const ICON_PX: float = 40.0
const PAD: float = 10.0
const ROW_H: float = 56.0

var piece: String = ""
var found: bool = false
var worn: bool = false

var _tint: Color = FieldPlate.INK
var _slot: String = ""


func _init(p_piece: String, p_found: bool, p_worn: bool, tint: Color) -> void:
	piece = p_piece
	found = p_found
	worn = p_worn
	_tint = tint
	_slot = Looks.slot_of(piece)
	focus_mode = Control.FOCUS_ALL
	custom_minimum_size = Vector2(0, ROW_H)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var accent: Color = FieldPlate.CYAN if found else FieldPlate.INK_DIM
	FieldPlate.key(self, accent, worn)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = ICON_PX + PAD * 2.0
	box.offset_right = -PAD
	box.offset_top = 4
	box.offset_bottom = -4
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var title := FieldPlate.stencil(Looks.display_name(piece), FieldPlate.INK if found else FieldPlate.INK_DIM)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)
	if worn:
		var stamp := FieldPlate.stencil(tr("Worn"), FieldPlate.CYAN)
		stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		head.add_child(stamp)
	if not found:
		var hint := FieldPlate.sentence(tr(Looks.hint(piece)), FieldPlate.INK_DIM)
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(hint)
		custom_minimum_size.y = ROW_H + 44.0
		tooltip_text = tr("Not found yet")


func _draw() -> void:
	var r := Rect2(PAD, (size.y - ICON_PX) * 0.5, ICON_PX, ICON_PX)
	draw_rect(r, FieldPlate.SHADOW if not found else Color(0.06, 0.07, 0.08, 0.9))
	draw_rect(r, FieldPlate.RULE, false, 1.0)
	var c: Color = _tint if found else Color(0.2, 0.22, 0.24)
	_mark(r.grow(-7.0), c)
	if worn:
		draw_rect(Rect2(0, 0, 4, size.y), FieldPlate.CYAN)


## The slot's mark inside `r`: one plain shape per slot, readable as a silhouette.
func _mark(r: Rect2, c: Color) -> void:
	var o: Vector2 = r.position
	var w: float = r.size.x
	var h: float = r.size.y
	var mid: Vector2 = r.get_center()
	match _slot:
		"paint":  # a paint tin with its lid lip
			draw_rect(Rect2(o + Vector2(w * 0.12, h * 0.3), Vector2(w * 0.76, h * 0.66)), c)
			draw_rect(Rect2(o + Vector2(w * 0.04, h * 0.12), Vector2(w * 0.92, h * 0.14)), c)
		"glow":  # a round lens chip
			draw_circle(mid, w * 0.46, c)
			draw_circle(mid, w * 0.24, Color(0, 0, 0, 0.35))
		"pattern":  # slanted bands
			for i: int in 3:
				var x: float = w * (0.02 + 0.33 * i)
				draw_colored_polygon(PackedVector2Array([o + Vector2(x + w * 0.16, 0), o + Vector2(x + w * 0.32, 0), o + Vector2(x + w * 0.16, h), o + Vector2(x, h)]), c)
		"eye_shape":  # two resting eyes
			for sx: float in [0.27, 0.73]:
				draw_arc(o + Vector2(w * sx, h * 0.62), w * 0.19, PI, TAU, 10, c, 4.0)
		"head":  # a fin on a crown
			draw_colored_polygon(PackedVector2Array([o + Vector2(w * 0.5, 0), o + Vector2(w * 0.7, h * 0.62), o + Vector2(w * 0.3, h * 0.62)]), c)
			draw_rect(Rect2(o + Vector2(w * 0.08, h * 0.68), Vector2(w * 0.84, h * 0.3)), c)
		"ears":  # a lens on each side of the head
			draw_rect(Rect2(o + Vector2(w * 0.3, h * 0.2), Vector2(w * 0.4, h * 0.6)), c.darkened(0.45))
			for sx: float in [0.16, 0.84]:
				draw_circle(o + Vector2(w * sx, h * 0.5), w * 0.16, c)
		"shoulders":  # two pads
			for sx: float in [0.02, 0.58]:
				draw_colored_polygon(PackedVector2Array([o + Vector2(w * sx, h * 0.7), o + Vector2(w * (sx + 0.08), h * 0.28), o + Vector2(w * (sx + 0.32), h * 0.28), o + Vector2(w * (sx + 0.4), h * 0.7)]), c)
		"chest":  # a plate with its mark
			draw_rect(Rect2(o + Vector2(w * 0.1, h * 0.08), Vector2(w * 0.8, h * 0.84)), c)
			draw_circle(mid, w * 0.17, Color(0, 0, 0, 0.35))
		"held":  # a claw round a small thing
			draw_arc(mid, w * 0.4, PI * 0.15, PI * 1.85, 14, c, 4.0)
			draw_rect(Rect2(mid - Vector2(w * 0.14, h * 0.14), Vector2(w * 0.28, h * 0.28)), c)
		"hip":  # a pouch on a strap
			draw_rect(Rect2(o + Vector2(0, h * 0.1), Vector2(w, h * 0.12)), c)
			draw_rect(Rect2(o + Vector2(w * 0.22, h * 0.3), Vector2(w * 0.56, h * 0.62)), c)
		_:  # companion: a small thing with wings
			draw_colored_polygon(PackedVector2Array([o + Vector2(0, h * 0.2), o + Vector2(w * 0.44, h * 0.5), o + Vector2(0, h * 0.8)]), c)
			draw_colored_polygon(PackedVector2Array([o + Vector2(w, h * 0.2), o + Vector2(w * 0.56, h * 0.5), o + Vector2(w, h * 0.8)]), c)
			draw_circle(mid, w * 0.12, c)
