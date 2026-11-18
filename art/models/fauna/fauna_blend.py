"""[fauna2] Shared helpers for the animal builders (Blender 4.0, run with `blender -b --python`).

Bodies are built from simple solids (ellipsoids, tapered capsules), joined, voxel-remeshed into
one seamless skin and smoothed, so joints blend like real anatomy instead of showing primitive
seams. Faces (eyes, nose, ears, whiskers) stay separate crisp parts. Bones get automatic weights
on the skin; rigid parts follow one bone. Actions are keyed with small pose helpers and exported
as glTF animations. Blender axes: +Y forward, +Z up (glTF export turns +Y into -Z, the game's
forward).
"""
import bpy
import bmesh
import math
from mathutils import Vector, Matrix, Euler, noise


def reset():
	bpy.ops.wm.read_factory_settings(use_empty=True)


def link(o):
	bpy.context.scene.collection.objects.link(o)
	return o


def activate(o):
	bpy.ops.object.select_all(action='DESELECT')
	o.select_set(True)
	bpy.context.view_layer.objects.active = o


def material(name, color=(0.8, 0.8, 0.8, 1), rough=0.6):
	m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
	m.use_nodes = True
	b = m.node_tree.nodes.get("Principled BSDF")
	b.inputs["Base Color"].default_value = color
	b.inputs["Roughness"].default_value = rough
	return m


def ellipsoid(c, r, rot=(0, 0, 0), segs=24, rings=14):
	bm = bmesh.new()
	bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=1.0)
	m = Matrix.Translation(Vector(c)) @ Euler([math.radians(a) for a in rot]).to_matrix().to_4x4() @ Matrix.Diagonal((r[0], r[1], r[2], 1))
	bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
	return bm


