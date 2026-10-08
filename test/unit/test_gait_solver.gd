extends GutTest
## Unit tests for scripts/walker/gait_solver.gd: one behaviour per test, the name states the rule.

const DT: float = 1.0 / 60.0
const PLANTED: int = GaitSolver.LegState.PLANTED
const SWINGING: int = GaitSolver.LegState.SWINGING
const HOVERING: int = GaitSolver.LegState.HOVERING


## A tiny fake walker: planted feet drift away at `speed` m/s, a foot error resets when it plants.
class FakeWalker:
	extends RefCounted
	var solver: GaitSolver
	var errors: PackedFloat32Array = PackedFloat32Array()
	var valid: Array[bool] = []
	var speed: float = 3.0
	var started: PackedInt32Array = PackedInt32Array()
	var planted: PackedInt32Array = PackedInt32Array()
	var max_airborne: int = 0

	func _init(leg_count: int) -> void:
		solver = GaitSolver.new(sides_for(leg_count), _reaches(leg_count))
		errors.resize(leg_count)
		started.resize(leg_count)
		planted.resize(leg_count)
		for i in leg_count:
			valid.append(true)
		solver.step_started.connect(_on_started)
		solver.foot_planted.connect(_on_planted)

	func tick(moving: bool, speed_ratio: float) -> void:
		for i in solver.leg_count():
			if solver.state_of(i) == GaitSolver.LegState.PLANTED:
				errors[i] += speed * DT
		solver.update(DT, moving, speed_ratio, errors, valid)
		max_airborne = maxi(max_airborne, solver.airborne_count())

	static func sides_for(n: int) -> PackedInt32Array:
		var s := PackedInt32Array()
		for i in n:
			s.append(-1 if i < n / 2 else 1)
		return s

	func _reaches(n: int) -> PackedFloat32Array:
		var r := PackedFloat32Array()
		for i in n:
			r.append(1.0)
		return r

	func _on_started(leg: int) -> void:
		started[leg] += 1

	func _on_planted(leg: int) -> void:
		planted[leg] += 1
		errors[leg] = 0.0


func _walker(n: int) -> FakeWalker:
	return FakeWalker.new(n)


func _valid(n: int) -> Array[bool]:
	var v: Array[bool] = []
	for i in n:
		v.append(true)
	return v


func _swinging_legs(w: FakeWalker) -> Array[int]:
	var out: Array[int] = []
	for i in w.solver.leg_count():
		if w.solver.state_of(i) == SWINGING:
			out.append(i)
	return out


func _run_walk(leg_count: int, speed_ratio: float, seed_value: int, invalid_chance: float) -> FakeWalker:
	var w := _walker(leg_count)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for t in 1200:
		for i in leg_count:
			w.valid[i] = rng.randf() >= invalid_chance
		w.tick(true, speed_ratio)
	return w


func test_six_legs_form_two_alternating_tripods() -> void:
	var s := _walker(6).solver
	assert_eq(s.group_count(), 2)
	var groups: Array[int] = []
	for i in 6:
		groups.append(s.group_of(i))
	# L0 L1 L2 R0 R1 R2
	assert_eq(groups, [0, 1, 0, 1, 0, 1] as Array[int])


func test_eight_legs_form_two_groups_of_four() -> void:
	var s := _walker(8).solver
	var groups: Array[int] = []
	for i in 8:
		groups.append(s.group_of(i))
	assert_eq(groups, [0, 1, 0, 1, 1, 0, 1, 0] as Array[int])


func test_four_legs_use_a_wave_gait_rear_to_front_left_then_right() -> void:
	var s := _walker(4).solver
	assert_eq(s.group_count(), 4)
	# Order L1, L0, R1, R0 = legs 1, 0, 3, 2.
	assert_eq(s.group_of(1), 0)
	assert_eq(s.group_of(0), 1)
	assert_eq(s.group_of(3), 2)
	assert_eq(s.group_of(2), 3)


func test_gait_limit_is_half_the_legs_for_tripod_and_one_for_wave() -> void:
	assert_eq(_walker(4).solver.gait_limit(), 1)
	assert_eq(_walker(5).solver.gait_limit(), 1)
	assert_eq(_walker(6).solver.gait_limit(), 3)
	assert_eq(_walker(8).solver.gait_limit(), 4)


