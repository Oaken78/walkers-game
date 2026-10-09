class_name AimRange
extends Node3D
## The aim range (T06): flat ground, a reference build, the orbit camera, the weapon rig, the aim marks and stand-in
## targets (0.6 m sphere hurtbox, 45 HP, 0.06 s white flash). The scenario aim_range calls the helpers below (the
## same style as GaitCourse and ValleyPockets), runs the checks and reads the read-only properties.
## World frame: the walker spawns at the origin facing -Z (yaw 0); `forward` means -Z, `right` means +X.

const GROUND_COLOR: Color = Color("CAB294")
const SKY_COLOR: Color = Color("90A092")
const SPAWN_Y: float = 1.0
const START_PITCH_DEG: float = 20.0
## Risk 8: the target sits 15 m out (drone orbit radius); the heading is "on" it within the target's angular radius.
const HEADING_TARGET_M: float = 15.0
const HEADING_RUN_TICKS: int = 150
## The scripted turner lets go this far before the bearing, plus its stopping distance (yaw rate x ramp / 2).
const STOP_MARGIN_DEG: float = 0.5
const YAW_RAMP_S: float = 0.1
## Risk 9: a target 12 m out on the heading and 6 m above the ground, camera pitch -20.
const RISK9_FORWARD_M: float = 12.0
const RISK9_UP_M: float = 6.0
const RISK9_PITCH_DEG: float = -20.0
## Screen numbers in reports are projected at this size.
const REF_WIDTH: float = 1920.0
const REF_HEIGHT: float = 1080.0

## Checks, since the last reset_checks().
## Largest angle between a barrel's yaw and the bearing from its drawn muzzle to Q, and between Q's bearing from the
## body origin and the walker's heading (both are checked on every tick).
var yaw_err_max_deg: float = 0.0
var q_bearing_err_max_deg: float = 0.0
## Largest angle a barrel's yaw is off the walker's heading: the convergence from the socket offset.
var convergence_max_deg: float = 0.0
## Largest angle between a shot's horizontal direction and the bearing from its muzzle to Q on the tick it left (spread 0).
var shot_yaw_err_max_deg: float = 0.0
## Shots fired with the barrel settled on its wanted elevation (inside the limits) and their largest angle to P. A shot
## fired while the barrel still slews toward a new P is counted in shots_unsettled and not measured.
var shots_checked: int = 0
var shots_unsettled: int = 0
var shot_err_max_deg: float = 0.0
var shot_frames: PackedInt32Array = PackedInt32Array()
## Risk 8: seconds from the first turn input to the heading being on the target, then the error after the run.
var heading_time_s: float = -1.0
var heading_final_error_deg: float = 0.0
var heading_run_done: bool = false
## Risk 9 (measure_risk9).
var risk9_ray_gap_m: float = 0.0
var risk9_dot_on_target: bool = false
var risk9_target_to_dot_px: float = INF
var risk9_target_radius_px: float = 0.0
var risk9_dot_inside_target: bool = false
var risk9_ring_to_dot_px: float = INF
var risk9_chassis_in_frame: bool = false
var risk9_arm_m: float = 0.0
var risk9_chassis_px: Vector2 = Vector2.ZERO
## The camera pitch (deg) that puts the dot on the target in begin_risk9_reach().
var risk9_pitch_deg: float = 0.0

## The at-limit ring rule (GDD 12), counted per physics tick since begin_dash_watch(): ticks watched, ticks with a
## limited aim, ticks with the ring dashed (rig flag) and frames with the marks dashed.
var watch_ticks: int = 0
var watch_limited: int = 0
var watch_dashed: int = 0
var watch_marks_dashed: int = 0
## Ticks from pressing `fire` to the ring being dashed, and from releasing it to the ring being solid again.
var dash_on_latency_ticks: int = -1
var dash_off_latency_ticks: int = -1
## Hit flash runs (ticks the ring stroke stayed flashed), since reset_checks().
var flash_runs: int = 0
var flash_run_min_ticks: int = 0
var flash_run_max_ticks: int = 0
## True while the tree is frozen by freeze_on_hit() (for the hit flash shot).
var frozen: bool = false

## The share of watched ticks with a limited aim.
var limited_share: float:
	get:
		return float(watch_limited) / float(maxi(watch_ticks, 1))
