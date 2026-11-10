extends GutTest
## Parked with the Seed Ark loop (M1-08). This test was part of tests/test_bloom.gd (its before_each /
## after_each apply); the functions it calls are in parked/prestige/bloom_seed_ark.gd.

func test_seed_ark_locked_until_bloom_then_endless_waves() -> void:
	GameState.stats["plants_bloomed"] = 500.0
	assert_false(Bloom.ark_unlocked())
	assert_eq(Bloom.ark_step(), 0)
	assert_eq(Bloom.globe_line(), "")
	Bloom.done_list().append("verdance_bloom")
	assert_true(Bloom.ark_unlocked())
	# Counting starts when the Ark opens: old blooms don't count.
	assert_eq(Bloom.ark_progress(), 0)
	assert_string_contains(Bloom.globe_line(), "Seed Ark wave 1")
	var t0: int = Bloom.ark_target(0)
	var t1: int = Bloom.ark_target(1)
	assert_gt(t1, t0, "waves grow")
	GameState.stats["plants_bloomed"] = 500.0 + t0 - 1
	assert_eq(Bloom.ark_step(), 0)
	GameState.stats["plants_bloomed"] = 500.0 + t0 + t1 + 3
	assert_eq(Bloom.ark_step(), 2, "a big catch-up finishes several waves")
	assert_eq(int(Bloom.ark_state()["wave"]), 2)
	assert_eq(Bloom.ark_progress(), 3)
	assert_almost_eq(float(GameState.stats.get("ark_waves", 0.0)), 2.0, 0.001)
	assert_gt(GameState.get_currency("seeds").to_float(), 0.0)
	assert_string_contains(Bloom.globe_line(), "wave 3")

