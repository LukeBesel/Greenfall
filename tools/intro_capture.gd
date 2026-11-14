class_name IntroCapture
extends Node
## Dev: saves the intro as a frame sequence so it can be judged on a box that cannot play it in
## real time. Run rendered with Godot's --fixed-fps so every frame is the same slice of film time
## however slow the renderer is:
##   bash render.sh --fixed-fps 30 -- --fresh --orbit --intro --quality=1 \
##       --intro-frames=screenshots/v9/intro/after --intro-every=6 [--intro-from-t=40 --intro-to-t=60]
## --intro-every=K keeps every Kth frame (30 fps / 6 = 5 frames per film second); the file name
## is the film time in hundredths of a second (f_004250.jpg = 42.5 s). --intro-tail=S keeps
## capturing S seconds after the hand-off (default 3), then quits. tools/intro_sheet.py makes
## contact sheets from the folder. See docs/ADJUSTING.md "The opening film".

var intro: Node
var _dir: String
var _every: int = 6
var _n: int = 0
var _tail: float = 3.0
var _after: float = 0.0
var _from: float = 0.0
var _to: float = 1e9
var _prev_t: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_dir = DevHooks.get_s("intro-frames", "screenshots/v9/intro/frames")
	if not _dir.begins_with("/"):
		_dir = ProjectSettings.globalize_path("res://" + _dir)
	DirAccess.make_dir_recursive_absolute(_dir)
	_every = maxi(1, int(DevHooks.get_f("intro-every", 6.0)))
	_tail = DevHooks.get_f("intro-tail", 3.0)
	_from = DevHooks.get_f("intro-from-t", 0.0)
	_to = DevHooks.get_f("intro-to-t", 1e9)
	print("[introcap] frames -> %s (every %d)" % [_dir, _every])


func _process(delta: float) -> void:
	if intro == null or not is_instance_valid(intro):
		return
	var t: float = float(intro.get("_t"))
	var busy: bool = bool(intro.call("busy"))
	if not busy:
		_after += delta
		t += _after
	# The viewport texture holds the frame drawn last tick: label it with that tick's time.
	_n += 1
	if _n % _every == 0 and _prev_t >= _from and _prev_t <= _to and _prev_t > 0.0:
		var img: Image = get_viewport().get_texture().get_image()
		img.save_jpg("%s/f_%06d.jpg" % [_dir, int(round(_prev_t * 100.0))], 0.88)
	_prev_t = t
	if (not busy and _after >= _tail) or _prev_t > _to + 0.5:
		print("[introcap] done at %.1fs" % t)
		get_tree().quit()
