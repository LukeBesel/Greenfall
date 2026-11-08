extends GutTest
## [v3clear] Owner item 41: Verdance clarity pass (bin in its bay, situation hints, plain texts).


func test_bin_body_stands_on_its_bay_anchor() -> void:
	# The start yard's depot anchor and the "bin" anchor the marked bay is drawn round
	# (planet/sites/verdance_site.gd START_YARD_ANCHORS): the bin body must stand on the latter.
	var root := Node3D.new()
	add_child_autofree(root)
	var sp := SitePrefab.new()
	root.add_child(sp)
	var dep_a: Array = VerdanceSite.START_YARD_ANCHORS["depot"]
	var bin_a: Array = VerdanceSite.START_YARD_ANCHORS["bin"]
	sp.set_anchor("depot", dep_a[0], dep_a[1])
	sp.set_anchor("bin", bin_a[0], bin_a[1])
	var d := Depot.new()
	root.add_child(d)
	d.transform = sp.anchor_local("depot")
	var before: float = d.bin_world().distance_to(bin_a[0])
	d.seat_bin(sp)
	assert_gt(before, 3.0, "the old chute stood ~4.3 m off its anchor")
	assert_lt(d.bin_world().distance_to(bin_a[0]), 0.05, "the bin body stands on the bin anchor")
	assert_lt(d.mouth_world().distance_to(bin_a[0]), 2.0, "its mouth is right above it")
