class_name OutpostPad
extends RefCounted
## [art4] The start yard's pad: a raised concrete quay (owner's world target: "a raised stone and
## concrete quay with a worn kerb and hazard paint at its edge, wet and stained, not a clean pale
## slab"). The mesh and its painted maps are made in code and kept next to their build scripts:
##   art/models/outpost/build_pad_maps.py   colour / normal / occlusion-roughness-metal + micro tile
##   art/models/outpost/build_pad.py        36 settled slabs with open joints, drain channel, kerb
##                                          stones, ramp plate, light lenses -> outpost_pad.glb
## Two draw calls (deck, lenses), no shadow pass, no collider (the walk surface is the site's own).
##   var pad := OutpostPad.build()                    # Node3D "YardPad" > MeshInstance3D "CleanPad"
##   OutpostPad.set_powered(tree, on)                 # the deck-edge lights: dark until the yard has power

const GLB: String = "res://art/models/outpost/outpost_pad.glb"
const DIR: String = "res://art/models/outpost/"
const SHADER: Shader = preload("res://art/models/outpost/outpost_pad.gdshader")
const GROUP: StringName = &"outpost_pad"
const LIGHT_ON := Color(1.0, 0.74, 0.42)

static var _mesh: Mesh
static var _deck: ShaderMaterial
static var _lens: Dictionary = {}  # powered -> StandardMaterial3D


static func mesh() -> Mesh:
	if _mesh == null:
		var ps: PackedScene = load(GLB) as PackedScene
		if ps:
			var inst: Node = ps.instantiate()
			var found: Array[Node] = inst.find_children("*", "MeshInstance3D", true, false)
			if inst is MeshInstance3D:
				found.push_front(inst)
			if not found.is_empty():
				_mesh = (found[0] as MeshInstance3D).mesh
			inst.free()
	return _mesh


static func deck_material() -> ShaderMaterial:
	if _deck == null:
		_deck = ShaderMaterial.new()
		_deck.shader = SHADER
		_deck.resource_name = "pad_deck"
		_deck.set_shader_parameter("alb_tex", load(DIR + "pad_albedo.png"))
		_deck.set_shader_parameter("nrm_tex", load(DIR + "pad_normal.png"))
		_deck.set_shader_parameter("orm_tex", load(DIR + "pad_orm.png"))
		_deck.set_shader_parameter("detail_tex", load(DIR + "pad_detail.png"))
	return _deck


## The lenses' glass: dark and glossy without power, a warm glow with it.
static func lens_material(on: bool) -> StandardMaterial3D:
	if not _lens.has(on):
		var m := StandardMaterial3D.new()
		m.resource_name = "pad_lights:%s" % on
		m.albedo_color = Color(0.9, 0.8, 0.65) if on else Color(0.07, 0.075, 0.08)
		m.roughness = 0.22
		if on:
			m.emission_enabled = true
			m.emission = LIGHT_ON
			m.emission_energy_multiplier = 2.4
		_lens[on] = m
	return _lens[on]


static func build() -> Node3D:
	var root := Node3D.new()
	root.name = "YardPad"
	var mi := MeshInstance3D.new()
	mi.name = "CleanPad"
	mi.mesh = mesh()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta("no_collide", true)
	mi.set_meta("pad_powered", false)
	mi.add_to_group(GROUP)
	root.add_child(mi)
	_apply(mi, false)
	return root


static func _apply(mi: MeshInstance3D, on: bool) -> void:
	if mi.mesh == null:
		return
	for s: int in mi.mesh.get_surface_count():
		var nm: String = (mi.mesh as ArrayMesh).surface_get_name(s) if mi.mesh is ArrayMesh else ""
		var mat: Material = mi.mesh.surface_get_material(s)
		if nm == "" and mat:
			nm = mat.resource_name
		mi.set_surface_override_material(s, lens_material(on) if nm.begins_with("pad_lights") else deck_material())
	mi.set_meta("pad_powered", on)


## Lights (or kills) the deck-edge lenses of every pad in the tree. Cheap to call again.
static func set_powered(tree: SceneTree, on: bool) -> void:
	if tree == null:
		return
	for n: Node in tree.get_nodes_in_group(GROUP):
		if n is MeshInstance3D and bool(n.get_meta("pad_powered", false)) != on:
			_apply(n as MeshInstance3D, on)
