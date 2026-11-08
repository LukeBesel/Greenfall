class_name Museum
extends Node3D
## [eggs2] Lumi's collection and the Museum (data/museum.json). Every collectible in the game is an
## exhibit: picked-up gnomes, Biscuit's shell, the time capsule, the last broadcast, the memory
## shards, trinkets, curiosities and the planet relics. The Codex Collection page lists them; the
## Museum, a late build Lumi leaves behind at Verdance's Cradle Returns (once the Cradle has
## answered), shows each on a plinth, a ghost of it on the plinths still empty. Filling every
## plinth is the 100% goal: flags.museum_complete, the "museum_complete" achievement and a small
## moment (the gnomes salute). Other planets plug in by adding exhibits (kind relic / flag / egg).

const PATH: String = "res://data/museum.json"
const PLINTH_GAP: float = 1.75

static var _cfg: Dictionary = {}

var world: Node
var plinths: Dictionary = {}  # exhibit id -> Node3D (the plinth)
var gnome_bed: EggDisplay
var _site: Node3D  # the plot sign before it is built


static func cfg() -> Dictionary:
	if _cfg.is_empty():
		_cfg = Economy.read_json(PATH)
	return _cfg


static func exhibits() -> Array:
	return cfg().get("exhibits", [])


static func exhibit(id: String) -> Dictionary:
	for x: Dictionary in exhibits():
		if str(x["id"]) == id:
			return x
	return {}


static func cost() -> Dictionary:
	return cfg().get("cost", {})


## [have, total] for one exhibit.
static func progress(x: Dictionary) -> Vector2i:
	var ref: String = str(x.get("ref", ""))
	match str(x.get("kind", "")):
		"egg":
			return Vector2i(1 if EasterEggs.is_found(ref) else 0, 1)
		"egg_parts":
			var total: int = 1
			for e: Dictionary in Codex.egg_defs():
				if str(e["id"]) == ref:
					total = int(e.get("parts", 1))
			return Vector2i(mini(EggCollect.count(ref), total), total)
		"eggs":
			var n: int = 0
			var t: int = 0
			for e: Dictionary in Codex.egg_defs():
				if str(e.get("where", "")) == "new_world":
					continue
				t += 1
				n += 1 if EasterEggs.is_found(str(e["id"])) else 0
			return Vector2i(n, t)
		"shards":
			var all: Array = Economy.read_json("res://data/shards.json").get("shards", [])
			return Vector2i(mini((GameState.flags.get("shards_found", []) as Array).size(), all.size()), all.size())
		"trinkets":
			return Vector2i(Collection.count(), Collection.total())
		"relic":
			return Vector2i(1 if ref in Homeward.relics() else 0, 1)
		"flag":
			return Vector2i(1 if GameState.flags.get(ref, false) else 0, 1)
	return Vector2i(0, 1)


static func is_full(x: Dictionary) -> bool:
	var p: Vector2i = progress(x)
	return p.x >= p.y


## Exhibits that are full / all exhibits.
static func filled() -> int:
	return exhibits().filter(func(x: Dictionary) -> bool: return is_full(x)).size()


static func complete() -> bool:
	return filled() >= exhibits().size()


static func hint(x: Dictionary) -> String:
	if x.has("hint"):
		return str(x["hint"])
	if str(x.get("kind", "")) in ["egg", "egg_parts"]:
		for e: Dictionary in Codex.egg_defs():
			if str(e["id"]) == str(x.get("ref", "")):
				return str(e.get("hint", ""))
	return ""


static func built() -> bool:
	return bool(GameState.flags.get("museum_built", false))


## The Museum's site: Verdance's Cradle Returns (the Homeward launch base), once the Cradle has answered.
static func unlocked() -> bool:
	return Homeward.answered() or DevHooks.has("museum")


static func site_here(w: Node) -> bool:
	if DevHooks.has("museum-here"):
		return true
	return Homeward.at_home_site(w)


static func blocker() -> String:
	if not unlocked():
		return TranslationServer.translate("The Cradle has to answer first (Cradle Returns)")
	if not GameState.can_afford_all(cost()):
		return TranslationServer.translate("Not enough cubes, parts or seeds")
	return ""


