extends GutTest
## B34: guards for long dev runs. --quit-after has a backstop that does not need the main loop
## (tools/quit_watchdog.gd), and --nan-watch names nodes given a non-finite transform
## (tools/nan_watch.gd).

class Fired extends RefCounted:
	var lock := Mutex.new()
	var count: int = 0

	func hit() -> void:
		lock.lock()
		count += 1
		lock.unlock()

	func hits() -> int:
		lock.lock()
		var n: int = count
		lock.unlock()
		return n


func test_watchdog_is_due_only_past_limit_and_grace() -> void:
	assert_false(QuitWatchdog.overdue(1000, 1000, 600000, 30000), "not at the start")
	assert_false(QuitWatchdog.overdue(601000, 1000, 600000, 30000), "not at the limit: the main loop quits by itself there")
	assert_false(QuitWatchdog.overdue(630999, 1000, 600000, 30000), "not inside the grace")
	assert_true(QuitWatchdog.overdue(631000, 1000, 600000, 30000), "due once the grace is over")


## The main loop is held here (no await), as in a frame that never ends: the watchdog still fires.
func test_watchdog_fires_while_the_main_loop_is_stuck() -> void:
	var f := Fired.new()
	var w := QuitWatchdog.new()
	w.start(Time.get_ticks_msec(), 0.1, 0.1, f.hit)
	OS.delay_msec(700)
	assert_eq(f.hits(), 1, "fired once, with no frame processed")
	w.stop()


func test_watchdog_stays_quiet_when_the_run_stops_in_time() -> void:
	var f := Fired.new()
	var w := QuitWatchdog.new()
	w.start(Time.get_ticks_msec(), 30.0, 30.0, f.hit)
	OS.delay_msec(250)
	w.stop()
	assert_eq(f.hits(), 0, "a run that stops in time is never touched")


## A later start (a planet that counts from the end of its build) moves the deadline with it.
func test_watchdog_follows_a_moved_start() -> void:
	var f := Fired.new()
	var w := QuitWatchdog.new()
	w.start(Time.get_ticks_msec(), 0.1, 0.1, f.hit)
	w.start_ms = Time.get_ticks_msec() + 60000
	OS.delay_msec(500)
	assert_eq(f.hits(), 0, "the limit counts from the moved start")
	w.stop()


func test_nan_watch_names_the_node_given_a_bad_transform() -> void:
	var root := Node3D.new()
	var good := Node3D.new()
	var bad := Node3D.new()
	var child := Node3D.new()
	add_child_autofree(root)
	root.add_child(good)
	root.add_child(bad)
	bad.add_child(child)
	assert_eq(NanWatch.non_finite(root).size(), 0, "a clean tree has none")
	bad.position = Vector3(NAN, 0.0, 0.0)
	var found: Array[Node3D] = NanWatch.non_finite(root)
	assert_eq(found.size(), 1, "the node given the value, not the child that inherits it")
	assert_eq(found[0], bad)


## The NaN source of B34: an idle robot's arm eased toward rest with an unclamped weight
## (delta * 4). On long frames the weight passes 2, each frame overshoots further, and after
## about a minute of idling the arm's angle overflowed and its transform went NaN.
func test_idle_robot_arm_stays_finite_on_long_frames() -> void:
	for look: String in ["salvage", "restored", "modern"]:
		var v := RobotVisual.new()
		add_child_autofree(v)
		v.build("scoopie", look)
		assert_not_null(v._arm, "the %s Scoopie has an arm" % look)
		for i: int in 3000:
			v.animate(0.0, false, 1.0)  # one game second a frame: an 8x run at 8 fps
		assert_true(v._arm.transform.is_finite(), "%s arm transform is finite" % look)
		assert_lt(absf(v._arm.rotation.x), 0.5, "%s arm rests near level" % look)
		assert_eq(NanWatch.non_finite(v).size(), 0, "no part of the idle %s robot has a bad transform" % look)
