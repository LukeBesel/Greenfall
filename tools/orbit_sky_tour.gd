class_name OrbitSkyTour
extends Node
## [orbE] Render tour for the round planet's sky (--orbit-tour=0.5,0.76,0.95 --tour-shot=PATH):
## after the world settles, freezes the clock, moves the planet so that Lumi's spot gets each
## local time in turn, waits for lights and Glim to settle, saves PATH_<i>.png and quits.
## --tour-settle=S (wall seconds before the first shot, default 25), --tour-every=S (default 8).

var sky: SkyDirector
var times: PackedFloat32Array = []
var _t0: int = 0
var _i: int = -1
var _next: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the system map pauses the tree
	for s: String in DevHooks.get_s("orbit-tour", "0.5,0.76,0.95").split(","):
		times.append(float(s))
	_t0 = Time.get_ticks_msec()
	_next = DevHooks.get_f("tour-settle", 25.0)


func _process(_delta: float) -> void:
	if sky == null:
		return
	var el: float = (Time.get_ticks_msec() - _t0) / 1000.0
	if el < _next:
		return
	if _i >= 0:  # shoot the time set last step
		var base: String = DevHooks.get_s("tour-shot", "screenshots/orbit_tour")
		DevHooks.save_viewport("%s_%d.png" % [base, _i])
		print("[tour] shot %d local=%.2f daylight=%.2f moon=%.2f sun=%.2f exposure=%.2f fps=%d" % [_i, sky.time_of_day, sky.daylight,
			sky.moon.light_energy, sky.sun.light_energy, sky.env.tonemap_exposure, Engine.get_frames_per_second()])
	_i += 1
	if _i >= times.size():
		get_tree().quit()
		return
	sky.frozen = true
	sky.time_of_day = times[_i]
	_next = el + DevHooks.get_f("tour-every", 8.0)
