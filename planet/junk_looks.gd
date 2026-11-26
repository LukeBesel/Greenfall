class_name JunkLooks
extends RefCounted
## [art3] How a junk piece LOOKS (the art overhaul's junk part; data/junk_looks.json). Nothing here
## changes what a piece is: its model id, type, volume, place, seat and pose stay SphereField's. A
## "look" is only the mesh and material the view draws for it:
## - a junk model can show as a piece of the junk kit (art/models/junk/junk_kit.glb, built by
##   build_junk.py: CRT monitor, open PC case, keyboard, boxes, a crate of parts, ...) for a share
##   of its pieces, fitted into the model's own box so it sits where the model sat;
## - every piece, scan or kit, is drawn with art/shaders/junk_piece.gdshader: aged colour, dirt
##   climbing from the ground, a damp band and contact darkening at its base (junk_far.gdshader
##   in the far band).
## A look id is "" (the model itself) or "<model>#<k>" (the model's k-th kit variant).

const DATA: String = "res://data/junk_looks.json"
const MAX_SIZE: float = 0.5  # metres (size as StartArea.junk_props measures it) a small model's look may reach
const KIT: String = "res://art/models/junk/junk_kit.glb"
const KIT_TEX: String = "res://art/models/junk/junk_kit_%s.png"
const PIECE_SHADER: String = "res://art/shaders/junk_piece.gdshader"
const FAR_SHADER: String = "res://art/shaders/junk_far.gdshader"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _kit: Dictionary = {}       # "<name>_lod0" -> Mesh (as exported)
static var _fit: Dictionary = {}       # "look id|lod" -> Mesh fitted into its host's box
static var _fit_box: Dictionary = {}   # look id -> AABB of the fitted lod0
static var _mats: Dictionary = {}      # key -> ShaderMaterial
static var _near: Dictionary = {}      # "model@tris" -> Mesh (scan with the piece material)
static var _piece_shader: Shader
static var _far_shader: Shader


static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		_data = Economy.read_json(DATA) if FileAccess.file_exists(DATA) else {}
		if DevHooks.has("no-junk-looks"):  # A/B: the scans as they were
			_data = {}
	return _data


static func enabled() -> bool:
	return not data().is_empty()


## The kit variants of a model: Array of {mesh, share, rot?, scale?, flat?}.
static func variants(model: String) -> Array:
	return (data().get("looks", {}) as Dictionary).get(model, [])


## The look of one piece: `key` is any number that stays the same for the piece from run to run
## (the view uses cell * 4096 + its index in the cell).
static func pick(model: String, key: int) -> String:
	var vs: Array = variants(model)
	if vs.is_empty():
		return ""
	var r: float = float(hash([model, key, 9173]) % 100000) / 100000.0
	for k: int in vs.size():
		r -= float((vs[k] as Dictionary).get("share", 0.0))
		if r < 0.0:
			return "%s#%d" % [model, k]
	return ""


static func host(look: String) -> String:
	return look.get_slice("#", 0)


static func spec(look: String) -> Dictionary:
	if not look.contains("#"):
		return {}
	var vs: Array = variants(host(look))
	var k: int = int(look.get_slice("#", 1))
	return vs[k] if k < vs.size() else {}


## True for a look that should never stand on its side (a keyboard, a paper pile): the view
## lays a "lying" piece of it flat again.
static func is_flat(look: String) -> bool:
	return bool(spec(look).get("flat", false))


## Every look id the field can show (for warm-up behind the loading screen).
static func all_looks() -> PackedStringArray:
	var out := PackedStringArray()
	for model: String in data().get("looks", {}):
		for k: int in variants(model).size():
			out.append("%s#%d" % [model, k])
	return out


static func kit_mesh(name: String, lod: int) -> Mesh:
	if _kit.is_empty():
		var ps: PackedScene = load(KIT) if ResourceLoader.exists(KIT) else null
		if ps:
			var root: Node = ps.instantiate()
			for n: Node in root.find_children("*", "MeshInstance3D", true, false):
				_kit[String(n.name)] = (n as MeshInstance3D).mesh
			root.free()
		_kit["_"] = null
	return _kit.get("%s_lod%d" % [name, lod])


## Behind the loading screen: the kit and its maps on a loader thread.
static func fetch() -> void:
	if not enabled():
		return
	var keep: Array = [await BuildBudget.fetch(KIT)]
	for t: String in ["albedo", "orm", "normal"]:
		keep.append(await BuildBudget.fetch(KIT_TEX % t))
	kit_mesh("", 0)
	_kit_material("", AABB())
	keep.clear()


