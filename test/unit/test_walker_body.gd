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


func test_fore_aft_room_from_the_rest_foot_is_at_least_0_65_reach_even_for_fanned_end_legs() -> void:
	var body := WalkerBody.new()
	var room: float = WalkerBody.fore_aft_room_ratio(
		body.hip_height_ratio, body.rest_out_ratio, body.rest_fan_ratio
	)
	body.free()
	assert_gte(room, 0.65)


func test_rest_stance_meets_every_gdd_5_target_at_once() -> void:
	var body := WalkerBody.new()
	var out: float = body.rest_out_ratio
	var hip_ratio: float = body.hip_height_ratio
	body.free()
	for reach in [0.6, 1.0, 1.6]:
		var hip := Vector3(0.0, hip_ratio * reach, 0.0)
		var foot := Vector3(out * reach, 0.0, 0.0)
		var pole: Vector3 = Vector3.UP + Vector3.RIGHT * 0.8
		var solution: TwoBoneIK.Solution = TwoBoneIK.solve(hip, foot, 0.46 * reach, 0.69 * reach, pole)
		var shin: Vector3 = foot - solution.knee
		# Shin leans 0 to 15 degrees outward from vertical (the knee is inboard of the foot).
		var shin_deg: float = rad_to_deg(atan2(foot.x - solution.knee.x, shin.y * -1.0))
		assert_gte(shin_deg, 0.0, "shin outward, reach %s" % reach)
		assert_lte(shin_deg, 15.0, "shin outward, reach %s" % reach)
		# Upper bone at least 15 degrees above horizontal.
		var upper: Vector3 = solution.knee - hip
		var upper_deg: float = rad_to_deg(atan2(upper.y, Vector2(upper.x, upper.z).length()))
		assert_gte(upper_deg, 15.0, "upper bone, reach %s" % reach)


func test_horizontal_is_the_flat_unit_direction_of_a_normal() -> void:
	var flat: Vector3 = WalkerBody._horizontal(Vector3(0.6, 0.8, 0.0), Vector3.ZERO)
	assert_almost_eq(flat.x, 1.0, 0.0001)
	assert_almost_eq(flat.y, 0.0, 0.0001)
	assert_almost_eq(flat.z, 0.0, 0.0001)


func test_horizontal_falls_back_when_the_normal_points_straight_up() -> void:
	var fallback := Vector3(0.0, 0.0, 1.0)
	assert_eq(WalkerBody._horizontal(Vector3.UP, fallback), fallback)


func test_telemetry_percentiles_pick_the_sorted_sample_at_that_rank() -> void:
	var telemetry := WalkerTelemetry.new()
	for ms in [5.0, 1.0, 3.0, 2.0, 4.0, 10.0, 9.0, 8.0, 7.0, 6.0]:
		telemetry._tick_ms.append(ms)
	assert_almost_eq(telemetry.tick_percentile_ms(0.5), 5.0, 0.0001)
	assert_almost_eq(telemetry.tick_p95_ms, 10.0, 0.0001)
	assert_almost_eq(telemetry.tick_max_ms, 10.0, 0.0001)
	telemetry.free()


func test_telemetry_percentile_is_zero_without_samples() -> void:
	var telemetry := WalkerTelemetry.new()
	assert_eq(telemetry.tick_p99_ms, 0.0)
	telemetry.free()


func test_pad_box_gap_is_the_length_of_the_positive_gaps_when_apart() -> void:
	assert_almost_eq(WalkerTelemetry.box_gap(0.3, 0.4, -0.1), 0.5, 0.0001)
	assert_almost_eq(WalkerTelemetry.box_gap(-0.2, -0.1, 0.25), 0.25, 0.0001)


func test_pad_box_gap_is_the_shallowest_overlap_when_the_boxes_intersect() -> void:
	assert_almost_eq(WalkerTelemetry.box_gap(-0.3, -0.2, -0.34), -0.2, 0.0001)
	# Pads one above the other do not overlap: the vertical gap is positive.
	assert_gt(WalkerTelemetry.box_gap(-0.3, 0.5, -0.34), 0.0)


