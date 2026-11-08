extends Node
## [style] Renders the Character Builder on its own (no world), for screenshots:
##   godot --path . --rendering-driver vulkan --resolution 1280x720 res://scenes/style_builder_shot.tscn -- --fresh --lumi-random=3 --lumi-builder-slot=head --out=screenshots/style_builder
## Writes <out>_0.png (the slot list + editor), then fires the demo laser and writes <out>_1.png.

var _b: LumiBuilder
var _t: float = 0.0
var _step: int = 0


func _ready() -> void:
	# A mid-game player: three designs unlocked, the rest still "???".
	GameState.flags["skins_unlocked"] = ["aurora", "bolt", "pixel", "nova"]
	GameState.stats["trinkets_found"] = 9
	if DevHooks.has("lumi-random"):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(DevHooks.get_f("lumi-random", 1.0))
		LumiStyle.set_current(LumiStyle.randomized(rng, LumiStyle.current()))
	_b = LumiBuilder.open(null, self)
	var sel: String = DevHooks.get_s("lumi-builder-slot", "")
	if sel != "":
		_b.call_deferred("_select", sel)


func _process(delta: float) -> void:
	_t += delta
	var out: String = DevHooks.get_s("out", "screenshots/style_builder")
	if _step == 0 and _t > 6.0:
		DevHooks.save_viewport(out + "_0.png")
		_step = 1
		_t = 0.0
		_b._preview.demo_beam()
	elif _step == 1 and _t > 0.3:
		DevHooks.save_viewport(out + "_1.png")
		get_tree().quit()
