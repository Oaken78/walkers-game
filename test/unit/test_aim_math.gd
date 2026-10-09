extends GutTest
## Unit tests for scripts/weapons/aim_math.gd and ui/aim/aim_layout.gd (GDD 8.3 aim model, 12 aim marks).

const PIVOT_LOCAL := Vector3(0.0, 0.9, -0.1)


func _heading_error_deg(yaw: float, elevation_deg: float) -> float:
	var forward: Vector3 = AimMath.barrel_basis(yaw, elevation_deg) * Vector3(0.0, 0.0, -1.0)
	var flat: Vector3 = Vector3(forward.x, 0.0, forward.z).normalized()
	return AimMath.angle_between_deg(flat, AimMath.heading(yaw))


# --- P, d, h, Q -------------------------------------------------------------------------------------------------


func test_range_is_clamped_to_4_m_when_the_camera_looks_straight_down() -> void:
	var origin := Vector3(10.0, 1.0, -5.0)
	# Looking straight down at the walker's own feet: P is almost under the body origin.
	var feet := Vector3(10.2, 0.0, -5.1)
	var rh: Vector2 = AimMath.range_and_height(Vector2(30.0, 3.0), feet, origin, 0.0, 0.0)
	assert_eq(rh.x, 4.0, "d never drops under 4 m, so the guns never point into the ground under the walker")
	assert_eq(rh.y, 0.0, "h is P's height")


func test_range_is_clamped_to_120_m() -> void:
	var rh: Vector2 = AimMath.range_and_height(Vector2(30.0, 3.0), Vector3(0.0, 40.0, -300.0), Vector3.ZERO, 0.0, 0.0)
	assert_eq(rh.x, 120.0)
	assert_eq(rh.y, 40.0)


func test_range_is_the_horizontal_distance_not_the_straight_one() -> void:
	var rh: Vector2 = AimMath.range_and_height(Vector2.ZERO, Vector3(3.0, 20.0, -4.0), Vector3.ZERO, 0.0, 0.0)
	assert_almost_eq(rh.x, 5.0, 0.0001)


func test_d_and_h_hold_when_the_camera_yaw_is_more_than_90_deg_off_the_heading() -> void:
	var previous := Vector2(17.0, 2.5)
	var p := Vector3(0.0, 9.0, -50.0)
	assert_eq(AimMath.range_and_height(previous, p, Vector3.ZERO, 91.0, 0.0), previous, "91 deg off: held")
	assert_eq(AimMath.range_and_height(previous, p, Vector3.ZERO, -120.0, 0.0), previous, "behind: held")
	assert_eq(AimMath.range_and_height(previous, p, Vector3.ZERO, 180.0, 0.0), previous)
	var fresh: Vector2 = AimMath.range_and_height(previous, p, Vector3.ZERO, 90.0, 0.0)
	assert_almost_eq(fresh.x, 50.0, 0.0001, "exactly 90 deg is not more than 90: P is read again")
	assert_eq(fresh.y, 9.0)
	var near: Vector2 = AimMath.range_and_height(previous, p, Vector3.ZERO, 89.0, 0.0)
	assert_eq(near, Vector2(50.0, 9.0), "back inside 90 deg the guns pick P up again")


func test_the_90_deg_gap_is_measured_from_the_body_heading_and_wraps() -> void:
	assert_almost_eq(AimMath.yaw_gap_deg(-170.0, deg_to_rad(170.0)), 20.0, 0.0001, "across the +-180 seam")
	assert_almost_eq(AimMath.yaw_gap_deg(100.0, deg_to_rad(30.0)), 70.0, 0.0001)
	assert_false(AimMath.holds(100.0, deg_to_rad(30.0)))
	assert_true(AimMath.holds(100.0, deg_to_rad(-30.0)), "130 deg off")


func test_q_lies_d_along_the_heading_at_height_h() -> void:
	var origin := Vector3(2.0, 1.0, 3.0)
	var q: Vector3 = AimMath.convergence_point(origin, 0.0, 10.0, 4.0)
	assert_eq(q, Vector3(2.0, 4.0, -7.0), "yaw 0 looks along -Z")
	q = AimMath.convergence_point(origin, deg_to_rad(90.0), 10.0, 4.0)
	assert_almost_eq(q.x, -8.0, 0.0001, "yaw +90 turns left, toward -X")
	assert_almost_eq(q.z, 3.0, 0.0001)
	assert_eq(q.y, 4.0)


# --- Yaw and elevation ------------------------------------------------------------------------------------------