## Marks the Museum complete once every plinth is full (true the first time).
static func check_complete() -> bool:
	if bool(GameState.flags.get("museum_complete", false)) or not built() or not complete():
		return false
	GameState.flags["museum_complete"] = true
	return true


## Dev (--museum-sample): a partly filled collection, for screenshots.
static func dev_sample() -> void:
	for id: String in ["tv", "duck", "time_capsule", "stars"]:
		GameState.flags["egg_" + id] = true
	for i: int in 3:
		EggCollect.add("gnomes", i)
	var sh: Array = []
	for d: Dictionary in Economy.read_json("res://data/shards.json").get("shards", []).slice(0, 3):
		sh.append(str(d["id"]))
	GameState.flags["shards_found"] = sh
	var rl: Variant = Homeward.state().get("relics", [])
	if rl is Array and not ("ochre_glass" in rl):
		(rl as Array).append("ochre_glass")


# --- In the world -----------------------------------------------------------------------

static func attach(w: Node) -> Museum:
	if not site_here(w) or not unlocked():
		return null
	var m := Museum.new()
	m.name = "Museum"
	m.world = w
	w.add_child(m)
	m._setup()
	return m


func _pos() -> Vector3:
	var p: Array = cfg().get("pos", [-15.0, 4.0])
	var v := Vector3(float(p[0]), 0.0, float(p[1]))
	if world and world.get("field") != null and world.field and world.field.layout:
		v.y = clampf(world.field.layout.height_at(v.x, v.z), 0.0, 0.3)
	return v


func _setup() -> void:
	global_position = _pos()
	rotation.y = deg_to_rad(float(cfg().get("yaw_deg", 0.0)))
	if DevHooks.has("museum-built"):
		GameState.flags["museum_built"] = true
	if built():
		_build_hall(false)
	else:
		_build_site()
	if DevHooks.has("spawn-museum"):
		_dev_spawn.call_deferred()


func _build_site() -> void:
	_site = Node3D.new()
	_site.name = "MuseumSite"
	add_child(_site)
	var wood: StandardMaterial3D = DecorProps.wood(Color(0.6, 0.45, 0.3))
	_site.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.08, 1.2, 0.08)), wood, Vector3(0, 0.6, 0)))
	_site.add_child(EggProps.mesh(ProcMesh.box(Vector3(1.3, 0.55, 0.05)), Mats.worn_paint(Color(0.92, 0.9, 0.82), 0.9, 0.1, 3.0, 0.3), Vector3(0, 1.2, 0.05)))
	_site.add_child(EggProps.label(tr("FUTURE MUSEUM"), 34, Color(0.2, 0.18, 0.15), Vector3(0, 1.28, 0.08)))
	_site.add_child(EggProps.label(tr("for whoever comes next"), 22, Color(0.35, 0.3, 0.25), Vector3(0, 1.12, 0.08)))
	# String lines marking out the footprint.
	var line := StandardMaterial3D.new()
	line.albedo_color = Color(0.95, 0.85, 0.3)
	for k: int in 4:
		var horiz: bool = k < 2
		var len_: float = 14.0 if horiz else 8.0
		var off := Vector3(0, 0.03, (4.0 if k == 0 else -4.0)) if horiz else Vector3((7.0 if k == 2 else -7.0), 0.03, 0)
		_site.add_child(EggProps.mesh(ProcMesh.box(Vector3(len_, 0.02, 0.03) if horiz else Vector3(0.03, 0.02, len_)), line, off + Vector3(0, 0, -4.5)))
	if world and world.get("interactables") != null:
		world.interactables.register(_site, 2.4, func() -> String:
			var b: String = blocker()
			return tr("E   build the Museum   %s") % Homeward.cost_text(cost()) if b == "" else tr("Museum   %s   (%s)") % [Homeward.cost_text(cost()), b],
			_try_build)


func _try_build() -> void:
	var b: String = blocker()
	if b != "":
		EventBus.toast.emit(b, "info")
		Audio.play("buzz", 1.2, -10.0)
		return
	GameState.spend_all(cost())
	GameState.flags["museum_built"] = true
	GameState.inc_stat("museum_built")
	if world and world.get("interactables") != null:
		world.interactables.unregister(_site)
	_site.queue_free()
	_site = null
	_build_hall(true)
	Audio.play("buy", 0.85, -2.0)
	EventBus.toast.emit(tr("The Museum is built. Everything Lumi found has a place now, for whoever comes next."), "story")


