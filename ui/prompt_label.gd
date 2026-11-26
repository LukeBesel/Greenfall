class_name PromptLabel
extends HBoxContainer
## [deck] A hint line with live input glyphs: "{ui_tab_prev}{ui_tab_next}  switch tabs   {ui_cancel}  close"
## renders text spans as Labels and every {action} as a PromptGlyph that follows the device in
## use. Use "{kbd:action}" or "{pad:action}" for a token only shown on that device, and
## "[k]...[/k]" / "[p]...[/p]" for text only shown on keyboard / pad. Pseudo-actions: @move,
## @look, @dpad (see PromptGlyph).

var template: String = ""
var font_px: int = 13
var color: Color = UITheme.MUTED
var align_center: bool = false


func _init(p_template: String = "", p_px: int = 13, p_color: Color = UITheme.MUTED) -> void:
	template = p_template
	font_px = p_px
	color = p_color
	add_theme_constant_override("separation", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _ready() -> void:
	if align_center:
		alignment = BoxContainer.ALIGNMENT_CENTER
	Settings.input_device_changed.connect(func(_p: bool) -> void: _rebuild())
	_rebuild()


func set_template(t: String) -> void:
	if t == template and get_child_count() > 0:
		return
	template = t
	if is_inside_tree():
		_rebuild()


## Parses the template for one device into [["text", s] | ["glyph", action]] parts (pure).
static func parse(t: String, pad: bool) -> Array:
	var out: Array = []
	# Device-only text spans first.
	var keep: String = "[p]" if pad else "[k]"
	var drop: String = "[k]" if pad else "[p]"
	var s: String = t
	while drop in s:
		var a: int = s.find(drop)
		var b: int = s.find("[/" + drop.substr(1), a)
		s = s.substr(0, a) + (s.substr(b + 4) if b >= 0 else "")
	s = s.replace(keep, "").replace("[/" + keep.substr(1), "")
	var i: int = 0
	while i < s.length():
		var o: int = s.find("{", i)
		if o < 0:
			out.append(["text", s.substr(i)])
			break
		if o > i:
			out.append(["text", s.substr(i, o - i)])
		var c: int = s.find("}", o)
		if c < 0:
			out.append(["text", s.substr(o)])
			break
		var tok: String = s.substr(o + 1, c - o - 1)
		if tok.begins_with("kbd:"):
			if not pad:
				out.append(["glyph", tok.substr(4)])
		elif tok.begins_with("pad:"):
			if pad:
				out.append(["glyph", tok.substr(4)])
		else:
			out.append(["glyph", tok])
		i = c + 1
	# Merge neighbouring text.
	var merged: Array = []
	for p: Array in out:
		if p[0] == "text" and not merged.is_empty() and merged[-1][0] == "text":
			merged[-1][1] += p[1]
		elif not (p[0] == "text" and str(p[1]) == ""):
			merged.append(p)
	return merged


func _rebuild() -> void:
	for ch: Node in get_children():
		remove_child(ch)
		ch.queue_free()
	for p: Array in parse(template, Settings.last_input_pad):
		if p[0] == "text":
			var l := UITheme.label(str(p[1]), font_px, color)
			l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			add_child(l)
		else:
			var g := PromptGlyph.new(str(p[1]), font_px)
			add_child(g)
