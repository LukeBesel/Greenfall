class_name YardSite
extends Node3D
## [orbD] The start yard's models on the walkable globe, on the hub-0 site prefab's anchors
## (VerdanceSite.START_YARD_ANCHORS). Every model is the yard helper's own (YardArt, the build
## scripts, FabricatorModel, the intro's pod); nothing is redrawn here. Who shows what:
##   Camp (systems/camp/camp.gd) drives the parts it drives on the flat game, through the slice's
##   `_ruin_bits`: the lean-to (frame, roof, back, side, work lamp, bulb, posts), the bench
##   (broken -> repaired), the yard street lamp and the generator.
##   This node follows the same saved state for the rest, the way their flat systems decide:
##   extra yard lamps and compost press, radio and nursery (YardBuilds.built), telescope
##   (GameState.world.telescope.built), stations (Stations.built_in_state), Bot Fabricator
##   (BotFabricator.built), and the escape pod in its crash site (always there).
## Already on the globe with their own models: the depot and its bin tiers, the signal tower
## tiers, the locker, Blink (camera_bot).
## Use (scenes/slice_orbit.gd, before Camp.attach): var bits := YardSite.build(slice, prefab, bench)

const LAMP_ANCHORS: Array[String] = ["lamps_0", "lamps_1", "lamps_2", "lamps_3"]

var world: Node
var prefab: SitePrefab
var bits: Dictionary = {}
var _extra_lamps: Array[Node3D] = []
var _composter: Node3D
var _radio: Node3D
var _nursery: Node3D
var _telescope: Node3D
var _stations: Dictionary = {}  # id -> Node3D
var _fabricator: FabricatorModel
var _pod: Node3D
var _poll: float = 0.0


## Builds every yard model on the prefab and returns the `_ruin_bits` Camp drives (bench included).
static func build(p_world: Node, p_prefab: SitePrefab, bench: Node3D) -> YardSite:
	var y := YardSite.new()
	y.name = "YardSite"
	y.world = p_world
	y.prefab = p_prefab
	p_prefab.add_child(y)
	y._build(bench)
	return y


var _slots: Dictionary = {}  # anchor name -> Node3D
var _shack: Node3D
var _bench: Node3D


func _slot(nm: String) -> Node3D:
	var n := Node3D.new()
	n.name = "Yard_" + nm
	n.transform = prefab.anchor_local(nm)
	add_child(n)
	_slots[nm] = n
	return n


## Anchors moved clear of another planet's geometry: the models follow (the shack with the bench).
func _on_anchors_moved(_names: PackedStringArray) -> void:
	for nm: String in _slots:
		(_slots[nm] as Node3D).transform = prefab.anchor_local(nm)
	if _shack:
		var bxf: Transform3D = prefab.anchor_local("bench")
		if _bench and _bench.get_parent() == prefab:
			_bench.transform = bxf
		_shack.transform = bxf * Transform3D(Basis(), Vector3(0, 0, 0.65))


