class_name KitMat
extends RefCounted
## [kit] Shared materials library for buildings and props (docs/ART_KIT.md).
## Every material is cached: ask for the same thing twice and you get the same Material, so
## meshes that share a material batch together.
##
## Mesh surfaces built by KitMesh are NAMED with a material key ("paint:teal", "steel", "trim:warm",
## "glass", "hazard", "decal:arrow", ...). KitMat.apply(mesh_instance, state, powered) assigns the
## right material to every surface for a building state, so callers rarely pick materials by hand.
##
## States: "broken" (rusty, dirty, chipped, faded), "repaired" (patched, some wear),
##         "restored" (clean, fresh paint, light wear on the edges only).

const STATES: PackedStringArray = ["broken", "repaired", "restored"]

## Cohesive kit palette (Moon Sweepers-like: warm creams, teal, orange, saturated but not neon).
const PALETTE: Dictionary = {
	"cream": Color(0.88, 0.8, 0.64),
	"white": Color(0.88, 0.89, 0.9),
	"teal": Color(0.04, 0.5, 0.55),
	"mint": Color(0.42, 0.78, 0.6),
	"sky": Color(0.3, 0.56, 0.86),
	"navy": Color(0.13, 0.19, 0.31),
	"orange": Color(0.95, 0.38, 0.05),
	"yellow": Color(0.98, 0.7, 0.05),
	"red": Color(0.78, 0.17, 0.13),
	"olive": Color(0.44, 0.5, 0.27),
	"slate": Color(0.28, 0.31, 0.35),
	"plum": Color(0.42, 0.24, 0.42),
}

## Default palette ROLES used by KitMesh.Builder for "paint:<role>" keys. Any role can be
## overridden per building/planet; values are PALETTE names, "#rrggbb" or Colors.
## "broken_<role>" is used instead in the broken state. "hazard" is the stripe colour,
## "trim_<kind>" remaps a glow kind (e.g. {"trim_cool": "green"}).
const ROLES: Dictionary = {
	"main": "cream", "accent": "teal", "pipe": "orange", "rail": "yellow", "pole": "slate",
	"crate": "orange", "barrel": "red", "patch": "#9a9a92", "flower_a": "#e8577a", "flower_b": "#f2e5c4",
	"broken_main": "#8d8576", "broken_accent": "#3f5a5a", "hazard": "yellow",
}

## Emissive trim colours (thin and subtle: "futuristic but not tron").
const GLOW: Dictionary = {
	"warm": Color(1.0, 0.72, 0.38),
	"cool": Color(0.45, 0.85, 1.0),
	"green": Color(0.5, 1.0, 0.55),
	"red": Color(1.0, 0.28, 0.2),
	"white": Color(1.0, 0.95, 0.88),
}

## Wear parameters per state.
const WEAR: Dictionary = {
	"broken": {"edge_wear": 0.72, "patch_wear": 0.55, "rust": 0.85, "fade": 0.6, "grime": 0.85, "dust": 0.6, "streaks": 0.8},
	"repaired": {"edge_wear": 0.42, "patch_wear": 0.1, "rust": 0.35, "fade": 0.08, "grime": 0.45, "dust": 0.2, "streaks": 0.3},
	"restored": {"edge_wear": 0.24, "patch_wear": 0.0, "rust": 0.06, "fade": 0.0, "grime": 0.25, "dust": 0.06, "streaks": 0.08},
}

const SHADER: Shader = preload("res://art/kit/kit_surface.gdshader")

static var _cache: Dictionary = {}
static var _white: Texture2D


static func _tex(id: String, map: String) -> Texture2D:
	var t: Texture2D = AssetLib.tex(id, map)
	if t:
		return t
	if _white == null:
		var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
		img.fill(Color(1, 1, 1) if map != "nor_gl" else Color(0.5, 0.5, 1.0))
		_white = ImageTexture.create_from_image(img)
	return _white


static func color(name: String) -> Color:
	if PALETTE.has(name):
		return PALETTE[name]
	if name.begins_with("#") or name.is_valid_html_color():
		return Color.html(name)
	return PALETTE["cream"]


