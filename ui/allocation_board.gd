class_name AllocationBoard
extends VBoxContainer
## Clean / Plant / Water juggle for Multibots, with bottleneck hints and presets.

var fleet: Fleet
var world: Node
var _counts: Dictionary = {}
var _hint: Label


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	add_child(UITheme.label("ALLOCATION BOARD   ·   MULTIBOTS", 16, UITheme.CREAM))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	add_child(row)
	for job: String in ["clean", "plant", "water"]:
		var col := VBoxContainer.new()
		row.add_child(col)
		col.add_child(UITheme.label(job.to_upper(), 13, UITheme.MUTED))
		var l := UITheme.label("0", 26, UITheme.CREAM)
		col.add_child(l)
		_counts[job] = l
		var btns := HBoxContainer.new()
		col.add_child(btns)
		for other: String in ["clean", "plant", "water"]:
			if other == job:
				continue
			var b := Button.new()
			b.text = "→ %s" % other
			b.custom_minimum_size = Vector2(80, 34)
			b.pressed.connect(func() -> void:
				if fleet.move_job(job, other):
					Audio.play("click", 1.0, -8.0)
				refresh())
			btns.add_child(b)
	var presets := HBoxContainer.new()
	add_child(presets)
	for p: Array in [["Clean Push", 1.0, 0.0], ["Balanced", 0.5, 0.3], ["Garden Mode", 0.1, 0.45]]:
		var b := Button.new()
		b.text = p[0]
		b.custom_minimum_size = Vector2(120, 36)
		b.pressed.connect(func() -> void:
			fleet.apply_preset(p[1], p[2])
			Audio.play("click", 1.1, -8.0)
			refresh())
		presets.add_child(b)
	_hint = UITheme.label("", 14, UITheme.GOLD)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(_hint)
	refresh()


func refresh() -> void:
	if fleet == null:
		return
	var a: Dictionary = fleet.allocation()
	for job: String in _counts:
		(_counts[job] as Label).text = str(a.get(job, 0))
	# Bottleneck hint: clean ground waiting, or thirsty plants.
	var g: Garden = world.get("garden") if world else null
	if g == null:
		return
	var empty_clean: int = 0
	var thirsty: int = 0
	for s: int in g.slot_species.size():
		if not world.field.is_clean(g.slot_hex[s]):
			continue
		if g.slot_species[s] < 0:
			empty_clean += 1
		elif g.slot_water[s] <= 0.0:
			thirsty += 1
	var lines: Array[String] = []
	if g.unlocked() and empty_clean > 60:
		lines.append("%d clean spots are waiting for planters." % empty_clean)
	if thirsty > 10:
		lines.append("%d plants are thirsty and not growing." % thirsty)
	_hint.text = "\n".join(lines)
