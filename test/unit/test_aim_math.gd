extends GutTest
## Unit tests for scripts/weapons/aim_math.gd and ui/aim/aim_layout.gd (GDD 8.3 aim model, 12 aim marks).

const DT: float = 1.0 / 60.0
const PIVOT := Vector3(0.0, 2.0, 0.0)


func _top() -> Dictionary:
	return AimMath.mount_arc(&"top")


## The world point `range_m` away from PIVOT along the chassis-frame pose (identity chassis).
func _point(pose: Vector2, range_m: float = 20.0) -> Vector3:
	return PIVOT + AimMath.barrel_basis(Basis.IDENTITY, pose) * Vector3.FORWARD * range_m


# --- Traverse rate (GDD 8.3) ----------------------------------------------------------------------------------


func test_traverse_rate_by_mass() -> void:
	assert_almost_eq(AimMath.traverse_rate(5.0), 720.0, 0.01)
	assert_almost_eq(AimMath.traverse_rate(10.0), 720.0, 0.01)
	assert_almost_eq(AimMath.traverse_rate(40.0), 180.0, 0.01)
	assert_almost_eq(AimMath.traverse_rate(80.0), 90.0, 0.01)
	assert_almost_eq(AimMath.traverse_rate(160.0), 45.0, 0.01)
	assert_almost_eq(AimMath.traverse_rate(300.0), 45.0, 0.01)


func test_traverse_rate_never_rises_with_mass() -> void:
	var previous: float = INF
	for mass in range(1, 400):
		var rate: float = AimMath.traverse_rate(float(mass))
		assert_lte(rate, previous, "mass %d" % mass)
		previous = rate


# --- Mount arcs --------------------------------------------------------------------------------------------------


func test_the_top_arc_is_360_in_yaw_and_minus_20_to_75_in_pitch() -> void:
	var arc: Dictionary = _top()
	assert_true(arc["unlimited"])
	assert_eq(arc["pitch_min_deg"], -20.0)
	assert_eq(arc["pitch_max_deg"], 75.0)


func test_the_other_faces_are_data_only_rows_of_the_gdd() -> void:
	for face in [&"front", &"back", &"left", &"right"]:
		var arc: Dictionary = AimMath.mount_arc(face)
		assert_false(arc["unlimited"], str(face))
		assert_eq(arc["yaw_half_deg"], 90.0)
		assert_eq(arc["pitch_min_deg"], -90.0)
		assert_eq(arc["pitch_max_deg"], 90.0)
	assert_eq(AimMath.mount_arc(&"back")["face_yaw_deg"], 180.0)
	assert_eq(AimMath.mount_arc(&"left")["face_yaw_deg"], 90.0)
	var bottom: Dictionary = AimMath.mount_arc(&"bottom")
	assert_true(bottom["unlimited"])
	assert_eq(bottom["pitch_min_deg"], -75.0)
	assert_eq(bottom["pitch_max_deg"], 20.0)


func test_inside_and_outside_with_half_a_degree_of_tolerance() -> void:
	var arc: Dictionary = _top()
	assert_true(AimMath.is_inside(Vector2(10.0, -19.0), arc))
	assert_true(AimMath.is_inside(Vector2(10.0, -20.4), arc), "-20.4 is still live")
	assert_false(AimMath.is_inside(Vector2(10.0, -20.6), arc), "-20.6 is gray")
	assert_true(AimMath.is_inside(Vector2(-170.0, 75.4), arc))
	assert_false(AimMath.is_inside(Vector2(-170.0, 75.6), arc))
	var front: Dictionary = AimMath.mount_arc(&"front")
	assert_true(AimMath.is_inside(Vector2(90.4, 0.0), front))
	assert_false(AimMath.is_inside(Vector2(90.6, 0.0), front))
	assert_false(AimMath.is_inside(Vector2(180.0, 0.0), front), "behind a front mount is outside")


func test_the_nearest_reachable_pose_keeps_the_bearing_and_clamps_the_pitch() -> void:
	var solved: Dictionary = AimMath.solve(PIVOT, Basis.IDENTITY, _point(Vector2(40.0, -30.0)), _top(), Vector2.ZERO)
	assert_false(solved["live"])
	var target: Vector2 = solved["target"]
	assert_almost_eq(target.x, 40.0, 0.001, "on P's bearing")
	assert_almost_eq(target.y, -20.0, 0.001, "at the arc limit")
	var high: Dictionary = AimMath.solve(PIVOT, Basis.IDENTITY, _point(Vector2(-60.0, 80.0)), _top(), Vector2.ZERO)
	assert_false(high["live"])
	assert_almost_eq((high["target"] as Vector2).y, 75.0, 0.001)