def capsule(a, b, ra, rb, segs=16):
	"""Tapered capsule from a (radius ra) to b (radius rb), as a bmesh."""
	a = Vector(a)
	b = Vector(b)
	d = b - a
	l = d.length
	bm = bmesh.new()
	bmesh.ops.create_cone(bm, cap_ends=True, segments=segs, radius1=ra, radius2=rb, depth=l)
	q = Vector((0, 0, 1)).rotation_difference(d.normalized())
	m = Matrix.Translation((a + b) * 0.5) @ q.to_matrix().to_4x4()
	bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
	for c, r in ((a, ra), (b, rb)):
		s = ellipsoid(c, (r, r, r), segs=segs, rings=max(8, segs // 2))
		merge_bm(bm, s)
	return bm


def merge_bm(dst, src):
	me = bpy.data.meshes.new("tmp")
	src.to_mesh(me)
	dst.from_mesh(me)
	bpy.data.meshes.remove(me)
	src.free()


def mesh_obj(name, bm, mat=None):
	me = bpy.data.meshes.new(name)
	bm.to_mesh(me)
	bm.free()
	o = link(bpy.data.objects.new(name, me))
	if mat:
		o.data.materials.append(mat)
	return o


def skin(name, parts, voxel=0.004, smooth_repeat=10, ratio=0.35, mat=None):
	"""Joins solids (list of bmesh) into one remeshed, smoothed, decimated skin."""
	bm = bmesh.new()
	for p in parts:
		merge_bm(bm, p)
	o = mesh_obj(name, bm, mat)
	activate(o)
	r = o.modifiers.new("remesh", 'REMESH')
	r.mode = 'VOXEL'
	r.voxel_size = voxel
	r.adaptivity = 0.0
	s = o.modifiers.new("smooth", 'SMOOTH')
	s.factor = 0.8
	s.iterations = smooth_repeat
	if ratio < 0.999:
		d = o.modifiers.new("dec", 'DECIMATE')
		d.ratio = ratio
	for m in list(o.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)
	bpy.ops.object.shade_smooth()
	return o


def apply_all(o):
	activate(o)
	for m in list(o.modifiers):
		bpy.ops.object.modifier_apply(modifier=m.name)


def colors(o, fn, name="Col"):
	"""Per-vertex colour from fn(co: Vector, normal: Vector) -> (r, g, b, a) (linear floats)."""
	attr = o.data.color_attributes.new(name, 'FLOAT_COLOR', 'POINT')
	o.data.color_attributes.active_color = attr
	o.data.color_attributes.render_color_index = o.data.color_attributes.active_color_index
	for i, v in enumerate(o.data.vertices):
		attr.data[i].color = fn(v.co.copy(), v.normal.copy())


def eye_uv(o, center, forward):
	"""UV = the eye's own front-facing disc coordinates (iris / pupil drawn by the shader)."""
	f = Vector(forward).normalized()
	up = Vector((0, 0, 1))
	right = f.cross(up).normalized()
	up2 = right.cross(f).normalized()
	uvl = o.data.uv_layers.new(name="UVMap")
	for poly in o.data.polygons:
		for li in poly.loop_indices:
			co = o.data.vertices[o.data.loops[li].vertex_index].co - Vector(center)
			n = co.normalized()
			uvl.data[li].uv = (n.dot(right) * 0.5 + 0.5, n.dot(up2) * 0.5 + 0.5)


def bind_rigid(o, bone):
	vg = o.vertex_groups.new(name=bone)
	vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')


def join(target, objs):
	bpy.ops.object.select_all(action='DESELECT')
	for x in objs:
		x.select_set(True)
	target.select_set(True)
	bpy.context.view_layer.objects.active = target
	bpy.ops.object.join()
	return target


def armature(name, bones):
	"""bones: list of (name, head, tail, parent or None, deform)."""
	arm = bpy.data.armatures.new(name)
	ao = link(bpy.data.objects.new(name, arm))
	activate(ao)
	bpy.ops.object.mode_set(mode='EDIT')
	eb = {}
	for n, h, t, par, deform in bones:
		b = arm.edit_bones.new(n)
		b.head = Vector(h)
		b.tail = Vector(t)
		b.roll = 0.0
		b.use_deform = deform
		if par:
			b.parent = eb[par]
			b.use_connect = False
		eb[n] = b
	bpy.ops.object.mode_set(mode='OBJECT')
	return ao


def auto_weights(body, arm):
	bpy.ops.object.select_all(action='DESELECT')
	body.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.parent_set(type='ARMATURE_AUTO')


def parent_groups(obj, arm):
	"""Parent with existing vertex groups (rigid parts)."""
	bpy.ops.object.select_all(action='DESELECT')
	obj.select_set(True)
	arm.select_set(True)
	bpy.context.view_layer.objects.active = arm
	bpy.ops.object.parent_set(type='ARMATURE_NAME')


class Anim:
	"""Keys pose-bone euler rotations (degrees, bone-local) and the root bone's location."""

	def __init__(self, arm):
		self.arm = arm
		for pb in arm.pose.bones:
			pb.rotation_mode = 'XYZ'

	def action(self, name, frames):
		act = bpy.data.actions.new(name)
		self.arm.animation_data_create()
		self.arm.animation_data.action = act
		self.cur = act
		self.frames = frames
		for pb in self.arm.pose.bones:
			pb.rotation_euler = (0, 0, 0)
			pb.location = (0, 0, 0)
			pb.scale = (1, 1, 1)
		return act

	def key(self, frame, rots, locs=None, scales=None):
		for pb in self.arm.pose.bones:
			r = rots.get(pb.name, (0, 0, 0))
			pb.rotation_euler = [math.radians(a) for a in r]
			pb.keyframe_insert("rotation_euler", frame=frame)
			l = (locs or {}).get(pb.name, (0, 0, 0))
			pb.location = l
			pb.keyframe_insert("location", frame=frame)
			s = (scales or {}).get(pb.name, (1, 1, 1))
			pb.scale = s
			pb.keyframe_insert("scale", frame=frame)

	def done(self):
		self.cur.use_fake_user = True
		tr = self.arm.animation_data.nla_tracks.new()
		tr.name = self.cur.name
		tr.strips.new(self.cur.name, 1, self.cur)
		self.arm.animation_data.action = None


def export(path):
	bpy.ops.object.select_all(action='SELECT')
	bpy.ops.export_scene.gltf(filepath=path, export_format='GLB', export_animations=True,
		export_animation_mode='ACTIONS', export_colors=True, export_skins=True, export_apply=False,
		export_yup=True, export_force_sampling=True, export_def_bones=True, export_optimize_animation_size=False)


def preview(path, cam_loc, target, res=(480, 360), samples=12):
	sc = bpy.context.scene
	sc.render.engine = 'CYCLES'
	sc.cycles.samples = samples
	sc.cycles.use_denoising = False
	sc.cycles.device = 'CPU'
	sc.render.resolution_x, sc.render.resolution_y = res
	sc.render.film_transparent = False
	if sc.world is None:
		sc.world = bpy.data.worlds.new("w")
	sc.world.use_nodes = True
	sc.world.node_tree.nodes["Background"].inputs[0].default_value = (0.6, 0.68, 0.78, 1)
	sc.world.node_tree.nodes["Background"].inputs[1].default_value = 0.8
	cam = bpy.data.objects.get("PrevCam")
	if cam is None:
		cam = link(bpy.data.objects.new("PrevCam", bpy.data.cameras.new("PrevCam")))
		sun = link(bpy.data.objects.new("PrevSun", bpy.data.lights.new("PrevSun", 'SUN')))
		sun.data.energy = 3.0
		sun.rotation_euler = (math.radians(50), 0, math.radians(30))
	cam.location = Vector(cam_loc)
	d = Vector(target) - cam.location
	cam.rotation_euler = d.to_track_quat('-Z', 'Y').to_euler()
	cam.data.lens = 60
	sc.camera = cam
	sc.render.filepath = path
	bpy.ops.render.render(write_still=True)
