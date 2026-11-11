class_name ShaderWarmup
extends Node
## [intro2] Draws every material of a freshly loaded scene once, behind the loading screen, so the
## shaders and pipelines compile there instead of on the first gameplay frames (a hitch, or a
## flat-colour flash where a material isn't ready yet).
## For each viewport (the main one and any SubViewport with its own 3D world) a small rig of tiny
## quads, one per unique spatial material, sits just in front of that viewport's camera for a few
## frames, then is freed. The scene itself also renders underneath the cover meanwhile.

const MAX_MATERIALS: int = 900
const FRAMES: int = 5
## [v6qa] Materials shown a frame: compiling every pipeline in the one frame the rig appeared froze the
## loading screen for that frame (the warm-up frame). In batches the bar and Lumi keep moving; the
## total work is the same and the batches overlap the frames the loader shows anyway.
const BATCH: int = 64

var _rigs: Array[Node3D] = []
var _frames: int = 0
var _need: int = FRAMES
var _count: int = 0
var _started: bool = false
var _pending: Array[MeshInstance3D] = []  # [v6qa] made, not yet shown


func start(scene: Node) -> void:
	_started = true
	# Headless runs and screenshot tooling (software Vulkan, slow frames) need just one pass.
	_need = 1 if DisplayServer.get_name() == "headless" or DevHooks.has("shot") else FRAMES
	var batched: bool = _need > 1  # [v6qa] headless and shot runs compile nothing: one pass as before
	var by_vp: Dictionary = {}  # Viewport -> Array[Material]
	var seen: Dictionary = {}
	for n: Node in scene.find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = n
		var vp: Viewport = gi.get_viewport()
		if vp == null:
			continue
		for m: Material in _materials_of(gi):
			if _count >= MAX_MATERIALS:
				break
			var id: int = m.get_instance_id()
			if seen.has(id) or not _spatial(m):
				continue
			seen[id] = true
			if not by_vp.has(vp):
				by_vp[vp] = []
			(by_vp[vp] as Array).append(m)
			_count += 1
	for vp: Viewport in by_vp:
		var cam: Camera3D = vp.get_camera_3d()
		if cam == null:
			continue
		var rig := Node3D.new()
		rig.name = "ShaderWarmupRig"
		cam.add_child(rig)
		var mats: Array = by_vp[vp]
		var side: int = int(ceil(sqrt(float(mats.size()))))
		var quad := QuadMesh.new()
		quad.size = Vector2(0.004, 0.004)
		for i: int in mats.size():
			var mi := MeshInstance3D.new()
			mi.mesh = quad
			mi.material_override = mats[i]
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if batched else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # [v6qa] the shadow (depth) pass's pipelines too
			var gx: float = (float(i % side) / maxf(side - 1, 1) - 0.5) * 0.3
			var gy: float = (float(i / side) / maxf(side - 1, 1) - 0.5) * 0.2
			mi.position = Vector3(gx, gy, -maxf(cam.near * 4.0, 0.5))
			rig.add_child(mi)
			if batched:
				mi.visible = false
				_pending.append(mi)
		_rigs.append(rig)
	print("[warmup] %d materials across %d viewports" % [_count, _rigs.size()])


static func _spatial(m: Material) -> bool:
	if m is BaseMaterial3D:
		return true
	if m is ShaderMaterial:
		var sh: Shader = (m as ShaderMaterial).shader
		return sh != null and sh.get_mode() == Shader.MODE_SPATIAL
	return false


static func _materials_of(gi: GeometryInstance3D) -> Array[Material]:
	var out: Array[Material] = []
	if gi.material_override:
		out.append(gi.material_override)
	if gi.material_overlay:
		out.append(gi.material_overlay)
	var mesh: Mesh = null
	if gi is MeshInstance3D:
		var mi: MeshInstance3D = gi
		mesh = mi.mesh
		if mesh:
			for i: int in mesh.get_surface_count():
				var o: Material = mi.get_surface_override_material(i)
				if o:
					out.append(o)
	elif gi is MultiMeshInstance3D:
		var mm: MultiMesh = (gi as MultiMeshInstance3D).multimesh
		mesh = mm.mesh if mm else null
	elif gi is CPUParticles3D:
		mesh = (gi as CPUParticles3D).mesh
	if mesh and gi.material_override == null:
		for i: int in mesh.get_surface_count():
			var sm: Material = mesh.surface_get_material(i)
			if sm:
				out.append(sm)
	return out


func _process(_delta: float) -> void:
	if not _started:
		return
	if not _pending.is_empty():  # [v6qa] the next batch; the frame count starts once all are shown
		for k: int in mini(BATCH, _pending.size()):
			var mi: MeshInstance3D = _pending.pop_back()
			if is_instance_valid(mi):
				mi.visible = true
		return
	_frames += 1
	if _frames >= _need:
		for r: Node3D in _rigs:
			if is_instance_valid(r):
				r.queue_free()
		_rigs.clear()


func progress() -> float:
	var batches: int = ceili(float(_count) / BATCH) if _need > 1 else 0
	var left: int = ceili(float(_pending.size()) / BATCH)
	return clampf(float(batches - left + _frames) / float(batches + _need), 0.0, 1.0)


func finished() -> bool:
	return _started and _frames >= _need


func _exit_tree() -> void:
	for r: Node3D in _rigs:
		if is_instance_valid(r):
			r.queue_free()
