extends GutTest
## Unit tests for scripts/walker/two_bone_ik.gd: one behaviour per test, the name states the rule.

const TOL: float = 0.001
const HIP := Vector3(0.3, 1.0, -0.2)
const POLE := Vector3(1.0, 1.0, 0.0)


func test_reachable_targets_are_hit_within_1_mm() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var splits: Array[Vector2] = [Vector2(0.4, 0.2), Vector2(0.7, 0.3), Vector2(0.9, 0.7)]
	for split in splits:
		var upper: float = split.x
		var lower: float = split.y
		var reach: float = upper + lower
		var min_d: float = absf(upper - lower) + 0.01 * reach
		for n in 1000:
			var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
			dir = dir.normalized()
			var d: float = rng.randf_range(min_d + 0.001, 0.99 * reach - 0.001)
			var target: Vector3 = HIP + dir * d
			var sol := TwoBoneIK.solve(HIP, target, upper, lower, POLE)
			assert_true(sol.reached)
			assert_lt(sol.foot.distance_to(target), TOL)
			if sol.foot.distance_to(target) >= TOL or not sol.reached:
				return


func test_bone_lengths_are_kept_within_1_mm() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for n in 500:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var target: Vector3 = HIP + dir.normalized() * rng.randf_range(0.0, 2.0)
		var sol := TwoBoneIK.solve(HIP, target, 0.7, 0.3, POLE)
		var err_u: float = absf(sol.knee.distance_to(HIP) - 0.7)
		var err_l: float = absf(sol.knee.distance_to(sol.foot) - 0.3)
		assert_lt(err_u, TOL)
		assert_lt(err_l, TOL)
		if err_u >= TOL or err_l >= TOL:
			return


func test_knee_bends_toward_the_pole() -> void:
	var sol := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -0.6, 0), 0.5, 0.5, Vector3(1, 0, 0))
	assert_gt(sol.knee.x, 0.1)
	var sol2 := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -0.6, 0), 0.5, 0.5, Vector3(-1, 0, 0))
	assert_lt(sol2.knee.x, -0.1)
	assert_almost_eq(sol.knee.z, 0.0, TOL)


func test_target_beyond_reach_clamps_the_foot_to_99_percent() -> void:
	var sol := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, 0, 5), 0.6, 0.4, POLE)
	assert_false(sol.reached)
	assert_almost_eq(sol.foot.length(), 0.99, TOL)
	assert_almost_eq(sol.foot.normalized().z, 1.0, 0.0001)


func test_target_too_close_clamps_to_the_minimum_distance() -> void:
	var sol := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -0.01, 0), 0.7, 0.3, POLE)
	assert_false(sol.reached)
	assert_almost_eq(sol.foot.length(), 0.4 + 0.01, TOL)
	assert_lt(sol.foot.y, 0.0)


func test_pole_parallel_to_the_leg_gives_a_finite_knee() -> void:
	var poles: Array[Vector3] = [Vector3(0, -1, 0), Vector3(0, 1, 0), Vector3.ZERO]
	for pole in poles:
		var sol := TwoBoneIK.solve(Vector3.ZERO, Vector3(0, -0.8, 0), 0.5, 0.5, pole)
		assert_true(sol.knee.is_finite())
		assert_almost_eq(sol.knee.length(), 0.5, TOL)


func test_zero_length_bones_give_finite_results() -> void:
	var both := TwoBoneIK.solve(HIP, Vector3(1, 0, 0), 0.0, 0.0, POLE)
	assert_true(both.knee.is_finite())
	assert_true(both.foot.is_finite())
	var cases: Array[Vector2] = [Vector2(0.0, 1.0), Vector2(1.0, 0.0)]
	for bones in cases:
		var sol := TwoBoneIK.solve(HIP, Vector3(1, 0, 0), bones.x, bones.y, POLE)
		assert_true(sol.knee.is_finite())
		assert_true(sol.foot.is_finite())
		assert_lte(sol.foot.distance_to(HIP), 0.99 + TOL)


func test_target_on_the_hip_gives_finite_results() -> void:
	var sol := TwoBoneIK.solve(HIP, HIP, 0.5, 0.5, POLE)
	assert_true(sol.knee.is_finite())
	assert_true(sol.foot.is_finite())
	assert_false(sol.reached)
	assert_lt(sol.foot.y, HIP.y)
