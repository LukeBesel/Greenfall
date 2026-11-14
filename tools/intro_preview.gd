extends Node3D
## Dev: plays the opening film's off-world shots (the SpaceStage ones) without building the globe,
## so they render in seconds and in little memory:
##   xvfb-run ... godot --path . --rendering-driver opengl3 --fixed-fps 10 res://tools/intro_preview.tscn -- \
##       --intro-frames=screenshots/v9/intro/x --intro-every=2 [--intro-at=31 --intro-to-t=45]
## A stand-in world gives the Intro what it asks of the game (a Lumi to hide, nothing else). The
## in-world shots (the landing, the wake-up) need the real game: `-- --fresh --orbit --intro`.

class StubPatch:
	extends Node3D
	var model: PatchModel
	var input: Variant = null

var patch: StubPatch


func _ready() -> void:
	patch = StubPatch.new()
	patch.model = PatchModel.new()
	patch.add_child(patch.model)
	add_child(patch)
	var cam := Camera3D.new()
	add_child(cam)
	var it := Intro.new()
	it.name = "Intro"
	it.world = self
	it.stage_only = true
	add_child(it)
	it.finished.connect(get_tree().quit)
	it.play.call_deferred()