## The ring flash of the last target's own hurtbox, in seconds left.
var target_flash_s: float:
	get:
		return _last_target.flash_left_s if _last_target != null and is_instance_valid(_last_target) else 0.0
## Distance between cannon 0's drawn (interpolated) position and the transform it was given on the last tick.
var barrel_interp_gap_m: float:
	get:
		return (_rig.barrel_drawn_transform(0).origin - _rig.barrel_transform(0).origin).length()

## Fixed-length gaps between consecutive shots, in physics ticks.
var gap_count: int:
	get:
		return maxi(shot_frames.size() - 1, 0)
var gap_min_ticks: int:
	get:
		return _gap_extreme(true)
var gap_max_ticks: int:
	get:
		return _gap_extreme(false)
var gap_mean_s: float:
	get:
		if shot_frames.size() < 2:
			return 0.0
		var span: int = shot_frames[shot_frames.size() - 1] - shot_frames[0]
		return float(span) / float(shot_frames.size() - 1) / float(Engine.physics_ticks_per_second)
var target_hits: int:
	get:
		return _last_target.hits() if _last_target != null and is_instance_valid(_last_target) else 0
var target_hp: float:
	get:
		return _last_target.health.hp if _last_target != null and is_instance_valid(_last_target) else 0.0
var pool_live: int:
	get:
		return _rig.pool.live
var pool_refused: int:
	get:
		return _rig.pool.refused_count
var rig_p99_ms: float:
	get:
		return _p99(_rig_ms)
var pool_p99_ms: float:
	get:
		return _p99(_pool_ms)
var cost_samples: int:
	get:
		return _rig_ms.size()

var _targets: Array[AimTarget] = []
var _slabs: Array[Hurtbox] = []
var _last_target: AimTarget
var _fire_event_frame: int = -1
var _fire_event_pressed: bool = false
var _flash_run: int = 0
var _freeze_pending: bool = false
var _watching: bool = false
var _heading_active: bool = false
var _heading_bearing_deg: float = 0.0
var _heading_ticks: int = 0
var _cost_on: bool = false
var _rig_ms: PackedFloat32Array = PackedFloat32Array()
var _pool_ms: PackedFloat32Array = PackedFloat32Array()

@onready var _walker: WalkerBody = %Walker
@onready var _orbit: OrbitCamera = %OrbitCamera
@onready var _rig: WeaponRig = %WeaponRig
@onready var _marks: AimMarks = %AimMarks


func _ready() -> void:
	# After the walker (0), the rig (100) and the pool (200): reads this tick's results.
	process_physics_priority = 300
	_build_world()
	_rig.fired.connect(_on_fired)


func _process(_delta: float) -> void:
	if _freeze_pending:
		# The flash was set in the physics tick; let the marks pick it up, then stop the world on it.
		_freeze_pending = false
		_marks.refresh()
		_marks.queue_redraw()
		frozen = true
		get_tree().paused = true


func _physics_process(delta: float) -> void:
	for i in _rig.cannon_count():
		yaw_err_max_deg = maxf(yaw_err_max_deg, _rig.yaw_error_deg(i))
		convergence_max_deg = maxf(convergence_max_deg, _rig.convergence_deg(i))
	if _rig.cannon_count() > 0:
		q_bearing_err_max_deg = maxf(q_bearing_err_max_deg, _rig.q_bearing_error_deg)
	_watch_ring()
	if _heading_active:
		_heading_tick(delta)
	if _cost_on:
		_rig_ms.append(float(_rig.tick_usec) / 1000.0)
		_pool_ms.append(float(_rig.pool.step_usec) / 1000.0)


# --- Scenario helpers: setup -------------------------------------------------------------------------------------


## "scout", "strider" or "crawler".
func use_build(build_name: String) -> void:
	var build: WalkerBuild
	match build_name:
		"scout":
			build = WalkerBuild.scout()
		"strider":
			build = WalkerBuild.strider()
		"crawler":
			build = WalkerBuild.crawler()
		_:
			push_error("AimRange.use_build: unknown build %s" % build_name)
			return
	_walker.apply_build(build)