static func _surface(key: String, base_id: String, state: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.resource_name = key
	m.set_shader_parameter("base_alb", _tex(base_id, "diff"))
	m.set_shader_parameter("base_nrm", _tex(base_id, "nor_gl"))
	m.set_shader_parameter("base_arm", _tex(base_id, "arm"))
	m.set_shader_parameter("rust_alb", _tex("rusty_metal_02", "diff"))
	m.set_shader_parameter("rust_arm", _tex("rusty_metal_02", "arm"))
	var w: Dictionary = WEAR.get(state, WEAR["repaired"])
	for k: String in w:
		m.set_shader_parameter(k, w[k])
	return m


## Painted metal. colour: palette name, "#rrggbb" or a Color. Edges wear to bare steel (rust when broken).
static func paint(colour: Variant = "cream", state: String = "repaired") -> ShaderMaterial:
	var c: Color = colour if colour is Color else color(str(colour))
	var key: String = "paint:%s:%s" % [c.to_html(false), state]
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "metal_plate", state)
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("paint_amount", 1.0)
	m.set_shader_parameter("clearcoat_amt", 0.35 if state == "restored" else 0.0)
	if state == "broken":
		m.set_shader_parameter("paint_color", c.darkened(0.18))
	_cache[key] = m
	return m


## [v7look] Upholstery (seat cushions, quilted pads): the paint colour with no wear, grime or
## streaks, matte. Kit paint wear read as dirty smudges on a padded seat.
static func pad(colour: Variant = "cream") -> ShaderMaterial:
	var c: Color = colour if colour is Color else color(str(colour))
	var key: String = "pad:%s" % c.to_html(false)
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "metal_plate", "restored")
	for k: String in WEAR["restored"]:
		m.set_shader_parameter(k, 0.0)
	m.set_shader_parameter("paint_color", c)
	m.set_shader_parameter("paint_amount", 1.0)
	m.set_shader_parameter("clearcoat_amt", 0.0)
	_cache[key] = m
	return m


## Bare steel (brushed plates). dark = true for gunmetal frames/greebles.
static func steel(state: String = "repaired", dark: bool = false) -> ShaderMaterial:
	var key: String = "steel:%s:%s" % [state, dark]
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "metal_plate", state)
	m.set_shader_parameter("paint_amount", 0.0)
	m.set_shader_parameter("base_tint", Color(0.5, 0.52, 0.56) if dark else Color(1.35, 1.36, 1.4))
	m.set_shader_parameter("base_metallic", 0.55 if dark else 0.7)
	m.set_shader_parameter("rust", float(WEAR[state]["rust"]) * 0.6 if WEAR.has(state) else 0.2)
	_cache[key] = m
	return m


## Rusty steel (always rusty; broken state is rustier).
static func rusty(state: String = "broken") -> ShaderMaterial:
	var key: String = "rusty:" + state
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "rusty_metal_03", state)
	m.set_shader_parameter("paint_amount", 0.0)
	m.set_shader_parameter("rust", 1.0 if state == "broken" else 0.6)
	m.set_shader_parameter("base_metallic", 0.4)
	m.set_shader_parameter("tex_scale", 0.6)
	_cache[key] = m
	return m


## Concrete (foundations, kerbs, plinths). painted: optional colour for painted concrete.
static func concrete(state: String = "repaired", tint: Color = Color(0.86, 0.84, 0.8)) -> ShaderMaterial:
	var key: String = "concrete:%s:%s" % [state, tint.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "concrete_floor_worn_001", state)
	m.set_shader_parameter("paint_amount", 0.0)
	m.set_shader_parameter("base_metallic", 0.0)
	m.set_shader_parameter("base_tint", tint)
	m.set_shader_parameter("rust", 0.0)
	m.set_shader_parameter("tex_scale", 0.45)
	m.set_shader_parameter("base_normal_strength", 0.9)
	m.set_shader_parameter("grime_height", 0.4)
	_cache[key] = m
	return m


## Yellow/black hazard stripes (painted metal, worn like paint).
static func hazard(state: String = "repaired", a: Color = Color(0.98, 0.74, 0.12), b: Color = Color(0.07, 0.07, 0.08)) -> ShaderMaterial:
	var key: String = "hazard:%s:%s:%s" % [state, a.to_html(false), b.to_html(false)]
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "metal_plate", state)
	m.set_shader_parameter("pattern", 1)
	m.set_shader_parameter("paint_color", a)
	m.set_shader_parameter("paint_color2", b)
	_cache[key] = m
	return m


