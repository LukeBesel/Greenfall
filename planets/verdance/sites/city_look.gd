class_name CityLook
extends RefCounted
## One Verdance city's look, read from planets/verdance/data/cities.json (the file's _doc explains
## every key): its palette (walls, roofs, awnings, tanks, signs, gables), its building mix, its roof
## props and street dressing, and the two copies of the city building material that carry the
## city's own "lit" and "sign_clean" (so one city's lights come back without its neighbours').
## paint() colours one planned building; VerdanceSite and TownOutskirts call it for every building.

const DATA_PATH: String = "res://planets/verdance/data/cities.json"
const TEXTURES: Dictionary = {"red_brick": BuildingDetail.T_RED_BRICK, "brick": BuildingDetail.T_BRICK, "render": BuildingDetail.T_CONCRETE}
const PAINT_SALT: int = 9173

static var _table: Dictionary = {}
static var _looks: Dictionary = {}

var id: String = ""
var data: Dictionary = {}
var walls: Array = []            # [texture index, Color]
var tall_walls: Array[int] = []
var tall_avoid: Array[int] = []
var tall_floors: int = 99
var roofs: Array[Color] = []
var awnings: Array[Color] = []
var tanks: Array[Color] = []
var signs: Array[Color] = []
var gables: Array[Color] = []
var boards: Array[Color] = []
var shop_names: Array[String] = []
var _mats: Array[ShaderMaterial] = [null, null]
var _lit: float = 0.0
var _sign_clean: float = 0.0


## The city ids the data file lists.
static func ids() -> Array[String]:
	var out: Array[String] = []
	for k: String in _cities():
		out.append(k)
	return out


static func has(city_id: String) -> bool:
	return _cities().has(city_id)


## The look of city `city_id` (one shared object per city), or null when the file has no such city.
static func of(city_id: String) -> CityLook:
	if _looks.has(city_id):
		return _looks[city_id]
	if not has(city_id):
		return null
	var l := CityLook.new()
	l._load(city_id, _cities()[city_id])
	_looks[city_id] = l
	return l


static func _cities() -> Dictionary:
	if _table.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if parsed is Dictionary:
			_table = (parsed as Dictionary).get("cities", {})
	return _table


static func colours(raw: Variant) -> Array[Color]:
	var out: Array[Color] = []
	if raw is Array:
		for c: Variant in raw:
			out.append(colour(c))
	return out


static func colour(raw: Variant) -> Color:
	var a: Array = raw if raw is Array else []
	if a.size() < 3:
		return Color.WHITE
	return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]) if a.size() > 3 else 1.0)


func _load(city_id: String, d: Dictionary) -> void:
	id = city_id
	data = d
	for w: Variant in d.get("walls", []):
		walls.append([int(TEXTURES.get(str(w[0]), BuildingDetail.T_CONCRETE)), colour(w[1])])
	for i: Variant in d.get("tall_walls", []):
		tall_walls.append(int(i))
	for i2: Variant in d.get("tall_avoid", []):
		tall_avoid.append(int(i2))
	tall_floors = int(d.get("tall_floors", 99))
	roofs = colours(d.get("roofs"))
	awnings = colours(d.get("awnings"))
	tanks = colours(d.get("tanks"))
	signs = colours(d.get("signs"))
	gables = colours(d.get("gables", d.get("roofs")))
	boards = colours(d.get("boards"))
	for n: Variant in d.get("shop_names", []):
		shop_names.append(str(n))


## The city's building material: a copy of the shared city material with its own "lit" and
## "sign_clean" (false: the pad town, in the site's space; true: the outskirts, in tile space).
func material(local_space: bool) -> ShaderMaterial:
	var i: int = 1 if local_space else 0
	if _mats[i] == null:
		_mats[i] = BuildingDetail.material().duplicate()
		_mats[i].set_shader_parameter("local_space", local_space)
		_mats[i].set_shader_parameter("lit", _lit)
		_mats[i].set_shader_parameter("sign_clean", _sign_clean)
	return _mats[i]


func set_lights(lit: float, sign_clean: float) -> void:
	_lit = lit
	_sign_clean = sign_clean
	for m: ShaderMaterial in _mats:
		if m:
			m.set_shader_parameter("lit", lit)
			m.set_shader_parameter("sign_clean", sign_clean)


## Paints one planned building (CityLayout / TownOutskirts dictionary) in the city's colours. Drawn
## from the building's own seed, so the layout's random stream is untouched.
func paint(bd: Dictionary, _rng: RandomNumberGenerator = null, _dist: float = 0.0) -> void:
	if walls.is_empty() or roofs.is_empty() or awnings.is_empty():
		return
	var h: int = hash([int(bd.get("seed", 0)), PAINT_SALT])
	var wall: Array = walls[h % walls.size()]
	if int(bd.get("floors", 3)) >= tall_floors and not tall_walls.is_empty() and tall_avoid.has(h % walls.size()):
		wall = walls[tall_walls[(h >> 4) % tall_walls.size()]]
	var tint: Color = wall[1]
	bd["wall_tex"] = int(wall[0])
	bd["tint"] = tint.lightened(float((h >> 8) % 7) * 0.01 - 0.03)
	bd["roof_tint"] = roofs[(h >> 12) % roofs.size()]
	bd["awning"] = awnings[(h >> 16) % awnings.size()]
	bd["awning_striped"] = (h >> 20) % 3 != 0


func share(prop: String) -> float:
	return float((data.get("roof_props", {}) as Dictionary).get(prop, 0.0))


func landmark() -> Dictionary:
	return data.get("landmark", {})
