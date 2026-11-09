class_name GardenMarks
extends Node3D
## [v4grow] Owner playtest 3 #51: "planted plants can't be seen, so I don't know where to water or
## whether it's working." The globe garden's readable layer, over Garden's species clumps:
##   - a soil mound under every planted slot: pale and dusty when dry, dark and glossy when wet;
##   - a sprout (stem and two leaves) for the seed and sprout stages, sized to read from Lumi's
##     camera; it droops and yellows when thirsty and bounces up when watered;
##   - a bobbing blue water-drop icon over every thirsty plant;
##   - a soft green ring round each planted cell;
##   - with the watering can out (key 3), a blue ring where the water would land, and the plants it
##     would reach lit at their mounds; with seeds out (key 2), a green ring on the next free slot;
##   - a splash and a ripple when a plant gets water.
## Rebuilt a few times a second from Garden's slots within VIEW_M of Lumi.

const VIEW_M: float = 90.0
const REFRESH_S: float = 0.2
const MAX_N: int = 800
const SPROUT_H: Array[float] = [0.4, 0.62]  # stage 0 / 1 sprout height (m)
const DRY_SOIL := Color(0.5, 0.36, 0.22)
const WET_SOIL := Color(0.11, 0.07, 0.045)
const GREEN := Color(0.38, 0.92, 0.25)
const THIRSTY_GREEN := Color(0.66, 0.62, 0.26)
const WATER_BLUE := Color(0.35, 0.7, 1.0)
## Water lasts water_s; the soil reads wet down to this share of it, then fades to dry.
const WET_FADE: float = 0.35

const SOIL_SHADER: String = """
shader_type spatial;
render_mode cull_back;
varying vec4 inst;
varying vec3 col;
void vertex() {
	inst = INSTANCE_CUSTOM;
	col = COLOR.rgb;
}
void fragment() {
	// inst.r: wetness 0..1, inst.g: lit by the watering can preview
	float n = fract(sin(dot(floor(UV * 18.0), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = col * (0.85 + 0.3 * n) + vec3(0.1, 0.35, 0.6) * inst.g * 0.6;
	ROUGHNESS = mix(1.0, 0.55, inst.r);
	SPECULAR = mix(0.15, 0.3, inst.r);
	EMISSION = vec3(0.15, 0.45, 0.9) * inst.g * 0.5;
}
"""

