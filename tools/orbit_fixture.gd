extends Node
## [orbB] Writes tests/fixtures/flat_v<N>_oldtown.save: a flat Old Town game a little way in
## (three hexes cleaned by hand, base level 2, a part in the chest) in SaveManager's format, for
## the old-save migration tests (tests/test_orbit_migrate.gd).
## Run: godot --headless --path . res://tools/orbit_fixture.tscn -- --fresh

const OUT := "res://tests/fixtures/flat_v%d_oldtown.save"


func _ready() -> void:
	var tree: SceneTree = get_tree()
	await tree.process_frame
	var s: Node = (load("res://scenes/slice.tscn") as PackedScene).instantiate()
	tree.root.add_child(s)
	for i: int in 5:
		await tree.process_frame
	var f: HexField = s.get("field")
	var cleaned: int = 0
	for h: int in f.hex_count():
		if cleaned >= 3:
			break
		if f.hex_hub[h] != 0 or f.is_water(h) or f.is_clean(h):
			continue
		for pid: int in f.hex_pieces[h]:
			if f.piece_alive[pid] == 1:
				s.collect_piece(pid)
		cleaned += 1
	# A half-scooped fourth hex.
	for h: int in f.hex_count():
		if f.hex_hub[h] == 0 and not f.is_water(h) and not f.is_clean(h):
			var pids: PackedInt32Array = f.hex_pieces[h]
			for k: int in pids.size() >> 1:
				if f.piece_alive[pids[k]] == 1:
					s.collect_piece(pids[k])
			break
	GameState.add_currency("cubes", BigNum.from_float(777))
	(s.get("patch") as Patch).compartment.fill = 2.5
	tree.get_nodes_in_group("persist").map(func(n: Node) -> void: n.call("persist_save"))
	GameState.world["hub_level"] = 2  # after the systems wrote theirs
	var path: String = OUT % GameState.SAVE_VERSION
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path).get_base_dir())
	var ok: bool = SaveManager.write_dict(ProjectSettings.globalize_path(path), GameState.to_dict())
	print("[fixture] %s %s: cleaned=%d field.cleaned=%d" % [path, "written" if ok else "FAILED", cleaned, f.cleaned_count])
	tree.quit(0 if ok else 1)
