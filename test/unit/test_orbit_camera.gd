extends GutTest
## Unit tests for scripts/camera/orbit_math.gd (pure maths of the orbit camera, GDD 5, 6, 10).

const SENS: float = 0.15
const STRIDER_FEET_X: Array[float] = [-2.4, 2.4]
const STRIDER_FEET_Z: Array[float] = [-2.0, 0.0, 2.0]
const CRAWLER_FEET_X: Array[float] = [-1.2, 1.2]
const CRAWLER_FEET_Z: Array[float] = [-1.2, -0.4, 0.4, 1.2]


func _angles(yaw: float, pitch: float, dx: float, dy: float, invert: bool = false) -> Vector2:
	return OrbitMath.mouse_to_angles(yaw, pitch, dx, dy, SENS, invert, -20.0, 60.0)


func test_mouse_turns_0_15_deg_per_pixel() -> void:
	var a: Vector2 = _angles(0.0, 20.0, 100.0, 0.0)
	assert_almost_eq(a.x, -15.0, 0.0001, "100 px right turns the view 15 deg right (yaw falls)")
	a = _angles(0.0, 20.0, 0.0, 100.0)
	assert_almost_eq(a.y, 35.0, 0.0001, "100 px down adds 15 deg of pitch")


func test_mouse_up_tilts_the_view_up_with_invert_y_off() -> void:
	var a: Vector2 = _angles(0.0, 20.0, 0.0, -40.0)
	assert_lt(a.y, 20.0, "mouse up lowers pitch toward -20, which looks up")
	var inverted: Vector2 = _angles(0.0, 20.0, 0.0, -40.0, true)
	assert_gt(inverted.y, 20.0, "invert-Y flips it")


func test_pitch_is_clamped_to_minus_20_and_60() -> void:
	assert_eq(_angles(0.0, 20.0, 0.0, -100000.0).y, -20.0)
	assert_eq(_angles(0.0, 20.0, 0.0, 100000.0).y, 60.0)


func test_the_camera_pitch_range_is_minus_20_to_60_with_minus_20_to_minus_10_as_aim_up() -> void:
	var camera := OrbitCamera.new()
	assert_eq(camera.pitch_min_deg, -20.0, "GDD 6: the aim-up range reaches -20")
	assert_eq(camera.pitch_max_deg, 60.0)
	camera.free()


func test_yaw_is_free_and_wraps() -> void:
	var yaw: float = 0.0
	for i in range(100):
		yaw = _angles(yaw, 20.0, 1000.0, 0.0).x
		assert_true(yaw >= -180.0 and yaw <= 180.0, "yaw stays in -180..180")
	# 100 * 150 deg = 15000 deg right = -15000 mod 360 = -240 -> 120
	assert_almost_eq(yaw, 120.0, 0.001)


func test_zoom_clamps_between_5_and_12_m() -> void:
	var d: float = 8.0
	for i in range(20):
		d = OrbitMath.zoom_distance(d, -1, 1.0, 5.0, 12.0)
	assert_eq(d, 12.0)
	for i in range(20):
		d = OrbitMath.zoom_distance(d, 1, 1.0, 5.0, 12.0)
	assert_eq(d, 5.0)


func test_follow_leaves_1_over_e_of_a_step_after_0_10_s_at_30_60_and_144_hz() -> void:
	for hz: int in [30, 60, 144]:
		var dt: float = 1.0 / float(hz)
		var pivot := Vector3.ZERO
		var goal := Vector3(1.0, 0.0, 0.0)
		var t: float = 0.0
		while t < 0.10 - 1e-9:
			var step: float = minf(dt, 0.10 - t)
			pivot = OrbitMath.follow(pivot, goal, step, 0.10)
			t += step
		assert_almost_eq(1.0 - pivot.x, exp(-1.0), 0.001, "%d Hz" % hz)