func test_fewer_than_four_legs_do_not_crash() -> void:
	var w := _walker(2)
	w.tick(true, 1.0)
	assert_eq(w.solver.gait_limit(), 1)
	assert_eq(_swinging_legs(w).size(), 1)


func test_leg_does_not_step_below_the_trigger() -> void:
	var w := _walker(6)
	w.errors[0] = 0.49
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), PLANTED)


func test_leg_steps_above_the_trigger_when_its_group_is_active() -> void:
	var w := _walker(6)
	w.errors[0] = 0.51
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), SWINGING)


func test_leg_waits_while_its_group_is_inactive() -> void:
	var w := _walker(6)
	w.errors[0] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	w.errors[1] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), SWINGING)
	assert_eq(w.solver.state_of(1), PLANTED)


func test_next_group_lifts_on_the_tick_the_active_group_plants() -> void:
	var w := _walker(6)
	w.tick(true, 1.0)
	assert_eq(_swinging_legs(w), [0, 2, 4] as Array[int])
	for i in [1, 3, 5]:
		w.errors[i] = 0.6
	for k in 10:
		w.solver.update(DT, true, 1.0, w.errors, w.valid)
		assert_eq(_swinging_legs(w), [0, 2, 4] as Array[int], "update %d" % k)
	w.solver.update(DT, true, 1.0, w.errors, w.valid)
	assert_eq(_swinging_legs(w), [1, 3, 5] as Array[int])


func test_next_group_gets_the_turn_at_85_percent_and_lifts_into_free_slots() -> void:
	var w := _walker(6)
	w.errors[0] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	for i in [1, 3, 5]:
		w.errors[i] = 0.6
	for k in 9:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
		assert_eq(_swinging_legs(w), [0] as Array[int], "update %d" % k)
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_gt(w.solver.swing_progress(0), 0.85)
	assert_eq(w.solver.state_of(0), SWINGING)
	assert_eq(_swinging_legs(w).size(), 3)
	assert_eq(w.solver.airborne_count(), 3)


func _assert_airborne_limit(leg_count: int) -> void:
	for ratio in [0.2, 1.0]:
		var w := _run_walk(leg_count, ratio, 4321, 0.05)
		assert_lte(w.max_airborne, w.solver.gait_limit(), "%d legs at %s" % [leg_count, ratio])
		assert_gt(w.max_airborne, 0)


func test_airborne_never_exceeds_the_limit_over_20_s_with_4_legs() -> void:
	_assert_airborne_limit(4)


func test_airborne_never_exceeds_the_limit_over_20_s_with_6_legs() -> void:
	_assert_airborne_limit(6)


func test_airborne_never_exceeds_the_limit_over_20_s_with_8_legs() -> void:
	_assert_airborne_limit(8)


func test_every_leg_steps_at_least_10_times_in_a_20_s_walk() -> void:
	for n in [4, 6, 8]:
		var w := _run_walk(n, 1.0, 7, 0.0)
		for i in n:
			assert_gte(w.started[i], 10, "leg %d of %d" % [i, n])


func test_first_group_lifts_on_the_first_moving_tick() -> void:
	var tripod := _walker(6)
	tripod.solver.update(DT, true, 0.0, tripod.errors, tripod.valid)
	assert_eq(_swinging_legs(tripod).size(), 3)
	var wave := _walker(4)
	wave.solver.update(DT, true, 0.0, wave.errors, wave.valid)
	assert_eq(_swinging_legs(wave), [1] as Array[int])


func test_step_duration_is_0_30_at_idle_and_0_18_at_top_speed() -> void:
	var s := _walker(6).solver
	assert_almost_eq(s.step_duration(0.0), 0.30, 0.0001)
	assert_almost_eq(s.step_duration(1.0), 0.18, 0.0001)
	assert_almost_eq(s.step_duration(0.5), 0.24, 0.0001)


