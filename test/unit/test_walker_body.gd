extends GutTest
## Unit tests for the pure helpers in scripts/walker/walker_body.gd (no scenes). One behaviour per test.

const DT: float = 1.0 / 60.0
const TOP: float = 4.5


func _plane_points(angle_deg: float, count: int, yaw_deg: float, offset: float) -> PackedVector3Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var normal := Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(angle_deg)).rotated(
		Vector3.UP, deg_to_rad(yaw_deg)
	)
	var points := PackedVector3Array()
	for i in count:
		var x: float = rng.randf_range(-1.5, 1.5)
		var z: float = rng.randf_range(-1.5, 1.5)
		# Height of the plane through (0, offset, 0) with this normal.
		var y: float = offset - (normal.x * x + normal.z * z) / normal.y
		points.append(Vector3(x, y, z))
	return points


func test_plane_fit_recovers_a_20_deg_plane_from_3_4_and_8_points() -> void:
	for count in [3, 4, 8]:
		var points: PackedVector3Array = _plane_points(20.0, count, 33.0, 0.5)
		var plane: Plane = WalkerBody.fit_plane(points)
		var angle: float = rad_to_deg(plane.normal.angle_to(Vector3.UP))
		assert_almost_eq(angle, 20.0, 0.1, "%d points" % count)
		assert_almost_eq(WalkerBody.plane_height(plane, 0.0, 0.0), 0.5, 0.01, "%d points" % count)


func test_plane_fit_of_level_points_is_level() -> void:
	var points := PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1)])
	var plane: Plane = WalkerBody.fit_plane(points)
	assert_almost_eq(plane.normal.y, 1.0, 0.0001)
	assert_almost_eq(WalkerBody.plane_height(plane, 5.0, 5.0), 1.0, 0.0001)


func test_plane_fit_of_collinear_points_does_not_blow_up() -> void:
	var points := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 1, 0), Vector3(2, 2, 0)])
	var plane: Plane = WalkerBody.fit_plane(points)
	assert_true(plane.normal.is_finite())
	assert_almost_eq(plane.normal.length(), 1.0, 0.0001)


func test_velocity_reaches_top_speed_after_15_ticks_at_60_hz() -> void:
	var target := Vector3(0, 0, -TOP)
	var v := Vector3.ZERO
	for i in 14:
		v = WalkerBody.approach_velocity(v, target, TOP, 0.25, 0.2, DT)
	assert_lt(v.length(), TOP - 0.1, "not there after 14 ticks")
	v = WalkerBody.approach_velocity(v, target, TOP, 0.25, 0.2, DT)
	assert_almost_eq(v.length(), TOP, 0.001, "at top speed after 15 ticks")


func test_velocity_stops_after_12_ticks() -> void:
	var v := Vector3(0, 0, -TOP)
	for i in 11:
		v = WalkerBody.approach_velocity(v, Vector3.ZERO, TOP, 0.25, 0.2, DT)
	assert_gt(v.length(), 0.1, "still moving after 11 ticks")
	v = WalkerBody.approach_velocity(v, Vector3.ZERO, TOP, 0.25, 0.2, DT)
	assert_almost_eq(v.length(), 0.0, 0.001, "stopped after 12 ticks")


func test_diagonal_input_never_exceeds_top_speed() -> void:
	var facing := Vector3(0, 0, -1)
	var right := Vector3(1, 0, 0)
	for forward in [-1.0, 0.0, 1.0]:
		for strafe in [-1.0, 0.0, 1.0]:
			var v: Vector3 = WalkerBody.target_velocity(facing, right, forward, strafe, TOP, 0.75)
			assert_lte(v.length(), TOP + 0.0001, "forward %s strafe %s" % [forward, strafe])


func test_strafe_is_0_75_of_top_speed() -> void:
	var v: Vector3 = WalkerBody.target_velocity(Vector3(0, 0, -1), Vector3(1, 0, 0), 0.0, 1.0, TOP, 0.75)
	assert_almost_eq(v.length(), TOP * 0.75, 0.0001)
	assert_almost_eq(v.x, TOP * 0.75, 0.0001)


func test_turn_rate_is_reached_after_6_ticks() -> void:
	var rate: float = 0.0
	for i in 5:
		rate = WalkerBody.approach_yaw_rate(rate, 1.0, 120.0, false, 0.1, 0.6, DT)
	assert_lt(rate, 119.0, "not there after 5 ticks")
	rate = WalkerBody.approach_yaw_rate(rate, 1.0, 120.0, false, 0.1, 0.6, DT)
	assert_almost_eq(rate, 120.0, 0.01, "full rate after 6 ticks")


