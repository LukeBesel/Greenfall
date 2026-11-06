class_name Liveries
extends RefCounted
## Fleet liveries bought with contract tokens (data/events.json "shop", kind "livery"): a small
## add-on fitted to every robot (underglow ring, pennant, holo halo). The equipped one is
## GameState.flags["livery"] ("" = none). WorldEvents calls sync() now and then; it only
## rebuilds a robot's add-on when the livery changed or the robot is new.

const NODE_NAME: String = "Livery"


static func equipped() -> String:
	return str(GameState.flags.get("livery", ""))


static func sync(fleet: Fleet) -> void:
	if fleet == null:
		return
	var want: String = equipped()
	for r: Robot in fleet.robots():
		var cur: Node = r.get_node_or_null(NODE_NAME)
		var have: String = str(cur.get_meta("livery", "")) if cur else ""
		if have == want:
			continue
		if cur:
			r.remove_child(cur)
			cur.queue_free()
		if want != "":
			var n: Node3D = build(want)
			if n:
				r.add_child(n)


static func build(id: String) -> Node3D:
	var it: Dictionary = Contracts.shop_item(id)
	if it.is_empty():
		return null
	var col: Color = Color.html(str(it.get("color", "#5fe6ff")))
	var n := Node3D.new()
	n.name = NODE_NAME
	n.set_meta("livery", id)
	match id:
		"livery_neon", "livery_sunset":
			var ring := MeshInstance3D.new()
			ring.mesh = ProcMesh.torus(0.42, 0.5, 32, 4)
			ring.material_override = EventProps.glow_mat(col, 0.9, 1.8)
			ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			ring.position = Vector3(0, 0.06, 0)
			ring.scale = Vector3(1, 0.25, 1)
			n.add_child(ring)
			var light := OmniLight3D.new()
			light.light_color = col
			light.light_energy = 0.9
			light.omni_range = 1.6
			light.position = Vector3(0, 0.12, 0)
			n.add_child(light)
		"livery_pennant":
			var pole_mat := StandardMaterial3D.new()
			pole_mat.albedo_color = Color(0.85, 0.85, 0.82)
			pole_mat.metallic = 0.8
			n.add_child(EggProps.mesh(ProcMesh.cyl(0.012, 0.012, 0.9, 6), pole_mat, Vector3(0.22, 1.2, 0.18)))
			var flag := StandardMaterial3D.new()
			flag.albedo_color = col
			flag.cull_mode = BaseMaterial3D.CULL_DISABLED
			flag.emission_enabled = true
			flag.emission = col
			flag.emission_energy_multiplier = 0.35
			var pm := PrismMesh.new()
			pm.size = Vector3(0.3, 0.2, 0.01)
			n.add_child(EggProps.mesh(pm, flag, Vector3(0.22, 1.55, 0.33), Vector3(0, 90, -90)))
		"livery_halo":
			var halo := MeshInstance3D.new()
			halo.name = "Halo"
			halo.mesh = ProcMesh.torus(0.26, 0.3, 32, 4)
			halo.material_override = EventProps.glow_mat(col, 0.85, 2.0)
			halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			halo.position = Vector3(0, 1.45, 0)
			halo.rotation_degrees = Vector3(12, 0, 0)
			n.add_child(halo)
	return n


## Small per-frame motion (the halo turns, the pennant flutters).
static func animate(fleet: Fleet, t: float) -> void:
	if fleet == null or equipped() == "":
		return
	for r: Robot in fleet.robots():
		var n: Node3D = r.get_node_or_null(NODE_NAME) as Node3D
		if n == null:
			continue
		var h: Node3D = n.get_node_or_null("Halo") as Node3D
		if h:
			h.rotation.y = t * 1.1
			h.position.y = 1.45 + sin(t * 2.0 + r.position.x) * 0.04
