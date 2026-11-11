class_name RigParts
extends RefCounted
## How a fitted rig module shows on Lumi (systems/rigs.gd; design spec section 7). A module's
## `part` in the planet's rig table names one of the shapes built here and its paint; the shape
## decides where it mounts: on the right wrist (arm tools) or on the body (chest and drive gear).
## Every shape is salvaged equipment bolted on: painted housings, bare steel, rubber hose.
##
## Rig parts are function, not looks. They hang on their own mounts and take no Locker slot, so a
## look never hides a tool and a tool never replaces a found piece.
##
## Use: var nodes: Array[Node3D] = RigParts.attach(model, [{id, slot, shape, color}])

const MOUNT_WRIST: String = "wrist"
const MOUNT_BODY: String = "body"
const META_MODULE: String = "module"
const SEGMENTS: int = 20
## Shape -> where it mounts. A shape not listed here is not shown.
const MOUNTS: Dictionary = {
	"cutter": MOUNT_WRIST, "fan": MOUNT_WRIST, "boom": MOUNT_WRIST, "paddle": MOUNT_WRIST,
	"hold": MOUNT_BODY, "rails": MOUNT_BODY, "drum": MOUNT_BODY, "tray": MOUNT_BODY,
	"coils": MOUNT_BODY, "skirt": MOUNT_BODY, "hitch": MOUNT_BODY, "doser": MOUNT_BODY, "mast": MOUNT_BODY,
}
const DARK := Color(0.11, 0.12, 0.14)
const CREAM := Color(0.9, 0.88, 0.8)


static func shapes() -> Array[String]:
	var out: Array[String] = []
	out.assign(MOUNTS.keys())
	return out


## Builds each part and hangs it on the model. Returns the part roots (meta "module" = module id).
static func attach(model: PatchModel, parts: Array[Dictionary]) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for part: Dictionary in parts:
		var shape: String = str(part.get("shape", ""))
		if not MOUNTS.has(shape):
			continue
		var mount: Node3D = model.rig_mount(str(MOUNTS[shape]))
		if mount == null:
			continue
		var root: Node3D = build(shape, part.get("color", Color(0.7, 0.7, 0.7)))
		root.name = "Rig_" + str(part.get("id", shape))
		root.set_meta(META_MODULE, str(part.get("id", "")))
		mount.add_child(root)
		out.append(root)
	return out


## One part, at its place in its mount's space (the wrist points down -Z; the body faces -Z).
static func build(shape: String, color: Color) -> Node3D:
	var root := Node3D.new()
	var paint: Material = Mats.worn_paint(color, 0.86, 0.3, float(shape.hash() % 97), 0.45)
	var steel: Material = Mats.metal("steel")
	var dark: Material = Mats.worn_paint(DARK, 0.8, 0.2, 5.0, 0.5)
	var rubber: Material = Mats.rubber()
	match shape:
		"cutter": _cutter(root, paint, steel, dark)
		"fan": _fan(root, paint, steel, dark)
		"boom": _boom(root, paint, steel, dark)
		"paddle": _paddle(root, paint, steel)
		"hold": _hold(root, paint, steel, dark)
		"rails": _rails(root, paint, steel)
		"drum": _drum(root, paint, steel, rubber)
		"tray": _tray(root, paint, steel, dark)
		"coils": _coils(root, paint, dark)
		"skirt": _skirt(root, paint, steel, rubber)
		"hitch": _hitch(root, paint, steel)
		"doser": _doser(root, paint, steel, rubber)
		"mast": _mast(root, paint, steel, color)
	return root


# --- Arm tools (wrist space) --------------------------------------------------------------------

## A motor housing over the wrist, a guarded cutting disc ahead of the claws.
static func _cutter(root: Node3D, paint: Material, steel: Material, dark: Material) -> void:
	_add(root, ProcMesh.rounded_box(Vector3(0.085, 0.07, 0.15), 0.014), paint, Vector3(0, 0.085, -0.03))
	_add(root, ProcMesh.cyl(0.105, 0.105, 0.008, SEGMENTS), steel, Vector3(0, 0.085, -0.22), Vector3(0, 0, 90))
	_add(root, ProcMesh.cyl(0.026, 0.026, 0.03, 12), dark, Vector3(0, 0.085, -0.22), Vector3(0, 0, 90))
	_add(root, ProcMesh.rounded_box(Vector3(0.03, 0.045, 0.2), 0.01), paint, Vector3(0, 0.185, -0.19))
	_add(root, ProcMesh.box(Vector3(0.012, 0.03, 0.06)), dark, Vector3(0, 0.125, -0.07))


## A broad, flat intake with slats.
static func _fan(root: Node3D, paint: Material, steel: Material, dark: Material) -> void:
	_add(root, ProcMesh.rounded_box(Vector3(0.1, 0.06, 0.1), 0.014), paint, Vector3(0, 0.08, -0.02))
	_add(root, ProcMesh.rounded_box(Vector3(0.42, 0.05, 0.11), 0.014), paint, Vector3(0, 0.08, -0.14))
	for i: int in 6:
		_add(root, ProcMesh.box(Vector3(0.008, 0.036, 0.02)), dark, Vector3(-0.17 + 0.068 * float(i), 0.08, -0.198))
	_add(root, ProcMesh.box(Vector3(0.43, 0.008, 0.012)), steel, Vector3(0, 0.108, -0.19))