func _build(bench: Node3D) -> void:
	# The lean-to over the bench: the flat layout (shack-local, opening toward +Z), so the bench
	# stands where it does on the flat yard, 0.65 m in from the shack's centre.
	var shack := Node3D.new()
	shack.name = "Shack"
	add_child(shack)
	_shack = shack
	_bench = bench
	prefab.anchors_moved.connect(_on_anchors_moved)
	shack.transform = (bench.transform if bench else prefab.anchor_local("bench")) * Transform3D(Basis(), Vector3(0, 0, 0.65))
	for k: String in ["frame", "roof", "back", "side", "bulb"]:
		var m := MeshInstance3D.new()
		m.name = k.capitalize()
		shack.add_child(m)
		bits[k] = m
	(bits["roof"] as Node3D).position = Vector3(0, 2.3, -0.05)
	(bits["roof"] as Node3D).rotation_degrees = Vector3(-9, 0, 2)
	(bits["back"] as Node3D).position = Vector3(0, 1.15, -1.15)
	(bits["side"] as Node3D).position = Vector3(-1.62, 0.8, -0.45)
	(bits["bulb"] as Node3D).position = Vector3(0, 2.15, -0.4)
	var lamp := SpotLight3D.new()
	lamp.light_color = Color(1.0, 0.85, 0.65)
	lamp.light_energy = 2.0
	lamp.spot_range = 3.5
	lamp.spot_angle = 50.0
	lamp.position = Vector3(0, 2.2, -0.4)
	lamp.rotation_degrees = Vector3(-90, 0, 0)
	shack.add_child(lamp)
	bits["lamp"] = lamp
	var sb := StaticBody3D.new()  # the back wall and the front posts (Camp switches them with the build)
	sb.collision_layer = PhysLayers.PROP
	var back_cs := CollisionShape3D.new()
	back_cs.shape = PropColliders.box_shape(Vector3(3.3, 2.3, 0.2))
	back_cs.position = Vector3(0, 1.15, -1.15)
	sb.add_child(back_cs)
	for px: float in [-1.6, 1.6]:
		var pcs := CollisionShape3D.new()
		pcs.shape = PropColliders.box_shape(Vector3(0.22, 2.1, 0.22))
		pcs.position = Vector3(px, 1.05, 1.0)
		sb.add_child(pcs)
		bits["post_l" if px < 0.0 else "post_r"] = pcs
	shack.add_child(sb)
	if bench:
		bits["bench"] = bench
	# Yard lamps: the first is the one Camp drives (street_lamp + street_light), the rest follow it.
	for i: int in LAMP_ANCHORS.size():
		var holder: Node3D = _slot(LAMP_ANCHORS[i])
		var sl := MeshInstance3D.new()
		sl.name = "StreetLamp"
		holder.add_child(sl)
		var light := SpotLight3D.new()
		light.light_color = Color(1.0, 0.82, 0.6)
		light.spot_range = 12.0
		light.spot_angle = 55.0
		light.shadow_enabled = i == 0
		light.rotation_degrees = Vector3(-90, 0, 0)
		holder.add_child(light)
		if i == 0:
			bits["street_lamp"] = sl
			bits["street_light"] = light
		else:
			YardArt.street_lamp().into(sl, 0.15)
			light.position.y = YardArt.LAMP_HEAD_Y - 0.12
			light.light_energy = 2.6
			_extra_lamps.append(holder)
	var gen_holder: Node3D = _slot("generator")
	var gen := MeshInstance3D.new()
	gen.name = "Generator"
	gen_holder.add_child(gen)
	bits["generator"] = gen
	YardArt.dress_board(bits)  # the yard helper's models into the flat node layout
	gen.position = Vector3.ZERO  # dress_board moves it out from under the flat lean-to; here the anchor is the spot
	# Compost press, CD-player stand, robot nursery (the models their systems build).
	_composter = _slot("composter")
	var cp: Dictionary = YardArt.composter()
	_composter.add_child((cp["body"] as YardArt.Kit).mi(0.2))
	for pair: Array in [["drum", Vector3(1.0, 1.1, 0)], ["head", Vector3(1.0, 1.15, -0.55)]]:
		var m: MeshInstance3D = (cp[pair[0]] as YardArt.Kit).mi(0.2)
		m.position = pair[1]
		_composter.add_child(m)
	YardArt.solid(_composter, Vector3(1.6, 1.4, 1.2), Vector3(0.5, 0.7, 0), "ComposterBody")
	_radio = _slot("radio")
	_radio.add_child(YardArt.radio_stand().mi(0.15, "Stand"))
	YardArt.solid(_radio, Vector3(1.2, 1.3, 0.8), Vector3(0, 0.65, 0), "RadioBody")
	_nursery = _slot("nursery")
	_nursery.add_child(YardArt.nursery(Vector2(5.0, 3.4)).mi(0.15, "Garden"))
	_nursery.add_child(YardArt.nursery_grass(Vector2(5.0, 3.4)))
	# The telescope's own model (automation/telescope.gd), without its view or remote progress.
	_telescope = _slot("telescope")
	var sc := Telescope.new()
	sc.data = RemoteProgress.cfg()
	sc.call("_spawn", false)
	var model: Node3D = sc.get("_model")
	if model:
		sc.remove_child(model)
		model.transform = Transform3D.IDENTITY
		_telescope.add_child(model)
	sc.free()
	# Stations: the real machine nodes, idle (their logic is the flat game's Stations), in a row.
	var st_root: Node3D = _slot("stations")
	var row: Array = [["conveyor", Conveyor.new(), Vector3(0, 0, 0)], ["auto_baler", AutoBaler.new(), Vector3(0, 0, -3.2)], ["recycler", Recycler.new(), Vector3(0, 0, 3.2)]]
	for e: Array in row:
		var n: Node3D = e[1]
		n.position = e[2]
		n.process_mode = Node.PROCESS_MODE_DISABLED
		st_root.add_child(n)
		_stations[e[0]] = n
	# The Bot Fabricator (systems/camp/fabricator_model.gd; logic: robots/fabricator, orbC).
	var fab_slot: Node3D = _slot("fabricator")
	_fabricator = FabricatorModel.new()
	fab_slot.add_child(_fabricator)
	# The escape pod in its crash site (story/intro.gd's pod, story/crash_site.gd), hatch open.
	var pod_slot: Node3D = _slot("pod")
	_pod = Intro.build_pod()
	CrashSite.attach(pod_slot, _pod, pod_slot.global_position if pod_slot.is_inside_tree() else Vector3.ZERO, 0.5)
	EscapePod.set_open(_pod, true, CrashSite.LEAN.x)
	if DevHooks.has("yard-all"):  # dev: the telescope, stations and Fabricator as built (their systems aren't on the globe yet)
		GameState.world["telescope"] = {"built": true}
		GameState.world["stations"] = {"conveyor": true, "recycler": true, "baler": {"pos": [0.0, 0.0]}}
		BotFabricator.state(BotFabricator.planet_of(world))["built"] = true
	_apply()
	YardBuilds.events.built.connect(func(_id: String) -> void: _apply())
	EventBus.upgrade_bought.connect(func(_a: Variant = null, _b: Variant = null) -> void: _apply())
	if DevHooks.has("yard-report"):  # dev: what stands in the yard (after Camp has applied the builds)
		get_tree().create_timer(2.0).timeout.connect(func() -> void: print(report()))


