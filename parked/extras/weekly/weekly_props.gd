class_name WeeklyProps
extends RefCounted
## [extras] Garden Mode decorations unlocked by Seed of the Week paint chips (data/decor.json
## needs_chips; art/decor_props.gd builds them through here). Colours come from the chips earned.


static func chip_colors() -> Array[Color]:
	var out: Array[Color] = []
	for c: Variant in WeeklyChallenge.chips():
		if c is Dictionary:
			out.append(Color.html(str((c as Dictionary).get("color", "#e8a33d"))))
	if out.is_empty():
		out.append(Color(0.91, 0.64, 0.24))
	return out


## A white pole with a swallow-tail pennant in the newest chip's colour.
static func pennant() -> Node3D:
	var n := Node3D.new()
	var cols: Array[Color] = chip_colors()
	var col: Color = cols[cols.size() - 1]
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.18, 0.22, 0.12, 12), DecorProps.stone(), Vector3(0, 0.06, 0)))
	n.add_child(EggProps.mesh(ProcMesh.cyl(0.025, 0.03, 2.4, 8), DecorProps.paint(Color(0.92, 0.92, 0.9), 0.35, 0.3), Vector3(0, 1.3, 0)))
	n.add_child(EggProps.mesh(ProcMesh.sphere(0.045, 10, 5), DecorProps.paint(Color(0.85, 0.7, 0.35), 0.3, 0.8), Vector3(0, 2.52, 0)))
	var flag := DecorProps.paint(col, 0.6)
	flag.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pm := PrismMesh.new()
	pm.size = Vector3(0.5, 0.9, 0.012)
	n.add_child(EggProps.mesh(pm, flag, Vector3(0.45, 2.15, 0), Vector3(0, 0, -90)))
	return n


## A 2 m arch of painted slats, one stripe per chip.
static func arch() -> Node3D:
	var n := Node3D.new()
	var cols: Array[Color] = chip_colors()
	var white: StandardMaterial3D = DecorProps.paint(Color(0.93, 0.93, 0.9), 0.4)
	for x: float in [-0.85, 0.85]:
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.1, 2.0, 0.1)), white, Vector3(x, 1.0, 0)))
	var k: int = 9
	for i: int in k:
		var a: float = PI * float(i) / float(k - 1)
		var p := Vector3(-cos(a) * 0.85, 2.0 + sin(a) * 0.45, 0)
		var slat: StandardMaterial3D = DecorProps.paint(cols[i % cols.size()], 0.5)
		n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.2, 0.08, 0.3)), slat, p, Vector3(0, 0, rad_to_deg(a) - 90.0)))
	return n