## A telescoping boom: three sleeves, a small head at the far end.
static func _boom(root: Node3D, paint: Material, steel: Material, dark: Material) -> void:
	_add(root, ProcMesh.cyl(0.032, 0.032, 0.16, 14), paint, Vector3(0, 0.085, -0.04), Vector3(90, 0, 0))
	_add(root, ProcMesh.cyl(0.024, 0.024, 0.2, 14), steel, Vector3(0, 0.085, -0.2), Vector3(90, 0, 0))
	_add(root, ProcMesh.cyl(0.017, 0.017, 0.2, 14), paint, Vector3(0, 0.085, -0.38), Vector3(90, 0, 0))
	_add(root, ProcMesh.rounded_box(Vector3(0.06, 0.045, 0.05), 0.01), dark, Vector3(0, 0.085, -0.5))
	_add(root, ProcMesh.cyl(0.036, 0.036, 0.012, 14), dark, Vector3(0, 0.085, -0.12), Vector3(90, 0, 0))


## A signal paddle on a short stem, held out ahead of the claw where robots can see it.
static func _paddle(root: Node3D, paint: Material, steel: Material) -> void:
	_add(root, ProcMesh.rounded_box(Vector3(0.06, 0.05, 0.08), 0.012), paint, Vector3(0, 0.08, -0.01))
	_add(root, ProcMesh.cyl(0.012, 0.012, 0.26, 10), steel, Vector3(0, 0.085, -0.17), Vector3(90, 0, 0))
	_add(root, ProcMesh.cyl(0.13, 0.13, 0.016, SEGMENTS), paint, Vector3(0, 0.085, -0.42), Vector3(0, 0, 90))
	_add(root, ProcMesh.cyl(0.07, 0.07, 0.02, SEGMENTS), Mats.worn_paint(CREAM, 0.9, 0.2, 3.0, 0.4), Vector3(0, 0.085, -0.42), Vector3(0, 0, 90))


# --- Chest gear (body space) --------------------------------------------------------------------

## A second hopper slung under the chest plate on two straps.
static func _hold(root: Node3D, paint: Material, steel: Material, dark: Material) -> void:
	_add(root, ProcMesh.rounded_box(Vector3(0.36, 0.15, 0.13), 0.025), paint, Vector3(0, 0.24, -0.285))
	_add(root, ProcMesh.box(Vector3(0.3, 0.012, 0.1)), dark, Vector3(0, 0.318, -0.285))
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.box(Vector3(0.026, 0.2, 0.01)), steel, Vector3(0.13 * sx, 0.3, -0.352))
		_add(root, ProcMesh.cyl(0.012, 0.012, 0.014, 8), steel, Vector3(0.13 * sx, 0.24, -0.356), Vector3(90, 0, 0))


## Two stiff press rails either side of the chest plate, tied by cross bars.
static func _rails(root: Node3D, paint: Material, steel: Material) -> void:
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.rounded_box(Vector3(0.05, 0.34, 0.08), 0.012), paint, Vector3(0.2 * sx, 0.38, -0.27))
		for y: float in [0.27, 0.49]:
			_add(root, ProcMesh.cyl(0.016, 0.016, 0.02, 8), steel, Vector3(0.2 * sx, y, -0.315), Vector3(90, 0, 0))
	_add(root, ProcMesh.rounded_box(Vector3(0.46, 0.045, 0.04), 0.01), paint, Vector3(0, 0.225, -0.3))
	_add(root, ProcMesh.box(Vector3(0.44, 0.028, 0.024)), steel, Vector3(0, 0.545, -0.29))


## A filter drum across the front with a spray bar under it and a hose to the can.
static func _drum(root: Node3D, paint: Material, steel: Material, rubber: Material) -> void:
	_add(root, ProcMesh.cyl(0.075, 0.075, 0.34, SEGMENTS), paint, Vector3(0, 0.25, -0.3), Vector3(0, 0, 90))
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.cyl(0.08, 0.08, 0.02, SEGMENTS), steel, Vector3(0.16 * sx, 0.25, -0.3), Vector3(0, 0, 90))
	_add(root, ProcMesh.cyl(0.011, 0.011, 0.4, 8), steel, Vector3(0, 0.16, -0.34), Vector3(0, 0, 90))
	for i: int in 4:
		_add(root, ProcMesh.cyl(0.012, 0.006, 0.03, 8), steel, Vector3(-0.15 + 0.1 * float(i), 0.145, -0.352), Vector3(60, 0, 0))
	_add(root, ProcMesh.cyl(0.014, 0.014, 0.2, 8), rubber, Vector3(0.2, 0.3, -0.25), Vector3(20, 0, -20))