func _process(delta: float) -> void:
	_poll -= delta
	if _poll <= 0.0:
		_poll = 1.0
		_apply()


## Shows what is built (the same state the flat systems read). Camp does its own bits.
func _apply() -> void:
	_yield_to_real_systems()
	var lamps: bool = YardBuilds.built("lamps")
	for h: Node3D in _extra_lamps:
		_show(h, lamps)
		YardArt.set_powered(h, lamps)
	_show(_composter, YardBuilds.built("composter"))
	var radio: bool = YardBuilds.built("radio")
	_show(_radio, radio)
	YardArt.set_powered(_radio, radio)
	var nursery: bool = YardBuilds.built("nursery")
	_show(_nursery, nursery)
	YardArt.set_powered(_nursery, nursery)
	var tel: Variant = GameState.world.get("telescope")
	_show(_telescope, tel is Dictionary and bool((tel as Dictionary).get("built", false)))
	for id: String in _stations:
		_show(_stations[id], Stations.built_in_state(id))
	_show(_fabricator, BotFabricator.built(world))


## When orbB attaches a yard system with its own model (the real Telescope, the intro's pod and
## crash site, the extras' radio and nursery), its model is the one that stands: this node's
## stand-in for it goes away, so nothing is drawn twice.
func _yield_to_real_systems() -> void:
	# The real Telescope draws its model only once built: keep the stand-in until then.
	var tel: Telescope = Telescope.of(world) if world.is_inside_tree() else null
	if _telescope and tel and tel.built():
		_telescope.queue_free()
		_telescope = null
	# The crashed pod: orbB's CrashSite on the slice (meta "orbit_pod", or a child named CrashSite).
	if _pod and (world.has_meta("orbit_pod") or world.get_node_or_null("CrashSite") != null):
		_pod.get_parent().queue_free()  # this node's crash site holder
		_pod = null
	# [orbB] The compost press: the real Composter (its drum, press and label) once it shows.
	var cmp: Node3D = world.get("composter") as Node3D
	if _composter and cmp and cmp.visible:
		_composter.queue_free()
		_composter = null
		_slots.erase("composter")
	# Radio and nursery: the extras' own models stand once they show (built).
	var ex: ExtrasDirector = ExtrasDirector.of(world)
	if ex:
		if _radio and ex.radio and ex.radio.visible:
			_radio.queue_free()
			_radio = null
		if _nursery and ex.nursery and ex.nursery.visible:
			_nursery.queue_free()
			_nursery = null


static func _show(n: Node3D, on: bool) -> void:
	if n == null or n.visible == on:
		return
	n.visible = on
	for c: Node in n.find_children("*", "CollisionShape3D", true, false):
		(c as CollisionShape3D).disabled = not on


## "[yard] name:shown ..." for every model (Camp's bits and this node's), for headless checks.
func report() -> String:
	var parts: PackedStringArray = []
	for k: String in ["frame", "roof", "back", "bench", "bulb", "street_lamp", "generator"]:
		var n: Node3D = bits.get(k) as Node3D
		if n:
			parts.append("%s:%s" % [k, "on" if n.is_visible_in_tree() else "off"])
	var mine: Dictionary = {"lamps+": _extra_lamps[0] if not _extra_lamps.is_empty() else null, "composter": _composter, "radio": _radio,
		"nursery": _nursery, "telescope": _telescope, "fabricator": _fabricator, "pod": _pod}
	for id: String in _stations:
		mine[id] = _stations[id]
	for k: String in mine:
		var n2: Node3D = mine[k]
		if n2:
			var meshes: int = n2.find_children("*", "MeshInstance3D", true, false).size() + (1 if n2 is MeshInstance3D else 0)
			parts.append("%s:%s(%d)" % [k, "on" if n2.is_visible_in_tree() else "off", meshes])
	return "[yard] " + " ".join(parts)