func test_aim_turns_at_60_percent() -> void:
	var rate: float = 0.0
	for i in 12:
		rate = WalkerBody.approach_yaw_rate(rate, 1.0, 120.0, true, 0.1, 0.6, DT)
	assert_almost_eq(rate, 72.0, 0.01)


func test_easing_is_frame_rate_independent_at_30_60_and_144_hz() -> void:
	var results: Array[float] = []
	for hz in [30, 60, 144]:
		var delta: float = 1.0 / float(hz)
		var value: float = 0.0
		for i in hz:
			value = WalkerBody.ease_toward(value, 1.0, delta, 0.15)
		results.append(value)
	assert_almost_eq(results[0], results[1], 0.01 * results[1], "30 vs 60 Hz")
	assert_almost_eq(results[2], results[1], 0.01 * results[1], "144 vs 60 Hz")


func test_tilt_is_clamped_to_25_deg() -> void:
	var steep: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(40.0))
	var clamped: Vector3 = WalkerBody.clamp_tilt(steep, 25.0)
	assert_almost_eq(rad_to_deg(clamped.angle_to(Vector3.UP)), 25.0, 0.01)
	assert_almost_eq(clamped.length(), 1.0, 0.0001)
	var gentle: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(10.0))
	assert_almost_eq(rad_to_deg(WalkerBody.clamp_tilt(gentle, 25.0).angle_to(Vector3.UP)), 10.0, 0.01)


## Two hips, one foot planted straight below each, 1 m reach.
func _two_leg_rig() -> Dictionary:
	var hips := PackedVector3Array([Vector3(-0.5, 0.0, 0.0), Vector3(0.5, 0.0, 0.0)])
	var feet := PackedVector3Array([Vector3(-0.5, -0.6, 0.0), Vector3(0.5, -0.6, 0.0)])
	var planted := PackedByteArray([1, 1])
	var limits := PackedFloat32Array([0.99, 0.99])
	return {"hips": hips, "feet": feet, "planted": planted, "limits": limits}


func _worst_distance(rig: Dictionary, origin: Vector3, yaw: float) -> float:
	var t: Transform3D = WalkerBody.pose_transform(origin, yaw, Vector3.UP)
	var worst: float = 0.0
	var hips: PackedVector3Array = rig["hips"]
	var feet: PackedVector3Array = rig["feet"]
	for i in hips.size():
		worst = maxf(worst, (t * hips[i]).distance_to(feet[i]))
	return worst


