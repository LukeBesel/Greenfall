class_name EggPower
extends RefCounted
## [qafix] Owner: "when you land, NOTHING works". Easter-egg machines (the vending machine, TV,
## jukebox, security camera, arcade and microwave) start dead: no lit screens, tubes or LEDs, no
## glow lights, no glowing text. Lumi's first poke wakes one (story/eggs.gd _effect), and a found
## egg stays awake on later loads.

const KINDS: Array[String] = ["vending", "tv", "jukebox", "camera", "arcade", "microwave"]
const META: String = "qafix_dead"


static func applies(kind: String) -> bool:
	return kind in KINDS


static func is_dead(node: Node) -> bool:
	return node != null and node.has_meta(META)


## Switches every emissive surface, glow light and unshaded label under `node` off (reversible).
static func kill(node: Node3D) -> void:
	if node == null or is_dead(node):
		return
	node.set_meta(META, true)
	for c: Node in node.find_children("*", "", true, false):
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var m: StandardMaterial3D = mi.material_override as StandardMaterial3D
			if m and m.emission_enabled:
				mi.set_meta(META, m)
				mi.material_override = dead_material(m)
			elif mi.material_override == null and mi.mesh:
				for s: int in mi.mesh.get_surface_count():
					var sm: StandardMaterial3D = mi.mesh.surface_get_material(s) as StandardMaterial3D
					if sm and sm.emission_enabled:
						mi.set_meta(META, true)
						mi.set_surface_override_material(s, dead_material(sm))
		elif c is OmniLight3D or c is SpotLight3D:
			var l: Light3D = c
			l.set_meta(META, l.light_energy)
			l.light_energy = 0.0
		elif c is Label3D and not (c as Label3D).shaded:
			(c as Label3D).set_meta(META, (c as Label3D).visible)
			(c as Label3D).visible = false


## Brings everything `kill` switched off back.
static func wake(node: Node3D) -> void:
	if not is_dead(node):
		return
	node.remove_meta(META)
	for c: Node in node.find_children("*", "", true, false):
		if not c.has_meta(META):
			continue
		var v: Variant = c.get_meta(META)
		c.remove_meta(META)
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			if v is Material:
				mi.material_override = v
			else:
				for s: int in mi.get_surface_override_material_count():
					mi.set_surface_override_material(s, null)
		elif c is Light3D:
			(c as Light3D).light_energy = float(v)
		elif c is Label3D:
			(c as Label3D).visible = bool(v)


## A switched-off copy: no emission, the colour of unlit glass or plastic.
static func dead_material(m: StandardMaterial3D) -> StandardMaterial3D:
	var d: StandardMaterial3D = m.duplicate()
	d.emission_enabled = false
	d.albedo_color = m.albedo_color.darkened(0.6)
	d.albedo_texture = null
	d.roughness = maxf(m.roughness, 0.45)
	return d