## The walker at the origin facing `yaw_deg` (0 = -Z, positive turns left), the camera behind it, no targets, fresh checks.
func spawn(yaw_deg: float = 0.0, pitch_deg: float = START_PITCH_DEG) -> void:
	clear_targets()
	_rig.pool.clear()
	_walker.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(0.0, SPAWN_Y, 0.0)))
	_walker.reset_physics_interpolation()
	_orbit.snap()
	_orbit.set_angles(yaw_deg, pitch_deg)
	reset_checks()


func reset_checks() -> void:
	yaw_err_max_deg = 0.0
	q_bearing_err_max_deg = 0.0
	convergence_max_deg = 0.0
	shot_yaw_err_max_deg = 0.0
	shots_checked = 0
	shots_unsettled = 0
	flash_runs = 0
	flash_run_min_ticks = 0
	flash_run_max_ticks = 0
	_flash_run = 0
	shot_err_max_deg = 0.0
	shot_frames = PackedInt32Array()
	_rig_ms = PackedFloat32Array()
	_pool_ms = PackedFloat32Array()


func set_spread(degrees: float) -> void:
	_rig.spread_override_deg = degrees


## A target `forward` metres along -Z, `up` metres above the ground and `right` metres along +X from the origin.
func add_target(forward_m: float, up_m: float, right_m: float = 0.0) -> void:
	_add_target_at(Vector3(right_m, up_m, -forward_m))


## A flat enemy hurtbox on the ground (6 m square, 0.1 m thick) centred `forward` metres along -Z: a place where the
## dot is on an enemy while the guns are at their lower limit.
func add_slab(forward_m: float) -> void:
	var slab := Hurtbox.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(6.0, 0.1, 6.0)
	shape.shape = box
	slab.add_child(shape)
	add_child(slab)
	slab.global_position = Vector3(0.0, 0.05, -forward_m)
	_slabs.append(slab)


func clear_targets() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	_last_target = null
	for slab in _slabs:
		if is_instance_valid(slab):
			slab.queue_free()
	_slabs.clear()


# --- Scenario helpers: scripted input ---------------------------------------------------------------------------


func hold_action(action: String, pressed: bool) -> void:
	if action == "fire":
		_fire_event_frame = Engine.get_physics_frames()
		_fire_event_pressed = pressed
		if pressed:
			dash_on_latency_ticks = -1
		else:
			dash_off_latency_ticks = -1
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Mouse motion in pixels, through the camera's own entry point (the same one the real mouse uses).
func mouse_motion(dx_px: float, dy_px: float) -> void:
	_orbit.orbit(dx_px, dy_px)


func set_camera(yaw_deg: float, pitch_deg: float) -> void:
	_orbit.set_angles(yaw_deg, pitch_deg)


## Points the camera's centre ray at the last target (what a mouse flick onto it would do).
func look_at_target() -> void:
	if _last_target == null:
		return
	var to: Vector3 = _last_target.global_position - (_walker.global_position + _orbit.target_offset)
	var flat: float = Vector2(to.x, to.z).length()
	_orbit.set_angles(rad_to_deg(atan2(-to.x, -to.z)), -rad_to_deg(atan2(to.y, flat)))


# --- Scenario helpers: checks ---------------------------------------------------------------------------------


## Risk 8: turn from the current heading onto a target `degrees` to the left (no `aim`), then hold it there.
func begin_heading_run(degrees: float) -> void:
	_heading_bearing_deg = rad_to_deg(_walker.yaw_radians()) + degrees
	_heading_ticks = 0
	heading_time_s = -1.0
	heading_final_error_deg = INF
	heading_run_done = false
	var bearing: float = deg_to_rad(_heading_bearing_deg)
	var spot: Vector3 = _walker.global_position + AimMath.heading(bearing) * HEADING_TARGET_M
	clear_targets()
	_add_target_at(Vector3(spot.x, 2.0, spot.z))
	_heading_active = true
	hold_action("turn_left" if degrees > 0.0 else "turn_right", true)


func heading_cone_deg() -> float:
	return rad_to_deg(asin(AimTarget.RADIUS_M / HEADING_TARGET_M))


## Risk 9: the target 12 m out and 6 m up, the camera at pitch -20 behind the walker.
func begin_risk9() -> void:
	clear_targets()
	add_target(RISK9_FORWARD_M, RISK9_UP_M)
	_orbit.set_angles(rad_to_deg(_walker.yaw_radians()), RISK9_PITCH_DEG)


