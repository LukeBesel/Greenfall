class_name PhotoFilters
extends RefCounted
## [photo] Photo mode filter presets. Each preset sets the user-facing look sliders (contrast,
## saturation, warmth, vignette, grain) plus hidden grade values (tint, split toning, fade, mono,
## bloom, diffusion) and a multiplier on the world's own glow. Values feed photo_grade.gdshader.

const ORDER: Array[String] = ["natural", "golden", "dawn", "neon", "film", "mono", "holo", "bloom"]

# l10n:begin
const PRESETS: Dictionary = {
	"natural": {"name": "Natural", "contrast": 1.0, "saturation": 1.0, "warmth": 0.0, "vignette": 0.15, "grain": 0.03},
	"golden": {"name": "Golden Hour", "contrast": 1.06, "saturation": 1.1, "warmth": 0.65, "vignette": 0.35, "grain": 0.05,
		"tint": 0.08, "split": 0.45, "shadow_col": Color(0.46, 0.47, 0.55), "high_col": Color(0.6, 0.52, 0.42), "bloom": 0.25, "glow": 1.35},
	"dawn": {"name": "Dawn Mist", "contrast": 0.9, "saturation": 0.86, "warmth": 0.12, "vignette": 0.2, "grain": 0.04,
		"tint": 0.25, "fade": 0.55, "soft": 0.32, "split": 0.4, "shadow_col": Color(0.47, 0.5, 0.56), "high_col": Color(0.56, 0.5, 0.53), "bloom": 0.2},
	"neon": {"name": "Neon Night", "contrast": 1.14, "saturation": 1.22, "warmth": -0.35, "vignette": 0.45, "grain": 0.07,
		"tint": 0.1, "split": 0.6, "shadow_col": Color(0.4, 0.52, 0.6), "high_col": Color(0.6, 0.45, 0.58), "bloom": 0.45, "glow": 1.8},
	"film": {"name": "Film", "contrast": 1.08, "saturation": 0.9, "warmth": 0.2, "vignette": 0.4, "grain": 0.22,
		"fade": 0.35, "split": 0.4, "shadow_col": Color(0.46, 0.52, 0.52), "high_col": Color(0.56, 0.52, 0.45)},
	"mono": {"name": "Mono", "contrast": 1.18, "saturation": 0.0, "warmth": 0.0, "vignette": 0.42, "grain": 0.16,
		"mono": 1.0, "fade": 0.12},
	"holo": {"name": "Holo Blue", "contrast": 1.05, "saturation": 0.82, "warmth": -0.75, "vignette": 0.3, "grain": 0.06,
		"tint": -0.08, "split": 0.6, "shadow_col": Color(0.4, 0.5, 0.62), "high_col": Color(0.48, 0.56, 0.62), "bloom": 0.3, "glow": 1.4},
	"bloom": {"name": "Bloom", "contrast": 0.98, "saturation": 1.1, "warmth": 0.1, "vignette": 0.2, "grain": 0.04,
		"bloom": 0.75, "soft": 0.14, "glow": 2.0},
}
# l10n:end

## Hidden grade defaults (anything a preset leaves out).
const HIDDEN: Dictionary = {
	"tint": 0.0, "split": 0.0, "shadow_col": Color(0.5, 0.5, 0.5), "high_col": Color(0.5, 0.5, 0.5),
	"fade": 0.0, "mono": 0.0, "bloom": 0.0, "soft": 0.0, "glow": 1.0,
}


static func names() -> Array[String]:
	var out: Array[String] = []
	for id: String in ORDER:
		out.append(TranslationServer.translate(str(PRESETS[id]["name"])))
	return out


## Full value set for a preset id (unknown ids give Natural).
static func values(id: String) -> Dictionary:
	var p: Dictionary = PRESETS.get(id, PRESETS["natural"])
	var out: Dictionary = HIDDEN.duplicate()
	for k: String in p:
		if k != "name":
			out[k] = p[k]
	return out


static func id_at(i: int) -> String:
	return ORDER[wrapi(i, 0, ORDER.size())]


static func index_of(id: String) -> int:
	return maxi(0, ORDER.find(id))


## Writes a full grade (preset values with the user's slider overrides) into the shader.
static func apply(mat: ShaderMaterial, v: Dictionary) -> void:
	for k: String in ["contrast", "saturation", "warmth", "tint", "vignette", "grain", "fade", "mono", "split", "bloom", "soft"]:
		mat.set_shader_parameter(k, float(v.get(k, HIDDEN.get(k, 0.0))))
	var sc: Color = v.get("shadow_col", HIDDEN["shadow_col"])
	var hc: Color = v.get("high_col", HIDDEN["high_col"])
	mat.set_shader_parameter("shadow_col", Vector3(sc.r, sc.g, sc.b))
	mat.set_shader_parameter("high_col", Vector3(hc.r, hc.g, hc.b))
