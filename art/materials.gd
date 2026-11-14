class_name Mats
extends RefCounted
## Shared realistic material factory for procedural meshes.

static var _cache: Dictionary = {}


## Worn painted metal (paint over rust over steel). Works on meshes without UVs.
static func worn_paint(paint: Color, coverage: float = 0.7, rust: float = 0.5, seed_: float = 0.0, grime: float = 0.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://art/shaders/worn_metal.gdshader")
	m.set_shader_parameter("paint_color", paint)
	m.set_shader_parameter("paint_coverage", coverage)
	m.set_shader_parameter("rust_amount", rust)
	m.set_shader_parameter("seed", seed_)
	m.set_shader_parameter("grime", grime)
	m.set_shader_parameter("metal_alb", AssetLib.tex("metal_plate", "diff"))
	m.set_shader_parameter("metal_nrm", AssetLib.tex("metal_plate", "nor_gl"))
	m.set_shader_parameter("metal_arm", AssetLib.tex("metal_plate", "arm"))
	m.set_shader_parameter("rust_alb", AssetLib.tex("rusty_metal_02", "diff"))
	m.set_shader_parameter("rust_nrm", AssetLib.tex("rusty_metal_02", "nor_gl"))
	m.set_shader_parameter("rust_arm", AssetLib.tex("rusty_metal_02", "arm"))
	return m


## Bare metal finishes: "steel", "chrome", "dark_steel", "brass".
static func metal(kind: String) -> StandardMaterial3D:
	var key: String = "metal_" + kind
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.metallic = 1.0
	match kind:
		"chrome":
			m.albedo_color = Color(0.85, 0.86, 0.88)
			m.roughness = 0.18
		"dark_steel":
			m.albedo_color = Color(0.25, 0.25, 0.27)
			m.roughness = 0.55
			m.albedo_texture = AssetLib.tex("metal_plate", "diff")
			m.normal_enabled = true
			m.normal_texture = AssetLib.tex("metal_plate", "nor_gl")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.0
		"brass":
			m.albedo_color = Color(0.72, 0.55, 0.3)
			m.roughness = 0.45
		_:
			m.albedo_color = Color(0.6, 0.6, 0.62)
			m.roughness = 0.4
			m.albedo_texture = AssetLib.tex("metal_plate", "diff")
			m.uv1_triplanar = true
			m.uv1_scale = Vector3.ONE * 2.0
	_cache[key] = m
	return m


## Rubber (tyres, hoses, seals).
static func rubber(color: Color = Color(0.06, 0.06, 0.065)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.88
	m.metallic = 0.0
	return m


## Glass / lens. tint alpha controls transparency.
static func glass(tint: Color = Color(0.05, 0.07, 0.09, 0.85), rough: float = 0.05) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.roughness = rough
	m.metallic = 0.2
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if tint.a < 1.0 else BaseMaterial3D.TRANSPARENCY_DISABLED
	return m


## Emissive lamp material (beacons, screens).
static func lamp(color: Color, energy: float = 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color.darkened(0.3)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 0.3
	return m


## Stenciled text decal (serial numbers, warnings). Returns a shaded Label3D lying on a surface.
static func stencil(text: String, size_px: int = 48, color: Color = Color(0.9, 0.88, 0.8, 0.85)) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size_px
	l.pixel_size = 0.0012
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	return l