## The hall: an open pavilion (floor, back and side walls, a roof on slim columns), two rows of plinths.
func _build_hall(animate: bool) -> void:
	var hall := Node3D.new()
	hall.name = "Hall"
	add_child(hall)
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.9, 0.88, 0.84)
	stone.roughness = 0.75
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.32, 0.5, 0.36)
	trim.roughness = 0.6
	var w: float = 14.0
	var d: float = 9.0
	hall.add_child(EggProps.mesh(ProcMesh.box(Vector3(w + 0.6, 0.25, d + 0.6)), stone, Vector3(0, 0.12, -d * 0.5)))
	hall.add_child(EggProps.mesh(ProcMesh.box(Vector3(w, 3.2, 0.3)), stone, Vector3(0, 1.85, -d + 0.15)))
	for s: float in [-1.0, 1.0]:
		hall.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.3, 3.2, d * 0.6)), stone, Vector3(s * (w * 0.5 - 0.15), 1.85, -d + d * 0.3)))
		hall.add_child(EggProps.mesh(ProcMesh.cyl(0.14, 0.16, 3.2, 12), stone, Vector3(s * (w * 0.5 - 0.3), 1.85, -0.3)))
	hall.add_child(EggProps.mesh(ProcMesh.box(Vector3(w + 0.8, 0.22, d + 0.8)), stone, Vector3(0, 3.55, -d * 0.5)))
	hall.add_child(EggProps.mesh(ProcMesh.box(Vector3(w + 0.82, 0.08, d + 0.82)), trim, Vector3(0, 3.42, -d * 0.5)))
	var sign_y: float = 3.1
	hall.add_child(EggProps.label(tr("THE MUSEUM OF COMING BACK"), 54, Color(0.25, 0.4, 0.3), Vector3(-3.0, sign_y, -0.12)))
	hall.add_child(EggProps.label(tr("everything Lumi found, kept for whoever comes next"), 26, Color(0.35, 0.38, 0.35), Vector3(-3.0, sign_y - 0.22, -0.12)))
	var lamp: OmniLight3D = EggProps.glow(Color(1.0, 0.9, 0.75), 1.4, 12.0, Vector3(0, 3.0, -d * 0.5))
	hall.add_child(lamp)
	EggProps.collider(hall, Vector3(w, 3.2, 0.3), Vector3(0, 1.6, -d + 0.15))
	for s: float in [-1.0, 1.0]:
		EggProps.collider(hall, Vector3(0.3, 3.2, d * 0.6), Vector3(s * (w * 0.5 - 0.15), 1.6, -d + d * 0.3))
	# Plinths: back row along the wall, front row in the middle.
	var xs: Array = exhibits()
	var per_row: int = int(ceil(xs.size() / 2.0))
	for i: int in xs.size():
		var row: int = i / per_row
		var col: int = i % per_row
		var n_in_row: int = per_row if row == 0 else xs.size() - per_row
		var x: float = (col - (n_in_row - 1) * 0.5) * PLINTH_GAP
		var z: float = -d + 1.6 if row == 0 else -d * 0.42
		var p: Node3D = _plinth(xs[i])
		p.position = Vector3(x, 0.25, z)
		hall.add_child(p)
		plinths[str(xs[i]["id"])] = p
	if animate:
		hall.scale = Vector3(1, 0.02, 1)
		var tw := hall.create_tween()
		tw.tween_property(hall, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Vfx.burst("confetti", global_position + Vector3(0, 3.0, 0), Color.WHITE)
	if check_complete():
		_complete_moment.call_deferred()
	if world and world.get("interactables") != null and gnome_bed:
		world.interactables.register(gnome_bed, 1.8, tr("E   salute the Gnome Patrol"), func() -> void:
			gnome_bed.salute(world.patch.global_position if world.patch else gnome_bed.global_position + Vector3(0, 0, 2)),
			func() -> bool: return EggCollect.count("gnomes") >= gnome_bed.total)


static func _ghost_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.55, 0.85, 1.0, 0.22)
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