## A kit variant fitted into its host model's box: turned (rot, degrees), scaled to fit (times
## `scale`), its base on the host's base and centred where the host is centred, so the piece's own
## transform and seat hold. lod 0 near, 1 far.
static func look_mesh(look: String, lod: int) -> Mesh:
	var key: String = "%s|%d" % [look, lod]
	if _fit.has(key):
		return _fit[key]
	var sp: Dictionary = spec(look)
	var src0: Mesh = kit_mesh(str(sp.get("mesh", "")), 0)
	var src: Mesh = kit_mesh(str(sp.get("mesh", "")), lod)
	if src0 == null or src == null:
		_fit[key] = null
		return null
	var hb: AABB = AssetLib.model_aabb(host(look))
	var rot: Array = sp.get("rot", [0, 0, 0])
	var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(float(rot[2]))))
	var vb: AABB = Transform3D(b, Vector3.ZERO) * src0.get_aabb()
	var s: float = minf(hb.size.x / maxf(vb.size.x, 0.001), minf(hb.size.y / maxf(vb.size.y, 0.001), hb.size.z / maxf(vb.size.z, 0.001)))
	s *= float(sp.get("scale", 1.0))
	# Never drawn bigger than the model it stands in for (or half a metre): the start area's rule
	# that nothing junk-looking there is over 0.6 m (StartArea.junk_props) reads the drawn mesh.
	var cap: float = maxf(hb.size.length(), MAX_SIZE / 0.577) / maxf((vb.size * s).length(), 0.001)
	s *= minf(1.0, cap)
	var xf := Transform3D(b.scaled(Vector3.ONE * s), Vector3.ZERO)
	var fb: AABB = xf * src0.get_aabb()
	var hc: Vector3 = hb.get_center()
	var fc: Vector3 = fb.get_center()
	xf.origin = Vector3(hc.x - fc.x, hb.position.y - fb.position.y, hc.z - fc.z)
	_fit_box[look] = xf * src0.get_aabb()
	var arr: Array = src.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	for i: int in v.size():
		v[i] = xf * v[i]
	arr[Mesh.ARRAY_VERTEX] = v
	if arr[Mesh.ARRAY_NORMAL] != null:
		var nr: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i: int in nr.size():
			nr[i] = (b * nr[i]).normalized()
		arr[Mesh.ARRAY_NORMAL] = nr
	if arr[Mesh.ARRAY_TANGENT] != null:
		var tg: PackedFloat32Array = arr[Mesh.ARRAY_TANGENT]
		for i: int in range(0, tg.size(), 4):
			var t: Vector3 = (b * Vector3(tg[i], tg[i + 1], tg[i + 2])).normalized()
			tg[i] = t.x
			tg[i + 1] = t.y
			tg[i + 2] = t.z
		arr[Mesh.ARRAY_TANGENT] = tg
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	out.surface_set_material(0, _kit_material(look, _fit_box[look], lod == 1))
	_fit[key] = out
	return out


## The fitted box of a look (the host's box for "").
static func look_aabb(look: String, model: String) -> AABB:
	if look.contains("#"):
		if not _fit_box.has(look):
			look_mesh(look, 0)
		if _fit_box.has(look):
			return _fit_box[look]
	return AssetLib.model_aabb(model)


## How far a "lying" piece of this look must drop (in its own scale-1 metres, along the planet's
## up) to touch the ground: a lying piece is seated on half its host's depth.
static func lie_drop(look: String) -> float:
	if not look.contains("#"):
		return 0.0
	var hb: AABB = AssetLib.model_aabb(host(look))
	if is_flat(look):
		return hb.size.z * 0.5 + hb.position.y  # back on its base: lying seat minus upright seat
	return maxf(0.0, (hb.size.z - look_aabb(look, "").size.z) * 0.5)


static func _tone(model: String) -> Dictionary:
	var t: Dictionary = (data().get("tone", {}) as Dictionary)
	var out: Dictionary = (t.get("default", {}) as Dictionary).duplicate()
	out.merge(t.get(model, {}), true)
	return out


static func _shader(far: bool) -> Shader:
	if far:
		if _far_shader == null:
			_far_shader = load(FAR_SHADER)
		return _far_shader
	if _piece_shader == null:
		_piece_shader = load(PIECE_SHADER)
	return _piece_shader


static func _apply_tone(m: ShaderMaterial, model: String, box: AABB) -> void:
	var t: Dictionary = _tone(model)
	m.set_shader_parameter("box_center", box.get_center())
	m.set_shader_parameter("box_half", box.size * 0.5)
	m.set_shader_parameter("sat", float(t.get("sat", 0.8)))
	m.set_shader_parameter("val", float(t.get("val", 0.9)))
	m.set_shader_parameter("dust_amt", float(t.get("dust", 0.12)))
	var g: Dictionary = data().get("ground", {})
	if g.has("dirt"):
		m.set_shader_parameter("dirt", Color(float(g["dirt"][0]), float(g["dirt"][1]), float(g["dirt"][2])))
	if g.has("dust"):
		m.set_shader_parameter("dust", Color(float(g["dust"][0]), float(g["dust"][1]), float(g["dust"][2])))
	# the dirt climbs a share of the piece's height, within sensible limits
	m.set_shader_parameter("dirt_h", clampf(minf(box.size.y, box.size.z) * float(g.get("dirt_share", 0.3)), 0.025, float(g.get("dirt_max", 0.14))))