## Risk 9 reach: the same target, with the camera pitched (inside the -20..-10 aim-up range) so that its centre ray goes
## through the target's centre. The pitch comes from the geometry, then measure_risk9() checks that the dot really is on
## the target.
func begin_risk9_reach() -> void:
	clear_targets()
	add_target(RISK9_FORWARD_M, RISK9_UP_M)
	look_at_target()
	risk9_pitch_deg = _orbit.pitch_deg


## Reads the risk 9 numbers once the camera has settled. Screen numbers are projected at 1920x1080 (the shot size
## of GDD 12), whatever the window is, so headless and windowed runs agree.
func measure_risk9(label: String = "scout") -> void:
	var camera: Camera3D = _orbit.camera()
	var target: Vector3 = _last_target.global_position
	var pivot: Vector3 = _orbit.global_position
	var look: Vector3 = -camera.global_basis.z
	var flat_look: float = Vector2(look.x, look.z).length()
	var flat_to_target: float = Vector2(target.x - pivot.x, target.z - pivot.z).length()
	risk9_ray_gap_m = pivot.y + look.y / flat_look * flat_to_target - target.y
	risk9_dot_on_target = _rig.aim_on_enemy
	var centre := Vector2(REF_WIDTH, REF_HEIGHT) * 0.5
	var target_px: Vector2 = _project_ref(camera, target)
	risk9_target_to_dot_px = target_px.distance_to(centre)
	var depth: float = -(camera.global_transform.affine_inverse() * target).z
	var focal: float = 0.5 * REF_HEIGHT / tan(deg_to_rad(camera.fov) * 0.5)
	risk9_target_radius_px = focal * AimTarget.RADIUS_M / maxf(depth, 0.001)
	risk9_dot_inside_target = risk9_target_to_dot_px <= risk9_target_radius_px
	_marks.refresh()
	risk9_ring_to_dot_px = _marks.ring_to_dot_px
	risk9_arm_m = _orbit.arm_length
	risk9_chassis_in_frame = _chassis_in_frame(camera)
	risk9_chassis_px = _project_ref(camera, _walker.body_pose() * Vector3(0.0, 0.3, 0.0))
	print(
		(
			"RISK9 %s pitch=%.2f shown=%.1f arm=%.2f ray_gap_m=%.2f dot_on_target=%s target_to_dot_px=%.1f target_radius_px=%.1f chassis_in_frame=%s chassis_px=(%.0f,%.0f) at 1920x1080, hits=%d"
			% [
				label, _orbit.pitch_deg, _orbit.shown_pitch_deg, risk9_arm_m, risk9_ray_gap_m, risk9_dot_on_target,
				risk9_target_to_dot_px, risk9_target_radius_px, risk9_chassis_in_frame, risk9_chassis_px.x,
				risk9_chassis_px.y, target_hits,
			]
		)
	)


## Cost runs: record the rig's and the pool's tick time (microseconds in the nodes, milliseconds here).
func begin_cost() -> void:
	_rig_ms = PackedFloat32Array()
	_pool_ms = PackedFloat32Array()
	_cost_on = true


func end_cost(label: String) -> void:
	_cost_on = false
	print(
		"COST %s rig_p99_ms=%.3f pool_p99_ms=%.3f samples=%d live=%d"
		% [label, rig_p99_ms, pool_p99_ms, cost_samples, pool_live]
	)


## Fills the pool with `count` bolts flying up and away (nothing for them to hit); returns how many were accepted.
func fill_pool(count: int) -> int:
	var accepted: int = 0
	var origin: Vector3 = _walker.global_position + Vector3(0.0, 3.0, 0.0)
	for i in count:
		var azimuth: float = TAU * float(i) / float(maxi(count, 1))
		var elevation: float = deg_to_rad(15.0 + float(i % 5) * 10.0)
		var direction := Vector3(sin(azimuth) * cos(elevation), sin(elevation), -cos(azimuth) * cos(elevation))
		if _rig.pool.fire(origin, direction, 60.0, 15.0, _walker):
			accepted += 1
	return accepted


