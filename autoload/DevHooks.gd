extends Node
## Command-line hooks for automated verification. Pass after `--`, e.g.
##   godot --path . -- --fresh --shot=screenshots/slice.png --shot-delay=3 --quit-after=4
## Flags:
##   --fresh            ignore and don't write the save file
##   --nosave           don't write saves (but load if present)
##   --shot=PATH        save a viewport PNG (res:// or relative to project) after --shot-delay seconds
##   --shots=N          take N screenshots spaced by --shot-every seconds (suffix _0, _1, ...)
##   --quit-after=S     quit after S seconds (game time)
##   [l10n] --locale=xx  force a locale (pseudo, de, es, en; not saved); --l10n-audit lists on-screen
##                      text that skipped tr() (screenshots/l10n_audit.txt, use with --locale=pseudo)
##   --autoplay         let tools/autoplay.gd drive Patch
##   --time-scale=X     Engine.time_scale
##   --seed=N           override the slice field seed
##   --cam=NAME         camera preset for screenshots (see CameraRig.apply_preset)
##   --give=N           start with N cubes (testing UI)
##   --open=NAME        open a UI screen on start (upgrades)
##   --quality=N        render quality preset 0..3 (Low..Ultra) for faster screenshots
##   --ui-scale=X       interface scale 0.8..1.5 for this run (not saved); --colorblind uses that palette
##   --tab=ID           upgrades screen starts on this tab (e.g. research)
##   --open=codex       open the Codex (--codex-tab=achievements|stats, --codex-sample fakes progress)
##   --give-data=N      start with N research Data; --research=a+b grants nodes;
##   --research-start=a+b starts/queues nodes (--research-elapsed=S backdates the start)
##   --robots=type:n,..  spawn test robots (slice.gd); any --robots run prints a [bots] report before quitting
##   --clean-hexes=N    pre-clean the N land hexes nearest the base
##   --bot-report       print the [bots] robot report before --quit-after
##   --trace-bot=NAME   print one robot's state every 2 s (target, hopper, stall timer, status)
##   --ledger-act=N     jump the Ledger arc to act N (1 intercepts, 2 drones, 3 relay, 4 resolved)
##   --ledger-drop[=S]  force a Ledger dump drone S seconds after start (ignores jammers)
##   --ledger-resolve[=S]  play the relay "rewrite the contract" cinematic (needs act 3)
##   --spawn-relay      put Patch next to the Ledger relay terminal (act >= 3)
##   --demo-scoop       Patch scoops the nearest junk nonstop (pickup animation shots; --demo-yaw, --demo-speed)
##   --spawn-egg=ID     put Patch next to an easter egg in this district (data/eggs.json ids);
##                      --egg-dist=M sets the distance, --egg-poke[=S] plays its reaction after S s
##   --event=ID         [events] force a world event (supply_drop, salvage_surge, rain_shower, robot_hiccup,
##                      wildlife_visit, rare_part_signal, ledger_audit) --event-at=S wall-clock seconds after start (default 3);
##                      --event-land drops the supply crate from just above the junk, slowly (screenshots)
##   --event-look[=M]   with --event: put Patch M m from the event, facing it (screenshots)
##   --event-every=S    next random event in S seconds (ignores the min-hexes gate)
##   --streak=N         start with N cleaning-streak points (30 per tier)
##   --tokens=N         start with N contract tokens; --trinkets=N grants N collectibles; --livery=ID equips one
##   --pad-audit        [deck] open every screen pad-only and check focus reachability + B to close
##   --scene-stats[=S]  [deck] print a geometry census (tools/scene_stats.gd) after S s (headless ok)
##   --tab=contracts    with --open=upgrades: the contracts board and token shop (--contracts-sample fills it)
##   [hud] --lumi-level=N start at Lumi Level N; --lumi-xp=N grant N XP; --lumi-levelup=S level up S s after start
##         (holds the level-up moment for screenshots); --tool=plant|water; --hud-pad (pad glyphs);
##         --hud-mode=full|minimal|hidden; --hud-goals=expanded
##   --photo[=S]        [photo] open photo mode after S s; --photo-seq="pose=wave|filter=golden;..." captures each
##                      entry (--photo-first/--photo-every=S, --photo-open=lumi,look, --photo-copy=DIR); see ui/photo_mode.gd
##   --builder-sample   [drones] stocked builder parts bin; --builder-demo showcase builds on the robots;
##                      --builder-shot fixed camera (--bshot-cam=x,y,z --bshot-at=x,y,z --bshot-fov --bshot-nohud --bshot-lumi);
##                      --tab=builder [--builder-robot=N --builder-slot=ID --builder-opt=N] focuses a part
##   --frontier=ID      [biomes] start in a frontier district (dust_flats, frozen_port, sunken_city, cradle_returns);
##                      --frontiers-open lets the rocket fly there without the unlocks; --storm[=S] sandstorm after S s
##                      (--storm-hold keeps it blowing); --thaw-all; --frontier-heaters=N; --frontier-greenhouses=N;
##                      --drain=N runs the Sunken City pumps N times; --frontier-done[=S] fires the Cradle hook;
##                      --frontier-cam=dist,pitch,yaw and --frontier-nohud for landscape screenshots
##   --demo             [steam] run as the Steam demo build (Demo.is_demo()); --no-steam skips Steam init
##   --no-hud           [steam] hide HUD, toasts, subtitles and event banners (store screenshots, trailer)
##   --demo-end[=S]     [steam] show the end-of-demo screen after S seconds