static func _ghostify(n: Node, mat: Material) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).material_override = mat
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if n is Light3D:
		(n as Light3D).visible = false
	if n is Label3D:
		(n as Label3D).visible = false
	if n is CollisionObject3D:
		n.queue_free()
		return
	for c: Node in n.get_children():
		_ghostify(c, mat)


static func _strip_colliders(n: Node) -> void:
	for c: Node in n.get_children():
		if c is CollisionObject3D:
			c.queue_free()
		else:
			_strip_colliders(c)


func _plinth(x: Dictionary) -> Node3D:
	var p := Node3D.new()
	p.name = "Plinth_" + str(x["id"])
	var prog: Vector2i = progress(x)
	var full: bool = prog.x >= prog.y
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.95, 0.94, 0.9) if prog.x > 0 else Color(0.7, 0.72, 0.74)
	stone.roughness = 0.5
	var pw: float = 1.6 if str(x.get("kind", "")) == "egg_parts" else 1.1
	p.add_child(EggProps.mesh(ProcMesh.box(Vector3(pw, 0.85, 1.0)), stone, Vector3(0, 0.425, 0)))
	var cap := StandardMaterial3D.new()
	cap.albedo_color = Color(0.32, 0.5, 0.36) if full else Color(0.4, 0.42, 0.44)
	p.add_child(EggProps.mesh(ProcMesh.box(Vector3(pw + 0.06, 0.05, 1.06)), cap, Vector3(0, 0.87, 0)))
	EggProps.collider(p, Vector3(pw, 0.85, 1.0), Vector3(0, 0.425, 0))
	var name_: String = tr(str(x["name"])) if prog.x > 0 else "?  ?  ?"
	var count: String = "%d / %d" % [prog.x, prog.y] if prog.y > 1 else ""
	p.add_child(EggProps.label(name_, 22, Color(0.2, 0.2, 0.2), Vector3(0, 0.62, 0.51)))
	if count != "":
		p.add_child(EggProps.label(count, 20, Color(0.3, 0.35, 0.3), Vector3(0, 0.48, 0.51)))
	var top := Node3D.new()
	top.name = "Top"
	top.position = Vector3(0, 0.9, 0)
	p.add_child(top)
	var kind: String = str(x.get("kind", ""))
	if kind == "egg_parts" and str(x.get("prop", "")) != "":
		var prop: String = str(x["prop"])
		gnome_bed = EggDisplay.make(str(x.get("ref", "")), prog.y, "", func(i: int) -> Node3D: return EggProps.build(prop, i), 0.24, 0.6)
		_strip_colliders(gnome_bed)
		top.add_child(gnome_bed)
		# Ghosts stand in the slots still empty.
		for i: int in gnome_bed.figures.size():
			if not gnome_bed.figures[i].visible:
				var g: Node3D = EggProps.build(prop, i)
				_ghostify(g, _ghost_mat())
				g.position = gnome_bed.figures[i].position
				g.scale = gnome_bed.figures[i].scale
				gnome_bed.add_child(g)
		return p
	var piece: Node3D = _piece(x, prog)
	if piece:
		top.add_child(piece)
	return p


