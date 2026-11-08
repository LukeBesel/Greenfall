class_name SphereMapMesh
extends RefCounted
## [orbE] Maps of a round planet built from its far shell (planet/sphere/sphere_shell.gd), which
## aggregates SphereCells into big hexes (level 5 ~16 fine hexes each, same cell ids underneath):
## the survey hologram (ui/globe_view.gd) and the PlanetGlobe overlay (ui/planet_globe.gd) colour
## each big hex by its shares of junk, cleaned, greened and water. A 163,842-hex globe as one
## mesh per fine hex was ~1M triangles and seconds of GDScript; the big hexes are 61k triangles.

## Shares of a big hex: r = junk left, g = cleaned, b = green, a = water (they sum to 1).
static func shares(img: Image, c: int) -> Color:
	@warning_ignore("integer_division")
	return img.get_pixel(c % SphereShell.TEX_W, c / SphereShell.TEX_W)


## A copy of the shell's share image (a survey snapshot).
static func snapshot(shell: SphereShell) -> Image:
	return (shell.get("_img_a") as Image).duplicate() as Image


## Survey colour of a big hex from its shares (colour-blind palette aware via UITheme).
static func survey_color(s: Color) -> Color:
	var junk: Color = UITheme.globe_state_color(PlanetData.State.JUNK, GlobeView.COLORS[PlanetData.State.JUNK])
	var clean: Color = UITheme.globe_state_color(PlanetData.State.CLEAN, GlobeView.COLORS[PlanetData.State.CLEAN])
	var green: Color = UITheme.globe_state_color(PlanetData.State.RESTORED, GlobeView.COLORS[PlanetData.State.RESTORED])
	var water: Color = UITheme.globe_state_color(PlanetData.State.WATER, GlobeView.COLORS[PlanetData.State.WATER])
	var land: float = maxf(s.r + s.g + s.b, 0.0001)
	var c: Color = junk.darkened(0.25) * (s.r / land) + clean * (s.g / land) + green * (s.b / land)
	return water.lerp(c, smoothstep(0.35, 0.65, 1.0 - s.a))


## One flat-shaded polygon per big hex, shrunk a little so the grid reads, at radius `lift`.
## col_fn(c: int) -> Color gives each big hex its colour (alpha kept for overlays).
static func build(coarse: SphereGrid, col_fn: Callable, lift: float = 1.004, shrink: float = 0.9) -> ArrayMesh:
	var n: int = coarse.cell_count()
	var verts := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(n * 18)
	cols.resize(n * 18)
	var o: int = 0
	for c: int in n:
		var col: Color = col_fn.call(c)
		var edge: Color = Color(col.r * 0.75, col.g * 0.75, col.b * 0.75, col.a)
		var ctr: Vector3 = coarse.centers[c] * lift
		var cs: PackedVector3Array = coarse.corners(c)
		var k: int = cs.size()
		for j: int in k:
			verts[o] = ctr
			verts[o + 1] = ctr.lerp(cs[(j + 1) % k] * lift, shrink)
			verts[o + 2] = ctr.lerp(cs[j] * lift, shrink)
			cols[o] = col
			cols[o + 1] = edge
			cols[o + 2] = edge
			o += 3
	verts.resize(o)
	cols.resize(o)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = verts
	arrays[Mesh.ARRAY_COLOR] = cols
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m
