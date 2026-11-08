class_name SystemProps
extends RefCounted
## [home] Props for the Homeward cinematics on a SpaceStage (story/space_stage.gd): the other four
## planets of the Verdance system hanging far off in the starfield (data/homeward.json colours,
## lit or still dusty), and a rocket model for the space shots.


## Adds the system's other planets around `center` (stage space set). `restored`: planet id -> 0..1.
static func add_planets(stage: SpaceStage, center: Vector3, restored: Dictionary = {}) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var root: Node3D = stage.root_of("space")
	var ps: Array = Homeward.planets()
	for k: int in range(1, ps.size()):
		var d: Dictionary = ps[k]
		var col: Array = d.get("color", [0.5, 0.5, 0.5])
		var c := Color(float(col[0]), float(col[1]), float(col[2]))
		var g: float = float(restored.get(str(d["id"]), 0.0))
		var m := StandardMaterial3D.new()
		m.albedo_color = c.lerp(Color(0.42, 0.4, 0.36), 0.45 * (1.0 - g)).lerp(Color(0.3, 0.55, 0.3), 0.25 * g)
		m.roughness = 0.85
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = 0.06 + 0.12 * g
		var mi := MeshInstance3D.new()
		mi.mesh = ProcMesh.sphere(1.0, 32, 16)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a: float = -0.9 + k * 0.55
		var dist: float = 260.0 + k * 90.0
		mi.position = center + Vector3(sin(a) * dist, 40.0 + k * 14.0, -cos(a) * dist)
		mi.scale = Vector3.ONE * (9.0 + float(d.get("orbit", 1.0)) * 2.0)
		mi.name = "Planet_%s" % str(d["id"])
		root.add_child(mi)
		out.append(mi)
	return out


## A rocket for the space shots (the Mk IV look with a green Homeward band), plume on.
static func add_rocket(stage: SpaceStage, pos: Vector3) -> RocketModel:
	var r := RocketModel.new()
	stage.root_of("space").add_child(r)
	r.build(4)
	r.position = pos
	var band := MeshInstance3D.new()
	band.mesh = ProcMesh.torus(1.15, 1.3, 32, 6)
	band.material_override = Mats.lamp(Color(0.5, 1.0, 0.6), 3.0)
	band.position = Vector3(0, 3.2, 0)
	band.scale = Vector3(1, 0.4, 1)
	r.add_child(band)
	if r.plume:
		r.plume.power = 1.0
	return r


## Green running lights along the ark's hull: the Cradle waking up (0..1).
static func wake_ark(ark: CradleShip, k: float) -> void:
	var holder: Node3D = ark.get_node_or_null("HomeWake") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "HomeWake"
		ark.add_child(holder)
		var mat := Mats.lamp(Color(0.55, 1.0, 0.65), 4.0)
		for i: int in 14:
			for s: float in [-1.0, 1.0]:
				var b := MeshInstance3D.new()
				b.mesh = ProcMesh.sphere(0.16, 8, 4)
				b.material_override = mat
				b.position = Vector3(s * 2.6, 0.6, -15.0 + i * 2.2)
				b.visible = false
				holder.add_child(b)
	var n: int = holder.get_child_count()
	for i: int in n:
		(holder.get_child(i) as Node3D).visible = float(i) / n < k