func test_swing_plants_after_one_step_duration() -> void:
	var w := _walker(4)
	w.solver.update(DT, true, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(1), SWINGING)
	for k in 10:
		w.solver.update(DT, true, 1.0, w.errors, w.valid)
		assert_eq(w.solver.state_of(1), SWINGING, "update %d" % (k + 1))
	w.solver.update(DT, true, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(1), PLANTED)


func test_foot_planted_fires_once_per_step() -> void:
	var w := _walker(4)
	w.errors[1] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	w.errors[1] = 0.0
	for k in 40:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.planted[1], 1)


func test_step_started_fires_once_per_step() -> void:
	var w := _walker(4)
	w.errors[1] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	w.errors[1] = 0.0
	for k in 40:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.started[1], 1)


func test_swing_point_starts_at_from_ends_at_to_and_peaks_at_lift() -> void:
	var from := Vector3(1, 0, 2)
	var to := Vector3(3, 0, 4)
	assert_eq(GaitSolver.swing_point(from, to, 0.0, 0.25), from)
	assert_true(GaitSolver.swing_point(from, to, 1.0, 0.25).is_equal_approx(to))
	var mid: Vector3 = GaitSolver.swing_point(from, to, 0.5, 0.25)
	assert_true(mid.is_equal_approx((from + to) * 0.5 + Vector3.UP * 0.25))


func test_target_lead_is_velocity_times_half_the_step_duration() -> void:
	var lead: Vector3 = GaitSolver.target_lead(Vector3(2, 0, -4), 0.2)
	assert_true(lead.is_equal_approx(Vector3(0.2, 0, -0.4)))


func test_rise_above_step_up_is_invalid() -> void:
	var step_up: float = 0.6 * 1.0
	assert_false(GaitSolver.is_target_valid(0.61, Vector3.UP, step_up, 35.0))
	assert_true(GaitSolver.is_target_valid(0.59, Vector3.UP, step_up, 35.0))


func test_surface_steeper_than_max_slope_is_invalid() -> void:
	var steep := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(36.0))
	var gentle := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(34.0))
	assert_false(GaitSolver.is_target_valid(0.0, steep, 0.6, 35.0))
	assert_true(GaitSolver.is_target_valid(0.0, gentle, 0.6, 35.0))


func test_blocked_leg_stays_planted_and_reports_blocked() -> void:
	var w := _walker(6)
	w.errors[0] = 0.6
	w.valid[0] = false
	for k in 5:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), PLANTED)
	assert_true(w.solver.is_blocked(0))
	assert_false(w.solver.is_blocked(1))


func _hover_leg_zero(w: FakeWalker) -> void:
	w.errors[0] = 0.6
	w.valid[0] = false
	for k in 40:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)


func test_blocked_leg_hovers_after_0_5_s_and_counts_as_airborne() -> void:
	var w := _walker(6)
	w.errors[0] = 0.6
	w.valid[0] = false
	for k in 29:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), PLANTED)
	for k in 3:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), HOVERING)
	assert_eq(w.solver.airborne_count(), 1)


func test_hovering_leg_steps_when_its_target_turns_valid() -> void:
	var w := _walker(6)
	_hover_leg_zero(w)
	assert_eq(w.solver.state_of(0), HOVERING)
	w.valid[0] = true
	w.errors[0] = 0.0
	for k in 2:
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(0), SWINGING)


func test_hovering_leg_does_not_hold_the_turn() -> void:
	var w := _walker(6)
	_hover_leg_zero(w)
	assert_eq(w.solver.state_of(0), HOVERING)
	for k in 3:
		if w.solver.active_group() == 0:
			break
		w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.active_group(), 0)
	w.errors[1] = 0.6
	w.solver.update(DT, false, 1.0, w.errors, w.valid)
	assert_eq(w.solver.state_of(1), SWINGING)


func test_reset_plants_every_leg() -> void:
	var w := _walker(6)
	w.solver.update(DT, true, 1.0, w.errors, w.valid)
	assert_gt(w.solver.airborne_count(), 0)
	w.solver.reset()
	assert_eq(w.solver.airborne_count(), 0)
	assert_eq(w.solver.active_group(), 0)
	for i in 6:
		assert_eq(w.solver.state_of(i), PLANTED)
		assert_eq(w.solver.swing_progress(i), 0.0)
