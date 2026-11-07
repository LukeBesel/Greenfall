class_name FarJunk
extends Node3D
## [world2] The planet past this district's field is still covered in trash (owner: "literally the
## entire world is meant to be covered in trash"; the only clear ground is what you or bots pick
## up). Beyond the junk field, out to FAR_R, the open ground (streets, sidewalks, lots; never
## inside buildings) gets a static, non-interactive layer: junk pieces drawn from this district's
## own palette (the models and poses its field uses, biome swaps included) on their light LOD
## meshes, over a sparser paper carpet. Built once; a few dozen MultiMeshes in four quadrants.
## Out there a scoop finds nothing: the first time Lumi wanders past the field edge, WREN says
## why (the district's survey line; other districts are reached by rocket).

const FAR_R: float = 125.0
const JUNK_PER_M2: float = 0.45
const LITTER_PER_M2: float = 4.0
const MODELS: int = 12

var field: HexField
var layout: CityLayout
var inner_r: float = 0.0
var pieces: int = 0
var litter: int = 0
var _told: bool = false
var _t: float = 0.0
var world: Node


func build(p_field: HexField) -> void:
	field = p_field
	layout = field.layout
	inner_r = 0.0
	for h: int in field.hex_count():
		inner_r = maxf(inner_r, Vector2(field.hex_center(h).x, field.hex_center(h).z).length())
	inner_r += field.hex_size * 0.6
	var rng := RandomNumberGenerator.new()
	rng.seed = field.seed_value + 60606
	# The district's palette: the most common (model, pose) pairs of its land junk.
	var counts: Dictionary = {}
	for pid: int in field.piece_count():
		if field.is_water(field.piece_hex[pid]):
			continue
		var k: String = field.piece_model[pid]
		counts[k] = int(counts.get(k, 0)) + 1
	var models: Array = counts.keys()
	models.sort_custom(func(a: String, b: String) -> bool: return int(counts[a]) > int(counts[b]))
	models = models.slice(0, MODELS)
	if models.is_empty():
		return
	var wsum: float = 0.0
	for m: String in models:
		wsum += float(counts[m])
	var groups: Dictionary = {}  # "q|model" -> Array[Transform3D]
	var lgroups: Dictionary = {}  # quadrant -> [Array[Transform3D], Array[Color]]
	var area: float = PI * (FAR_R * FAR_R - inner_r * inner_r)
	var n_junk: int = int(area * JUNK_PER_M2)
	var n_lit: int = int(area * LITTER_PER_M2)
	for k: int in n_junk + n_lit:
		var ang: float = rng.randf() * TAU
		var r: float = sqrt(lerpf(inner_r * inner_r, FAR_R * FAR_R, rng.randf()))
		var p := Vector3(cos(ang) * r, 0.0, sin(ang) * r)
		if not _open(p):
			continue
		var q: int = (1 if p.x > 0.0 else 0) + (2 if p.z > 0.0 else 0)
		p.y = layout.height_at(p.x, p.z) if layout else 0.0
		if k < n_junk:
			var x: float = rng.randf() * wsum
			var model: String = models[0]
			for m: String in models:
				x -= float(counts[m])
				if x <= 0.0:
					model = m
					break
			var key: String = "%d|%s" % [q, model]
			if not groups.has(key):
				groups[key] = []
			(groups[key] as Array).append(_pose(model, rng, p))
			pieces += 1
		else:
			if not lgroups.has(q):
				lgroups[q] = [[], []]
			var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.FORWARD, rng.randf_range(-0.2, 0.2))
			(lgroups[q][0] as Array).append(Transform3D(b.scaled(Vector3.ONE * rng.randf_range(0.8, 1.5)), p + Vector3(0, 0.01, 0)))
			var c: Color = [Color(0.8, 0.77, 0.68), Color(0.62, 0.5, 0.36), Color(0.5, 0.48, 0.45), Color(0.15, 0.15, 0.16), Color(0.7, 0.6, 0.35)][rng.randi() % 5]
			(lgroups[q][1] as Array).append(c.lerp(Color(0.48, 0.43, 0.37), rng.randf_range(0.2, 0.5)))
			litter += 1
	var tris: Array[int] = [80, 120, 180, 240]
	for key: String in groups:
		var model: String = key.get_slice("|", 1)
		var xfs: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = JunkLod.far_mesh(model, tris[clampi(Settings.quality, 0, 3)])
		mm.instance_count = xfs.size()
		for i: int in xfs.size():
			mm.set_instance_transform(i, xfs[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Far_" + key.replace("|", "_")
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = 190.0
		mmi.set_meta("inst_xf", xfs)
		add_child(mmi)
	var paper: Mesh = LitterView._crumple(Vector2(0.4, 0.3), 1, 0.05, rng, Color.WHITE)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.9
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for q: int in lgroups:
		var xfs2: Array = lgroups[q][0]
		var cols: Array = lgroups[q][1]
		var mm2 := MultiMesh.new()
		mm2.transform_format = MultiMesh.TRANSFORM_3D
		mm2.use_colors = true
		mm2.mesh = paper
		mm2.instance_count = xfs2.size()
		for i: int in xfs2.size():
			mm2.set_instance_transform(i, xfs2[i])
			mm2.set_instance_color(i, cols[i])
		var mmi2 := MultiMeshInstance3D.new()
		mmi2.name = "FarLitter%d" % q
		mmi2.multimesh = mm2
		mmi2.material_override = mat
		mmi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi2.visibility_range_end = 150.0
		add_child(mmi2)
	print("[farjunk] %d pieces + %d litter from %.0f to %.0f m (%d models)" % [pieces, litter, inner_r, FAR_R, models.size()])


## Open ground outside the field: not in a field hex (warped), not a building or the yard.
func _open(p: Vector3) -> bool:
	if field.hex_at(p) >= 0 or field.owner_hex(p) >= 0:
		return false
	if layout:
		var s: int = layout.surface_at(p.x, p.z)
		if s == CityLayout.Surface.BUILDING or s == CityLayout.Surface.YARD:
			return false
		if not layout.wild:
			# Not hard against a wall (kit pieces stick out of the footprint a little).
			for o: Vector2 in [Vector2(0.5, 0), Vector2(-0.5, 0), Vector2(0, 0.5), Vector2(0, -0.5)]:
				if layout.surface_at(p.x + o.x, p.z + o.y) == CityLayout.Surface.BUILDING:
					return false
	return true


func _pose(model: String, rng: RandomNumberGenerator, p: Vector3) -> Transform3D:
	var b := Basis(Vector3.UP, rng.randf() * TAU)
	if rng.randf() < 0.5:
		b = b * Basis(Vector3.RIGHT if rng.randf() < 0.5 else Vector3.FORWARD, PI * 0.5)
	b = b * Basis(Vector3.RIGHT, rng.randf_range(-0.12, 0.12))
	b = b.scaled(Vector3.ONE * rng.randf_range(0.9, 1.1))
	var aabb: AABB = AssetLib.model_aabb(model)
	var min_y: float = INF
	for i: int in 8:
		min_y = minf(min_y, (b * aabb.get_endpoint(i)).y)
	return Transform3D(b, p + Vector3(0, -min_y - 0.01, 0))


## The first walk past the survey line: one line from WREN about why the scoop finds nothing here.
func _process(delta: float) -> void:
	if _told or world == null or world.get("patch") == null:
		return
	_t += delta
	if _t < 1.0:
		return
	_t = 0.0
	var pp: Vector3 = (world.patch as Node3D).global_position
	if Vector2(pp.x, pp.z).length() > inner_r + 4.0:
		_told = true
		if not bool(GameState.flags.get("far_junk_told", false)):
			GameState.flags["far_junk_told"] = true
			EventBus.toast.emit(tr("Past the survey line the junk runs too deep to start on. One district at a time: clean this one, then the rockets take us to the next."), "story")
