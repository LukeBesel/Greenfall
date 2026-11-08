class_name PhotoAlbum
extends Node
## [extras] The photo album. Each district gets a "before" picture when Lumi first arrives and an
## "after" picture at three milestones (half the junk cleaned, a Thriving district, base level 5),
## always from the same camera over the base so the Album's before/after slider lines up. Photos
## taken in photo mode (ui/photo_mode.gd) get a thumbnail in the Album too.
## Cheap by design: a 384x216 one-shot SubViewport sharing the district's world (no SDFGI / SSR /
## volumetrics, no HUD), read back with RenderingDevice.texture_get_data_async where the renderer
## has one, and JPG-encoded on a WorkerThreadPool task (waited for on exit).
## Files: <SaveManager.save_dir()>/album/slot_<slot>/ (so per save profile and per world slot).
## State: GameState.flags.album = {d: {"<hub>": {name, before, m50, thriving, base5}}, photos: [{src, thumb, unix}]}.

const SHOT_SIZE := Vector2i(384, 216)
const THUMB_SIZE := Vector2i(256, 144)
const MILESTONES: Array[String] = ["m50", "thriving", "base5"]
const THRIVING_SHARE: float = 0.25
const MAX_PHOTOS: int = 60
const BEFORE_DELAY_S: float = 6.0
## The album camera, relative to the base: up and back over the yard, looking across the district.
const CAM_POS := Vector3(15.0, 17.0, 21.0)
const CAM_AT := Vector3(-3.0, 0.0, -12.0)

var world: Node
var _alive_t: float = 0.0
var _busy: bool = false
var _tasks: Array[int] = []
var _born_ms: int = 0
var _next_ms: int = 0


# --- Rules (static) ---------------------------------------------------------------------

static func st() -> Dictionary:
	var v: Variant = GameState.flags.get("album")
	if not (v is Dictionary):
		v = {}
		GameState.flags["album"] = v
	var d: Dictionary = v
	if not (d.get("d") is Dictionary):
		d["d"] = {}
	if not (d.get("photos") is Array):
		d["photos"] = []
	return d


static func dir() -> String:
	if not CradleMode.persist:  # --fresh / tests: never touch a player's album
		return "user://extras_scratch/album/slot_%d" % SaveManager.slot
	return SaveManager.save_dir().path_join("album").path_join("slot_%d" % SaveManager.slot)


static func entry(hub: int) -> Dictionary:
	var dd: Dictionary = st()["d"]
	var k: String = str(hub)
	if not (dd.get(k) is Dictionary):
		dd[k] = {}
	return dd[k]


static func has_shot(hub: int, kind: String) -> bool:
	var e: Variant = (st()["d"] as Dictionary).get(str(hub))
	return e is Dictionary and str((e as Dictionary).get(kind, "")) != ""


## Districts with a before picture, in hub order.
static func districts() -> Array[int]:
	var out: Array[int] = []
	for k: Variant in (st()["d"] as Dictionary):
		if has_shot(int(str(k)), "before"):
			out.append(int(str(k)))
	out.sort()
	return out


## The newest "after" kind a district has ("" = none yet).
static func latest_after(hub: int) -> String:
	var best: String = ""
	for m: String in MILESTONES:
		if has_shot(hub, m):
			best = m
	return best


static func milestone_name(kind: String) -> String:
	match kind:
		"before": return TranslationServer.translate("First arrival")
		"m50": return TranslationServer.translate("Half clean")
		"thriving": return TranslationServer.translate("Thriving")
		"base5": return TranslationServer.translate("Base level 5")
	return kind


static func shots_taken() -> int:
	var n: int = 0
	for k: Variant in (st()["d"] as Dictionary):
		for m: String in ["before"] + MILESTONES:
			if has_shot(int(str(k)), m):
				n += 1
	return n


## Which milestones a district has reached (pure; inputs from the live district).
static func reached(clean_share: float, thriving_share: float, hub_level: int) -> Array[String]:
	var out: Array[String] = []
	if clean_share >= 0.5:
		out.append("m50")
	if thriving_share >= THRIVING_SHARE:
		out.append("thriving")
	if hub_level >= 5:
		out.append("base5")
	return out


