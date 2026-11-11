class_name OldTownShopSigns
extends Node3D
## Painted shop names for Old Town's streets past the yard's own dressing (StreetDressing only
## signs the facades within its NEAR_R of the yard): a board over the shopfront of the buildings
## nearest the way from the yard to the pump house, each with a trade's name in cream or dark
## paint. One MultiMesh for every board; one Label3D a name, hidden past LABEL_RANGE_M.

const MAX_SIGNS: int = 18
const BOARD_H: float = 0.62
const BOARD_Y: float = 3.4            # over the awning, under the first-floor windows
const LETTER_M: float = 0.3          # board width a letter needs
const LABEL_RANGE_M: float = 70.0
const BOARD_RANGE_M: float = 160.0
const NAMES: Array[String] = ["LAKESIDE BAKERY", "TOWN SEEDS", "KETTLE & PAN", "CLOCK REPAIR", "LANTERN CAFE", "PAPER & INK",
	"GREENGROCER", "TEA ROOM", "COBBLER", "FLORIST", "BARBER", "DAIRY", "IRONMONGER", "HABERDASHER", "CHEMIST", "PIE SHOP",
	"WATERSIDE FISH", "MAINS & VALVES"]
const BOARDS: Array[Color] = [Color(0.06, 0.4, 0.42), Color(0.7, 0.14, 0.1), Color(0.1, 0.22, 0.5), Color(0.9, 0.8, 0.58),
	Color(0.16, 0.42, 0.24), Color(0.86, 0.56, 0.08)]
const PAINT_LIGHT := Color(0.97, 0.92, 0.74)
const PAINT_DARK := Color(0.36, 0.1, 0.07)

var count: int = 0


## Signs the buildings of `site` that front a street, lie past `skip_r` of the yard and are
## nearest the line from the yard to `toward` (site-local metres).
func build(site: VerdanceSite, toward: Vector2, skip_r: float, seed_v: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var fronts: Array[Dictionary] = []
	for key: Vector2i in site.layout.blocks:
		for bd: Dictionary in site.layout.blocks[key]["buildings"]:
			if bool(bd.get("ruined", false)) or not bd.has("face"):
				continue
			var f: Dictionary = front_of(bd["rect"], bd["face"])
			var c: Vector2 = f["c"]
			if c.length() <= skip_r:
				continue
			f["d"] = Geometry2D.get_closest_point_to_segment(c, Vector2.ZERO, toward).distance_to(c)
			fronts.append(f)
	fronts.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var xfs: Array[Transform3D] = []
	var cols: Array[Color] = []
	for i: int in mini(MAX_SIGNS, fronts.size()):
		var f: Dictionary = fronts[i]
		var text: String = NAMES[i % NAMES.size()]
		var width: float = minf(float(f["width"]) - 0.8, LETTER_M * float(text.length()) + 0.7)
		if width < LETTER_M * float(text.length()) * 0.8:
			continue
		var face: Vector2 = f["face"]
		var out := Vector3(face.x, 0.0, face.y)
		var at: Vector2 = (f["c"] as Vector2) + face * 0.07
		var xf := Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), Vector3(at.x, BOARD_Y, at.y))
		var board: Color = BOARDS[rng.randi() % BOARDS.size()].lerp(Color(0.75, 0.72, 0.66), rng.randf_range(0.05, 0.2))
		xfs.append(xf * Transform3D(Basis.from_scale(Vector3(width, BOARD_H, 0.06)), Vector3.ZERO))
		cols.append(board)
		add_child(_label(text, xf.translated_local(Vector3(0, 0, 0.04)), PAINT_LIGHT if board.get_luminance() < 0.5 else PAINT_DARK))
		count += 1
	if xfs.is_empty():
		return
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	CityOldTown.mmi_on(self, "ShopBoards", BoxMesh.new(), xfs, cols, mat, false, BOARD_RANGE_M)


## The street side of a building plan: {c: middle of its front wall, face, width along the street}.
static func front_of(rect: Rect2, face: Vector2) -> Dictionary:
	var c: Vector2 = rect.get_center() + face * (rect.size * 0.5)
	var width: float = rect.size.y if absf(face.x) > 0.5 else rect.size.x
	return {"c": c, "face": face, "width": width}


func _label(text: String, xf: Transform3D, paint: Color) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = 72
	l.outline_size = 0
	l.pixel_size = 0.0046
	l.modulate = Color(paint.r, paint.g, paint.b, 0.9)
	l.shaded = true
	l.double_sided = false
	l.alpha_cut = Label3D.ALPHA_CUT_OPAQUE_PREPASS
	l.transform = xf
	l.visibility_range_end = LABEL_RANGE_M
	return l