static func _kit_material(look: String, box: AABB, far: bool = false) -> ShaderMaterial:
	var key: String = "kit:%s:%s" % [look, far]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(false)
	m.set_shader_parameter("albedo_tex", load(KIT_TEX % "albedo"))
	m.set_shader_parameter("orm_tex", load(KIT_TEX % "orm"))
	m.set_shader_parameter("normal_tex", load(KIT_TEX % "normal"))
	m.set_shader_parameter("ao_mix", 1.0)
	if far:
		m.set_shader_parameter("normal_scale", 0.4)
	if look != "":
		_apply_tone(m, "kit", box)
		var sp: Dictionary = spec(look)
		if sp.has("val"):
			m.set_shader_parameter("val", float(sp["val"]))
		if sp.has("tint"):
			m.set_shader_parameter("albedo", Color(float(sp["tint"][0]), float(sp["tint"][1]), float(sp["tint"][2])))
	_mats[key] = m
	return m


## A scan's surface material as the piece shader (same maps), with the model's tone and box.
## Transparent or odd materials are kept as they are.
static func piece_material(src: Material, model: String, box: AABB) -> Material:
	if src == null or not (src is BaseMaterial3D):
		return src
	var bm: BaseMaterial3D = src
	if bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
		return src
	var key: String = "scan:%s:%d" % [model, src.get_instance_id()]
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(false)
	if bm.albedo_texture:
		m.set_shader_parameter("albedo_tex", bm.albedo_texture)
	m.set_shader_parameter("albedo", bm.albedo_color)
	if bm.normal_enabled and bm.normal_texture:
		m.set_shader_parameter("normal_tex", bm.normal_texture)
		m.set_shader_parameter("normal_scale", bm.normal_scale)
	else:
		m.set_shader_parameter("normal_scale", 0.0)
	var orm: Texture2D = bm.roughness_texture if bm.roughness_texture else bm.metallic_texture
	if orm:
		m.set_shader_parameter("orm_tex", orm)
		m.set_shader_parameter("roughness_mul", bm.roughness if bm.roughness_texture else 1.0)
		m.set_shader_parameter("metallic_mul", bm.metallic if bm.metallic_texture else 0.0)
		m.set_shader_parameter("ao_mix", 1.0 if bm.ao_enabled and bm.ao_texture == orm else 0.0)
	else:
		m.set_shader_parameter("roughness_mul", bm.roughness)
		m.set_shader_parameter("metallic_mul", bm.metallic)
	_apply_tone(m, model, box)
	_mats[key] = m
	return m


## The far band's material for a model (vertex colours; JunkFarSingle).
static func far_material(model: String, box: AABB) -> ShaderMaterial:
	var key: String = "far:%s" % model
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = _shader(true)
	_apply_tone(m, model, box)
	var g: Dictionary = data().get("ground", {})
	if g.has("far_mean"):
		m.set_shader_parameter("far_mean", Color(float(g["far_mean"][0]), float(g["far_mean"][1]), float(g["far_mean"][2])))
	m.set_shader_parameter("far_amt", float(g.get("far_amt", 0.45)))
	_mats[key] = m
	return m


## A copy of a scan mesh (any LOD of `model`) wearing the piece shader. Main thread or worker:
## reads surfaces through AssetLib's snapshots.
static func dressed(mesh: Mesh, model: String) -> Mesh:
	if mesh == null or not enabled() or not (mesh is ArrayMesh):
		return mesh
	var key: String = "%d" % mesh.get_rid().get_id()
	if _near.has(key):
		return _near[key]
	var box: AABB = AssetLib.model_aabb(model)
	var out := ArrayMesh.new()
	var made: Array = []
	for s: int in mesh.get_surface_count():
		var arr: Array = AssetLib.surf_arrays(mesh, s)
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		made.append(arr)
		out.surface_set_material(s, piece_material(mesh.surface_get_material(s), model, box))
	AssetLib.surf_note(out, made)
	_near[key] = out
	return out


## The far band's mesh for a model: JunkFarSingle's one-surface mesh (vertex colours) under the far
## shader; a model that was one surface anyway keeps its maps, in the piece shader.
static func far(mesh: Mesh, model: String) -> Mesh:
	if mesh == null or not enabled() or not (mesh is ArrayMesh):
		return mesh
	if mesh.surface_get_material(0) == JunkFarSingle.material():
		mesh.surface_set_material(0, far_material(model, AssetLib.model_aabb(model)))
		return mesh
	if mesh.surface_get_material(0) is ShaderMaterial:
		return mesh  # dressed already
	return dressed(mesh, model)


## A kit piece as it is (no host model): the litter carpet's small items.
static func kit_item(name: String, lod: int) -> Mesh:
	var key: String = "item:%s|%d" % [name, lod]
	if _fit.has(key):
		return _fit[key]
	var src: Mesh = kit_mesh(name, lod)
	var out: Mesh = src
	if src != null:
		out = ArrayMesh.new()
		(out as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(0))
		var m: ShaderMaterial = _kit_material("item:" + name, src.get_aabb(), lod == 1)
		_apply_tone(m, "kit", src.get_aabb())
		out.surface_set_material(0, m)
	_fit[key] = out
	return out