func test_a_limited_mount_aims_at_the_nearest_edge_of_its_yaw_arc() -> void:
	var front: Dictionary = AimMath.mount_arc(&"front")
	var target: Vector2 = AimMath.clamp_to_arc(Vector2(150.0, 10.0), front)
	assert_almost_eq(target.x, 90.0, 0.001)
	target = AimMath.clamp_to_arc(Vector2(-150.0, 10.0), front)
	assert_almost_eq(target.x, -90.0, 0.001)


func test_a_p_inside_the_arc_is_live_and_aimed_at_exactly() -> void:
	var p: Vector3 = _point(Vector2(-120.0, 12.0))
	var solved: Dictionary = AimMath.solve(PIVOT, Basis.IDENTITY, p, _top(), Vector2.ZERO)
	assert_true(solved["live"])
	var pose: Vector2 = solved["target"]
	var along: Vector3 = AimMath.barrel_basis(Basis.IDENTITY, pose) * Vector3.FORWARD
	assert_lt(AimMath.angle_between_deg(along, (p - PIVOT).normalized()), 0.001)


func test_a_p_within_1_5_m_of_the_pivot_holds_the_pose_gray() -> void:
	var held := Vector2(33.0, 5.0)
	var solved: Dictionary = AimMath.solve(PIVOT, Basis.IDENTITY, PIVOT + Vector3(0.0, -1.4, 0.0), _top(), held)
	assert_true(solved["hold"])
	assert_false(solved["live"])
	assert_eq(solved["target"], held)
	var outside: Dictionary = AimMath.solve(PIVOT, Basis.IDENTITY, PIVOT + Vector3(0.0, -1.6, 0.0), _top(), held)
	assert_false(outside["hold"], "1.6 m is outside the hold radius")


func test_the_arc_is_in_the_chassis_frame() -> void:
	# A body tilted 39 deg nose-up: the lowest the roof arc goes straight ahead is world +19 deg.
	var tilt := Basis(Vector3.RIGHT, deg_to_rad(39.0))
	var lowest: Vector3 = AimMath.barrel_basis(tilt, Vector2(0.0, -20.0)) * Vector3.FORWARD
	assert_almost_eq(rad_to_deg(asin(lowest.y)), 19.0, 0.5)
	# Straight behind, the same arc reaches down to world -59.
	var behind: Vector3 = AimMath.barrel_basis(tilt, Vector2(180.0, -20.0)) * Vector3.FORWARD
	assert_almost_eq(rad_to_deg(asin(behind.y)), -59.0, 0.5)
	# And a P on the level at 30 m ahead is gray on that body, live on a level one.
	var p := Vector3(0.0, 2.0, -30.0)
	assert_false(AimMath.solve(PIVOT, tilt, p, _top(), Vector2.ZERO)["live"])
	assert_true(AimMath.solve(PIVOT, Basis.IDENTITY, p, _top(), Vector2.ZERO)["live"])


# --- Step ----------------------------------------------------------------------------------------------------------


func test_a_90_deg_yaw_swing_at_180_deg_per_s_takes_30_ticks_and_never_exceeds_3_deg_per_tick() -> void:
	var pose := Vector2.ZERO
	var target := Vector2(90.0, 0.0)
	var ticks: int = 0
	var worst: float = 0.0
	while absf(target.x - pose.x) > 0.0001 and ticks < 100:
		var next: Vector2 = AimMath.step(pose, target, 180.0, DT, _top())
		worst = maxf(worst, absf(next.x - pose.x))
		pose = next
		ticks += 1
	assert_eq(ticks, 30)
	assert_lte(worst, 3.0 * 1.005)


func test_a_30_deg_pitch_swing_takes_10_ticks() -> void:
	var pose := Vector2.ZERO
	var ticks: int = 0
	while absf(30.0 - pose.y) > 0.0001 and ticks < 100:
		pose = AimMath.step(pose, Vector2(0.0, 30.0), 180.0, DT, _top())
		ticks += 1
	assert_eq(ticks, 10)


func test_each_axis_is_limited_on_its_own() -> void:
	var next: Vector2 = AimMath.step(Vector2.ZERO, Vector2(90.0, 20.0), 180.0, DT, _top())
	assert_almost_eq(next.x, 3.0, 0.0001, "yaw uses its whole 3 deg")
	assert_almost_eq(next.y, 3.0, 0.0001, "pitch uses its own 3 deg")
	var small: Vector2 = AimMath.step(Vector2.ZERO, Vector2(90.0, 1.0), 180.0, DT, _top())
	assert_almost_eq(small.y, 1.0, 0.0001, "arrives without overshooting")


