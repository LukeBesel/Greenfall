class_name GardenPlanters
extends Node3D
## What a plant on paving stands in (B41): a slot on a street or the yard pad takes a timber
## planter box, a slot on a sidewalk or a kerb a street-tree pit (a low concrete surround with a
## stake for the young plant). The plant and its soil mound sit on the planter's soil
## (Garden.lift_of), so nothing grows out of the asphalt. One MultiMesh per globe chunk and kind,
## like the plants themselves; an instance is placed the first time its slot holds a plant and
## stays (plants never die).

enum Kind { NONE, BOX, PIT }

## Height (m) of each kind's soil above the ground under the slot (the plant stands on it).
const SOIL_TOP: Array[float] = [0.0, 0.4, 0.17]
## How far each planter reaches below the ground (it never floats on a slope or a kerb).
const SINK_M: float = 0.15
const BOX_HALF: float = 0.72
const BOX_TOP: float = 0.45
const BOARD_T: float = 0.06
const PIT_HALF: float = 0.75
const PIT_TOP: float = 0.22
const PIT_KERB: float = 0.12
const TIMBER := Color(0.56, 0.4, 0.26)
const TIMBER_DARK := Color(0.4, 0.28, 0.18)
const CONCRETE := Color(0.7, 0.68, 0.63)
const SOIL := Color(0.2, 0.14, 0.09)
const BARK := Color(0.42, 0.26, 0.15)
const STAKE := Color(0.66, 0.52, 0.34)
const VISIBLE_M: float = 150.0  # as far as the plants show (Garden's clumps)

var _mms: Dictionary = {}  # "chunk|kind" -> MultiMeshInstance3D
var _at: Dictionary = {}  # slot -> [key, index]
var _meshes: Array[Mesh] = []
var _mat: StandardMaterial3D


## The soil height of a planter kind (0 for open ground).
static func soil_top(kind: int) -> float:
	return SOIL_TOP[clampi(kind, 0, SOIL_TOP.size() - 1)]


## True when slot s has a planter shown.
func has_slot(s: int) -> bool:
	return _at.has(s)


## How many planters stand (tests, the probe).
func count() -> int:
	return _at.size()


## Shows a planter of `kind` under slot s at `xf` (ground point, +Y up, X along the street);
## `cap` is the chunk's slot count (each batch's room). A slot whose kind went to NONE (its town
## came in and it turned out to be open ground) loses its planter.
func place(s: int, kind: int, chunk: Vector2i, cap: int, xf: Transform3D) -> void:
	var key: String = "%d,%d|%d" % [chunk.x, chunk.y, kind]
	if _at.has(s) and str((_at[s] as Array)[0]) != key:
		_hide(s)
	if kind == Kind.NONE:
		return
	if not _at.has(s):
		_at[s] = [key, _grow(key, kind, cap)]
	var info: Array = _at[s]
	(_mms[info[0]] as MultiMeshInstance3D).multimesh.set_instance_transform(int(info[1]), xf)


func _hide(s: int) -> void:
	var info: Array = _at[s]
	var mm: MultiMesh = (_mms[info[0]] as MultiMeshInstance3D).multimesh
	mm.set_instance_transform(int(info[1]), Transform3D(Basis().scaled(Vector3.ONE * 0.0001), mm.get_instance_transform(int(info[1])).origin))
	_at.erase(s)


## The next free instance of a batch, made (or grown) on demand.
func _grow(key: String, kind: int, cap: int) -> int:
	if not _mms.has(key):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh(kind)
		mm.instance_count = maxi(cap, 1)
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material()
		mi.visibility_range_end = VISIBLE_M
		add_child(mi)
		_mms[key] = mi
	var m: MultiMesh = (_mms[key] as MultiMeshInstance3D).multimesh
	var idx: int = m.visible_instance_count
	if idx >= m.instance_count:
		var keep: Array[Transform3D] = []
		for k: int in idx:
			keep.append(m.get_instance_transform(k))
		m.instance_count = maxi(cap, idx + 1)
		for k: int in idx:
			m.set_instance_transform(k, keep[k])
	m.visible_instance_count = idx + 1
	return idx


func _material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.roughness = 0.92
	return _mat


func _mesh(kind: int) -> Mesh:
	if _meshes.is_empty():
		_meshes = [null, box_mesh(), pit_mesh()]
	return _meshes[kind]


## A salvaged timber planter box: four walls of stacked boards, corner posts and a soil fill.
static func box_mesh() -> Mesh:
	var h: float = BOX_TOP + SINK_M
	var cy: float = BOX_TOP - h * 0.5
	var parts: Array = []
	for k: int in 4:
		var rot := Vector3(0, 90.0 * k, 0)
		var b := Basis.from_euler(rot * (PI / 180.0))
		for row: int in 3:
			var ry: float = BOX_TOP - (row + 0.5) * (h / 3.0)
			var col: Color = TIMBER if row % 2 == 0 else TIMBER_DARK
			parts.append(ProcMesh.part(ProcMesh.box(Vector3(BOX_HALF * 2.0, h / 3.0 - 0.01, BOARD_T)),
				Transform3D(b, b * Vector3(0, ry, BOX_HALF - BOARD_T * 0.5)), col))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(0.09, h + 0.03, 0.09)),
			Transform3D(b, b * Vector3(BOX_HALF - 0.03, cy + 0.015, BOX_HALF - 0.03)), TIMBER_DARK))
	var inner: float = (BOX_HALF - BOARD_T) * 2.0
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(inner, 0.08, inner)), ProcMesh.xf(Vector3(0, SOIL_TOP[Kind.BOX] - 0.04, 0)), SOIL))
	return ProcMesh.merge(parts)


## A street-tree pit: a low concrete surround, bark mulch and a timber stake.
static func pit_mesh() -> Mesh:
	var h: float = PIT_TOP + SINK_M
	var cy: float = PIT_TOP - h * 0.5
	var parts: Array = []
	for k: int in 4:
		var b := Basis.from_euler(Vector3(0, 90.0 * k, 0) * (PI / 180.0))
		parts.append(ProcMesh.part(ProcMesh.box(Vector3(PIT_HALF * 2.0 - PIT_KERB, h, PIT_KERB)),
			Transform3D(b, b * Vector3(-PIT_KERB * 0.5, cy, PIT_HALF - PIT_KERB * 0.5)), CONCRETE))
	var inner: float = (PIT_HALF - PIT_KERB) * 2.0
	parts.append(ProcMesh.part(ProcMesh.box(Vector3(inner, 0.06, inner)), ProcMesh.xf(Vector3(0, SOIL_TOP[Kind.PIT] - 0.03, 0)), BARK))
	parts.append(ProcMesh.part(ProcMesh.cyl(0.022, 0.026, 1.25, 6), ProcMesh.xf(Vector3(0.32, SOIL_TOP[Kind.PIT] + 0.5, -0.3), Vector3(0, 0, -4)), STAKE))
	return ProcMesh.merge(parts)