func test_weapon_yaw_equals_the_heading_within_0_1_deg_at_any_elevation() -> void:
	var worst: float = 0.0
	for yaw_step in range(-18, 19):
		for elevation in range(-10, 46, 5):
			worst = maxf(worst, _heading_error_deg(deg_to_rad(float(yaw_step) * 10.0), float(elevation)))
	assert_lt(worst, 0.1, "worst yaw error %.5f deg" % worst)


func test_solved_elevation_makes_the_muzzle_line_end_on_q() -> void:
	var muzzle := Vector3(0.0, 0.0, -0.75)
	var pivot := Vector3(1.0, 2.0, -1.0)
	var worst: float = 0.0
	for height in [-3.0, 0.0, 2.0, 6.0, 20.0]:
		for range_m in [4.0, 12.0, 60.0, 120.0]:
			var yaw: float = deg_to_rad(33.0)
			var q: Vector3 = AimMath.convergence_point(pivot, yaw, range_m, height)
			var elevation: float = AimMath.solve_elevation(pivot, muzzle, yaw, q)
			var from: Vector3 = AimMath.muzzle_position(pivot, yaw, elevation, muzzle)
			worst = maxf(worst, absf(AimMath.elevation_to(from, q) - elevation))
	assert_lt(worst, 0.01, "the barrel's elevation is the muzzle-to-Q angle within 0.01 deg (worst %.5f)" % worst)


func test_a_target_on_the_heading_is_hit_by_a_shot_from_the_solved_elevation() -> void:
	var muzzle := Vector3(0.0, 0.0, -0.75)
	var pivot := Vector3(0.0, 2.0, 0.0)
	var target := Vector3(0.0, 3.0, -25.0)
	var q: Vector3 = AimMath.convergence_point(pivot, 0.0, AimMath.horizontal_distance(pivot, target), target.y)
	var elevation: float = AimMath.solve_elevation(pivot, muzzle, 0.0, q)
	var from: Vector3 = AimMath.muzzle_position(pivot, 0.0, elevation, muzzle)
	var shot: Vector3 = AimMath.barrel_basis(0.0, elevation) * Vector3(0.0, 0.0, -1.0)
	assert_lt(AimMath.angle_between_deg(shot, target - from), 0.01, "the shot line passes through the target")


func test_elevation_clamps_to_minus_10_and_45_world_relative_on_a_body_tilted_39_deg() -> void:
	var tilt: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(39.0))
	var pose: Transform3D = WalkerBody.pose_transform(Vector3(0.0, 5.0, 0.0), 0.0, tilt)
	assert_almost_eq(rad_to_deg(Vector3.UP.angle_to(pose.basis.y)), 39.0, 0.01, "the body is tilted 39 deg nose up")
	var pivot: Vector3 = pose * PIVOT_LOCAL
	var muzzle := Vector3(0.0, 0.0, -0.75)
	# Level shot for a body-relative clamp would be 39 deg; world-relative, level is 0.
	var level: float = AimMath.solve_elevation(pivot, muzzle, 0.0, Vector3(0.0, pivot.y, -30.0))
	assert_almost_eq(AimMath.clamp_elevation(level), 0.0, 0.1, "a level target on a tilted body still aims level")
	var high: float = AimMath.solve_elevation(pivot, muzzle, 0.0, Vector3(0.0, pivot.y + 40.0, -30.0))
	assert_gt(high, 45.0)
	assert_eq(AimMath.clamp_elevation(high), 45.0, "world-relative +45, not 45 on top of the tilt")
	var low: float = AimMath.solve_elevation(pivot, muzzle, 0.0, Vector3(0.0, pivot.y - 15.0, -30.0))
	assert_lt(low, -10.0)
	assert_eq(AimMath.clamp_elevation(low), -10.0, "world-relative -10, not -10 relative to the nose")
	assert_true(AimMath.is_limited(high))
	assert_true(AimMath.is_limited(low))
	assert_false(AimMath.is_limited(level))
	var drawn: Vector3 = AimMath.barrel_basis(0.0, AimMath.clamp_elevation(high)) * Vector3(0.0, 0.0, -1.0)
	assert_almost_eq(rad_to_deg(asin(drawn.y)), 45.0, 0.001, "the drawn barrel is 45 deg above the horizon")


func test_elevation_slews_at_360_deg_per_s() -> void:
	var tick: float = 1.0 / 60.0
	var elevation: float = 0.0
	for i in 7:
		elevation = AimMath.slew(elevation, 45.0, tick)
	assert_almost_eq(elevation, 42.0, 0.0001, "6 deg per 60 Hz tick")
	elevation = AimMath.slew(elevation, 45.0, tick)
	assert_eq(elevation, 45.0, "arrives without overshooting")
	# The longest flick, -10 to +45, is followed within 0.15 s plus one tick.
	elevation = -10.0
	var ticks: int = 0
	while elevation < 45.0:
		elevation = AimMath.slew(elevation, 45.0, tick)
		ticks += 1
	assert_lte(float(ticks) * tick, 0.15 + tick)


