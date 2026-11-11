class_name OldTownTrees
extends Node3D
## Old Town's street trees (CityOldTown builds one of these): a few bare-tree shapes with a leaning,
## flared trunk that forks into limbs, branches and twigs, and a crown of leaf clusters hung on the
## branch ends. Bare at the start; set_stage brings the leaves from stage 3 (young, light green),
## fills the crown at 4 and at 5 puts some of the trees in blossom, with flowers at their feet.
## Cheap: one MultiMesh per trunk shape, one for every leaf cluster (cards with a cut-out leaf
## texture round a dark core, tree_leaves.gdshader), one for the flowers.

const VARIANTS: int = 3
const RANGE_M: float = 300.0
const LEAF_PX: int = 256
const LEAVES: int = 300
## Crown size per stage (0-5) and how far the leaf colour leans to the pale green of new leaves.
const GROW: Array[float] = [0.0, 0.0, 0.0, 0.74, 0.9, 1.0]
const YOUNG: Array[float] = [0.0, 0.0, 0.0, 0.5, 0.15, 0.0]
const YOUNG_LEAF := Color(0.6, 0.78, 0.26)
const SPECIES: Array[Color] = [Color(0.33, 0.6, 0.17), Color(0.2, 0.47, 0.16), Color(0.46, 0.64, 0.18), Color(0.27, 0.55, 0.2)]
const BLOSSOM: Array[Color] = [Color(1.0, 0.6, 0.74), Color(1.0, 0.9, 0.86), Color(0.98, 0.78, 0.3)]
const BLOSSOM_SHARE: float = 0.2
const BARK := Color(0.4, 0.33, 0.27)

static var _leaf_tex: ImageTexture
static var _shapes: Array[Dictionary] = []  # per variant: {mesh: ArrayMesh, tips: Array[Vector3]}

var count: int = 0
var _crown: MultiMeshInstance3D
var _crown_xf: Array[Transform3D] = []
var _crown_col: Array[Color] = []
var _crown_bloom: Array[Color] = []  # the cluster's blossom colour at stage 5 (alpha 0: stays green)
var _flowers: MultiMeshInstance3D


## Plants a tree at every spot (site-local metres). `body` takes the trunks' colliders.
func build(spots: Array[Vector2], seed_v: int, body: StaticBody3D, stats: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var shapes: Array[Dictionary] = shapes_cached()
	var trunks: Array = []
	for v: int in VARIANTS:
		trunks.append([] as Array[Transform3D])
	var blooms: Array[Transform3D] = []
	for i: int in spots.size():
		var p: Vector2 = spots[i]
		var v: int = rng.randi() % VARIANTS
		var s: float = rng.randf_range(0.85, 1.2)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.92, 1.12), s)), Vector3(p.x, 0.02, p.y))
		(trunks[v] as Array[Transform3D]).append(xf)
		var green: Color = SPECIES[rng.randi() % SPECIES.size()]
		var bloom := Color(0, 0, 0, 0)
		if rng.randf() < BLOSSOM_SHARE:
			bloom = BLOSSOM[rng.randi() % BLOSSOM.size()]
		for tip: Vector3 in shapes[v]["tips"]:
			var cs: float = rng.randf_range(1.75, 2.35) * s
			var cb: Basis = Basis.from_euler(Vector3(rng.randf_range(-0.5, 0.5), rng.randf() * TAU, rng.randf_range(-0.5, 0.5)))
			_crown_xf.append(Transform3D(cb.scaled(Vector3(cs, cs * rng.randf_range(0.8, 0.95), cs)), xf * tip))
			_crown_col.append(green.lightened(rng.randf_range(-0.1, 0.16)))
			_crown_bloom.append(bloom.lightened(rng.randf_range(0.0, 0.2)) if bloom.a > 0.0 and rng.randf() < 0.8 else Color(0, 0, 0, 0))
		for k: int in 3:
			var a: float = rng.randf() * TAU
			blooms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.3, 1.9)),
				Vector3(p.x, 0.07, p.y) + Vector3(cos(a), 0, sin(a)) * rng.randf_range(0.45, 0.8)))
		PropColliders.add_cyl(body, Vector3(p.x, 0.0, p.y), 0.18, 2.6)
	count = spots.size()
	var bark: StandardMaterial3D = _bark_material()
	for v: int in VARIANTS:
		var xfs: Array[Transform3D] = trunks[v]
		if not xfs.is_empty():
			CityOldTown.mmi_on(self, "StreetTrees%d" % v, shapes[v]["mesh"], xfs, [], bark, true, RANGE_M)
	var leaf := ShaderMaterial.new()
	leaf.shader = load("res://planets/verdance/sites/tree_leaves.gdshader")
	leaf.set_shader_parameter("leaf_tex", leaf_texture())
	_crown = CityOldTown.mmi_on(self, "TreeCanopy", cluster_mesh(), _crown_xf, _crown_col, leaf, true, RANGE_M)
	var gaz: Array[Mesh] = PlantParts.variants("flower_gazania", 400)
	if not gaz.is_empty():
		_flowers = CityOldTown.mmi_on(self, "TreeFlowers", gaz[0], blooms, [], null, false, 160.0)
	stats["trees"] = count
	stats["tree_clusters"] = _crown_xf.size()


