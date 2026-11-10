# Parked with the Telescope (M1-08). This was a static function of YardArt (systems/camp/yard_art.gd):
# paste it back into that class to restore the observatory's dressing (telescope.gd).

# --- Observatory annex (automation/telescope.gd; the dome itself is kitified) -------------------------

## Kit dressing round the observatory (model-local: door at +Z): entrance steps with a hazard nose,
## a utility box with LEDs and a pipe into the drum, a little dish, crates.
static func observatory_dress() -> Kit:
	var k := Kit.new()
	k.box(Vector3(1.3, 0.1, 0.6), Vector3(0, 0.05, 2.45), Color.WHITE, Vector3.ZERO, 0.03, "concrete")
	k.hazard(Vector3(1.3, 0.04, 0.08), Vector3(0, 0.11, 2.72))
	for x: float in [-0.75, 0.75]:
		k.box(Vector3(0.12, 0.7, 0.12), Vector3(x, 0.35, 2.4), TEAL)
		k.glow_box(Vector3(0.06, 0.06, 0.02), Vector3(x, 0.66, 2.465), WARM)
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(-55.0)), Vector3.ZERO))
	k.box(Vector3(0.6, 0.9, 0.5), Vector3(0, 0.45, 2.1), CREAM, Vector3.ZERO, 0.04)
	k.box(Vector3(0.66, 0.06, 0.56), Vector3(0, 0.92, 2.1), TEAL, Vector3.ZERO, 0.02)
	k.vent(0.36, 0.24, Vector3(0, 0.4, 2.355), CREAM.darkened(0.15), Vector3.ZERO, 3)
	k.decal("power", Vector2(0.12, 0.12), Vector3(0.18, 0.72, 2.355))
	for i: int in 3:
		k.glow_box(Vector3(0.03, 0.03, 0.02), Vector3(-0.15 + i * 0.06, 0.74, 2.36), [MINT, CYAN, MINT][i])
	k.pipe(Vector3(0, 0.95, 2.0), Vector3(0, 1.2, 1.75), 0.04, GUNMETAL, true)
	k.pop()
	k.push(Transform3D(Basis(Vector3.UP, deg_to_rad(130.0)), Vector3.ZERO))
	k.box(Vector3(0.5, 0.4, 0.5), Vector3(0, 0.2, 2.2), ORANGE)
	k.box(Vector3(0.4, 0.34, 0.4), Vector3(0.05, 0.57, 2.18), CREAM, Vector3(0, 15, 0))
	k.cyl(0.24, 0.7, Vector3(0.7, 0.35, 2.0), BLUE)
	k.pop()
	return k