# --- Spread -----------------------------------------------------------------------------------------------------


func test_spread_zero_leaves_the_direction_alone() -> void:
	var direction := Vector3(0.0, 0.0, -1.0)
	assert_eq(AimMath.spread_direction(direction, 0.0, 0.7, 0.3), direction)


func test_spread_stays_inside_a_cone_of_the_given_half_angle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7001
	var direction := Vector3(0.3, 0.2, -0.9).normalized()
	var worst: float = 0.0
	var total: float = 0.0
	for i in 2000:
		var shot: Vector3 = AimMath.spread_direction(direction, 1.5, rng.randf(), rng.randf())
		var angle: float = AimMath.angle_between_deg(shot, direction)
		worst = maxf(worst, angle)
		total += angle
	assert_lte(worst, 1.5 + 0.0001, "never outside the half-angle")
	assert_gt(worst, 1.4, "and the cone is used")
	assert_almost_eq(total / 2000.0, 1.0, 0.05, "uniform over the disc: mean angle is two thirds of the half-angle")


# --- Marks layout (GDD 12) -----------------------------------------------------------------------------------


func test_marks_scale_with_the_screen_height() -> void:
	assert_eq(AimLayout.ui_scale(1080.0), 1.0)
	assert_almost_eq(AimLayout.ui_scale(720.0), 2.0 / 3.0, 0.0001)


func test_the_ring_is_28_px_across_whatever_the_stroke() -> void:
	assert_almost_eq((AimLayout.ring_radius(1.0, 3.0) + 1.5) * 2.0, 28.0, 0.0001)
	assert_almost_eq((AimLayout.ring_radius(1.0, 5.0) + 2.5) * 2.0, 28.0, 0.0001, "the enemy stroke grows inward")


func test_the_ring_merges_with_the_dot_within_12_px() -> void:
	var dot := Vector2(960.0, 540.0)
	assert_true(AimLayout.is_merged(dot + Vector2(12.0, 0.0), dot, 1.0))
	assert_false(AimLayout.is_merged(dot + Vector2(12.5, 0.0), dot, 1.0))
	assert_true(AimLayout.is_merged(dot + Vector2(8.0, 0.0), dot, 2.0 / 3.0), "12 px at 1080p is 8 px at 720p")
	assert_false(AimLayout.is_merged(dot + Vector2(9.0, 0.0), dot, 2.0 / 3.0))


func test_the_chevron_sits_24_px_in_from_the_screen_edge() -> void:
	var view := Vector2(1920.0, 1080.0)
	assert_eq(AimLayout.chevron_position(Vector2.RIGHT, view, 1.0), Vector2(1896.0, 540.0))
	assert_eq(AimLayout.chevron_position(Vector2.LEFT, view, 1.0), Vector2(24.0, 540.0))
	assert_eq(AimLayout.chevron_position(Vector2.UP, view, 1.0), Vector2(960.0, 24.0))
	var corner: Vector2 = AimLayout.chevron_position(Vector2(1.0, 1.0), view, 1.0)
	assert_almost_eq(corner.y, 1056.0, 0.0001, "a diagonal reaches the nearer edge first")
	assert_lt(corner.x, 1896.0)
	var small: Vector2 = AimLayout.chevron_position(Vector2.RIGHT, Vector2(1280.0, 720.0), 2.0 / 3.0)
	assert_almost_eq(small.x, 1280.0 - 16.0, 0.0001, "the inset scales too")


func test_the_chevron_points_the_way_it_was_asked() -> void:
	var points: PackedVector2Array = AimLayout.chevron_points(Vector2(100.0, 100.0), Vector2.RIGHT, 1.0)
	assert_eq(points.size(), 4)
	assert_almost_eq(points[0].x, 116.0, 0.0001, "the tip is half of 32 px ahead")
	assert_almost_eq(points[0].y, 100.0, 0.0001)


func test_the_dashed_ring_has_8_dashes_with_gaps() -> void:
	var arcs: Array[Vector2] = AimLayout.dash_arcs()
	assert_eq(arcs.size(), 8)
	for i in arcs.size():
		assert_gt(arcs[i].y, arcs[i].x)
		var next_start: float = arcs[(i + 1) % arcs.size()].x + (TAU if i == arcs.size() - 1 else 0.0)
		assert_gt(next_start, arcs[i].y, "a gap between dash %d and the next" % i)


func test_the_marks_control_ignores_the_mouse() -> void:
	var marks := AimMarks.new()
	assert_eq(marks.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	marks.free()
