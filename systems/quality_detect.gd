class_name QualityDetect
extends RefCounted
## [deck] First-launch graphics preset from the hardware. Pure: `pick(info)` maps a hardware
## description to {quality, render_scale, ui_scale, note}; `probe_info()` reads the real one.
## Settings calls this only when settings.cfg has no saved quality; a manual choice always wins.
## Presets: 0 Low, 1 Medium, 2 High, 3 Ultra (never picked automatically).

const LOW := 0
const MEDIUM := 1
const HIGH := 2

## Software rasterisers and VMs: always Low.
const SOFTWARE_HINTS: Array[String] = ["llvmpipe", "lavapipe", "swiftshader", "softpipe", "microsoft basic", "virtio", "vmware", "virgl"]
## Steam Deck APU names (LCD "Custom GPU 0405", OLED "Custom GPU 0932", "VanGogh"/"Sephiroth").
const DECK_HINTS: Array[String] = ["custom gpu 0405", "custom gpu 0932", "vangogh", "van gogh", "sephiroth"]
## Discrete GPUs that handle the High preset (SDFGI, SSIL, TAA) at 1080p.
const HIGH_HINTS: Array[String] = ["rtx", "rx 6", "rx 7", "rx 9", "radeon pro w6", "radeon pro w7", "arc a7", "arc b", "titan"]
## Older or entry-level discrete GPUs: Medium.
const MID_HINTS: Array[String] = ["gtx", "rx 5", "rx 4", "vega", "radeon pro 5", "radeon pro 4", "arc a3", "arc a5", "quadro", "geforce mx"]


## Real hardware description. Only meaningful with a rendering device (not headless).
static func probe_info() -> Dictionary:
	var screen := Vector2i(1920, 1080)
	var dpi: int = 96
	if DisplayServer.get_name() != "headless":
		var s: int = DisplayServer.window_get_current_screen()
		screen = DisplayServer.screen_get_size(s)
		dpi = DisplayServer.screen_get_dpi(s)
	return {
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"type": int(RenderingServer.get_video_adapter_type()),
		"os": OS.get_name(),
		"arch": Engine.get_architecture_name(),
		"screen": screen,
		"dpi": dpi,
		"steam_deck_env": OS.get_environment("SteamDeck") == "1" or OS.get_environment("SteamOS") == "1",
		"method": RenderingServer.get_current_rendering_method(),
		"ram_gb": float(OS.get_memory_info().get("physical", 0)) / 1073741824.0,
	}


static func is_steam_deck(info: Dictionary) -> bool:
	if bool(info.get("steam_deck_env", false)):
		return true
	var name: String = str(info.get("adapter", "")).to_lower()
	for h: String in DECK_HINTS:
		if h in name:
			return true
	# A 1280x800 Linux screen with an AMD APU is a Deck in desktop mode in practice.
	var scr: Vector2i = info.get("screen", Vector2i.ZERO)
	return str(info.get("os", "")) == "Linux" and scr == Vector2i(1280, 800) \
		and int(info.get("type", 0)) == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU


## True for small, dense screens (handheld PCs): the interface is scaled up a step.
static func is_handheld(info: Dictionary) -> bool:
	if is_steam_deck(info):
		return true
	var scr: Vector2i = info.get("screen", Vector2i.ZERO)
	return scr.y > 0 and scr.y <= 900 and int(info.get("dpi", 96)) >= 160


## {quality, render_scale, ui_scale (0 = leave), note} for a hardware description.
static func pick(info: Dictionary) -> Dictionary:
	var name: String = str(info.get("adapter", "")).to_lower()
	var vendor: String = str(info.get("vendor", "")).to_lower()
	var type: int = int(info.get("type", 0))
	var os_name: String = str(info.get("os", ""))
	var scr: Vector2i = info.get("screen", Vector2i(1920, 1080))
	var pixels: float = float(scr.x * scr.y)
	var q: int = MEDIUM
	var scale: float = 1.0
	var why: String = ""
	var handheld: bool = is_handheld(info)
	if str(info.get("method", "forward_plus")) not in ["forward_plus", ""]:
		q = LOW
		why = "%s renderer" % str(info.get("method", "")).capitalize()
	elif type == RenderingDevice.DEVICE_TYPE_CPU or type == RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU or _has_any(name, SOFTWARE_HINTS):
		q = LOW
		scale = 0.75
		why = "software / virtual GPU"
	elif is_steam_deck(info):
		q = LOW
		why = "Steam Deck"
	elif os_name == "macOS":
		if str(info.get("arch", "")) == "arm64" or "apple" in name or "apple" in vendor:
			# Apple Silicon: base chips are integrated-class, Pro/Max/Ultra are not.
			if _has_any(name, ["max", "ultra"]):
				q = HIGH
			elif "pro" in name:
				q = MEDIUM
			else:
				q = MEDIUM if pixels <= 2304.0 * 1440.0 else LOW
				scale = 1.0 if pixels <= 2304.0 * 1440.0 else 0.75
			why = "Apple Silicon (%s)" % _short(str(info.get("adapter", "")))
		else:
			# Intel Macs: Intel Iris/UHD integrated graphics or older Radeon Pro parts.
			q = MEDIUM if (type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU or "radeon" in name) else LOW
			why = "Intel Mac (%s)" % _short(str(info.get("adapter", "")))
	elif type == RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
		q = LOW
		why = "integrated GPU (%s)" % _short(str(info.get("adapter", "")))
	elif type == RenderingDevice.DEVICE_TYPE_DISCRETE_GPU or _has_any(name, HIGH_HINTS + MID_HINTS):
		if _has_any(name, HIGH_HINTS):
			q = HIGH
		elif _has_any(name, MID_HINTS):
			q = MEDIUM
		else:
			q = MEDIUM
		why = "%s" % _short(str(info.get("adapter", "")))
	else:
		why = "unknown GPU"
	# Big screens on weak GPUs: render 3D a little smaller (the interface stays sharp).
	if q == LOW and scale >= 1.0 and pixels > 1920.0 * 1200.0:
		scale = 0.75 if pixels <= 2560.0 * 1600.0 else 0.67
	elif q == MEDIUM and scale >= 1.0 and pixels > 2560.0 * 1600.0:
		scale = 0.85
	if float(info.get("ram_gb", 16.0)) > 0.0 and float(info.get("ram_gb", 16.0)) < 6.0 and q > LOW:
		q -= 1
		why += ", low memory"
	return {"quality": q, "render_scale": scale, "ui_scale": 1.1 if handheld else 0.0,
		"note": why, "handheld": handheld, "deck": is_steam_deck(info)}


static func preset_name(q: int) -> String:
	return ["Low", "Medium", "High", "Ultra"][clampi(q, 0, 3)]


static func _has_any(s: String, hints: Array) -> bool:
	for h: String in hints:
		if h in s:
			return true
	return false


static func _short(adapter: String) -> String:
	var a: String = adapter.replace("(TM)", "").replace("(R)", "").replace("Corporation", "").strip_edges()
	return a.left(36) if a != "" else "GPU"
