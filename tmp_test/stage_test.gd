extends Node
var st: SpaceStage
var f: int = 0
func _ready() -> void:
	var root: Viewport = get_tree().root
	var cl := CanvasLayer.new()
	add_child(cl)
	st = SpaceStage.new()
	cl.add_child(st)
	if OS.get_environment("D3D") == "1":
		root.disable_3d = true
	var setn: String = OS.get_environment("SET")
	if setn == "":
		setn = "space"
	st.show_set(setn)
	var ark: CradleShip = st.ark
	ark.rotation = Vector3(0, -PI * 0.5, 0)
	ark.position = Vector3(-8, 0, 0)
	var cam := OS.get_environment("CAM").split(",")
	if cam.size() >= 6:
		var o: Vector3 = SpaceStage.VAULT_AT if setn == "vault" else (SpaceStage.GARDEN_AT if setn == "garden" else Vector3.ZERO)
		st.aim(o + Vector3(float(cam[0]), float(cam[1]), float(cam[2])), o + Vector3(float(cam[3]), float(cam[4]), float(cam[5])), 45.0)
	else:
		st.aim(Vector3(30, 9, 52), Vector3(-6, -8, 0), 42.0)
	if setn == "vault":
		st.lumi.position = Vector3(-0.2, 0.15, -1.05)
		st.lumi.rotation.y = PI - 0.15

func _process(_d: float) -> void:
	f += 1
	if f == int(OS.get_environment("FR") if OS.get_environment("FR") != "" else "8"):
		var img: Image = get_tree().root.get_texture().get_image()
		img.save_png(OS.get_environment("OUT"))
		print("saved ", OS.get_environment("OUT"))
		print("DBG vp size ", st.vp.size, " cam ", st.vp.get_camera_3d(), " cur ", st.cam.current, " csize ", st.size, " world ", st.vp.world_3d, " camworld ", st.cam.get_world_3d(), " env ", st.env.background_mode)
		get_tree().quit()
