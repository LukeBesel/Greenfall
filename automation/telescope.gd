class_name Telescope
extends Node3D
## [scope] The Telescope: a small observatory at the base (bought in the Hub tab, ui/telescope_panel.gd).
## E at its door opens the telescope view (ui/telescope_view.gd): pick another world you've visited
## and watch its crew at work. While in use the dome's two shells part and the optical tube rises.
## Built once per district: GameState.world["telescope"] = {"built": true}. data/telescope.json.
## It also runs the remote-progress payout on world arrival (systems/remote_progress.gd), whether
## or not a telescope is built (robots work everywhere; the telescope just lets you watch).
## Dev: --scope (build it free here), --scope-sample (a sample visited world with no save),
##      --open=scope[=N] (open the view; N = world list index to zoom straight in), --scope-open (dome open).

signal used

var world: Node
var data: Dictionary = {}
var view: TelescopeView
var _model: Node3D
var _shell_l: Node3D
var _shell_r: Node3D
var _tube: Node3D
var _ring_mat: StandardMaterial3D
var _open: float = 0.0
var _open_target: float = 0.0
var _t: float = 0.0
var _anchor: Node3D


func _ready() -> void:
	add_to_group("telescope")
	add_to_group("persist")
	process_mode = Node.PROCESS_MODE_ALWAYS
	data = RemoteProgress.cfg()
	if DevHooks.has("scope-sample") and RemoteProgress.sample.is_empty():
		RemoteProgress.make_sample()
	if DevHooks.has("scope"):
		state()["built"] = true
	if built():
		_spawn(false)
	view = TelescopeView.new()
	view.name = "TelescopeView"
	view.world = world
	view.closed.connect(_on_view_closed)
	add_child(view)
	# Remote progress: pay what the crew here earned while Lumi was on another world.
	var fm: bool = bool(world.get("scope_from_memory")) if world and world.get("scope_from_memory") != null else false
	var res: Dictionary = RemoteProgress.on_district_ready(fm)
	if not res.is_empty() and float(res.get("cubes", 0.0)) + float(res.get("waiting_value", 0.0)) > 0.0:
		get_tree().create_timer(2.5).timeout.connect(func() -> void: EventBus.toast.emit(RemoteProgress.arrival_text(res), "story"))
	if DevHooks.has("scope-open"):
		_open_target = 1.0
		_open = 1.0
	if DevHooks.has("scope-debug"):
		print("[scope] ready built=%s open=%s" % [str(built()), DevHooks.get_s("open", "")])
	if DevHooks.get_s("open", "") == "scope":
		(func() -> void: open_view(int(DevHooks.get_f("scope-pick", -1.0)))).call_deferred()


static func of(n: Node) -> Telescope:
	if n == null or not n.is_inside_tree():
		return null
	return n.get_tree().get_first_node_in_group("telescope") as Telescope


func state() -> Dictionary:
	if not GameState.world.has("telescope") or not (GameState.world["telescope"] is Dictionary):
		GameState.world["telescope"] = {}
	return GameState.world["telescope"]


func persist_save() -> void:
	state()["built"] = built()


func built() -> bool:
	return bool(state().get("built", false)) or _model != null


func hub_level() -> int:
	if world and world.get("hub") != null:
		return int(world.hub.level)
	return int(GameState.world.get("hub_level", 1))


## The cost with "parts" mapped to the game's parts currency (the money rework) or bolts.
static func cost() -> Dictionary:
	var c: Dictionary = (RemoteProgress.cfg().get("cost", {"cubes": 6000, "parts": 40}) as Dictionary).duplicate()
	if c.has("parts"):
		var pid: String = "parts" if GameState.currencies.has("parts") else "bolts"
		if pid != "parts":
			c[pid] = c["parts"]
			c.erase("parts")
	return c


## "" when it can be built now, else why not.
func block_reason() -> String:
	if built():
		return tr("Built.")
	var rid: String = str(data.get("requires_research", "observatory"))
	var lv: int = int(data.get("requires_level", 4))
	if hub_level() < lv and not (Research.exists(rid) and Research.has(rid)):
		return tr("Requires hub level %d or research: %s.") % [lv, tr(str(Research.def(rid).get("name", rid))) if Research.exists(rid) else rid]
	if not Hub.can_pay(cost()):
		return tr("Not enough materials.")
	return ""


func build() -> bool:
	if block_reason() != "" or not Hub.pay(cost()):
		return false
	state()["built"] = true
	_spawn(true)
	GameState.inc_stat("telescopes_built")
	Audio.play("buy", 0.85, -2.0)
	EventBus.toast.emit(tr("Telescope built. Walk up to it and press E to look across the system."), "info")
	return true


# --- Use -------------------------------------------------------------------------------------