## The thing on top of a plinth: the egg's prop (shrunk to fit), a gem, a row of shards or boxes.
func _piece(x: Dictionary, prog: Vector2i) -> Node3D:
	var have: bool = prog.x > 0
	var n := Node3D.new()
	var prop: String = str(x.get("prop", ""))
	if prop != "":
		var m: Node3D = EggProps.build(prop, 0)
		_strip_colliders(m)
		n.add_child(m)
		var aabb: AABB = _aabb(m)
		var big: float = maxf(aabb.size.x, maxf(aabb.size.y * 0.8, aabb.size.z))
		m.scale = Vector3.ONE * clampf(0.9 / maxf(big, 0.01), 0.15, 1.2)
		m.position.x = -aabb.get_center().x * m.scale.x
		m.position.z = -aabb.get_center().z * m.scale.z
		if not have:
			_ghostify(m, _ghost_mat())
		return n
	var col: Color = Color.html(str(x.get("color", "#a0e0ff")))
	match str(x.get("shape", "")):
		"gem":
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.metallic = 0.3
			mat.roughness = 0.15
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 0.6
			var gem: MeshInstance3D = EggProps.mesh(ProcMesh.sphere(0.16, 8, 4), mat if have else _ghost_mat(), Vector3(0, 0.35, 0), Vector3(0, 30, 0), Vector3(1, 1.5, 1))
			n.add_child(gem)
			n.add_child(EggProps.mesh(ProcMesh.cyl(0.05, 0.1, 0.18, 8), Mats.metal("brass"), Vector3(0, 0.09, 0)))
		_:
			# A tray of tokens, one per find (shards: glowing slivers; trinkets/curiosities: little boxes).
			var total: int = mini(prog.y, 24)
			var shown: int = int(round(float(prog.x) / maxf(prog.y, 1) * total))
			var shard: bool = str(x.get("shape", "")) == "shard"
			var lit := StandardMaterial3D.new()
			lit.albedo_color = Color(0.7, 0.95, 1.0) if shard else Color(0.95, 0.8, 0.45)
			lit.emission_enabled = shard
			lit.emission = Color(0.5, 0.9, 1.0)
			lit.emission_energy_multiplier = 0.8
			n.add_child(EggProps.mesh(ProcMesh.box(Vector3(0.95, 0.04, 0.85)), Mats.metal("dark_steel"), Vector3(0, 0.02, 0)))
			var cols: int = 6
			for i: int in total:
				var px: float = (i % cols - (cols - 1) * 0.5) * 0.14
				var pz: float = (i / cols - 1.5) * 0.18
				var mesh_: Mesh = ProcMesh.box(Vector3(0.04, 0.16, 0.02)) if shard else ProcMesh.box(Vector3(0.09, 0.07, 0.09))
				var mi: MeshInstance3D = EggProps.mesh(mesh_, lit if i < shown else _ghost_mat(), Vector3(px, 0.1 if shard else 0.075, pz), Vector3(0, 20.0 * (i % 3), 8.0 if shard else 0.0))
				n.add_child(mi)
	return n


static func _aabb(n: Node3D) -> AABB:
	var out := AABB()
	var first: bool = true
	var stack: Array[Node] = [n]
	while not stack.is_empty():
		var c: Node = stack.pop_back()
		if c is VisualInstance3D and not (c is Light3D) and not (c is Label3D):
			var a: AABB = (c as VisualInstance3D).get_aabb()
			var xf: Transform3D = _rel_xf(n, c as Node3D)
			a = xf * a
			out = a if first else out.merge(a)
			first = false
		for k: Node in c.get_children():
			stack.append(k)
	return out


static func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var c: Node3D = n
	while c != null and c != root:
		xf = c.transform * xf
		c = c.get_parent() as Node3D
	return xf


func _complete_moment() -> void:
	Achievements.check_all()
	EventBus.toast.emit(tr("Every plinth is full. The Museum is complete: everything Lumi found, kept for whoever comes next."), "story")
	Vfx.burst("confetti", global_position + Vector3(0, 3.0, -4.0), Color.WHITE)
	Audio.play("chime", 1.0, -4.0)
	if gnome_bed:
		get_tree().create_timer(1.0, false).timeout.connect(func() -> void:
			if is_instance_valid(gnome_bed):
				gnome_bed.salute(world.patch.global_position if world and world.patch else gnome_bed.global_position + Vector3(0, 0, 3)))
	if world and world.get("wren") != null and (world.wren as Wren).lines.has("museum_complete"):
		world.wren.say("museum_complete", 1.0, true)


func _dev_spawn() -> void:
	if world == null or world.patch == null:
		return
	var fwd: Vector3 = global_transform.basis.z
	var p: Vector3 = global_position + fwd * DevHooks.get_f("museum-dist", 3.5) + global_transform.basis.x * DevHooks.get_f("museum-side", 0.0)
	world.patch.global_position = Vector3(p.x, global_position.y + 0.3, p.z)
	world.patch.rotation.y = atan2(fwd.x, fwd.z)
	world.cam.yaw = world.patch.rotation.y + DevHooks.get_f("museum-yaw", 0.0)
	world.cam.snap()
	print("[museum] Lumi at the Museum (%s), %d / %d exhibits full" % [str(global_position), filled(), exhibits().size()])
