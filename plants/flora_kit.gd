class_name FloraKit
extends RefCounted
## [art7] The regrowth plant kit: the meshes of art/models/flora/flora.glb (built in Blender by
## art/models/flora/build_flora.py) and the one material every plant shares (plants/flora.gdshader
## on art/models/flora/flora_atlas.png). CellVerdure draws them as MultiMeshes.

const GLB: String = "res://art/models/flora/flora.glb"
const ATLAS: String = "res://art/models/flora/flora_atlas.png"
const FLOWERS: Array[String] = ["flower_daisy", "flower_poppy", "flower_umbel", "flower_lupin", "flower_aster"]
const BUSHES: Array[String] = ["bush_a", "bush_b", "bush_c"]
const TREES: Array[String] = ["birch", "oak", "pine", "blossom"]

static var _meshes: Dictionary = {}
static var _mat: ShaderMaterial


## name -> Mesh for every object in the kit (loaded once).
static func meshes() -> Dictionary:
	if _meshes.is_empty():
		_trace(GLB)
		var ps: PackedScene = load(GLB) as PackedScene
		if ps == null:
			push_error("FloraKit: %s is missing (blender -b --python art/models/flora/build_flora.py)" % GLB)
			return _meshes
		var root: Node = ps.instantiate()
		for n: Node in root.find_children("*", "MeshInstance3D", true, false):
			_meshes[str(n.name)] = (n as MeshInstance3D).mesh
		root.free()
	return _meshes


static func mesh(nm: String) -> Mesh:
	return meshes().get(nm) as Mesh


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://plants/flora.gdshader") as Shader
		_trace(ATLAS)
		_mat.set_shader_parameter("atlas", load(ATLAS))
	return _mat


## A tree mesh name: species, age 0..2 (sapling, young, grown), far = its low-detail twin.
static func tree(species: int, age: int, far: bool) -> String:
	var nm: String = "tree_%s_%d" % [TREES[species % TREES.size()], clampi(age, 0, 2)]
	return nm + "_lod" if far and age > 0 else nm


## A blocking load during a traced build goes on the preload list (data/orbit_preload.json, as
## AssetLib's own textures do), so the loader threads read the kit behind the loading screen.
static func _trace(path: String) -> void:
	if AssetLib.tracing and not ResourceLoader.has_cached(path) and not AssetLib.traced.has("tex:" + path):
		AssetLib.traced.append("tex:" + path)