func test_follow_trails_by_0_45_m_at_a_steady_4_5_m_s() -> void:
	for hz: int in [30, 60, 144]:
		var dt: float = 1.0 / float(hz)
		var pivot := Vector3.ZERO
		var goal := Vector3.ZERO
		var before: float = 0.0
		var after: float = 0.0
		for i in range(hz * 3):
			goal.x += 4.5 * dt
			before = goal.x - pivot.x
			pivot = OrbitMath.follow(pivot, goal, dt, 0.10)
			after = goal.x - pivot.x
		# The target moves continuously, so measure against its mid-frame position.
		assert_almost_eq(0.5 * (before + after), 0.45, 0.02, "%d Hz" % hz)


func test_rotation_applies_on_the_same_frame() -> void:
	var before: Vector3 = OrbitMath.camera_offset(0.0, 20.0, 8.0)
	var a: Vector2 = _angles(0.0, 20.0, 200.0, 0.0)
	var after: Vector3 = OrbitMath.camera_offset(a.x, a.y, 8.0)
	assert_gt(before.distance_to(after), 1.0, "one call to the maths moves the camera at once, no smoothing")
	assert_almost_eq(after.length(), 8.0, 0.0001)
	assert_gt(before.y, 0.0, "positive pitch puts the camera above the pivot")
	assert_almost_eq(before.x, 0.0, 0.0001)
	assert_gt(before.z, 0.0, "yaw 0: camera sits at +Z, looking along -Z")


func test_arm_is_shortened_by_rock_even_closer_than_the_2_m_minimum() -> void:
	assert_eq(OrbitMath.arm_length(1.0, 8.0, 2.0), 1.0, "rock wins over the 2 m minimum")
	assert_eq(OrbitMath.arm_length(0.1, 8.0, 2.0), 0.1)
	assert_eq(OrbitMath.arm_length(3.0, 8.0, 2.0), 3.0)
	assert_eq(OrbitMath.arm_length(20.0, 8.0, 2.0), 8.0)


func test_aim_eases_fov_to_50_and_back_to_70() -> void:
	var f: float = 70.0
	for i in range(20):
		f = OrbitMath.ease_linear(f, 50.0, 20.0, 0.10, 1.0 / 60.0)
	assert_eq(f, 50.0)
	for i in range(20):
		f = OrbitMath.ease_linear(f, 70.0, 20.0, 0.10, 1.0 / 60.0)
	assert_eq(f, 70.0)
	var mid: float = OrbitMath.ease_linear(70.0, 50.0, 20.0, 0.10, 1.0 / 60.0)
	assert_true(mid < 70.0 and mid > 50.0, "eases rather than jumping")


func _recenter(idle: float, speed: float, delta: float = 1.0 / 60.0, min_speed: float = 0.5) -> float:
	return OrbitMath.recenter_step(90.0, 0.0, idle, speed, delta, 1.5, 90.0, min_speed)


func test_recentre_waits_1_5_s_of_mouse_idle() -> void:
	assert_eq(_recenter(1.49, 4.5), 90.0)
	assert_lt(_recenter(1.5, 4.5), 90.0)


func test_mouse_motion_restarts_the_recentre_timer() -> void:
	var yaw: float = 90.0
	var idle: float = 1.6
	assert_lt(OrbitMath.recenter_step(yaw, 0.0, idle, 4.5, 1.0 / 60.0, 1.5, 90.0, 0.5), 90.0, "turning after 1.6 s idle")
	# Mouse motion sets idle back to 0; one second later it is still waiting.
	idle = 0.0
	for i in range(60):
		idle += 1.0 / 60.0
		yaw = OrbitMath.recenter_step(yaw, 0.0, idle, 4.5, 1.0 / 60.0, 1.5, 90.0, 0.5)
	assert_eq(yaw, 90.0, "1 s after the restart nothing has turned")


