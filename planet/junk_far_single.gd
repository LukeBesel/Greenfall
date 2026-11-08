class_name JunkFarSingle
extends RefCounted
## [orbE] Far junk impostors in one draw per model (docs/PERFORMANCE.md, perf pass 4). The far
## band (JunkLod.far_mesh) keeps every surface of a model with its own material: a crate of wine
## bottles was 16 draws per MultiMesh. At impostor distance a piece is a few pixels, so its
## surfaces merge into one, each tinted with its material's average colour (albedo x texture
## average) in the vertex colours, under one shared material.

static var _cache: Dictionary = {}  # mesh rid -> Mesh
static var _colors: Dictionary = {}  # material id -> Color
static var _mat: StandardMaterial3D


static func single(mesh: Mesh) -> Mesh:
	if mesh == null or mesh.get_surface_count() <= 1:
		return mesh
	var key: int = mesh.get_rid().get_id()
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s: int in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var col: Color = average_color(mesh.surface_get_material(s))
		var count: int = idx.size() if not idx.is_empty() else verts.size()
		for i: int in count:
			var vi: int = idx[i] if not idx.is_empty() else i
			st.set_color(col)
			if not norms.is_empty():
				st.set_normal(norms[vi])
			st.add_vertex(verts[vi])
	st.index()
	var out: ArrayMesh = st.commit()
	out.surface_set_material(0, material())
	_cache[key] = out
	return out


## The shared far material: vertex colour, matte (the far band casts no shadow).
static func material() -> StandardMaterial3D:
	if _mat == null:
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		_mat.vertex_color_is_srgb = true
		_mat.roughness = 0.85
	return _mat


## A material's look at a distance: albedo colour times its texture's average.
static func average_color(m: Material) -> Color:
	if m == null:
		return Color(0.5, 0.5, 0.5)
	var k: int = m.get_instance_id()
	if _colors.has(k):
		return _colors[k]
	var c := Color(0.5, 0.5, 0.5)
	if m is BaseMaterial3D:
		var bm: BaseMaterial3D = m
		c = bm.albedo_color
		if bm.albedo_texture:
			var img: Image = bm.albedo_texture.get_image()
			if img:
				img = img.duplicate() as Image
				if img.is_compressed():
					img.decompress()
				img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
				var t: Color = img.get_pixel(0, 0)
				c = Color(c.r * t.r, c.g * t.g, c.b * t.b, 1.0)
	_colors[k] = c
	return c