## Bare below stage 3; then the crown grows, loses its pale new-leaf colour, and blossoms at 5.
func set_stage(stage: int) -> void:
	var s: int = clampi(stage, 0, GROW.size() - 1)
	if _flowers:
		_flowers.visible = s >= 5
	if _crown == null:
		return
	_crown.visible = s >= 3
	if s < 3:
		return
	var mm: MultiMesh = _crown.multimesh
	for i: int in _crown_xf.size():
		var xf: Transform3D = _crown_xf[i]
		mm.set_instance_transform(i, Transform3D(xf.basis.scaled(Vector3.ONE * GROW[s]), xf.origin))
		var col: Color = _crown_col[i].lerp(YOUNG_LEAF, YOUNG[s])
		if s >= 5 and _crown_bloom[i].a > 0.0:
			col = _crown_bloom[i]
		mm.set_instance_color(i, Color(col.r, col.g, col.b, 1.0))


func has_crown() -> bool:
	return _crown != null


static func shapes_cached() -> Array[Dictionary]:
	if _shapes.is_empty():
		for v: int in VARIANTS:
			_shapes.append(tree_shape(5519 + v * 131))
	return _shapes


# --- Bare tree ------------------------------------------------------------------------------------

## One bare tree: {mesh, tips}. A flared trunk in three leaning pieces, forking four times into
## limbs, branches and twigs; each fork is thinner and paler than its parent. `tips` are the limb
## and branch ends, where the leaf clusters hang.
static func tree_shape(seed_v: int) -> Dictionary:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var tips: Array[Vector3] = []
	var lean := Vector3(rng.randf_range(-0.09, 0.09), 0.0, rng.randf_range(-0.09, 0.09))
	var p0 := Vector3.ZERO
	var p1: Vector3 = Vector3(0, 0.35, 0) + lean * 0.2
	var p2: Vector3 = Vector3(0, 1.5, 0) + lean
	var p3: Vector3 = Vector3(0, 2.75 + rng.randf_range(-0.2, 0.25), 0) + lean * rng.randf_range(-0.4, 1.6)
	limb(st, p0, p1, 0.27, 0.17, BARK.darkened(0.12), 8)   # the root flare
	limb(st, p1, p2, 0.17, 0.145, BARK, 8)
	limb(st, p2, p3, 0.145, 0.12, BARK, 8)
	var forks: Array = [[p3, (p3 - p2).normalized(), 0.12, 4]]
	while not forks.is_empty():
		var f: Array = forks.pop_back()
		var at: Vector3 = f[0]
		var dir: Vector3 = f[1]
		var r: float = f[2]
		var depth: int = f[3]
		var kids: int = 3 if depth >= 3 else 2
		var a0: float = rng.randf() * TAU
		for k: int in kids:
			var a: float = a0 + TAU * (float(k) / float(kids)) + rng.randf_range(-0.4, 0.4)
			var tilt: float = rng.randf_range(0.42, 0.85)
			var side := Vector3(cos(a), 0.0, sin(a))
			var d: Vector3 = (dir * cos(tilt) + side * sin(tilt)).normalized()
			d = (d + Vector3.UP * 0.28).normalized()
			var length: float = rng.randf_range(0.75, 1.2) * (0.42 + 0.2 * float(depth))
			var kr: float = r * (0.62 if k > 0 else 0.76)
			var mid: Vector3 = at + d * length * 0.5 + side * rng.randf_range(-0.08, 0.08) + Vector3(0, rng.randf_range(-0.04, 0.06), 0)
			var e: Vector3 = at + d * length + Vector3(0, rng.randf_range(0.0, 0.14), 0)
			var col: Color = BARK.lightened(0.06 * float(4 - depth))
			var r_end: float = kr * 0.55
			if depth <= 2:  # twigs: one straight piece, three sides
				limb(st, at, e, r * 0.9, r_end, col, 3)
			else:
				var r_mid: float = (r * 0.92 + r_end) * 0.5
				limb(st, at, mid, r * 0.92, r_mid, col, 5)
				limb(st, mid, e, r_mid, r_end, col, 5)
				tips.append(e)
			if depth > 1:
				forks.append([e, (e - mid).normalized(), kr * 0.6, depth - 1])
	var top := Vector3.ZERO
	for t: Vector3 in tips:
		top += t / float(tips.size())
	tips.append(Vector3(top.x, top.y + 1.1, top.z))  # the crown's cap
	return {"mesh": st.commit(), "tips": tips}