func test_convex_hull_drops_interior_points_and_is_counter_clockwise() -> void:
	var points := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2), Vector2(1, 1), Vector2(1, 0)])
	var hull: PackedVector2Array = WalkerBody.convex_hull(points)
	assert_eq(hull.size(), 4, "the interior and edge points are dropped")
	var area: float = 0.0
	for k in hull.size():
		area += hull[k].cross(hull[(k + 1) % hull.size()]) * 0.5
	assert_almost_eq(area, 4.0, 0.0001, "positive area means counter-clockwise")


func test_convex_hull_of_fewer_than_three_points_is_returned_as_is() -> void:
	assert_eq(WalkerBody.convex_hull(PackedVector2Array([Vector2(1, 1), Vector2(2, 2)])).size(), 2)


func test_polygon_margin_is_positive_inside_negative_outside() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	assert_almost_eq(WalkerBody.polygon_margin(square, Vector2(1, 1)), 1.0, 0.0001)
	assert_almost_eq(WalkerBody.polygon_margin(square, Vector2(1.8, 1)), 0.2, 0.0001)
	assert_almost_eq(WalkerBody.polygon_margin(square, Vector2(2.5, 1)), -0.5, 0.0001)
	assert_eq(WalkerBody.polygon_margin(PackedVector2Array([Vector2(0, 0), Vector2(1, 0)]), Vector2(0.5, 0.1)), -1.0)


func test_climb_plane_follows_the_line_from_the_rear_feet_to_the_front_feet() -> void:
	# Two rows of feet 2 m apart along -Z, the front row 1 m up on a ledge: the body must lie along a 1 m per 2 m line.
	var feet := PackedVector3Array(
		[Vector3(-0.5, 0, 1), Vector3(0.5, 0, 1), Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 1, -1), Vector3(0.5, 1, -1)]
	)
	var plane: Plane = WalkerBody.climb_plane(feet, feet.size(), Vector3(0, 0, -1))
	assert_gt(plane.normal.z, 0.0, "the normal leans back when the front is up")
	var slope: float = plane.normal.z / plane.normal.y
	assert_gt(slope, 0.3, "steeper than the flat least-squares fit of a long body with two feet up")


func test_climb_plane_of_flat_ground_is_flat() -> void:
	var feet := PackedVector3Array(
		[Vector3(-0.5, 0, 1), Vector3(0.5, 0, 1), Vector3(-0.5, 0, 0), Vector3(0.5, 0, 0), Vector3(-0.5, 0, -1), Vector3(0.5, 0, -1)]
	)
	var plane: Plane = WalkerBody.climb_plane(feet, feet.size(), Vector3(0, 0, -1))
	assert_almost_eq(plane.normal.y, 1.0, 0.0001)


func test_convex_hull_scratch_reuse_does_not_leak_points_between_calls() -> void:
	var big := PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4), Vector2(2, 2), Vector2(1, 3)])
	assert_eq(WalkerBody.convex_hull(big).size(), 4)
	var small := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)])
	var hull: PackedVector2Array = WalkerBody.convex_hull(small)
	assert_eq(hull.size(), 3, "the second call sees only its own points")
	assert_almost_eq(WalkerBody.polygon_margin(hull, Vector2(0.25, 0.25)), 0.25, 0.0001)


func test_support_advance_keeps_the_back_off_input_while_a_leg_waits() -> void:
	var facing := Vector3(0, 0, -1)
	var back: Vector3 = WalkerBody.support_advance(Vector3(0, 0, 4.0), facing, Vector3.ZERO, 1.8)
	assert_gt(back.z, 1.0, "S moves the body back even with no shift")
	var forward: Vector3 = WalkerBody.support_advance(Vector3(0, 0, -4.0), facing, Vector3.ZERO, 1.8)
	assert_almost_eq(forward.length(), 0.0, 0.0001, "forward input is not added to the shift")
	var strafe: Vector3 = WalkerBody.support_advance(Vector3(3.0, 0, -4.0), facing, Vector3.ZERO, 1.8)
	assert_gt(strafe.x, 1.0, "strafe input is kept")



