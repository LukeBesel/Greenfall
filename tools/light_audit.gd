class_name LightAudit
extends Node
## [world3] Lists everything in the world that glows as if it were working: Light3D nodes and
## emissive materials (neon tubes, bulbs, StandardMaterial3D emission, glow uniforms).
## Owner rule: when you land nothing works; every light comes back through paid progress.
## Run: godot --headless --path . res://tools/light_audit.tscn -- --fresh [--time=0.0] [--audit-scene=res://...]
## Exit code 1 when a fresh district has a lit light. tests/test_dead_power.gd runs scan().
##
## Lumi, robots, the HUD and effects are not the world and are skipped. Neon-shader meshes count
## as lit when their `energy * power` is above a faint glow and some vertex is not flagged dead.

const SKIP_CLASSES: Array[String] = ["Patch", "Robot", "PickupFx", "HUD", "PhotoMode", "Vfx", "GlobeView",
	"SkyDirector", "JunkCube", "Glim", "GlimBot", "LitterView", "FarJunk", "Fauna", "Garden"]
const SKIP_NAMES: Array[String] = ["Sky", "Weather", "Fleet", "Cubes", "Fauna", "Garden", "Plants"]
## Not the district's power, listed apart (tools run) and left out of the check:
##   CrashSite  Lumi's own crashed pod (its damaged beacon and sparking wires are the pod story)
##   Outposts   a ruined outpost's dying fault light: a broken flicker, as the rule allows
##   EasterEggs found-and-poked secrets (vending machine, TV, jukebox...): story/eggs.gd's own
const NOT_GRID: Array[String] = ["CrashSite", "Outposts", "EasterEggs"]
const NEON: String = "res://art/shaders/neon.gdshader"
## Shader uniforms that mean "glows" in other shaders.
const GLOW_PARAMS: Array[String] = ["glow", "emission", "emission_energy", "emit", "lit", "light", "lights_on", "window_glow"]


static func _class_of(n: Node) -> String:
	var s: Script = n.get_script() as Script
	while s:
		if s.get_global_name() != "":
			return s.get_global_name()
		s = s.get_base_script()
	return n.get_class()


static func _path(n: Node, root: Node) -> String:
	var parts: PackedStringArray = []
	var a: Node = n
	while a and a != root and parts.size() < 5:
		var c: String = _class_of(a)
		parts.insert(0, String(a.name) if c == a.get_class() else "%s(%s)" % [c, a.name])
		a = a.get_parent()
	return "/".join(parts)


static func _skipped(n: Node, root: Node) -> bool:
	var a: Node = n
	while a and a != root:
		if a.name in SKIP_NAMES or _class_of(a) in SKIP_CLASSES:
			return true
		a = a.get_parent()
	return false


static func _under(n: Node, root: Node, names: Array[String]) -> bool:
	var a: Node = n
	while a and a != root:
		if String(a.name) in names or _class_of(a) in names:
			return true
		a = a.get_parent()
	return false


static func _visible(n: Node) -> bool:
	if n is Node3D:
		return (n as Node3D).is_visible_in_tree()
	return true


## Mesh vertices not flagged dead (UV.y = 2) in the neon shader's convention.
static func _neon_live(m: Mesh) -> bool:
	if m == null or not (m is ArrayMesh):
		return true
	for s: int in m.get_surface_count():
		var arr: Array = m.surface_get_arrays(s)
		var uv: Variant = arr[Mesh.ARRAY_TEX_UV]
		if uv == null:
			return true
		for p: Vector2 in uv as PackedVector2Array:
			if p.y < 1.5:
				return true
	return false


static func _mat_glow(mat: Material, mesh: Mesh) -> String:
	if mat == null:
		return ""
	if mat is StandardMaterial3D:
		var sm := mat as StandardMaterial3D
		if sm.emission_enabled and sm.emission_energy_multiplier > 0.05 and sm.emission.get_luminance() > 0.05:
			return "emission %.2f" % sm.emission_energy_multiplier
		return ""
	if mat is ShaderMaterial:
		var shm := mat as ShaderMaterial
		if shm.shader == null:
			return ""
		if shm.shader.resource_path == NEON:
			var e: Variant = shm.get_shader_parameter("energy")
			var en: float = float(e) if e != null else 4.0
			var p: Variant = shm.get_shader_parameter("power")
			var pw: float = float(p) if p != null else 1.0
			if en * pw > 0.3 and _neon_live(mesh):
				return "neon %.1f" % (en * pw)
			return ""
		for pn: String in GLOW_PARAMS:
			var v: Variant = shm.get_shader_parameter(pn)
			if (v is float or v is int) and float(v) > 0.05:
				return "%s:%s=%.2f" % [shm.shader.resource_path.get_file(), pn, float(v)]
	return ""


## Returns [{path, what}] for every lit light / glowing mesh under root.
static func scan(root: Node, ignore: Array[String] = []) -> Array:
	var out: Array = []
	for n: Node in root.find_children("*", "Node3D", true, false):
		if not _visible(n) or _skipped(n, root):
			continue
		if not ignore.is_empty() and _under(n, root, ignore):
			continue
		if n is Light3D and not (n is DirectionalLight3D):
			var lt := n as Light3D
			if lt.light_energy > 0.02:
				out.append({"path": _path(n, root), "what": "%s %.2f" % [lt.get_class(), lt.light_energy]})
			continue
		if not (n is GeometryInstance3D):
			continue
		var g := n as GeometryInstance3D
		var mesh: Mesh = null
		if g is MeshInstance3D:
			mesh = (g as MeshInstance3D).mesh
		elif g is MultiMeshInstance3D and (g as MultiMeshInstance3D).multimesh:
			var mm: MultiMesh = (g as MultiMeshInstance3D).multimesh
			if mm.instance_count == 0 or mm.visible_instance_count == 0:
				continue
			mesh = mm.mesh
		var mats: Array[Material] = [g.material_override]
		if mesh:
			for s: int in mesh.get_surface_count():
				mats.append(mesh.surface_get_material(s))
				if g is MeshInstance3D:
					mats.append((g as MeshInstance3D).get_surface_override_material(s))
		for m: Material in mats:
			var w: String = _mat_glow(m, mesh)
			if w != "" and m.resource_name != "":
				w += " " + m.resource_name
			if w != "":
				out.append({"path": _path(n, root), "what": w})
				break
	return out


func _ready() -> void:
	await get_tree().process_frame
	var s: Node = (load(DevHooks.get_s("audit-scene", "res://scenes/slice.tscn")) as PackedScene).instantiate()
	get_tree().root.add_child(s)
	for i: int in int(DevHooks.get_f("audit-frames", 40.0)):
		await get_tree().physics_frame
	var lit: Array = scan(s, NOT_GRID)
	for l: Dictionary in scan(s):
		if not lit.any(func(x: Dictionary) -> bool: return x["path"] == l["path"]):
			print("[lights] (not the grid) %s  [%s]" % [l["path"], l["what"]])
	var by: Dictionary = {}
	for l: Dictionary in lit:
		var key: String = "%s  [%s]" % [l["path"], l["what"]]
		by[key] = int(by.get(key, 0)) + 1
	for k: String in by:
		print("[lights] LIT x%d  %s" % [by[k], k])
	print("[lights] lit lights: %d (hub level %d)" % [lit.size(), int(GameState.world.get("hub_level", 1))])
	get_tree().quit(1 if lit.size() > 0 else 0)