## Rubber (tyres, hoses, seals, cable).
static func rubber() -> StandardMaterial3D:
	if _cache.has("rubber"):
		return _cache["rubber"]
	var m := StandardMaterial3D.new()
	m.resource_name = "rubber"
	m.albedo_color = Color(0.07, 0.07, 0.075)
	m.roughness = 0.82
	m.vertex_color_use_as_albedo = false
	_cache["rubber"] = m
	return m


## Window glass. powered: warm interior glow (lit windows read at night).
static func glass(powered: bool = false, state: String = "repaired") -> StandardMaterial3D:
	var key: String = "glass:%s:%s" % [powered, state]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_color = Color(0.05, 0.11, 0.14) if state != "broken" else Color(0.07, 0.07, 0.06)
	m.metallic = 0.0
	m.roughness = 0.12 if state != "broken" else 0.6
	m.metallic_specular = 0.35
	if powered and state != "broken":
		m.emission_enabled = true
		m.emission = Color(1.0, 0.7, 0.4)
		m.emission_energy_multiplier = 0.4
	_cache[key] = m
	return m


## Light, see-through greenhouse/dome glass (alpha). Broken = grimy, nearly opaque.
static func glasshouse(state: String = "repaired") -> StandardMaterial3D:
	var key: String = "glasshouse:" + state
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.88, 0.9, 0.28) if state != "broken" else Color(0.42, 0.4, 0.33, 0.8)
	m.roughness = 0.08 if state != "broken" else 0.7
	m.metallic_specular = 0.6
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


## Emissive trim strip / lamp lens. kind: "warm", "cool", "green", "red", "white" or a Color.
## Unpowered trims are dark frosted plastic, so a ruined site never glows.
static func trim(kind: Variant = "cool", powered: bool = true, energy: float = 2.2) -> StandardMaterial3D:
	var c: Color = kind if kind is Color else GLOW.get(str(kind), GLOW["cool"])
	var key: String = "trim:%s:%s:%.2f" % [c.to_html(false), powered, energy]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.roughness = 0.35
	if powered:
		m.albedo_color = c.lerp(Color.WHITE, 0.4)
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
	else:
		m.albedo_color = c.darkened(0.75).lerp(Color(0.12, 0.12, 0.12), 0.5)
		m.roughness = 0.5
	_cache[key] = m
	return m


## Plant/grass material for tufts and planters (vertex colour gradient, no texture, no alpha).
static func foliage(state: String = "restored") -> StandardMaterial3D:
	var key: String = "foliage:" + state
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1) if state != "broken" else Color(0.75, 0.62, 0.38)
	m.roughness = 0.8
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.backlight_enabled = true
	m.backlight = Color(0.25, 0.35, 0.1)
	_cache[key] = m
	return m


## Leafy bushes in planters (restored sites). Triplanar leaf texture, no alpha. Broken = dry.
static func leaves(state: String = "restored") -> StandardMaterial3D:
	var key: String = "leaves:" + state
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	m.albedo_texture = _tex("leafy_grass", "diff")
	m.normal_enabled = true
	m.normal_texture = _tex("leafy_grass", "nor_gl")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * 1.6
	m.albedo_color = Color(0.75, 1.0, 0.55) if state != "broken" else Color(0.75, 0.6, 0.38)
	m.roughness = 0.85
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_LAMBERT_WRAP
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Soil / dirt under props (ground patches).
static func dirt(state: String = "repaired") -> ShaderMaterial:
	var key: String = "dirt:" + state
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "dirt", state)
	m.set_shader_parameter("base_tint", Color(1.05, 0.95, 0.8))
	m.set_shader_parameter("paint_amount", 0.0)
	m.set_shader_parameter("base_metallic", 0.0)
	m.set_shader_parameter("rust", 0.0)
	m.set_shader_parameter("grime", 0.0)
	m.set_shader_parameter("dust", 0.0)
	m.set_shader_parameter("streaks", 0.0)
	m.set_shader_parameter("tex_scale", 0.35)
	m.set_shader_parameter("base_normal_strength", 1.0)
	_cache[key] = m
	return m