static func limb(st: SurfaceTool, a: Vector3, b: Vector3, r0: float, r1: float, col: Color, sides: int = 6) -> void:
	var d: Vector3 = (b - a).normalized()
	var x: Vector3 = d.cross(Vector3.RIGHT if absf(d.x) < 0.8 else Vector3.FORWARD).normalized()
	var z: Vector3 = d.cross(x).normalized()
	for i: int in sides:
		var a0: float = TAU * float(i) / float(sides)
		var a1: float = TAU * float(i + 1) / float(sides)
		var n0: Vector3 = x * cos(a0) + z * sin(a0)
		var n1: Vector3 = x * cos(a1) + z * sin(a1)
		var quad: Array = [[a + n0 * r0, n0], [b + n0 * r1, n0], [b + n1 * r1, n1], [a + n1 * r0, n1]]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(quad[idx][1])
			st.add_vertex(quad[idx][0])


## Bark: the limb colours under a streaky noise (furrows running up the trunk) and its bump.
static func _bark_material() -> StandardMaterial3D:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.05
	noise.fractal_octaves = 3
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.5, 0.48, 0.46))
	ramp.set_color(1, Color(1.0, 1.0, 1.0))
	var tex := NoiseTexture2D.new()
	tex.noise = noise
	tex.seamless = true
	tex.width = 128
	tex.height = 128
	tex.color_ramp = ramp
	tex.generate_mipmaps = true
	var bump := NoiseTexture2D.new()
	bump.noise = noise
	bump.seamless = true
	bump.width = 128
	bump.height = 128
	bump.as_normal_map = true
	bump.bump_strength = 6.0
	var bark := StandardMaterial3D.new()
	bark.vertex_color_use_as_albedo = true
	bark.albedo_texture = tex
	bark.normal_enabled = true
	bark.normal_texture = bump
	bark.normal_scale = 1.0
	bark.roughness = 1.0
	bark.uv1_triplanar = true
	bark.uv1_scale = Vector3(1.6, 0.35, 1.6)  # stretched up the trunk: furrows, not blotches
	return bark


# --- Leaves ---------------------------------------------------------------------------------------

