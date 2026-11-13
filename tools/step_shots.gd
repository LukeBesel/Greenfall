class_name StepShots
extends RefCounted
## [v9d] The clarity sweep's pictures: one rendered frame at the moment each story step starts,
## in one run (the brief's VISUAL check: a marker in the world, a picture on the card, a count).
## It jumps the objective card to each step in turn (the world state stays the start's: the card,
## the beam and the step's markers are what is judged), waits, and saves the frame.
##   tools/shot.sh v9/steps --orbit --no-intro --step-shots[=wait_s] [--step-shots-from=K --step-shots-to=K]
##   (rendered; the first frame after --step-shots-at=S wall-clock s, default 100; wait_s is wall-clock too). Frames: screenshots/v9/step_NN_<id>.png
## After the story steps, the first goals of the goal chain (--step-shots-goals=N, default 3).


static func run_dev(so: SliceOrbit) -> void:
	var tree: SceneTree = so.w.get_tree()
	await _wall(tree, DevHooks.get_f("step-shots-at", 100.0))
	var w: Node = so.w
	var ob: Objectives = w.get("objectives") as Objectives
	if ob == null:
		print("[stepshots] no objectives")
		return
	print("[stepshots] start: %d steps" % ob.chain.size())
	var wait: float = DevHooks.get_f("step-shots", 7.0)
	var from: int = int(DevHooks.get_f("step-shots-from", 0.0))
	var to: int = mini(int(DevHooks.get_f("step-shots-to", float(ob.chain.size() - 1))), ob.chain.size() - 1)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://screenshots/v9"))
	GameState.flags["onboard_brief"] = true
	GameState.flags["tutorial_step"] = Tutorial.STEPS.size()
	var tut: Variant = w.get("tutorial")
	if tut is Tutorial:  # past the opening checklist (its card would cover the step's)
		(tut as Tutorial).step = Tutorial.STEPS.size()
		EventBus.tutorial_changed.emit("")
	if not Camp.bench_ok() and w.get("camp") != null:
		(w.get("camp") as Camp).repair_bench()
	ob.revealed = true
	for k: int in range(from, to + 1):
		ob.step = k
		GameState.flags["objective_step"] = k
		ob.changed.emit(k)
		await _wall(tree, wait)
		await _save(tree, "step_%02d_%s" % [k, str(ob.chain[k].get("id", ""))], ob)
	var gl: Goals = w.get("goals") as Goals
	var n: int = int(DevHooks.get_f("step-shots-goals", 3.0))
	if gl != null and n > 0:
		ob.step = ob.chain.size()
		GameState.flags["objective_step"] = ob.step
		for i: int in n:
			ob.changed.emit(ob.step)
			await _wall(tree, wait)
			var gi: Array[int] = gl.current()
			if gi.is_empty():
				break
			await _save(tree, "goal_%02d_%s" % [i, str(gl.chain[gi[0]].get("id", ""))], ob)
			gl.complete(gi[0])
	print("[stepshots] done")
	tree.quit(0)


## Waits wall-clock seconds (a rendered globe runs at ~2 fps, where the engine's capped frame
## step makes game-time timers run several times slower than the clock), at least 3 frames.
static func _wall(tree: SceneTree, secs: float) -> void:
	var until: int = Time.get_ticks_msec() + int(secs * 1000.0)
	var n: int = 0
	while Time.get_ticks_msec() < until or n < 3:
		await tree.process_frame
		n += 1


static func _save(tree: SceneTree, name: String, ob: Objectives) -> void:
	await tree.process_frame
	await tree.process_frame
	var img: Image = tree.root.get_texture().get_image()
	var path: String = "res://screenshots/v9/%s.png" % name
	if img != null and not img.is_empty():
		img.save_png(ProjectSettings.globalize_path(path))
	var d: Dictionary = ob.current()
	var tgt: Dictionary = ob.step_target(d) if not d.is_empty() else {}
	print("[stepshots] %s  card='%s'  target=%s  progress=%s" % [path, str(d.get("text", "")), str(tgt.get("to", "")), str(ob.progress()[1]) if not d.is_empty() else ""])
