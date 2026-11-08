class_name EggDisplay
extends Node3D
## [eggs2] A small self-contained display at the base for a collectible egg (EggCollect): a low
## garden bed with a hand-painted sign and one slot per part. Collected parts stand in their slot;
## missing ones show an empty peg. When the set is complete, `salute()` plays the egg's finale
## (the gnomes turn to face Lumi and hop). Reusable: pass the egg id, part count, a title and a
## Callable(part: int) -> Node3D that builds one part's figure.

## Where the Gnome Patrol bed stands: the back fence, left of the depot, clear of the rocket pad,
## the wind tower, the observatory and the depot (>= 3 m from every yard interactable).
const GNOME_POS := Vector3(-2.6, 0.0, -7.6)

var egg_id: String = ""
var total: int = 5
var figures: Array[Node3D] = []
var _pegs: Array[Node3D] = []
var _builder: Callable


static func make(id: String, n_parts: int, title: String, builder: Callable, spacing: float = 0.42) -> EggDisplay:
	var d := EggDisplay.new()
	d.name = "EggDisplay_" + id
	d.egg_id = id
	d.total = n_parts
	d._builder = builder
	d._build(title, spacing)
	d.refresh()
	return d


func _build(title: String, spacing: float) -> void:
	var w: float = spacing * total + 0.35
	var wood: StandardMaterial3D = DecorProps.wood(Color(0.55, 0.38, 0.24))
	var dark: StandardMaterial3D = DecorProps.wood(Color(0.36, 0.25, 0.16))
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.2, 0.14, 0.1)
	soil.roughness = 0.95
	# Raised bed: four planks round a strip of soil, a little moss.
	add_child(EggProps.mesh(ProcMesh.box(Vector3(w, 0.16, 0.06)), wood, Vector3(0, 0.08, 0.27)))
	add_child(EggProps.mesh(ProcMesh.box(Vector3(w, 0.16, 0.06)), wood, Vector3(0, 0.08, -0.27)))
	for s: float in [-1.0, 1.0]:
		add_child(EggProps.mesh(ProcMesh.box(Vector3(0.06, 0.16, 0.6)), dark, Vector3(s * (w * 0.5 - 0.03), 0.08, 0)))
	add_child(EggProps.mesh(ProcMesh.box(Vector3(w - 0.1, 0.1, 0.5)), soil, Vector3(0, 0.07, 0)))
	var moss := StandardMaterial3D.new()
	moss.albedo_color = Color(0.32, 0.45, 0.2)
	moss.roughness = 0.9
	for k: int in 4:
		add_child(EggProps.mesh(ProcMesh.sphere(0.07, 8, 4), moss, Vector3(-w * 0.4 + k * w * 0.27, 0.12, 0.17 - (k % 2) * 0.3), Vector3.ZERO, Vector3(1.4, 0.35, 1.0)))
	# Sign on a stake behind the bed.
	add_child(EggProps.mesh(ProcMesh.box(Vector3(0.05, 0.75, 0.05)), dark, Vector3(0, 0.37, -0.36)))
	add_child(EggProps.mesh(ProcMesh.box(Vector3(0.78, 0.22, 0.03)), Mats.worn_paint(Color(0.9, 0.86, 0.72), 0.85, 0.2, 5.0, 0.4), Vector3(0, 0.7, -0.34)))
	var l: Label3D = EggProps.label(title, 30, Color(0.25, 0.18, 0.12), Vector3(0, 0.7, -0.32))
	add_child(l)
	var cnt: Label3D = EggProps.label("", 22, Color(0.3, 0.22, 0.15), Vector3(0, 0.62, -0.32))
	cnt.name = "Count"
	add_child(cnt)
	l.position.y = 0.73
	for i: int in total:
		var x: float = (i - (total - 1) * 0.5) * spacing
		var peg := EggProps.mesh(ProcMesh.cyl(0.05, 0.06, 0.04, 10), DecorProps.wood(Color(0.62, 0.5, 0.35)), Vector3(x, 0.13, 0.02))
		add_child(peg)
		_pegs.append(peg)
		var f: Node3D = _builder.call(i) if _builder.is_valid() else Node3D.new()
		f.name = "Figure%d" % i
		f.position = Vector3(x, 0.14, 0.02)
		f.scale = Vector3.ONE * 0.9
		add_child(f)
		figures.append(f)
	EggProps.collider(self, Vector3(w, 0.3, 0.6), Vector3(0, 0.15, 0))


## Shows the figures that have been collected.
func refresh() -> void:
	var have: Array = EggCollect.parts(egg_id)
	var n: int = 0
	for i: int in figures.size():
		var on: bool = i in have
		figures[i].visible = on
		n += 1 if on else 0
	var cnt: Label3D = get_node_or_null("Count")
	if cnt:
		cnt.text = "%d / %d" % [n, total]


## A collected figure pops into its slot.
func pop_in(part: int) -> void:
	refresh()
	if part < 0 or part >= figures.size():
		return
	var f: Node3D = figures[part]
	f.scale = Vector3.ONE * 0.1
	var tw := f.create_tween()
	tw.tween_property(f, "scale", Vector3.ONE * 0.9, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if is_inside_tree():
		Vfx.burst("sparkle", f.global_position + Vector3(0, 0.4, 0), Color(1.0, 0.9, 0.6), 0.5)


## The finale: every figure turns, very slowly, to face `look_at_pos`, then hops (a salute).
func salute(look_at_pos: Vector3) -> void:
	for i: int in figures.size():
		var g: Node3D = figures[i]
		if not g.visible:
			continue
		var to: Vector3 = look_at_pos - g.global_position if is_inside_tree() else Vector3(0, 0, 1)
		var want: float = atan2(to.x, to.z) - global_rotation.y if is_inside_tree() else 0.0
		var tw := g.create_tween()
		tw.tween_interval(0.15 * i)
		tw.tween_property(g, "rotation:y", want, 1.2).set_trans(Tween.TRANS_SINE)
		tw.tween_callback(func() -> void:
			var a: Node3D = g.get_node_or_null("Anim")
			if a == null:
				return
			var y0: float = a.position.y
			var t2 := a.create_tween()
			t2.tween_property(a, "position:y", y0 + 0.18, 0.15).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
			t2.tween_property(a, "position:y", y0, 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			t2.parallel().tween_property(a, "rotation_degrees:x", -12.0, 0.15)
			t2.tween_property(a, "rotation_degrees:x", 0.0, 0.3))
	if is_inside_tree():
		Vfx.burst("sparkle", global_position + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.5), 1.0)
		Audio.play("chime", 1.4, -8.0)
