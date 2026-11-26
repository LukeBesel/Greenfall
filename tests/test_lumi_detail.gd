extends GutTest
## [art2] Lumi's hardware detail (art/models/aurora/lumi_detail.glb) stays editable at the Locker:
## every surface uses one of PatchModel's named material slots (so paint, trim, accent, glow and the
## side-module colour reach it), and the parts are separate objects the Locker can swap.

const SLOTS: Array[String] = ["paint", "trim", "accent", "dark", "steel", "glow", "lamp_accent", "side"]


func test_detail_parts_use_only_locker_slots() -> void:
	var scene: PackedScene = load(PatchModel.DETAIL_PATH)
	assert_not_null(scene)
	var inst: Node = scene.instantiate()
	var names: Array[String] = []
	for n: Node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		names.append(str(mi.name))
		for i: int in mi.mesh.get_surface_count():
			var src: Material = mi.mesh.surface_get_material(i)
			assert_true(src != null and SLOTS.has(src.resource_name), "%s surface %d: slot %s" % [mi.name, i, src.resource_name if src else "none"])
	inst.free()
	for want: String in ["detail_head", "detail_ears", "detail_body"]:
		assert_has(names, want)


func test_detail_follows_the_models_materials() -> void:
	var m := PatchModel.new()
	add_child_autofree(m)
	var mats: Dictionary = m.get("_mats")
	var seen_glow: bool = false
	for n: Node in m.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = n
		if mi.mesh == null or not str(mi.mesh.resource_path).contains("lumi_detail"):
			continue
		for i: int in mi.mesh.get_surface_count():
			var key: String = mi.mesh.surface_get_material(i).resource_name
			var want: Material = mats.get(key)
			var got: Material = mi.get_surface_override_material(i)
			assert_true(want != null and got == want, "%s uses the shared %s material" % [mi.name, key])
			seen_glow = seen_glow or (key == "glow" and got == mats["glow"])
	assert_true(seen_glow, "the ear rings glow with the Locker's light colour")
