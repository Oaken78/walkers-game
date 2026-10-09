extends GutTest
## Unit tests for scripts/camera/orbit_math.gd (pure maths of the orbit camera, GDD 5, 6, 10).

const SENS: float = 0.15
const STRIDER_FEET_X: Array[float] = [-2.4, 2.4]
const STRIDER_FEET_Z: Array[float] = [-2.0, 0.0, 2.0]
const CRAWLER_FEET_X: Array[float] = [-1.2, 1.2]
const CRAWLER_FEET_Z: Array[float] = [-1.2, -0.4, 0.4, 1.2]


func _angles(yaw: float, pitch: float, dx: float, dy: float, invert: bool = false) -> Vector2:
	return OrbitMath.mouse_to_angles(yaw, pitch, dx, dy, SENS, invert, -10.0, 60.0)


func test_mouse_turns_0_15_deg_per_pixel() -> void:
	var a: Vector2 = _angles(0.0, 20.0, 100.0, 0.0)
	assert_almost_eq(a.x, -15.0, 0.0001, "100 px right turns the view 15 deg right (yaw falls)")
	a = _angles(0.0, 20.0, 0.0, 100.0)
	assert_almost_eq(a.y, 35.0, 0.0001, "100 px down adds 15 deg of pitch")


func test_mouse_up_tilts_the_view_up_with_invert_y_off() -> void:
	var a: Vector2 = _angles(0.0, 20.0, 0.0, -40.0)
	assert_lt(a.y, 20.0, "mouse up lowers pitch toward -10, which looks up")
	var inverted: Vector2 = _angles(0.0, 20.0, 0.0, -40.0, true)
	assert_gt(inverted.y, 20.0, "invert-Y flips it")


func test_pitch_is_clamped_to_minus_10_and_60() -> void:
	assert_eq(_angles(0.0, 20.0, 0.0, -100000.0).y, -10.0)
	assert_eq(_angles(0.0, 20.0, 0.0, 100000.0).y, 60.0)


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
	var a: Vector2 = OrbitMath.motion_to_angles(event, 0.0, 20.0, SENS, false, -10.0, 60.0)
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

func _make_rig(target: Node3D) -> OrbitCamera:
	var rig: OrbitCamera = load("res://scenes/camera/orbit_camera.tscn").instantiate()
	rig.capture_mouse = false
	rig.target = target
	add_child_autofree(rig)
	return rig


func test_freed_target_is_survived() -> void:
	var target := Node3D.new()
	add_child(target)
	var rig: OrbitCamera = _make_rig(target)
	await wait_frames(2)
	target.free()
	await wait_frames(2)
	rig.snap()
	assert_true(is_instance_valid(rig), "rig still running after its target was freed")


func test_aim_point_ignores_things_between_the_camera_and_the_player() -> void:
	var target := Node3D.new()
	add_child_autofree(target)
	var rig: OrbitCamera = _make_rig(target)
	rig.set_angles(0.0, 0.0)
	var behind := _box(Vector3(0.0, 1.5, 4.0))
	var ahead := _box(Vector3(0.0, 1.5, -10.0))
	await wait_physics_frames(3)
	var hit: Vector3 = rig.aim_point(100.0)
	assert_almost_eq(hit.z, -9.0, 0.05, "hits the box ahead (face at z=-9), not the enemy behind the player")
	behind.free()
	ahead.free()


func _box(pos: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.0, 2.0)
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = pos
	return body