## One log line of what the marks show (and where, in screen pixels) for pixel checks on the shots.
func log_marks(label: String) -> void:
	_marks.refresh()
	print(
		(
			"AIMMARKS %s size=(%.0f,%.0f) scale=%.3f dot=(%.1f,%.1f) ring=(%.1f,%.1f) ring=%s pip=%s dot_shown=%s dashed=%s thick=%s chevron=%s chevron_at=(%.1f,%.1f) d=%.1f h=%.1f limited=%s held=%s elev=%.1f wanted=%.1f"
			% [
				label, _marks.view_size.x, _marks.view_size.y, _marks.ui_scale, _marks.dot_screen.x, _marks.dot_screen.y,
				_marks.ring_screen.x, _marks.ring_screen.y, _marks.ring_visible, _marks.pip_visible,
				_marks.dot_visible, _marks.dashed, _marks.thick, _marks.chevron_visible, _marks.chevron_screen.x,
				_marks.chevron_screen.y, _rig.aim_range_m, _rig.aim_height_m, _rig.limited, _rig.held_off_heading,
				_rig.elevation_deg(0), _rig.wanted_elevation_deg(0),
			]
		)
	)


func log_checks(label: String) -> void:
	print(
		(
			"AIMCHECK %s flash_runs=%d flash_ticks=%d..%d dash_on=%d dash_off=%d yaw_err_max_deg=%.4f q_bearing_err_max_deg=%.4f convergence_max_deg=%.2f shot_yaw_err_max_deg=%.4f shots=%d unsettled=%d shot_err_max_deg=%.4f gaps=%d gap_min=%d gap_max=%d gap_mean_s=%.4f hits=%d heading_time_s=%.3f heading_final_err_deg=%.2f spread=%.2f"
			% [
				label, flash_runs, flash_run_min_ticks, flash_run_max_ticks, dash_on_latency_ticks,
				dash_off_latency_ticks, yaw_err_max_deg, q_bearing_err_max_deg, convergence_max_deg, shot_yaw_err_max_deg,
				shots_checked, shots_unsettled,
				shot_err_max_deg, gap_count, gap_min_ticks,
				gap_max_ticks, gap_mean_s, target_hits, heading_time_s, heading_final_error_deg,
				_rig.spread_deg(),
			]
		)
	)


## The at-limit ring rule: count ticks with a limited aim and ticks with the ring dashed from now on.
func begin_dash_watch() -> void:
	watch_ticks = 0
	watch_limited = 0
	watch_dashed = 0
	watch_marks_dashed = 0
	_watching = true


func end_dash_watch(label: String) -> void:
	_watching = false
	print(
		"DASHWATCH %s ticks=%d limited=%d (%.1f %%) ring_dashed=%d marks_dashed_frames=%d"
		% [label, watch_ticks, watch_limited, limited_share * 100.0, watch_dashed, watch_marks_dashed]
	)


## For the hit flash shot: stop the whole tree (the harness keeps running) on the frame after the first hit lands.
func freeze_on_hit() -> void:
	frozen = false
	_freeze_pending = false
	_rig.pool.impacted.connect(_freeze_once, CONNECT_ONE_SHOT)


func unfreeze() -> void:
	get_tree().paused = false
	frozen = false


## Moves the walker far away in one step (a teleport), to check that nothing is drawn streaking after it.
func jump_to(x: float, z: float) -> void:
	_walker.teleport(Transform3D(Basis(Vector3.UP, _walker.yaw_radians()), Vector3(x, SPAWN_Y, z)))
	_orbit.snap()


# --- Internals -------------------------------------------------------------------------------------------------


func _heading_tick(delta: float) -> void:
	_heading_ticks += 1
	var yaw_deg: float = rad_to_deg(_walker.yaw_radians())
	var error: float = wrapf(_heading_bearing_deg - yaw_deg, -180.0, 180.0)
	if heading_time_s < 0.0 and absf(error) <= heading_cone_deg():
		heading_time_s = float(_heading_ticks) * delta
	var stop: float = absf(_walker.yaw_rate_dps) * YAW_RAMP_S * 0.5 + STOP_MARGIN_DEG
	hold_action("turn_left", error > stop)
	hold_action("turn_right", error < -stop)
	heading_final_error_deg = absf(error)
	if _heading_ticks >= HEADING_RUN_TICKS:
		_heading_active = false
		heading_run_done = true
		hold_action("turn_left", false)
		hold_action("turn_right", false)