var args: Dictionary = {}
var _elapsed: float = 0.0
var _shots_taken: int = 0
var _perf_t: float = 0.0
var _start_ms: int = Time.get_ticks_msec()
var _frames: int = 0
var _perf_frames: int = 0
var _perf_wall: float = 0.0
var _stats_done: bool = false  # [deck]


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	if has("fresh") or has("nosave"):
		SaveManager.enabled = false
	if has("quality"):
		Settings.quality = clampi(int(get_f("quality", 2.0)), 0, 3)
	if has("ui-scale"):
		Settings.ui_scale = get_f("ui-scale", 1.0)
		Settings.apply_ui_scale()
	if has("colorblind"):
		Settings.colorblind = true
	if has("time-scale"):
		Engine.time_scale = float(args["time-scale"])
	if has("l10n-audit"):  # [l10n] untranslated on-screen text (tools/l10n_audit.gd), use with --locale=pseudo
		var au := L10nAudit.new()
		au.name = "L10nAudit"
		add_child(au)
	if has("pad-audit"):  # [deck] controller-only screen audit (tools/pad_audit.gd)
		add_child(PadAudit.new())
	if has("no-hud"):  # [steam] store/trailer shots without HUD, toasts and subtitles
		add_child(load("res://steam/store_shots.gd").new())
	if has("demo-end"):  # [steam] open the end-of-demo screen after S seconds (screenshots)
		get_tree().create_timer(get_f("demo-end", 5.0)).timeout.connect(func() -> void: Demo.show_end_screen("auto"))
	if not args.is_empty():
		print("[DevHooks] args: ", args)


func has(flag: String) -> bool:
	return args.has(flag)


func get_f(flag: String, default: float) -> float:
	return float(args.get(flag, default))


func get_s(flag: String, default: String) -> String:
	return str(args.get(flag, default))


func _process(delta: float) -> void:
	# Wall-clock time (frame delta is clamped by the engine on very slow frames).
	_elapsed = (Time.get_ticks_msec() - _start_ms) / 1000.0
	_frames += 1
	if has("shot"):
		var count: int = int(get_f("shots", 1.0))
		var delay: float = get_f("shot-delay", 2.0)
		var every: float = get_f("shot-every", 1.0)
		if _shots_taken < count and _elapsed >= delay + every * _shots_taken:
			_take_shot(count)
	if has("perf"):
		# Wall clock too: on software rendering the clamped delta never adds up to 3 s.
		_perf_t = maxf(_perf_t + delta, _elapsed - _perf_wall)
		_perf_frames += 1
		if _perf_t >= 3.0:
			print("[perf] t=%.0fs frames=%d game_fps=%.2f draw_calls=%d objects=%d prims=%d" % [_elapsed, _frames, _perf_frames / _perf_t,
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
			_perf_t = 0.0
			_perf_wall = _elapsed
			_perf_frames = 0
	if has("scene-stats") and _elapsed >= get_f("scene-stats", 4.0) and not _stats_done:  # [deck] geometry census
		_stats_done = true
		SceneStats.print_census(get_tree().current_scene)
	if has("quit-after") and _elapsed >= get_f("quit-after", 5.0):
		print("[DevHooks] quitting after %.1fs" % _elapsed)
		if has("report"):
			print("[report] cubes=%s stats=%s parts=%d" % [GameState.get_currency("cubes").format(), JSON.stringify(GameState.stats), GameState.parts.size()])
		if has_node("L10nAudit"):  # [l10n]
			(get_node("L10nAudit") as L10nAudit).report()
		get_tree().quit()


func _take_shot(count: int) -> void:
	var path: String = get_s("shot", "screenshots/shot.png")
	if count > 1:
		path = path.get_basename() + "_%d.png" % _shots_taken
	_shots_taken += 1
	save_viewport(path)


func save_viewport(path: String) -> void:
	var abs_path: String = path if path.begins_with("res://") or path.begins_with("user://") or path.begins_with("/") \
		else ProjectSettings.globalize_path("res://" + path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var img: Image = get_viewport().get_texture().get_image()
	var err: Error = img.save_png(abs_path)
	print("[DevHooks] screenshot -> %s (%s)" % [abs_path, error_string(err)])