func open_view(pick: int = -1) -> void:
	if view == null or view.is_open:
		return
	_open_target = 1.0
	if world and world.get("patch") != null and world.patch.input is PlayerInput:
		(world.patch.input as PlayerInput).enabled = false
	Audio.play("whoosh", 0.7, -10.0)
	used.emit()
	GameState.inc_stat("telescope_uses")
	# The dome parts first, then the view opens (a beat to see it, not long).
	var delay: float = 0.0 if DevHooks.get_s("open", "") == "scope" else 0.7
	if delay <= 0.0:
		view.open_view(pick)
	else:
		get_tree().create_timer(delay).timeout.connect(func() -> void: view.open_view(pick))


func _on_view_closed() -> void:
	_open_target = 0.0
	if world and world.has_method("_on_modal_closed"):
		world._on_modal_closed()


func _process(delta: float) -> void:
	if _model == null:
		return
	_t += delta
	_open = move_toward(_open, _open_target, delta * 0.9)
	var e: float = _open * _open * (3.0 - 2.0 * _open)
	# The shells swing a little and slide apart on their rails: a clean slit, not a cracked egg.
	_shell_l.rotation.z = deg_to_rad(16.0) * e
	_shell_r.rotation.z = -deg_to_rad(16.0) * e
	_shell_l.position.x = -1.6 - 0.32 * e
	_shell_r.position.x = 1.6 + 0.32 * e
	_tube.rotation.x = deg_to_rad(25.0 + 32.0 * e)
	_tube.position.y = 1.7 + 0.35 * e
	_model.get_node("Dome").rotation.y = sin(_t * 0.05) * 0.25
	if _ring_mat:
		_ring_mat.emission_energy_multiplier = 1.1 + 0.5 * e + 0.12 * sin(_t * 1.3)


# --- Model -----------------------------------------------------------------------------------

func _pos() -> Vector3:
	var p: Array = data.get("pos", [-4.4, -6.2])  # [camp] the back edge of the yard
	return Vector3(float(p[0]), 0.0, float(p[1]))


## [camp] Where Lumi stands to use it (in front of the door), built or not.
func door_point() -> Vector3:
	var local: Vector3 = _pos() + Basis(Vector3.UP, deg_to_rad(float(data.get("yaw_deg", 30.0)))) * Vector3(0, 0, 2.2)
	return to_global(local) if is_inside_tree() else local  # [orbB] world space (this node sits on the globe's anchor)


static func _mat(c: Color, rough: float, metal: float = 0.0, coat: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if coat > 0.0:
		m.clearcoat_enabled = true
		m.clearcoat = coat
		m.clearcoat_roughness = 0.2
	return m


static func _glow_mat(c: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## A quarter sphere (half a dome): azimuth over half a turn on one side of the x = 0 plane.
static func dome_half(r: float, side: float, segs: int = 18, rings: int = 9) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in rings:
		for j: int in segs:
			var quad: Array[Vector3] = []
			for k: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1)]:
				var el: float = (float(i + k.y) / rings) * PI * 0.5
				var az: float = (float(j + k.x) / segs) * PI - PI * 0.5
				quad.append(Vector3(side * cos(el) * cos(az), sin(el), cos(el) * sin(az)) * r)
			var tri: Array = [[0, 1, 2], [0, 2, 3]] if side > 0.0 else [[0, 2, 1], [0, 3, 2]]
			for t: Array in tri:
				for idx: int in t:
					st.set_normal(quad[idx].normalized())
					st.add_vertex(quad[idx])
	return st.commit()