func _watch_ring() -> void:
	if _rig.cannon_count() == 0:
		return
	if _watching:
		watch_ticks += 1
		watch_limited += 1 if _rig.limited else 0
		watch_dashed += 1 if _rig.ring_dashed else 0
		watch_marks_dashed += 1 if _marks.dashed else 0
	var frames: int = Engine.get_physics_frames() - _fire_event_frame
	if _fire_event_frame >= 0:
		if _fire_event_pressed and dash_on_latency_ticks < 0 and _rig.ring_dashed:
			dash_on_latency_ticks = frames
		if not _fire_event_pressed and dash_off_latency_ticks < 0 and not _rig.ring_dashed:
			dash_off_latency_ticks = frames
	if _rig.ring_flashing:
		_flash_run += 1
	elif _flash_run > 0:
		flash_runs += 1
		flash_run_min_ticks = _flash_run if flash_runs == 1 else mini(flash_run_min_ticks, _flash_run)
		flash_run_max_ticks = maxi(flash_run_max_ticks, _flash_run)
		_flash_run = 0


func _freeze_once(_point: Vector3, collider: Object, _projectile: Projectile) -> void:
	if collider != null and collider.has_method("take_hit"):
		_freeze_pending = true
	else:
		_rig.pool.impacted.connect(_freeze_once, CONNECT_ONE_SHOT)


func _on_fired(weapon: int, origin: Vector3, direction: Vector3) -> void:
	shot_frames.append(Engine.get_physics_frames())
	var flat: Vector3 = Vector3(direction.x, 0.0, direction.z).normalized()
	var to_q: Vector3 = Vector3(_rig.convergence.x - origin.x, 0.0, _rig.convergence.z - origin.z).normalized()
	shot_yaw_err_max_deg = maxf(shot_yaw_err_max_deg, AimMath.angle_between_deg(flat, to_q))
	var wanted: float = AimMath.clamp_elevation(_rig.wanted_elevation_deg(weapon))
	if _rig.limited or absf(_rig.elevation_deg(weapon) - wanted) > 0.001:
		shots_unsettled += 1
		return
	shots_checked += 1
	shot_err_max_deg = maxf(shot_err_max_deg, AimMath.angle_between_deg(direction, _rig.aim_point - origin))


func _add_target_at(position_world: Vector3) -> void:
	var target := AimTarget.new()
	add_child(target)
	target.global_position = position_world
	_targets.append(target)
	_last_target = target


func _chassis_in_frame(camera: Camera3D) -> bool:
	var chassis: MeshInstance3D = _walker.get_node("Chassis")
	var box: BoxMesh = chassis.mesh as BoxMesh
	if box == null:
		return false
	var half: Vector3 = box.size * 0.5
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner: Vector3 = chassis.global_transform * (half * Vector3(sx, sy, sz))
				if not AimLayout.on_screen(_project_ref(camera, corner), Vector2(REF_WIDTH, REF_HEIGHT)):
					return false
	return true


## A world point at 1920x1080 pixels through the camera as it is now (INF when behind it).
func _project_ref(camera: Camera3D, point: Vector3) -> Vector2:
	return OrbitMath.project(point, camera.global_transform, camera.fov, REF_WIDTH, REF_HEIGHT)


func _gap_extreme(smallest: bool) -> int:
	var best: int = 0
	for i in range(1, shot_frames.size()):
		var gap: int = shot_frames[i] - shot_frames[i - 1]
		if i == 1 or (gap < best if smallest else gap > best):
			best = gap
	return best


func _p99(values: PackedFloat32Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = values.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(0.99 * float(sorted.size()))) - 1, 0, sorted.size() - 1)]


func _build_world() -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	var ground := StaticBody3D.new()
	ground.collision_layer = CombatLayers.WORLD
	ground.collision_mask = 0
	ground.position = Vector3(0.0, -1.0, 0.0)
	var shape := BoxShape3D.new()
	shape.size = Vector3(600.0, 2.0, 600.0)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	ground.add_child(collider)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	ground.add_child(piece)
	add_child(ground)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = SKY_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.75, 0.78, 0.82)
	environment.ambient_light_energy = 0.6
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60.0, 25.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	add_child(sun)