const DROP_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 tint : source_color = vec4(0.35, 0.7, 1.0, 1.0);
void vertex() {
	// billboard round the instance origin, bobbing
	float bob = sin(TIME * 3.0 + dot(MODEL_MATRIX[3].xyz, vec3(1.7, 2.3, 0.9))) * 0.08;
	vec3 up_w = normalize(MODEL_MATRIX[1].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3] + vec4(up_w * bob, 0.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec2 p = UV * 2.0 - 1.0;  // -1..1, y down
	p.y = -p.y;
	// a teardrop: a circle at the bottom, a point at the top
	vec2 c = p - vec2(0.0, -0.25);
	float r = length(c);
	float body = 0.55 - r;
	float tip = 0.55 * (1.0 - clamp((p.y + 0.25) / 1.0, 0.0, 1.0)) - abs(p.x);
	float d = p.y > -0.25 ? min(tip, 0.6 - p.y) : body;
	float edge = smoothstep(-0.04, 0.02, d);
	float rim = smoothstep(0.1, 0.0, d) * edge;
	float shine = smoothstep(0.16, 0.04, length(p - vec2(-0.18, -0.15)));
	ALBEDO = mix(tint.rgb, vec3(1.0), rim * 0.65 + shine * 0.8);
	ALPHA = edge * 0.95;
}
"""

const RING_SHADER: String = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;
uniform vec4 tint : source_color = vec4(0.35, 0.7, 1.0, 1.0);
uniform float band = 0.85;
uniform float pulse = 1.0;
void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float a = exp(-pow((r - band) / 0.09, 2.0)) * 1.2 + smoothstep(band, 0.0, r) * 0.22;
	a *= 0.75 + 0.25 * sin(TIME * 4.0) * pulse;
	ALBEDO = tint.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * step(r, 1.0) * tint.a;
}
"""

var world: Node
var garden: Garden
var _t: float = 0.0
var _soil: MultiMeshInstance3D
var _sprout: MultiMeshInstance3D
var _drops: MultiMeshInstance3D
var _water_ring: MeshInstance3D
var _plant_ring: MeshInstance3D
var _hex_rings: Dictionary = {}  # cell -> MeshInstance3D
var _hex_ring_mat: StandardMaterial3D
## Last refresh: how many planted / thirsty slots were drawn (tests, the probe).
var shown: Dictionary = {"planted": 0, "thirsty": 0, "sprouts": 0, "rings": 0, "reach": 0}


static func attach(w: Node) -> GardenMarks:
	var g: Garden = w.get("garden") as Garden
	if g == null:
		return null
	var m := GardenMarks.new()
	m.name = "GardenMarks"
	m.world = w
	m.garden = g
	w.add_child(m)
	if DevHooks.has("orbit-garden"):  # dev: --orbit-garden[=S] plants a demo bed ahead of Lumi after S s
		w.connect("built", func() -> void: m._dev_garden(DevHooks.get_f("orbit-garden", 4.0)), CONNECT_ONE_SHOT)
	return m


func _ready() -> void:
	top_level = true
	_soil = _mm(_soil_mesh(), _shader_mat(SOIL_SHADER), true, true)
	var sm := StandardMaterial3D.new()
	sm.vertex_color_use_as_albedo = true
	sm.roughness = 0.75
	_sprout = _mm(_sprout_mesh(), sm, true, false)
	var dq := QuadMesh.new()
	dq.size = Vector2(0.55, 0.7)
	var dm: ShaderMaterial = _shader_mat(DROP_SHADER)
	_drops = _mm(dq, dm, false, false)
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.visibility_range_end = 45.0
	_water_ring = _ring(WATER_BLUE)
	_plant_ring = _ring(GREEN)
	_hex_ring_mat = StandardMaterial3D.new()
	_hex_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_hex_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hex_ring_mat.albedo_color = Color(0.55, 1.0, 0.45, 0.42)
	_hex_ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_hex_ring_mat.no_depth_test = false
	garden.watered.connect(_on_watered)
	garden.planted.connect(func(_s: int) -> void: _t = 0.0)


func _mm(mesh: Mesh, mat: Material, colors: bool, custom: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = custom
	mm.mesh = mesh
	mm.instance_count = MAX_N
	mm.visible_instance_count = 0
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.visibility_range_end = VIEW_M + 10.0
	add_child(mi)
	return mi


func _shader_mat(code: String) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = code
	var m := ShaderMaterial.new()
	m.shader = sh
	return m


func _ring(c: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0, 2.0)
	mi.mesh = pm
	var m: ShaderMaterial = _shader_mat(RING_SHADER)
	m.set_shader_parameter("tint", c)
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


## A low mound of turned soil, 1.4 m across.
static func _soil_mesh() -> Mesh:
	var c := CylinderMesh.new()
	c.top_radius = 0.46
	c.bottom_radius = 0.68
	c.height = 0.14
	c.radial_segments = 14
	c.rings = 1
	c.cap_bottom = false
	return ProcMesh.merge([ProcMesh.part(c, ProcMesh.xf(Vector3(0, 0.03, 0)), Color(1, 1, 1))])


## A seedling 1 m tall (scaled per stage): a stem, two broad leaves and a bud.
static func _sprout_mesh() -> Mesh:
	var stem := Color(0.5, 0.75, 0.3)
	var leaf := Color(1.0, 1.0, 1.0)
	var parts: Array = [
		ProcMesh.part(ProcMesh.cyl(0.035, 0.05, 0.75, 6), ProcMesh.xf(Vector3(0, 0.375, 0)), stem),
		ProcMesh.part(ProcMesh.sphere(0.5, 10, 5), ProcMesh.xf(Vector3(0.24, 0.66, 0), Vector3(0, 0, 28), Vector3(0.5, 0.06, 0.26)), leaf),
		ProcMesh.part(ProcMesh.sphere(0.5, 10, 5), ProcMesh.xf(Vector3(-0.22, 0.56, 0.02), Vector3(0, 20, -32), Vector3(0.44, 0.06, 0.24)), leaf),
		ProcMesh.part(ProcMesh.sphere(0.08, 8, 4), ProcMesh.xf(Vector3(0, 0.8, 0), Vector3.ZERO, Vector3(1, 1.4, 1)), leaf),
	]
	return ProcMesh.merge(parts)


## 0..1: how wet slot s's soil reads (1 just watered, 0 dry).
func wetness(s: int) -> float:
	var ws: float = float(garden.species[garden.slot_species[s]].get("water_s", 120))
	return clampf(garden.slot_water[s] / maxf(ws * WET_FADE, 1.0), 0.0, 1.0)


func _process(delta: float) -> void:
	if world == null or garden == null:
		return
	_preview()
	_t -= delta
	if _t > 0.0 and garden._perk.is_empty():
		return
	_t = REFRESH_S
	_refresh()


func _patch() -> Patch:
	return world.get("patch") as Patch


func _refresh() -> void:
	var p: Patch = _patch()
	var at: Vector3 = p.global_position if p else Vector3.ZERO
	var reach: Array[int] = []
	if p and p.tool == Patch.Tool.WATER and _hud_on():
		reach = garden.planted_near(p.global_position, p.forward())
	var soil: MultiMesh = _soil.multimesh
	var spr: MultiMesh = _sprout.multimesh
	var drp: MultiMesh = _drops.multimesh
	var n: int = 0
	var ns: int = 0
	var nd: int = 0
	var cells: Dictionary = {}
	for s: int in garden.planted_slots():
		var sp: Vector3 = garden.slot_pos[s]
		cells[garden.slot_hex[s]] = true
		if p and sp.distance_to(at) > VIEW_M:
			continue
		if n >= MAX_N:
			break
		var fr: Basis = SphereGrid.frame(sp.normalized()) if OrbitUp.on_globe() else Basis()
		var up: Vector3 = fr.y
		var wet: float = wetness(s)
		var dry: bool = garden.slot_water[s] <= 0.0
		soil.set_instance_transform(n, Transform3D(fr * Basis(Vector3.UP, garden.slot_yaw[s]), sp - up * 0.02))
		soil.set_instance_color(n, DRY_SOIL.lerp(WET_SOIL, wet))
		soil.set_instance_custom_data(n, Color(wet, 1.0 if s in reach else 0.0, 0.0, 0.0))
		n += 1
		var st: int = garden.slot_stage[s]
		if st < SPROUT_H.size() and ns < MAX_N:
			var h: float = SPROUT_H[st] * (1.0 + 0.2 * garden.perk_of(s))
			var b := Basis(Vector3.UP, garden.slot_yaw[s]).scaled(Vector3.ONE * h)
			if dry:
				b = Basis(Vector3.RIGHT, 0.7) * b.scaled(Vector3(1.0, 0.8, 1.0))
			spr.set_instance_transform(ns, Transform3D(fr * b, sp + up * 0.08))
			spr.set_instance_color(ns, THIRSTY_GREEN if dry else GREEN)
			ns += 1
		if dry and nd < MAX_N:
			var top: float = maxf(SPROUT_H[mini(st, SPROUT_H.size() - 1)] if st < SPROUT_H.size() else garden.globe_height(st), 0.3)
			drp.set_instance_transform(nd, Transform3D(fr, sp + up * (top + 0.55)))
			nd += 1
	soil.visible_instance_count = n
	spr.visible_instance_count = ns
	drp.visible_instance_count = nd
	shown = {"planted": n, "thirsty": nd, "sprouts": ns, "rings": 0, "reach": reach.size()}
	_sync_hex_rings(cells)
	shown["rings"] = _hex_rings.size()


func _hud_on() -> bool:
	var hud: Variant = world.get("hud")
	return hud == null or (hud as CanvasLayer).visible


## The watering can's landing ring (key 3) and the next seed's slot (key 2).
func _preview() -> void:
	var p: Patch = _patch()
	var water_on: bool = p != null and p.tool == Patch.Tool.WATER and _hud_on() and garden.unlocked()
	var plant_on: bool = p != null and p.tool == Patch.Tool.PLANT and _hud_on() and garden.unlocked()
	_water_ring.visible = water_on
	_plant_ring.visible = false
	if water_on:
		var c: Vector3 = p.global_position + p.forward() * 1.2  # Garden.planted_near's centre and reach
		_place_ring(_water_ring, c, 2.8)
	elif plant_on:
		var s: int = garden.free_slot_near(p.global_position, p.forward())
		if s >= 0:
			_plant_ring.visible = true
			_place_ring(_plant_ring, garden.slot_pos[s], 0.7)


func _place_ring(mi: MeshInstance3D, c: Vector3, r: float) -> void:
	var g: Vector3 = _ground(c)
	var fr: Basis = SphereGrid.frame(g.normalized()) if OrbitUp.on_globe() else Basis()
	mi.global_transform = Transform3D(fr.scaled(Vector3(r / 0.85, 1.0, r / 0.85)), g + fr.y * 0.16)


func _ground(p: Vector3) -> Vector3:
	var f: Variant = world.get("field")
	if f is SphereField:
		return (f as SphereField).terrain.ground(p.normalized())
	return Vector3(p.x, 0.0, p.z)


## A thin soft-green ring along each planted cell's corners (hugging the ground).
func _sync_hex_rings(cells: Dictionary) -> void:
	for h: int in _hex_rings.keys():
		if not cells.has(h):
			(_hex_rings[h] as Node).queue_free()
			_hex_rings.erase(h)
	var f: Variant = world.get("field")
	if not f is SphereField:
		return
	for h: int in cells:
		if not _hex_rings.has(h):
			_hex_rings[h] = _hex_ring(f as SphereField, h)


func _hex_ring(f: SphereField, h: int) -> MeshInstance3D:
	var ctr: Vector3 = f.grid.centers[h]
	var cs: PackedVector3Array = f.grid.corners(h)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts: Array[Vector3] = []
	var ins: Array[Vector3] = []
	for k: int in cs.size():
		var a: Vector3 = cs[k]
		var b: Vector3 = cs[(k + 1) % cs.size()]
		for s: int in 6:
			var d: Vector3 = a.lerp(b, s / 6.0).normalized()
			var di: Vector3 = d.lerp(ctr.normalized(), 0.04).normalized()  # a band just inside the edge
			pts.append(f.terrain.ground(d) + d * 0.07)
			ins.append(f.terrain.ground(di) + di * 0.07)
	for i: int in pts.size():
		var j: int = (i + 1) % pts.size()
		st.add_vertex(pts[i])
		st.add_vertex(pts[j])
		st.add_vertex(ins[i])
		st.add_vertex(ins[i])
		st.add_vertex(pts[j])
		st.add_vertex(ins[j])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _hex_ring_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = VIEW_M + 30.0
	add_child(mi)
	return mi


## A splash and a ripple where the water lands; a plant that was dry gets a sparkle as it perks up.
func _on_watered(s: int, was_dry: bool) -> void:
	var p: Vector3 = garden.slot_pos[s]
	var up: Vector3 = OrbitUp.up(p)
	if was_dry:
		Vfx.burst("soil", p + up * 0.25, Color(0.5, 0.78, 1.0, 0.9), 0.6)
		Vfx.ring(p + up * 0.06, 0.9, Color(0.45, 0.75, 1.0, 0.8), 0.7)
		Vfx.burst("sparkle", p + up * 0.5, Color(0.7, 1.0, 0.6), 0.2)
	_t = 0.0


# --- Dev: a demo bed for renders and the probe --------------------------------------------------

## Cleans the cells about 7 m ahead of Lumi and plants every slot there: stages 0..4 in turn, every
## third slot thirsty. Takes the watering can out (its ring shows) unless --orbit-garden-tool=none.
func _dev_garden(delay: float) -> void:
	print("[garden-marks] demo bed in %.0f s" % delay)
	await get_tree().create_timer(delay, true, false, true).timeout
	var p: Patch = _patch()
	var so: Variant = world.get("orbit")
	var f: Variant = world.get("field")
	if p == null or so == null or not f is SphereField:
		print("[garden-marks] demo bed: no patch / globe")
		return
	var sf: SphereField = f
	var c: Vector3 = p.global_position + p.forward() * 7.0
	GameState.flags["seeds_unlocked"] = true
	var k: int = 0
	for h: int in sf.hexes_near(c, 1):
		if sf.hex_hub[h] != 0 or sf.is_water(h):
			continue
		((so as Object).get("crews") as OrbitCrews).work_cell(h, 0.0)
		garden.ensure_hex(h)
		for sl: int in garden.hex_slots.get(h, PackedInt32Array()):
			if garden.slot_pos[sl].distance_to(c) > 9.0:
				continue
			garden.slot_species[sl] = k % 6
			garden.slot_stage[sl] = k % 5
			garden.slot_water[sl] = 0.0 if k % 3 == 0 else 60.0
			garden._update_inst(sl)
			k += 1
		garden._recount(h)
	if DevHooks.get_s("orbit-garden-tool", "water") == "water":
		p.tool = Patch.Tool.WATER
	_t = 0.0
	await get_tree().create_timer(0.5, true, false, true).timeout
	print("[garden-marks] demo bed: %d plants; shown %s" % [k, str(shown)])