## Decal (label/sign/arrow) from art/kit/decals/<name>.png, alpha-scissored, on a quad that KitMesh
## places a few mm off the surface. Decals are images, never 3D text.
static func decal(name: String, state: String = "repaired") -> StandardMaterial3D:
	var key: String = "decal:%s:%s" % [name, state]
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.resource_name = key
	var p: String = "res://art/kit/decals/%s.png" % name
	if ResourceLoader.exists(p):
		m.albedo_texture = load(p)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	m.roughness = 0.6
	m.albedo_color = Color(1, 1, 1) if state == "restored" else (Color(0.85, 0.82, 0.76) if state == "repaired" else Color(0.55, 0.5, 0.44))
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_cache[key] = m
	return m


## Painted metal whose colour comes from the mesh (CUSTOM0, set by KitMesh.Builder): one material
## for every paint colour + hazard stripes on a building.
static func paint_vc(state: String = "repaired") -> ShaderMaterial:
	var key: String = "paint_vc:" + state
	if _cache.has(key):
		return _cache[key]
	var m := _surface(key, "metal_plate", state)
	m.set_shader_parameter("paint_from_vertex", true)
	m.set_shader_parameter("paint_amount", 1.0)
	m.set_shader_parameter("clearcoat_amt", 0.35 if state == "restored" else 0.0)
	_cache[key] = m
	return m


const TRIM_SHADER: Shader = preload("res://art/kit/kit_trim.gdshader")


## Trims whose glow colour comes from the mesh (CUSTOM0). powered false = dark lenses.
static func trim_vc(powered: bool = true, energy: float = 2.2) -> ShaderMaterial:
	var key: String = "trim_vc:%s:%.2f" % [powered, energy]
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.resource_name = key
	m.shader = TRIM_SHADER
	m.set_shader_parameter("powered", 1.0 if powered else 0.0)
	m.set_shader_parameter("energy", energy)
	_cache[key] = m
	return m


## Material for a surface key as KitMesh names surfaces.
## Keys: paint:<colour>, steel, dark_steel, rusty, concrete, hazard, rubber, glass, trim:<kind>,
## foliage, leaves, dirt, decal:<name>. "paint:accent" etc. can be remapped by the caller through `palette`.
static func for_key(key: String, state: String = "repaired", powered: bool = true, palette: Dictionary = {}) -> Material:
	var parts: PackedStringArray = key.split(":", true, 1)
	var head: String = parts[0]
	var arg: String = parts[1] if parts.size() > 1 else ""
	match head:
		"pad":  # [v7look] upholstery: no wear in any state
			return pad(str(palette.get(arg, arg)))
		"paint":
			if arg == "":
				return paint_vc(state)
			var c: String = str(palette.get(arg, arg))
			if state == "broken" and palette.has("broken_" + arg):
				c = str(palette["broken_" + arg])
			return paint(c, state)
		"steel":
			return steel(state, false)
		"dark_steel":
			return steel(state, true)
		"rusty":
			return rusty(state)
		"concrete":
			return concrete(state)
		"hazard":
			return hazard(state)
		"rubber":
			return rubber()
		"glass":
			return glass(powered, state)
		"glasshouse":
			return glasshouse(state)
		"trim":
			if arg == "":
				return trim_vc(powered and state != "broken")
			return trim(str(palette.get("trim_" + arg, arg)), powered and state != "broken")
		"foliage":
			return foliage(state)
		"leaves":
			return leaves(state)
		"dirt":
			return dirt(state)
		"decal":
			return decal(arg if arg != "" else "atlas", state)
	return paint("cream", state)


## Assign materials to every named surface of mi.mesh for a state.
static func apply(mi: MeshInstance3D, state: String = "repaired", powered: bool = true, palette: Dictionary = {}) -> void:
	if mi == null or mi.mesh == null:
		return
	var am: ArrayMesh = mi.mesh as ArrayMesh
	for s: int in mi.mesh.get_surface_count():
		var key: String = am.surface_get_name(s) if am else ""
		if key == "":
			continue
		mi.set_surface_override_material(s, for_key(key, state, powered, palette))


static func clear_cache() -> void:
	_cache.clear()
