extends RefCounted
## The dummy test planet's sites script (PlanetDefinition.sites_script): one bare hub site, a
## marker block on the pad. Only tests load it.

const MARKER: String = "TestPadMarker"


## Sites-script hook (SiteBuilders): builds `site_id` under `parent` in site-local metres.
static func build(parent: Node3D, site_id: String, _stage: int, _restoration: float) -> Node3D:
	var marker := MeshInstance3D.new()
	marker.name = MARKER
	var box := BoxMesh.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	marker.mesh = box
	marker.position = Vector3(20.0, 1.0, 20.0)
	marker.set_meta("site_id", site_id)
	parent.add_child(marker)
	return marker