func test_recentre_turns_toward_behind_the_target_at_its_rate() -> void:
	assert_almost_eq(_recenter(2.0, 4.5, 0.1), 81.0, 0.0001, "90 deg/s for 0.1 s is 9 deg")
	var yaw: float = OrbitMath.recenter_step(-170.0, 170.0, 2.0, 4.5, 0.1, 1.5, 90.0, 0.5)
	assert_almost_eq(yaw, -179.0, 0.0001, "takes the short way across the wrap")
	assert_eq(OrbitMath.recenter_step(2.0, 0.0, 2.0, 4.5, 0.1, 1.5, 90.0, 0.5), 0.0, "stops exactly on target")
	assert_almost_eq(OrbitMath.behind_yaw(Vector3(0.0, 0.0, -1.0)), 0.0, 0.0001)
	assert_almost_eq(absf(OrbitMath.behind_yaw(Vector3(0.0, 0.0, 1.0))), 180.0, 0.0001)
	assert_almost_eq(OrbitMath.behind_yaw(Vector3(-1.0, 0.0, 0.0)), 90.0, 0.0001)


func test_no_recentre_while_aiming() -> void:
	var held: float = OrbitMath.recenter_step(90.0, 0.0, 5.0, 4.5, 0.1, 1.5, 90.0, 0.5, true)
	assert_eq(held, 90.0)
	var released: float = OrbitMath.recenter_step(90.0, 0.0, 5.0, 4.5, 0.1, 1.5, 90.0, 0.5, false)
	assert_lt(released, 90.0)


func test_mouse_event_turns_by_physical_pixels_not_content_scaled_ones() -> void:
	var event := InputEventMouseMotion.new()
	event.screen_relative = Vector2(100.0, 0.0)
	event.relative = Vector2(67.0, 0.0)
	var a: Vector2 = OrbitMath.motion_to_angles(event, 0.0, 20.0, SENS, false, -20.0, 60.0)
	assert_almost_eq(a.x, -15.0, 0.0001, "100 physical px = 15 deg of yaw (right turns the view right)")


func test_no_recentre_while_the_target_stands_still() -> void:
	assert_eq(_recenter(5.0, 0.0), 90.0)
	assert_eq(_recenter(5.0, 0.5), 90.0, "at the threshold it still does not turn")
	assert_lt(_recenter(5.0, 0.0, 1.0 / 60.0, 0.0), 90.0, "min speed 0 recentres while standing")


func test_shake_never_exceeds_its_amplitude_and_ends_after_its_duration() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var peak: float = 0.0
	for i in range(9):
		var t: float = float(i) / 60.0
		var o: Vector2 = OrbitMath.shake_offset(rng.randf_range(-1, 1), rng.randf_range(-1, 1), t, 0.15, 0.15)
		peak = maxf(peak, maxf(absf(o.x), absf(o.y)))
	assert_lte(peak, 0.15)
	assert_gt(peak, 0.0)
	assert_eq(OrbitMath.shake_offset(1.0, 1.0, 0.15, 0.15, 0.15), Vector2.ZERO)
	assert_eq(OrbitMath.shake_offset(1.0, 1.0, 1.0, 0.15, 0.15), Vector2.ZERO)


func _foot_corners(foot: Vector3) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for sx: float in [-0.125, 0.125]:
		for sy: float in [-0.10, 0.10]:
			for sz: float in [-0.125, 0.125]:
				out.append(foot + Vector3(sx, sy, sz))
	return out