## One leaf cluster, about 1.3 units across: a small dark core (so the crown is never see-through)
## and fourteen leaf cards, some facing out and some standing on edge so the outline stays ragged
## from every side. Normals point out of the cluster; vertex colour is darker underneath.
static func cluster_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7741
	var rings: int = 4
	var segs: int = 8
	var core_r: float = 0.3
	for i: int in rings:
		for j: int in segs:
			var quad: Array[Vector3] = []
			for c: Vector2i in [Vector2i(i, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1), Vector2i(i + 1, j)]:
				var th: float = PI * float(c.x) / float(rings)
				var ph: float = TAU * float(c.y % segs) / float(segs)
				quad.append(Vector3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * core_r)
			for idx: int in [0, 1, 2, 0, 2, 3]:
				var v: Vector3 = quad[idx]
				var shade: float = clampf(0.5 + v.y * 0.9, 0.3, 0.75)
				st.set_color(Color(shade, shade, shade))
				st.set_normal(v.normalized())
				st.set_uv(Vector2(0.5, 0.5))
				st.set_uv2(Vector2(0.0, 1.0))
				st.add_vertex(v)
	var cards: int = 14
	for i: int in cards:
		var y: float = 1.0 - (float(i) + 0.5) / float(cards) * 1.75
		var rr: float = sqrt(maxf(0.0, 1.0 - y * y))
		var phi: float = float(i) * 2.39996
		var d := Vector3(cos(phi) * rr, y, sin(phi) * rr)
		var jit := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var nrm: Vector3 = d.cross(jit).normalized() if i % 3 == 2 else (d + jit * 0.4).normalized()
		var ax: Vector3 = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
		ax = ax.rotated(nrm, rng.randf() * TAU)
		var ay: Vector3 = nrm.cross(ax)
		var h: float = 0.34 * rng.randf_range(0.9, 1.15)
		var c0: Vector3 = d * (0.3 if i % 3 == 2 else 0.25)
		var tone: float = rng.randf_range(0.9, 1.06)
		var corners: Array = [[-1.0, -1.0], [1.0, -1.0], [1.0, 1.0], [-1.0, 1.0]]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			var sx: float = corners[idx][0]
			var sy: float = corners[idx][1]
			var v: Vector3 = c0 + ax * sx * h + ay * sy * h
			var shade: float = clampf(0.74 + v.y * 0.62, 0.5, 1.0) * tone
			st.set_color(Color(shade, shade, shade))
			st.set_normal((v + Vector3(0, 0.18, 0)).normalized())
			st.set_uv(Vector2(sx * 0.5 + 0.5, sy * 0.5 + 0.5))
			st.set_uv2(Vector2(1.0, 0.0))
			st.add_vertex(v)
	return st.commit()


## The leaf card's texture: a few hundred pointed leaves with a midrib, thick in the middle of
## the card and thinning to nothing at its edge. Near-white (the instance colour tints it).
static func leaf_texture() -> ImageTexture:
	if _leaf_tex:
		return _leaf_tex
	var n: int = LEAF_PX
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for i: int in n * n:
		px[i * 4] = 196
		px[i * 4 + 1] = 212
		px[i * 4 + 2] = 170
	var rng := RandomNumberGenerator.new()
	rng.seed = 9102
	for k: int in LEAVES:
		var rr: float = pow(rng.randf(), 0.7) * 0.43 * float(n)
		var a: float = rng.randf() * TAU
		var cx: float = float(n) * 0.5 + cos(a) * rr
		var cy: float = float(n) * 0.5 + sin(a) * rr
		var half: float = rng.randf_range(9.0, 13.0)
		var wid: float = half * rng.randf_range(0.4, 0.52)
		var rot: float = rng.randf() * TAU
		var cr: float = cos(rot)
		var sr: float = sin(rot)
		var lum: float = rng.randf_range(0.62, 1.0)
		var warm: float = rng.randf_range(0.86, 0.98)
		for y: int in range(maxi(0, int(cy - half)), mini(n, int(cy + half) + 2)):
			for x: int in range(maxi(0, int(cx - half)), mini(n, int(cx + half) + 2)):
				var dx: float = float(x) - cx
				var dy: float = float(y) - cy
				var u: float = (dx * cr + dy * sr) / half
				var lim: float = 1.0 - u * u
				if lim <= 0.0:
					continue
				var v: float = absf(-dx * sr + dy * cr) / wid
				if v > lim:
					continue
				var shade: float = lum * (0.8 if v < 0.14 else 1.0) * (0.9 + 0.1 * u)
				var o: int = (y * n + x) * 4
				px[o] = int(255.0 * shade * warm)
				px[o + 1] = int(255.0 * shade)
				px[o + 2] = int(255.0 * shade * 0.78)
				px[o + 3] = 255
	var img: Image = Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, px)
	img.generate_mipmaps()
	_leaf_tex = ImageTexture.create_from_image(img)
	return _leaf_tex
