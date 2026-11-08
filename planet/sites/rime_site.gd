class_name RimeSite
extends RimeEnv
## [orbD] Rime's hub site for the walkable globe: RimeEnv's own pieces (frozen Ledger core-drill
## derricks, frozen geysers with their hot-spring pools, greenhouse domes, alpine blooms and
## ice-lanterns) laid out compactly on a flat pad in site-local metres, with no terrain, sky,
## camera or light of its own (the globe has those). Same stage groups as the flat district
## (ruin 1, mid 2-3, up 2-5, future 4-5) and the same warmth-driven restoration.
##   RimeSite.place(parent, site_id, stage, restoration) -> RimeSite
## Sites: "crater_camp" (hub: two derricks, a geyser pair, pools and a dome), "drill_field"
## (landmark: the derrick cluster).

const SITES: Array[String] = ["crater_camp", "drill_field"]
const RADIUS: float = 46.0


static func place(parent: Node3D, p_site: String, stage: int, p_restoration: float, seed_v: int = 9091) -> RimeSite:
	var s := RimeSite.new()
	s.name = "RimeSite_" + p_site
	s.kind = PlanetEnvs.entry("rime")
	parent.add_child(s)
	s._make(p_site if p_site in SITES else SITES[0], seed_v)
	s.set_level(stage, false)
	s.set_restore(p_restoration)
	return s


func _make(p_site: String, seed_v: int) -> void:
	_rng.seed = seed_v
	_r_in = 10.0
	for k: int in 4:
		var nz: FastNoiseLite = _n[k]
		nz.seed = seed_v + 313 * (k + 1)
		nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		nz.frequency = [0.0035, 0.012, 0.0045, 0.006][k]
	for g: String in STAGES:
		var n := Node3D.new()
		n.name = g.capitalize()
		add_child(n)
		_groups[g] = n
	match p_site:
		"drill_field":
			_derricks = [Vector3(-14, -10, 36.0), Vector3(16, -6, 30.0), Vector3(2, 18, 40.0)]
			_geysers = [Vector3(-22, 20, 1.0)]
			_pool_sites = [Vector3(-16, 24, 2.6), Vector3(24, 18, 2.2)]
			_domes = []
		_:
			# Keeps a 14 m clear core for the hub's depot, bench and rocket pad.
			_derricks = [Vector3(-26, -18, 34.0), Vector3(27, -24, 30.0)]
			_geysers = [Vector3(30, 18, 1.0), Vector3(-34, 22, 1.2)]
			_pool_sites = [Vector3(24, 24, 2.8), Vector3(-27, 28, 3.0), Vector3(-6, 32, 2.0), Vector3(36, 2, 2.2)]
			_domes = [Vector3(-30, 2, 8.0)]
	for i: int in _derricks.size():
		_derrick(_derricks[i], i)
	_build_geysers()
	_build_pools()
	_build_blooms()
	if not _domes.is_empty():
		_build_greenhouses()


## The pad is flat: no heightfield, no borehole berm.
func ground_y(_x: float, _z: float) -> float:
	return 0.0


func _hm(_x: float, _z: float) -> Array:
	return [0.0, 0.0, 0.0, 0.0, 0.0]


func _raw_h(_x: float, _z: float) -> Array:
	return [0.0, 0.0, 0.0, 0.0, 0.0]


## No sky, light or hex-level polling of its own: the globe drives set_level / set_restore.
func _process(_delta: float) -> void:
	pass


func _ready() -> void:
	set_process(false)