func test_move_is_shortened_so_every_planted_foot_stays_within_0_99_reach() -> void:
	var rig: Dictionary = _two_leg_rig()
	var current := Vector3(0.0, 0.0, 0.0)
	var desired := Vector3(0.0, 0.0, 2.0)
	var fraction: float = WalkerBody.safe_fraction(
		current, 0.0, Vector3.UP, desired, 0.0, Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	assert_gt(fraction, 0.0)
	assert_lt(fraction, 1.0, "the full step would drag a foot")
	var end: Vector3 = current.lerp(desired, fraction)
	assert_lte(_worst_distance(rig, end, 0.0), 0.99 + 0.0001, "translation stays in reach")
	# Just past the returned fraction a foot would be out of reach: the move is the largest safe one.
	assert_gt(_worst_distance(rig, current.lerp(desired, minf(fraction + 0.02, 1.0)), 0.0), 0.99)


func test_a_step_inside_reach_is_not_shortened() -> void:
	var rig: Dictionary = _two_leg_rig()
	var fraction: float = WalkerBody.safe_fraction(
		Vector3.ZERO, 0.0, Vector3.UP, Vector3(0.0, 0.0, 0.1), 0.0, Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	assert_eq(fraction, 1.0)


func test_a_yaw_that_would_drag_a_foot_is_shortened() -> void:
	var rig: Dictionary = _two_leg_rig()
	# Feet sit 0.5 m to each side of the centre; a big yaw swings the hips around them.
	var wide_feet := PackedVector3Array([Vector3(-0.5, -0.6, 0.6), Vector3(0.5, -0.6, -0.6)])
	rig["feet"] = wide_feet
	var fraction: float = WalkerBody.safe_fraction(
		Vector3.ZERO, 0.0, Vector3.UP, Vector3.ZERO, deg_to_rad(180.0), Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	assert_lt(fraction, 1.0)
	assert_lte(
		_worst_distance(rig, Vector3.ZERO, lerpf(0.0, deg_to_rad(180.0), fraction)), 0.99 + 0.0001
	)


func test_a_foot_that_starts_out_of_reach_may_still_back_off() -> void:
	var rig: Dictionary = _two_leg_rig()
	var far_feet := PackedVector3Array([Vector3(-0.5, -0.6, -1.0), Vector3(0.5, -0.6, -1.0)])
	rig["feet"] = far_feet
	# Both feet are 1.17 m away from the hips; moving toward them must be allowed, moving away must not.
	var toward: float = WalkerBody.safe_fraction(
		Vector3.ZERO, 0.0, Vector3.UP, Vector3(0, 0, -0.3), 0.0, Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	var away: float = WalkerBody.safe_fraction(
		Vector3.ZERO, 0.0, Vector3.UP, Vector3(0, 0, 0.3), 0.0, Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	assert_eq(toward, 1.0)
	assert_lt(away, 0.1)


func test_unplanted_feet_never_hold_the_body() -> void:
	var rig: Dictionary = _two_leg_rig()
	rig["planted"] = PackedByteArray([0, 0])
	var fraction: float = WalkerBody.safe_fraction(
		Vector3.ZERO, 0.0, Vector3.UP, Vector3(0, 0, 5.0), 0.0, Vector3.UP,
		rig["hips"], rig["feet"], rig["planted"], rig["limits"]
	)
	assert_eq(fraction, 1.0)


func test_six_legs_spread_evenly_without_a_gap_at_the_empty_socket() -> void:
	var zs: PackedFloat32Array = WalkerBody.hip_z_positions(3, 0.8)
	assert_eq(zs.size(), 3)
	assert_almost_eq(zs[1] - zs[0], 0.8, 0.0001)
	assert_almost_eq(zs[2] - zs[1], 0.8, 0.0001)
	assert_almost_eq(zs[0] + zs[2], 0.0, 0.0001, "centred on the body")
	assert_lt(zs[0], zs[2], "front (-Z) first")
	var eight: PackedFloat32Array = WalkerBody.hip_z_positions(4, 0.8)
	assert_almost_eq(eight[3] - eight[2], eight[1] - eight[0], 0.0001)


func test_step_times_scale_with_the_square_root_of_mean_leg_reach() -> void:
	# Scout keeps 0.18 / 0.30 s; Strider (1.6 m) about 0.23 / 0.38 s; Crawler (0.6 m) about 0.14 / 0.23 s.
	assert_almost_eq(WalkerBody.scaled_step_time(0.18, 1.0), 0.18, 0.0001)
	assert_almost_eq(WalkerBody.scaled_step_time(0.30, 1.0), 0.30, 0.0001)
	assert_almost_eq(WalkerBody.scaled_step_time(0.18, 1.6), 0.2277, 0.001)
	assert_almost_eq(WalkerBody.scaled_step_time(0.30, 1.6), 0.3795, 0.001)
	assert_almost_eq(WalkerBody.scaled_step_time(0.18, 0.6), 0.1394, 0.001)
	assert_almost_eq(WalkerBody.scaled_step_time(0.30, 0.6), 0.2324, 0.001)


func test_camera_yaw_dead_band_ignores_a_small_nudge() -> void:
	assert_eq(WalkerBody.yaw_turn_input(0.5, 6.0, 1.0), 0.0)
	assert_eq(WalkerBody.yaw_turn_input(-0.99, 6.0, 1.0), 0.0)
	assert_almost_eq(WalkerBody.yaw_turn_input(3.0, 6.0, 1.0), 0.5, 0.0001)
	assert_eq(WalkerBody.yaw_turn_input(-20.0, 6.0, 1.0), -1.0)


func test_yaw_source_half_a_degree_off_while_idle_produces_no_step_started() -> void:
	var sides := PackedInt32Array([-1, -1, -1, 1, 1, 1])
	var reaches := PackedFloat32Array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	var solver := GaitSolver.new(sides, reaches)
	var started: Array[int] = []
	solver.step_started.connect(func(leg: int) -> void: started.append(leg))
	var errors := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	var valid: Array[bool] = [true, true, true, true, true, true]
	for i in 120:
		# The walker feeds `moving` from the turn input toward the yaw source: 0.5 degrees is inside the dead band.
		var turn: float = WalkerBody.yaw_turn_input(0.5, 6.0, 1.0)
		solver.update(1.0 / 60.0, absf(turn) > 0.01, 0.0, errors, valid)
	assert_eq(started.size(), 0)


func test_hip_height_for_reach_gives_the_highest_hip_that_still_reaches() -> void:
	# 1.0 m reach, foothold 0.6 m away horizontally and 0.5 m below the origin: hip may be 0.8 m above it.
	assert_almost_eq(WalkerBody.hip_height_for_reach(-0.5, 0.6, 1.0), 0.3, 0.0001)
	assert_eq(WalkerBody.hip_height_for_reach(0.0, 1.2, 1.0), -INF)


## Arched leg (GDD 5): hip 0.5 x reach above the foot plane, bones 0.46 + 0.69 x reach, pole up plus 0.8 x the outward rest direction.
func _arched_knee(reach: float, foot_x: float, foot_z: float) -> Vector3:
	var hip := Vector3(0.0, 0.5 * reach, 0.0)
	var foot := Vector3(foot_x * reach, 0.0, foot_z * reach)
	var pole: Vector3 = Vector3.UP + Vector3.RIGHT * 0.8
	var solution: TwoBoneIK.Solution = TwoBoneIK.solve(hip, foot, 0.46 * reach, 0.69 * reach, pole)
	return solution.knee - hip


func test_knee_rises_above_the_hip_by_the_gdd_targets_for_reach_0_6_1_0_and_1_6() -> void:
	for reach in [0.6, 1.0, 1.6]:
		# At rest: foot 0.5 x reach out from the hip.
		assert_gte(_arched_knee(reach, 0.5, 0.0).y, 0.15 * reach, "rest, reach %s" % reach)
		# 0.5 x reach fore-aft of rest.
		assert_gte(_arched_knee(reach, 0.5, 0.5).y, 0.10 * reach, "forward, reach %s" % reach)
		assert_gte(_arched_knee(reach, 0.5, -0.5).y, 0.10 * reach, "back, reach %s" % reach)
		# Foot at 0.99 x reach from the hip (0.5 out, 0.5 down, the rest fore-aft).
		var along: float = sqrt(0.99 * 0.99 - 0.5 * 0.5 - 0.5 * 0.5)
		assert_gte(_arched_knee(reach, 0.5, along).y, 0.0, "0.99 reach, reach %s" % reach)


func test_knee_never_flips_when_the_foot_passes_under_the_hip() -> void:
	var reach: float = 1.0
	var previous_side: float = 0.0
	for step in range(-6, 7):
		var foot_x: float = float(step) * 0.05
		var knee: Vector3 = _arched_knee(reach, foot_x, 0.0)
		assert_gt(knee.x, 0.0, "knee stays outward of the hip at foot x %s" % foot_x)
		# The knee sits on the pole side of the hip-to-foot line (up and outward), never on the far side.
		var hip := Vector3(0.0, 0.5, 0.0)
		var chord: Vector3 = (Vector3(foot_x, 0.0, 0.0) - hip).normalized()
		var pole: Vector3 = Vector3.UP + Vector3.RIGHT * 0.8
		var off_chord: Vector3 = knee - chord * knee.dot(chord)
		assert_gt(off_chord.dot(pole), 0.0, "pole side at foot x %s" % foot_x)
		previous_side = signf(knee.x)
	assert_ne(previous_side, 0.0)


func test_foot_directly_below_the_hip_bends_the_knee_outward() -> void:
	var knee: Vector3 = _arched_knee(1.0, 0.0, 0.0)
	assert_gt(knee.x, 0.0, "outward")
	assert_true(knee.is_finite())


func test_step_time_is_quantized_to_whole_physics_ticks() -> void:
	var tick: float = 1.0 / 60.0
	# 0.139 s is 8.3 ticks: it lands on tick 8, just under so that tick lands it.
	assert_almost_eq(WalkerBody.quantized_step_time(0.1394, tick), 8.0 * tick, 0.001)
	assert_lt(WalkerBody.quantized_step_time(0.1394, tick), 8.0 * tick)
	assert_almost_eq(WalkerBody.quantized_step_time(0.18, tick), 11.0 * tick, 0.001)
	assert_almost_eq(WalkerBody.quantized_step_time(0.001, tick), tick, 0.001)


func test_hip_hangs_half_its_own_reach_above_the_foot_plane() -> void:
	# Medium body (mean reach 1.0): chassis underside 0.6 above the plane, a medium hip 0.5 above it.
	assert_almost_eq(WalkerBody.hip_local_y(0.6, 1.0, 0.5, 1.0), -0.1, 0.0001)
	# A short leg on a body with mean reach 0.867: hip 0.3 above the plane, underside 0.52.
	assert_almost_eq(WalkerBody.hip_local_y(0.6, 0.867, 0.5, 0.6), -0.22, 0.001)
