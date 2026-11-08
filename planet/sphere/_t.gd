extends SceneTree
func _init() -> void:
	for lv in [6, 7]:
		var t: int = Time.get_ticks_msec()
		var g = load("res://core/geosphere.gd").new(lv)
		g.generate()
		var t1: int = Time.get_ticks_msec()
		g.save_cache("user://sg_test_%d.bin" % lv)
		var t2: int = Time.get_ticks_msec()
		var h = load("res://core/geosphere.gd").new(lv)
		h.load_cache("user://sg_test_%d.bin" % lv)
		print("level %d cells %d gen %d ms save %d load %d ms" % [lv, g.cell_count(), t1 - t, t2 - t1, Time.get_ticks_msec() - t2])
	quit()
