extends Node
## [biomes] Prints the size of each frontier district next to an ordinary one (docs/BALANCE.md):
## hexes, pieces, junk volume, bale-equivalent value at the scale, and hub level costs.
## Run: godot --headless --path . res://tools/frontier_balance.tscn


func _ready() -> void:
	var cfg: Dictionary = Economy.planet.get("slice_field", {})
	var types: Array = []
	for id: String in Economy.junk_ids:
		types.append(Economy.junk_types[id])
	var rows: Array = [{"id": "old_town", "name": "Ordinary district", "radius": int(cfg.get("radius", 3)), "layout": "city"}]
	rows.append_array(Frontiers.kinds())
	var hub_cubes: float = 0.0
	for l: Dictionary in Economy.read_json("res://data/hub.json").get("levels", []):
		hub_cubes += float(l.get("cost", {}).get("cubes", 0.0))
	print("| District | Hexes (water) | Pieces | Junk volume | Volume x value | Value at scale | Base 1-5 cubes |")
	print("|---|---|---|---|---|---|---|")
	for k: Dictionary in rows:
		var seed_v: int = 4471 + 34 * 1009
		var layout := CityLayout.new(seed_v, 150.0, str(k.get("layout", "wild")) != "city")
		var f := HexField.new(int(k["radius"]), float(cfg.get("hex_size", 10.0)), seed_v, layout)
		f.clean_threshold = float(cfg.get("clean_threshold", 0.97))
		if k.has("biome"):
			f.biome = str(k["biome"])
			f.biome_set = Economy.biome_set(f.biome)
			f.water_ids = Frontiers.water_ids_for(k, int(k["radius"]), f.hex_size)
			f.float_mult = float(k.get("float_mult", 1.0))
		var ppx: Array = cfg.get("pieces_per_hex", [260, 420])
		var pm: float = float(k.get("pieces_mult", 1.0))
		f.generate(types, Vector2i(int(float(ppx[0]) * pm), int(float(ppx[1]) * pm)))
		Frontiers.toughen(f, float(k.get("vol_mult", 1.0)))
		var vol: float = 0.0
		var val: float = 0.0
		for pid: int in f.piece_count():
			vol += f.piece_vol[pid]
			val += f.piece_vol[pid] * float(Economy.junk_types[Economy.junk_ids[f.piece_type[pid]]].get("value", 1.0))
		var water: int = 0
		for h: int in f.hex_count():
			if f.is_water(h):
				water += 1
		var vm: float = float(k.get("value_mult", 1.0))
		print("| %s | %d (%d) | %d | %d | %d | %d | %d |" % [str(k.get("name", k["id"])), f.junk_hex_count, water, f.piece_count(), int(vol), int(val), int(val * vm), int(hub_cubes * float(k.get("cost_mult", 1.0)))])
	get_tree().quit()