func test_the_step_never_exceeds_rate_times_delta_on_any_axis() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	for i in 200:
		var from := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-20.0, 75.0))
		var to := Vector2(rng.randf_range(-180.0, 180.0), rng.randf_range(-20.0, 75.0))
		var rate: float = [45.0, 90.0, 180.0, 720.0][i % 4]
		var next: Vector2 = AimMath.step(from, to, rate, DT, _top())
		assert_lte(absf(wrapf(next.x - from.x, -180.0, 180.0)), rate * DT + 0.0001)
		assert_lte(absf(next.y - from.y), rate * DT + 0.0001)


func test_a_360_mount_swings_the_shortest_way_round() -> void:
	var next: Vector2 = AimMath.step(Vector2(170.0, 0.0), Vector2(-170.0, 0.0), 180.0, DT, _top())
	assert_almost_eq(next.x, 173.0, 0.0001, "170 -> 173: on toward 180 and across it, not back through 0")
	var back: Vector2 = AimMath.step(Vector2(-170.0, 0.0), Vector2(170.0, 0.0), 180.0, DT, _top())
	assert_almost_eq(back.x, -173.0, 0.0001)


func test_a_limited_mount_never_swings_through_its_dead_zone() -> void:
	for face in [&"front", &"back", &"left", &"right"]:
		var arc: Dictionary = AimMath.mount_arc(face)
		var face_yaw: float = arc["face_yaw_deg"]
		var pose := Vector2(face_yaw - 85.0, 0.0)
		var target := Vector2(face_yaw + 85.0, 0.0)
		var ticks: int = 0
		while absf(wrapf(target.x - pose.x, -180.0, 180.0)) > 0.0001 and ticks < 200:
			pose = AimMath.step(pose, target, 180.0, DT, arc)
			assert_lte(absf(wrapf(pose.x - face_yaw, -180.0, 180.0)), 90.0 + 0.0001, "%s tick %d" % [face, ticks])
			ticks += 1
		assert_eq(ticks, 57, "170 deg the long way inside the arc: %s" % face)


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
	for scale in [1.0, 2.0 / 3.0]:
		for thick in [false, true]:
			var stroke: float = AimLayout.stroke_screen_px(thick, scale)
			var across: float = (AimLayout.ring_radius(scale, stroke) + stroke * 0.5) * 2.0
			assert_almost_eq(across, 28.0 * scale, 0.0001, "thick %s at scale %.2f" % [thick, scale])


func test_the_enemy_stroke_stays_at_least_3_px_at_720p() -> void:
	var scale: float = AimLayout.ui_scale(720.0)
	assert_gte(AimLayout.stroke_screen_px(true, scale), 3.0, "5 px at 1080p is 3.3 px at 720p")
	assert_gt(AimLayout.stroke_screen_px(true, scale), AimLayout.stroke_screen_px(false, scale), "still thicker")
	assert_eq(AimLayout.stroke_screen_px(true, 1.0), 5.0, "at 1080p the numbers are the GDD's")
	assert_eq(AimLayout.stroke_screen_px(false, 1.0), 3.0)


func test_the_gray_ring_is_neutral_and_at_least_0_2_luma_below_the_accent() -> void:
	var gray: Color = AimLayout.GRAY
	assert_eq(gray, Color("646464"))
	assert_almost_eq(gray.r, gray.g, 0.0001, "saturation 0")
	assert_almost_eq(gray.g, gray.b, 0.0001)
	var accent_luma: float = AimLayout.ACCENT.get_luminance()
	assert_gte(accent_luma - gray.get_luminance(), 0.2, "luma %.3f vs %.3f" % [accent_luma, gray.get_luminance()])


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


func test_the_dashed_ring_has_8_dashes_with_gaps_at_about_50_percent_duty() -> void:
	var arcs: Array[Vector2] = AimLayout.dash_arcs()
	assert_eq(arcs.size(), 8)
	var drawn: float = 0.0
	for i in arcs.size():
		assert_gt(arcs[i].y, arcs[i].x)
		drawn += arcs[i].y - arcs[i].x
		var next_start: float = arcs[(i + 1) % arcs.size()].x + (TAU if i == arcs.size() - 1 else 0.0)
		assert_gt(next_start, arcs[i].y, "a gap between dash %d and the next" % i)
	assert_almost_eq(drawn / TAU, 0.5, 0.01, "about 50 % duty")


func test_the_dash_gaps_are_at_least_2_px_at_720p() -> void:
	var scale: float = AimLayout.ui_scale(720.0)
	var radius: float = AimLayout.ring_radius(scale, AimLayout.stroke_screen_px(false, scale))
	var arcs: Array[Vector2] = AimLayout.dash_arcs()
	var gap_angle: float = arcs[1].x - arcs[0].y
	assert_gte(gap_angle * radius, 2.0, "gap of %.2f px" % (gap_angle * radius))


func test_the_marks_control_ignores_the_mouse() -> void:
	var marks := AimMarks.new()
	assert_eq(marks.mouse_filter, Control.MOUSE_FILTER_IGNORE)
	marks.free()
