extends GutTest
## [orbE] The lens view on the globe: SphereCam puts the eye at the model's lens point, looks level
## along the frame on the local up (no roll on the curve), and gives the near plane back after.


func _target(surface: SphereSurface, dir: Vector3) -> Node3D:
	var sc := GDScript.new()
	sc.source_code = "extends Node3D\nvar model: Node3D\n"
	sc.reload()
	var t := Node3D.new()
	t.set_script(sc)
	var model := Node3D.new()
	t.add_child(model)
	t.set("model", model)
	add_child_autofree(t)
	t.global_transform = Transform3D(SphereMath.basis_from_up_fwd(dir, SphereGrid.frame(dir).x), surface.ground(dir))
	return t


func test_lens_pose_on_the_curve() -> void:
	var surface := SphereSurface.new(1840.0)
	var dir := Vector3(0.4, 0.6, -0.69).normalized()
	var t: Node3D = _target(surface, dir)
	var cam := SphereCam.new()
	cam.surface = surface
	cam.target = t
	add_child_autofree(cam)
	cam.reset_frame(SphereGrid.frame(dir).x)
	cam.pitch = 0.0
	var near0: float = cam.camera.near
	cam.lens_view = true
	cam.update_camera(0.0)
	var lens_p: Vector3 = (t.get("model") as Node3D).to_global(Vector3(0, 0.78, -0.3))
	assert_almost_eq(cam.camera.global_position.distance_to(lens_p), 0.0, 0.01, "the eye sits at the lens")
	var u: Vector3 = surface.up_at(t.global_position)
	assert_almost_eq(cam.camera.global_basis.x.dot(u), 0.0, 0.01, "no roll against the local horizon")
	assert_almost_eq((-cam.camera.global_basis.z).dot(u), 0.0, 0.01, "pitch 0 looks level")
	assert_almost_eq(cam.camera.near, 0.32, 0.001)
	cam.lens_view = false
	cam.update_camera(0.0)
	assert_almost_eq(cam.camera.near, near0, 0.001, "near plane given back")