func _check_footprint(xs: Array[float], zs: Array[float], origin_h: float, label: String) -> void:
	var pivot := Vector3(0.0, 1.5, 0.0)
	var worst_px: float = INF
	var failures: int = 0
	for pitch in range(-10, 61, 5):
		for yaw in range(0, 360, 15):
			var cam: Transform3D = OrbitMath.camera_transform(pivot, float(yaw), float(pitch), 8.0)
			for fx: float in xs:
				for fz: float in zs:
					var centre := Vector3(fx, -origin_h + 0.10, fz)
					var lo: float = INF
					var hi: float = -INF
					var in_frame: bool = true
					for c: Vector3 in _foot_corners(centre):
						var p: Vector2 = OrbitMath.project(c, cam, 70.0, 1920.0, 1080.0)
						lo = minf(lo, p.y)
						hi = maxf(hi, p.y)
						if p.x < 0.0 or p.x > 1920.0 or p.y < 0.0 or p.y > 1080.0:
							in_frame = false
					worst_px = minf(worst_px, hi - lo)
					if not in_frame or hi - lo < 12.0:
						failures += 1
	assert_eq(failures, 0, "%s: feet out of frame or under 12 px tall" % label)
	gut.p("%s: smallest foot extent %.1f px" % [label, worst_px])


func test_every_foot_is_in_frame_and_at_least_12_px_tall_at_1080p() -> void:
	_check_footprint(STRIDER_FEET_X, STRIDER_FEET_Z, 0.96, "strider")
	_check_footprint(CRAWLER_FEET_X, CRAWLER_FEET_Z, 0.36, "crawler")


func test_rig_exposes_its_camera_after_ready() -> void:
	var rig: OrbitCamera = load("res://scenes/camera/orbit_camera.tscn").instantiate()
	rig.capture_mouse = false
	add_child_autofree(rig)
	assert_not_null(rig.camera(), "camera() hands out the Camera3D at the end of the arm")
	assert_true(rig.camera() is Camera3D)



func _rig() -> OrbitCamera:
	var rig: OrbitCamera = load("res://scenes/camera/orbit_camera.tscn").instantiate()
	rig.capture_mouse = false
	add_child_autofree(rig)
	rig.set_angles(0.0, 20.0)
	return rig


func _ramp(deg: float, count: int, spacing: float = 0.75) -> PackedFloat32Array:
	var h := PackedFloat32Array()
	for i in range(1, count + 1):
		h.append(tan(deg_to_rad(deg)) * spacing * float(i))
	return h


func test_descent_floor_is_off_at_or_below_25_deg() -> void:
	assert_eq(OrbitCamera.floor_pitch(25.0, 25.0, 5.0, 60.0), -INF, "25 deg: no floor")
	assert_eq(OrbitCamera.floor_pitch(0.0, 25.0, 5.0, 60.0), -INF, "flat: no floor")


func test_descent_floor_is_slope_minus_5_above_25_deg_and_capped() -> void:
	assert_almost_eq(OrbitCamera.floor_pitch(40.0, 25.0, 5.0, 60.0), 35.0, 0.0001)
	assert_eq(OrbitCamera.floor_pitch(80.0, 25.0, 5.0, 60.0), 60.0, "capped at pitch_max")


func test_a_40_deg_ramp_gives_40() -> void:
	assert_almost_eq(OrbitCamera.slope_from_heights(0.0, _ramp(40.0, 6), 0.75), 40.0, 0.001)


func test_one_steep_step_between_flat_samples_gives_no_floor() -> void:
	var step := PackedFloat32Array([0.0, 0.0, 1.5, 1.5, 1.5, 1.5])
	assert_eq(OrbitCamera.slope_from_heights(0.0, step, 0.75), 0.0, "a 1.5 m block is one steep segment")
	var big := PackedFloat32Array([1.5, 1.5, 1.5])
	assert_eq(OrbitCamera.slope_from_heights(0.0, big, 0.75), 0.0, "a wall right behind: one segment")


func test_two_steep_segments_that_rise_under_1_2_m_give_no_floor() -> void:
	var low := PackedFloat32Array([0.4, 0.8, 0.8])
	assert_eq(OrbitCamera.slope_from_heights(0.0, low, 0.75), 0.0, "0.8 m total is a step-up, not a slope")