func _mi(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation = rot
	parent.add_child(m)
	return m


func _spawn(animate: bool) -> void:
	if _model != null:
		return
	var pearl := _mat(Color(0.92, 0.93, 0.94), 0.3, 0.0, 0.6)
	var satin := _mat(Color(0.16, 0.17, 0.19), 0.38, 0.65)
	var glass := Mats.glass(Color(0.06, 0.1, 0.14, 0.85), 0.04)
	var inner := _mat(Color(0.08, 0.085, 0.1), 0.6, 0.3)
	inner.cull_mode = BaseMaterial3D.CULL_DISABLED
	var shell := pearl.duplicate() as StandardMaterial3D
	shell.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ring_mat = _glow_mat(Color(0.55, 0.88, 1.0), 1.2)
	_model = Node3D.new()
	_model.name = "Observatory"
	_model.position = _pos()
	_model.rotation.y = deg_to_rad(float(data.get("yaw_deg", 90.0)))
	add_child(_model)
	# Plinth: a low satin hex step with a hairline light seam.
	_mi(_model, ProcMesh.cyl(2.25, 2.35, 0.18, 6), satin, Vector3(0, 0.09, 0))
	_mi(_model, ProcMesh.torus(2.17, 2.2, 6, 4), _ring_mat, Vector3(0, 0.185, 0), Vector3(0, PI / 6.0, 0))
	# Drum: pearl shell, a band of dark glass, a satin cornice and the thin glow line under the dome.
	_mi(_model, ProcMesh.cyl(1.62, 1.68, 1.25, 32), pearl, Vector3(0, 0.8, 0))
	_mi(_model, ProcMesh.cyl(1.635, 1.635, 0.22, 32), glass, Vector3(0, 1.02, 0))
	_mi(_model, ProcMesh.cyl(1.72, 1.66, 0.1, 32), satin, Vector3(0, 1.48, 0))
	_mi(_model, ProcMesh.torus(1.705, 1.72, 40, 4), _ring_mat, Vector3(0, 1.535, 0))
	# Door: a tall glass slot framed in satin, facing out, with a slim lit sill.
	var door := Node3D.new()
	door.position = Vector3(0, 0, 1.6)
	_model.add_child(door)
	_mi(door, ProcMesh.box(Vector3(0.95, 1.18, 0.12)), satin, Vector3(0, 0.78, 0.02))
	_mi(door, ProcMesh.box(Vector3(0.78, 1.04, 0.05)), glass, Vector3(0, 0.78, 0.09))
	_mi(door, ProcMesh.box(Vector3(0.78, 0.025, 0.04)), _ring_mat, Vector3(0, 0.25, 0.12))
	var sign_l := Label3D.new()
	sign_l.text = tr("OBSERVATORY")
	sign_l.font_size = 26
	sign_l.pixel_size = 0.004
	sign_l.modulate = Color(0.85, 0.95, 1.0, 0.8)
	sign_l.outline_size = 0
	sign_l.position = Vector3(0, 1.3, 0.14)
	door.add_child(sign_l)
	# Dome: two pearl shells that part on hinges along the rim; dark inside.
	var dome := Node3D.new()
	dome.name = "Dome"
	dome.position = Vector3(0, 1.53, 0)
	_model.add_child(dome)
	_shell_l = Node3D.new()
	_shell_l.position = Vector3(-1.6, 0, 0)
	dome.add_child(_shell_l)
	_shell_r = Node3D.new()
	_shell_r.position = Vector3(1.6, 0, 0)
	dome.add_child(_shell_r)
	_mi(_shell_l, dome_half(1.6, -1.0), shell, Vector3(1.6, 0, 0))
	_mi(_shell_r, dome_half(1.6, 1.0), shell, Vector3(-1.6, 0, 0))
	_mi(_shell_l, dome_half(1.56, -1.0), inner, Vector3(1.6, 0, 0))
	_mi(_shell_r, dome_half(1.56, 1.0), inner, Vector3(-1.6, 0, 0))
	# Optical tube on a fork mount, tilted up through the slit when open.
	var mount := _mi(_model, ProcMesh.cyl(0.32, 0.42, 1.1, 16), satin, Vector3(0, 1.2, 0))
	mount.name = "Mount"
	_tube = Node3D.new()
	_tube.position = Vector3(0, 1.7, 0)
	_model.add_child(_tube)
	_mi(_tube, ProcMesh.cyl(0.24, 0.27, 1.8, 20), pearl, Vector3(0, 0, -0.2), Vector3(PI * 0.5, 0, 0))
	_mi(_tube, ProcMesh.cyl(0.285, 0.285, 0.14, 20), satin, Vector3(0, 0, -1.06), Vector3(PI * 0.5, 0, 0))
	_mi(_tube, ProcMesh.cyl(0.22, 0.22, 0.02, 20), glass, Vector3(0, 0, -1.14), Vector3(PI * 0.5, 0, 0))
	_mi(_tube, ProcMesh.torus(0.272, 0.286, 24, 4), _ring_mat, Vector3(0, 0, -0.95), Vector3(PI * 0.5, 0, 0))
	# A slim mast with a soft aviation light, like the rest of the restored base.
	_mi(_model, ProcMesh.cyl(0.025, 0.035, 1.4, 6), satin, Vector3(1.35, 2.1, -0.9))
	_mi(_model, ProcMesh.sphere(0.06, 8, 4), Mats.lamp(Color(0.6, 0.9, 1.0), 2.0), Vector3(1.35, 2.83, -0.9))
	YardArt.kitify(_model)  # [yard] bevelled kit parts and shaders (glass, glow rings and domes stay)
	var annex: MeshInstance3D = YardArt.observatory_dress().mi(0.12, "Annex")  # [yard]
	_model.add_child(annex)
	YardArt.set_powered(annex, true)
	_anchor = Node3D.new()
	_anchor.position = _model.position + Basis(Vector3.UP, _model.rotation.y) * Vector3(0, 0, 2.2)
	add_child(_anchor)
	var col := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 1.75
	cyl.height = 3.2
	cs.shape = cyl
	cs.position = Vector3(0, 1.6, 0)
	col.add_child(cs)
	_model.add_child(col)
	if world and world.get("interactables") != null:
		world.interactables.register(_anchor, float(data.get("use_range", 3.4)), func() -> String: return tr("E   Telescope: look across the system"), open_view)
	if animate:
		_model.scale = Vector3(1, 0.02, 1)
		create_tween().tween_property(_model, "scale", Vector3.ONE, 1.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		Vfx.burst("sparkle", _model.global_position + _model.global_basis.y.normalized() * 2.0, Color(0.7, 0.9, 1.0), 1.0)  # [orbB] local up