func _fold_rig() -> Array:
	# One hip 1.0 m above a planted foot, fold distance 0.4: poses are plain translations.
	var hips := PackedVector3Array([Vector3.ZERO])
	var feet := PackedVector3Array([Vector3(0, -1.0, 0)])
	var planted := PackedByteArray([1])
	var limits := PackedFloat32Array([1.5])
	var folds := PackedFloat32Array([0.4])
	return [hips, feet, planted, limits, folds]


func test_a_hip_may_not_come_inside_the_fold_distance_of_its_planted_foot() -> void:
	var r: Array = _fold_rig()
	var now := Transform3D.IDENTITY
	var near := Transform3D(Basis.IDENTITY, Vector3(0, -0.5, 0))
	assert_true(WalkerBody.feet_in_reach(near, now, r[0], r[1], r[2], r[3], r[4]), "0.5 m above the foot is outside 0.4")
	var inside := Transform3D(Basis.IDENTITY, Vector3(0, -0.7, 0))
	assert_false(WalkerBody.feet_in_reach(inside, now, r[0], r[1], r[2], r[3], r[4]), "0.3 m above the foot is inside the fold distance")
	assert_true(WalkerBody.feet_in_reach(inside, now, r[0], r[1], r[2], r[3]), "without fold distances the old rule holds")


func test_a_hip_already_inside_the_fold_distance_may_only_move_away_from_its_foot() -> void:
	var r: Array = _fold_rig()
	var inside := Transform3D(Basis.IDENTITY, Vector3(0, -0.7, 0))
	var away := Transform3D(Basis.IDENTITY, Vector3(0, -0.65, 0))
	assert_true(WalkerBody.feet_in_reach(away, inside, r[0], r[1], r[2], r[3], r[4]), "moving away is always allowed")
	var closer := Transform3D(Basis.IDENTITY, Vector3(0, -0.75, 0))
	assert_false(WalkerBody.feet_in_reach(closer, inside, r[0], r[1], r[2], r[3], r[4]), "nearer would push the pad out and up")


func test_a_climb_swing_settles_onto_its_landing_with_no_step_at_either_end() -> void:
	assert_almost_eq(WalkerBody.ease_settle(0.0), 0.0, 0.000001)
	assert_almost_eq(WalkerBody.ease_settle(1.0), 1.0, 0.000001)
	# Flat at the end: the last tick of a 21-tick swing leaves under 1 % of the settle (smoothstep leaves about 3 %).
	assert_lt(1.0 - WalkerBody.ease_settle(0.9), 0.01)
	var last: float = 0.0
	for k in 21:
		var value: float = WalkerBody.ease_settle(float(k) / 20.0)
		assert_gte(value, last, "monotone at %d" % k)
		last = value


func test_a_ledge_is_climbed_within_45_deg_of_head_on_and_slid_along_beyond() -> void:
	var body := WalkerBody.new()
	# Heading -Z (yaw 0); a face ahead points its normal out toward the walker (+Z).
	for case in [[0.0, true], [30.0, true], [44.0, true], [46.0, false], [60.0, false], [90.0, false]]:
		var out := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(case[0]))
		assert_eq(body._approach_ok(out, false), case[1], "up a face %s deg off head-on" % case[0])
	# Stepping down: the edge's face points out of the higher ground, along the heading.
	for case in [[0.0, true], [40.0, true], [50.0, false]]:
		var out_down := Vector3(0.0, 0.0, -1.0).rotated(Vector3.UP, deg_to_rad(case[0]))
		assert_eq(body._approach_ok(out_down, true), case[1], "down an edge %s deg off head-on" % case[0])
	body.free()


func test_a_climb_under_way_finishes_whatever_the_heading() -> void:
	var body := WalkerBody.new()
	var shallow := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(70.0))
	assert_false(body._approach_ok(shallow, false))
	body._climb_session = true
	assert_true(body._approach_ok(shallow, false), "a foot is up: the climb finishes")
	body.free()