func test_the_steepest_qualifying_run_wins_and_downhill_is_zero() -> void:
	var h := PackedFloat32Array([0.0, 0.5, 1.0, 1.5, 1.5, 3.0, 4.5])
	# first run: 3 segments of 33.7 deg (rise 1.5); second run: 2 segments of 63.4 deg (rise 3.0)
	assert_almost_eq(OrbitCamera.slope_from_heights(0.0, h, 0.75), 63.43, 0.05)
	assert_eq(OrbitCamera.slope_from_heights(0.0, _ramp(-40.0, 6), 0.75), 0.0)


func test_a_drop_ahead_counts_like_a_rise_behind() -> void:
	var drop := PackedFloat32Array([0.0, -0.63, -1.26])
	var negated := PackedFloat32Array()
	for y in drop:
		negated.append(-y)
	assert_gt(OrbitCamera.slope_from_heights(-0.0, negated, 0.75), 25.0)


func test_ease_floor_runs_in_over_about_0_45_s_per_20_deg_and_out_over_0_8_s() -> void:
	var rig: OrbitCamera = _rig()
	for i in range(14):
		rig._ease_floor(1.0 / 60.0, 40.0)
	rig._apply_rotation()
	assert_gt(rig.shown_pitch_deg, 20.0, "easing in")
	assert_lt(rig.shown_pitch_deg, 35.0, "not there after 0.23 s")
	for i in range(40):
		rig._ease_floor(1.0 / 60.0, 40.0)
	rig._apply_rotation()
	assert_almost_eq(rig.shown_pitch_deg, 35.0, 0.0001, "held at slope - 5")
	assert_eq(rig.pitch_deg, 20.0, "player pitch untouched")
	for i in range(30):
		rig._ease_floor(1.0 / 60.0, 0.0)
	rig._apply_rotation()
	assert_gt(rig.shown_pitch_deg, 20.0, "out is slower: still lifted after 0.5 s")
	for i in range(40):
		rig._ease_floor(1.0 / 60.0, 0.0)
	rig._apply_rotation()
	assert_almost_eq(rig.shown_pitch_deg, 20.0, 0.0001, "back to the player's pitch")


func test_mouse_flick_above_the_floor_shows_at_once_without_overshoot() -> void:
	var rig: OrbitCamera = _rig()
	for i in range(60):
		rig._ease_floor(1.0 / 60.0, 40.0)
	rig._apply_rotation()
	rig.orbit(0.0, 133.4)
	assert_almost_eq(rig.pitch_deg, 40.0, 0.01)
	assert_almost_eq(rig.shown_pitch_deg, 40.0, 0.01, "above the floor: the player's pitch, immediately")
	for i in range(60):
		rig._ease_floor(1.0 / 60.0, 40.0)
		rig._apply_rotation()
		assert_lt(rig.shown_pitch_deg, 40.5, "never overshoots")


func test_floor_lets_go_while_aim_is_held() -> void:
	var rig: OrbitCamera = _rig()
	for i in range(60):
		rig._ease_floor(1.0 / 60.0, 40.0)
	Input.action_press("aim")
	for i in range(120):
		rig._ease_floor(1.0 / 60.0, 40.0)
	Input.action_release("aim")
	rig._apply_rotation()
	assert_almost_eq(rig.shown_pitch_deg, 20.0, 0.0001)


func test_snap_without_ground_clears_a_stale_floor() -> void:
	var rig: OrbitCamera = _rig()
	for i in range(60):
		rig._ease_floor(1.0 / 60.0, 40.0)
	var holder := Node3D.new()
	add_child_autofree(holder)
	rig.target = holder
	rig.snap()
	assert_almost_eq(rig.shown_pitch_deg, 20.0, 0.0001, "no ground under the target: no floor")


func test_sample_spacing_is_clamped_so_the_measure_cannot_hang() -> void:
	var rig: OrbitCamera = _rig()
	rig.slope_sample_spacing = 0.0
	var holder := Node3D.new()
	add_child_autofree(holder)
	rig.target = holder
	rig._measure_slopes()
	assert_eq(rig.slope_behind_deg, 0.0)


