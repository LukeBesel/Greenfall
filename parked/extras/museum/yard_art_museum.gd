# Parked with the Museum building (M1-08). This was a static function of YardArt (systems/camp/yard_art.gd):
# paste it back into that class to restore the Museum hall's dressing (museum.gd).

# --- Museum hall (systems/museum.gd; the hall's own boxes are kitified) -------------------------------

## Kit dressing for the 14 x 9 m pavilion (hall-local: front edge at z 0, back wall at z -9):
## entrance steps, column bases and capitals, a teal roof fascia with skylights and vents, wall
## pilasters, logo banners, planters and lamp posts at the front.
static func museum_dress(w: float = 14.0, d: float = 9.0) -> Kit:
	var k := Kit.new()
	for i: int in 2:
		k.box(Vector3(5.0 - i * 0.6, 0.12, 0.5), Vector3(0, 0.06 + i * 0.12, 0.45 - i * 0.25), Color.WHITE, Vector3.ZERO, 0.03, "concrete")
	k.hazard(Vector3(5.0, 0.03, 0.06), Vector3(0, 0.13, 0.68))
	for s: float in [-1.0, 1.0]:
		var cx: float = s * (w * 0.5 - 0.3)
		k.cyl(0.27, 0.22, Vector3(cx, 0.36, -0.3), TEAL, Vector3.ZERO, 0.04, 16)
		k.cyl(0.27, 0.16, Vector3(cx, 3.37, -0.3), TEAL, Vector3.ZERO, 0.04, 16)
		k.cyl(0.18, 0.05, Vector3(cx, 2.6, -0.3), ORANGE, Vector3.ZERO, 0.012, 14)
		k.glow_box(Vector3(0.05, 0.4, 0.02), Vector3(cx, 1.8, -0.14), WARM)
	# Roof fascia, skylights and vents.
	for z: float in [0.42, -d - 0.42]:
		k.box(Vector3(w + 0.9, 0.26, 0.08), Vector3(0, 3.55, z), TEAL, Vector3.ZERO, 0.025)
	for x: float in [-(w * 0.5 + 0.42), w * 0.5 + 0.42]:
		k.box(Vector3(0.08, 0.26, d + 0.9), Vector3(x, 3.55, -d * 0.5), TEAL, Vector3.ZERO, 0.025)
	for x: float in [-4.0, 0.0, 4.0]:
		k.box(Vector3(2.4, 0.16, 1.4), Vector3(x, 3.74, -d * 0.5), GUNMETAL, Vector3.ZERO, 0.03)
		k.box(Vector3(2.2, 0.06, 1.2), Vector3(x, 3.84, -d * 0.5), Color.WHITE, Vector3.ZERO, 0.01, "glass")
	for x: float in [-6.0, 6.0]:
		k.vent(0.7, 0.4, Vector3(x, 3.86, -d + 1.0), GUNMETAL, Vector3(-90, 0, 0), 4)
	# Pilasters and banners on the back wall's inner face.
	for i: int in 7:
		var x: float = -w * 0.5 + 1.0 + i * (w - 2.0) / 6.0
		k.box(Vector3(0.24, 3.1, 0.08), Vector3(x, 1.8, -d + 0.34), CREAM.darkened(0.04), Vector3.ZERO, 0.03)
	for x: float in [-4.6, 4.6]:
		k.box(Vector3(1.4, 0.06, 0.06), Vector3(x, 3.0, -d + 0.4), GUNMETAL, Vector3.ZERO, 0.015)
		k.box(Vector3(1.2, 1.7, 0.02), Vector3(x, 2.1, -d + 0.4), TEAL, Vector3.ZERO, 0.006)
		k.decal("logo", Vector2(0.9, 0.9), Vector3(x, 2.25, -d + 0.42))
	# Front: planters with bushes and two lamp posts.
	for s: float in [-1.0, 1.0]:
		KitProps.planter(k.b, k._t(ProcMesh.xf(Vector3(s * 4.2, 0.0, 1.2))), 2.2, "restored")
		KitProps.lamp_post(k.b, k._t(ProcMesh.xf(Vector3(s * 7.4, 0.0, 1.0))), 3.6, "restored")
	return k