static func load_texture(path: String) -> Texture2D:
	if path == "" or not FileAccess.file_exists(path):
		return null
	var img: Image = Image.load_from_file(path)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


# --- Live node --------------------------------------------------------------------------

func setup(p_world: Node) -> void:
	world = p_world
	name = "PhotoAlbum"
	_born_ms = Time.get_ticks_msec()
	var ph: Variant = world.get("photo")
	if ph is PhotoMode:
		(ph as PhotoMode).captured.connect(_on_photo)


func _exit_tree() -> void:
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()


## Wall clock, not frame time: on a very slow frame rate the checks still come every 3 s.
func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	_alive_t = (now - _born_ms) / 1000.0
	if now < _next_ms or _busy:
		return
	_next_ms = now + 3000
	_reap()
	if not _can_shoot():
		return
	var hub: int = GameState.current_hub
	if not has_shot(hub, "before"):
		if _alive_t >= BEFORE_DELAY_S:
			capture("before")
		return
	for m: String in reached(_clean_share(), _thriving_share(), _hub_level()):
		if not has_shot(hub, m):
			capture(m)
			return


func _can_shoot() -> bool:
	if world == null or world.get("field") == null or bool(world.get("launching")):
		return false
	var intro: Variant = world.get("intro")
	if intro is Intro and (intro as Intro).busy():
		return false
	if BloomFinale.playing:
		return false
	return true


func _clean_share() -> float:
	var f: HexField = world.field
	return float(f.junk_hexes_cleaned()) / float(f.junk_hex_count) if f.junk_hex_count > 0 else 0.0


func _thriving_share() -> float:
	var hl: HexLevels = world.get("hex_levels") as HexLevels
	var f: HexField = world.field
	if hl == null:
		return 0.0
	var land: int = 0
	var thr: int = 0
	for h: int in f.hex_count():
		if f.is_water(h) or f.hex_hub[h] != 0:
			continue
		land += 1
		if hl.level_of(h) >= HexLevels.MAX_LEVEL:
			thr += 1
	return float(thr) / float(land) if land > 0 else 0.0


func _hub_level() -> int:
	var hb: Variant = world.get("hub")
	return (hb as Hub).level if hb is Hub else 1


## Takes one album picture of this district now (kind: "before" or a milestone).
func capture(kind: String) -> void:
	if _busy:
		return
	_busy = true
	var hub: int = GameState.current_hub
	var path: String = dir().path_join("h%d_%s.jpg" % [hub, kind])
	DirAccess.make_dir_recursive_absolute(dir())
	var img: Image = await _render()
	if img == null:
		_busy = false
		return
	var e: Dictionary = entry(hub)
	e["name"] = str(world.get("district_name")) if world.get("district_name") != null else ""
	e[kind] = path
	e[kind + "_unix"] = Time.get_unix_time_from_system()
	GameState.stats["album_shots"] = float(shots_taken())
	_save_async(img, path)
	if kind != "before":
		EventBus.toast.emit(tr("Album: an \"after\" picture of %s (%s).") % [tr(str(e["name"])), milestone_name(kind)], "info")
	_busy = false


## Renders the album view once; returns the image (a generated placeholder without a renderer).
func _render() -> Image:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		var ph := Image.create(SHOT_SIZE.x / 8, SHOT_SIZE.y / 8, false, Image.FORMAT_RGB8)
		ph.fill(Color(0.4, 0.5, 0.42) if GameState.current_hub % 2 == 0 else Color(0.5, 0.45, 0.4))
		await get_tree().process_frame
		return ph
	var vp := SubViewport.new()
	vp.size = SHOT_SIZE
	vp.world_3d = world.get_viewport().find_world_3d()
	vp.msaa_3d = Viewport.MSAA_DISABLED
	vp.use_taa = false
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.far = 900.0
	var env: Environment = world.get("_env") as Environment
	if env:
		var e2: Environment = env.duplicate()
		e2.sdfgi_enabled = false
		e2.ssr_enabled = false
		e2.ssil_enabled = false
		e2.volumetric_fog_enabled = false
		e2.ssao_enabled = false
		cam.environment = e2
	vp.add_child(cam)
	add_child(vp)
	cam.look_at_from_position(CAM_POS, CAM_AT, Vector3.UP)
	cam.current = true
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img: Image = await _read_back(vp)
	vp.queue_free()
	return img


