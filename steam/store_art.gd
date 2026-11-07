class_name StoreArt
extends RefCounted
## Shared look for the "GREENFALL" wordmark: the title screen's font (Godot's default UI font,
## emboldened, wide tracking). Used by the end-of-demo screen and tools/steam/capsules.gd (store art).

const LOGO_COLOR := Color(1.0, 0.95, 0.86)


static func logo_font(embolden: float = 0.55, tracking: int = 10) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = ThemeDB.fallback_font
	f.variation_embolden = embolden
	f.spacing_glyph = tracking
	return f