## A slanted sorting tray with rims and a row of dividers.
static func _tray(root: Node3D, paint: Material, steel: Material, dark: Material) -> void:
	var tilt := Vector3(28, 0, 0)
	_add(root, ProcMesh.box(Vector3(0.36, 0.016, 0.16)), paint, Vector3(0, 0.25, -0.31), tilt)
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.box(Vector3(0.016, 0.05, 0.16)), paint, Vector3(0.18 * sx, 0.265, -0.317), tilt)
	for i: int in 3:
		_add(root, ProcMesh.box(Vector3(0.008, 0.03, 0.15)), dark, Vector3(-0.09 + 0.09 * float(i), 0.262, -0.316), tilt)
	_add(root, ProcMesh.box(Vector3(0.38, 0.02, 0.02)), steel, Vector3(0, 0.2, -0.385))


# --- Drive gear (body space) --------------------------------------------------------------------

## Rewound coils stacked round the hover pod.
static func _coils(root: Node3D, paint: Material, dark: Material) -> void:
	for i: int in 3:
		_add(root, ProcMesh.torus(0.235, 0.275, 28, 8), paint, Vector3(0, 0.07 + 0.05 * float(i), 0))
	for k: int in 4:
		var a: float = TAU * (float(k) + 0.5) / 4.0
		_add(root, ProcMesh.box(Vector3(0.03, 0.16, 0.03)), dark, Vector3(cos(a) * 0.275, 0.12, sin(a) * 0.275))


## A flared float skirt with a skimming lip at the front.
static func _skirt(root: Node3D, paint: Material, steel: Material, rubber: Material) -> void:
	_add(root, ProcMesh.cyl(0.25, 0.4, 0.13, 28), paint, Vector3(0, 0.085, 0))
	_add(root, ProcMesh.torus(0.385, 0.42, 28, 8), rubber, Vector3(0, 0.022, 0))
	_add(root, ProcMesh.torus(0.235, 0.262, 28, 8), steel, Vector3(0, 0.15, 0))
	_add(root, ProcMesh.box(Vector3(0.46, 0.012, 0.1)), steel, Vector3(0, 0.03, -0.43), Vector3(-14, 0, 0))


## A bale rack off the back: two arms, a cross bar and an upright stop.
static func _hitch(root: Node3D, paint: Material, steel: Material) -> void:
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.box(Vector3(0.03, 0.03, 0.3)), paint, Vector3(0.15 * sx, 0.2, 0.36))
		_add(root, ProcMesh.box(Vector3(0.026, 0.2, 0.026)), paint, Vector3(0.15 * sx, 0.29, 0.5))
	_add(root, ProcMesh.box(Vector3(0.34, 0.03, 0.03)), steel, Vector3(0, 0.2, 0.5))
	_add(root, ProcMesh.box(Vector3(0.34, 0.024, 0.024)), steel, Vector3(0, 0.385, 0.5))
	_add(root, ProcMesh.box(Vector3(0.3, 0.01, 0.26)), steel, Vector3(0, 0.183, 0.37))


## A dosing bar under the front of the hover ring, fed by two small tanks.
static func _doser(root: Node3D, paint: Material, steel: Material, rubber: Material) -> void:
	_add(root, ProcMesh.cyl(0.014, 0.014, 0.62, 8), steel, Vector3(0, 0.07, -0.3), Vector3(0, 0, 90))
	for i: int in 6:
		_add(root, ProcMesh.cyl(0.012, 0.005, 0.045, 8), steel, Vector3(-0.25 + 0.1 * float(i), 0.045, -0.3))
	for sx: float in [-1.0, 1.0]:
		_add(root, ProcMesh.capsule(0.055, 0.2), paint, Vector3(0.3 * sx, 0.16, -0.12), Vector3(90, 0, 0))
		_add(root, ProcMesh.cyl(0.011, 0.011, 0.17, 8), rubber, Vector3(0.3 * sx, 0.11, -0.25), Vector3(60, 0, 0))
		_add(root, ProcMesh.box(Vector3(0.012, 0.03, 0.1)), steel, Vector3(0.3 * sx, 0.215, -0.12))


## A tall relay mast up the back with cross arms and a lit tip.
static func _mast(root: Node3D, paint: Material, steel: Material, color: Color) -> void:
	_add(root, ProcMesh.rounded_box(Vector3(0.09, 0.1, 0.07), 0.014), paint, Vector3(-0.2, 0.3, 0.27))
	_add(root, ProcMesh.cyl(0.011, 0.016, 1.3, 10), steel, Vector3(-0.2, 0.98, 0.27))
	for y: float in [1.3, 1.45]:
		_add(root, ProcMesh.cyl(0.006, 0.006, 0.26 - (y - 1.3) * 0.6, 8), steel, Vector3(-0.2, y, 0.27), Vector3(0, 0, 90))
	_add(root, ProcMesh.cyl(0.07, 0.02, 0.03, 16), paint, Vector3(-0.2, 1.56, 0.27))
	_add(root, ProcMesh.sphere(0.022, 10, 6), Mats.lamp(color.lightened(0.2), 2.5), Vector3(-0.2, 1.65, 0.27))


static func _add(root: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.layers = 1 | PatchModel.HERO_LAYER
	root.add_child(mi)