func _read_back(vp: SubViewport) -> Image:
	var rd: RenderingDevice = RenderingServer.get_rendering_device()
	if rd != null:
		var rid: RID = RenderingServer.texture_get_rd_texture(vp.get_texture().get_rid())
		if rid.is_valid():
			var got: Array = []
			var err: Error = rd.texture_get_data_async(rid, 0, func(data: PackedByteArray) -> void: got.append(data))
			if err == OK:
				for i: int in 30:
					await get_tree().process_frame
					if not got.is_empty():
						break
				if not got.is_empty():
					var data: PackedByteArray = got[0]
					if data.size() == SHOT_SIZE.x * SHOT_SIZE.y * 4:
						var img := Image.create_from_data(SHOT_SIZE.x, SHOT_SIZE.y, false, Image.FORMAT_RGBA8, data)
						img.convert(Image.FORMAT_RGB8)
						return img
	return vp.get_texture().get_image()


func _save_async(img: Image, path: String) -> void:
	var abs_path: String = ProjectSettings.globalize_path(path)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		if img.get_format() != Image.FORMAT_RGB8:
			img.convert(Image.FORMAT_RGB8)
		img.save_jpg(abs_path, 0.82)))


func _reap() -> void:
	for i: int in range(_tasks.size() - 1, -1, -1):
		if WorkerThreadPool.is_task_completed(_tasks[i]):
			WorkerThreadPool.wait_for_task_completion(_tasks[i])
			_tasks.remove_at(i)


## Photo mode saved a picture: thumbnail it (on a worker) and list it in the Album.
func _on_photo(src: String) -> void:
	add_photo(src)


func add_photo(src: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(dir())
	var thumb: String = dir().path_join("photo_%s.jpg" % src.get_file().get_basename())
	var rec: Dictionary = {"src": src, "thumb": thumb, "unix": Time.get_unix_time_from_system()}
	var photos: Array = st()["photos"]
	photos.append(rec)
	while photos.size() > MAX_PHOTOS:
		var old: Dictionary = photos.pop_front()
		if FileAccess.file_exists(str(old.get("thumb", ""))):
			DirAccess.remove_absolute(str(old["thumb"]))
	GameState.stats["album_photos"] = float(GameState.stats.get("album_photos", 0.0)) + 1.0
	var src_abs: String = ProjectSettings.globalize_path(src)
	var dst_abs: String = ProjectSettings.globalize_path(thumb)
	_tasks.append(WorkerThreadPool.add_task(func() -> void:
		var img: Image = Image.load_from_file(src_abs)
		if img == null or img.is_empty():
			return
		img.convert(Image.FORMAT_RGB8)
		img.resize(THUMB_SIZE.x, THUMB_SIZE.y, Image.INTERPOLATE_BILINEAR)
		img.save_jpg(dst_abs, 0.8)))
	return rec


## Dev / shots: write the pictures now (synchronously), for every kind passed.
func dev_snap(kinds: Array) -> void:
	for k: Variant in kinds:
		await capture(str(k))
	for id: int in _tasks:
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	print("[album] dev snap %s -> %s" % [str(kinds), dir()])


## Dev / shots: register this district's pictures that are already on disk (a previous run).
func dev_adopt() -> void:
	var hub: int = GameState.current_hub
	for k: String in ["before"] + MILESTONES:
		var p: String = dir().path_join("h%d_%s.jpg" % [hub, k])
		if FileAccess.file_exists(p):
			entry(hub)[k] = p
			entry(hub)["name"] = str(world.get("district_name"))
	print("[album] adopted %s" % str(entry(hub)))