func test_the_steepest_full_segment_is_used_not_the_mean() -> void:
	# a partial segment at the corner (0.4 m rise, 28 deg) followed by two full 40 deg segments
	var h := PackedFloat32Array([0.4, 1.029, 1.658])
	assert_almost_eq(OrbitCamera.slope_from_heights(0.0, h, 0.75), 40.0, 0.05)


func test_a_slope_below_the_sight_line_gives_no_floor() -> void:
	var ramp: PackedFloat32Array = _ramp(30.0, 4)
	assert_almost_eq(OrbitCamera.slope_from_heights(0.0, ramp, 0.75, 25.0, 2, 1.2, 0.4), 30.0, 0.001, "above")
	assert_eq(OrbitCamera.slope_from_heights(0.0, ramp, 0.75, 25.0, 2, 1.2, 0.8), 0.0, "below the line: feet seen")


func test_a_missed_ahead_ray_falls_back_to_minus_base() -> void:
	assert_eq(OrbitCamera.sample_or_base(NAN, 2.0), 2.0)
	assert_eq(OrbitCamera.sample_or_base(1.0, 2.0), 1.0)
	var base: float = 3.0
	var ahead := PackedFloat32Array([-OrbitCamera.sample_or_base(NAN, base), -OrbitCamera.sample_or_base(NAN, base)])
	assert_eq(OrbitCamera.slope_from_heights(-base, ahead, 0.75), 0.0, "a missed ray is level, not a cliff")


func test_a_wobbling_measurement_moves_the_shown_pitch_under_half_a_degree_per_frame() -> void:
	var rig: OrbitCamera = _rig()
	for i in range(60):
		rig._ease_floor(1.0 / 60.0, 40.0)
	rig._apply_rotation()
	var last: float = rig.shown_pitch_deg
	var worst: float = 0.0
	for slope: float in [37.9, 40.0, 37.9, 40.0]:
		for i in range(45):
			rig._ease_floor(1.0 / 60.0, slope)
			rig._apply_rotation()
			worst = maxf(worst, absf(rig.shown_pitch_deg - last))
			last = rig.shown_pitch_deg
	assert_lt(worst, 0.5, "target eases at 20 deg/s = 0.33 deg per frame")


func test_the_mouse_drops_to_0_10_deg_per_px_while_aim_is_held() -> void:
	assert_eq(OrbitCamera.look_sensitivity(0.15, 0.10, false), 0.15)
	assert_eq(OrbitCamera.look_sensitivity(0.15, 0.10, true), 0.10)
	var cam: Node = load("res://scenes/camera/orbit_camera.tscn").instantiate()
	assert_eq(cam.sensitivity_deg_per_px, 0.15, "the normal value is unchanged")
	assert_eq(cam.aim_sensitivity_deg_per_px, 0.10)
	cam.free()
	var turned: Vector2 = OrbitMath.mouse_to_angles(0.0, 0.0, 100.0, 0.0, OrbitCamera.look_sensitivity(0.15, 0.10, true), false, -20.0, 60.0)
	assert_almost_eq(turned.x, -10.0, 0.0001, "100 px is 10 deg with aim held")


func test_recentring_pauses_while_aim_or_fire_is_held() -> void:
	assert_false(OrbitCamera.recenter_paused(false, false))
	assert_true(OrbitCamera.recenter_paused(true, false))
	assert_true(OrbitCamera.recenter_paused(false, true))
	assert_true(OrbitCamera.recenter_paused(true, true))
	var held: float = OrbitMath.recenter_step(90.0, 0.0, 5.0, 4.5, 0.1, 1.5, 90.0, 0.5, OrbitCamera.recenter_paused(false, true))
	assert_eq(held, 90.0, "fire held: the camera stays where the mouse put it")
