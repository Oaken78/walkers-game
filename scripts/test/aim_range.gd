class_name AimRange
extends Node3D
## The aim range (T06, reworked in T22): flat ground, a reference build, the orbit camera, the weapon rig, the aim marks
## and stand-in targets (0.6 m sphere hurtbox, 45 HP, 0.06 s white flash). The scenario aim_range calls the helpers
## below (the same style as GaitCourse and ValleyPockets), runs the checks and reads the read-only properties.
## World frame: the walker spawns at the origin facing -Z (yaw 0); `forward` means -Z, `right` means +X.
## Most GDD 8.3 tests need an exact P, so the helpers can pin P with the rig's override (set_p_*): a pose in the
## chassis frame, recomputed every tick before the rig, or a fixed point in the world. clear_p() gives the camera back.

const GROUND_COLOR: Color = Color("CAB294")
const SKY_COLOR: Color = Color("90A092")
const SPAWN_Y: float = 1.0
const START_PITCH_DEG: float = 20.0
## Risk 9: a target 12 m out on the heading and 6 m above the ground, camera pitch -20.
const RISK9_FORWARD_M: float = 12.0
const RISK9_UP_M: float = 6.0
const RISK9_PITCH_DEG: float = -20.0
## Screen numbers in reports are projected at this size.
const REF_WIDTH: float = 1920.0
const REF_HEIGHT: float = 1080.0
## A cannon is "within" P at this error (GDD 8.3 tests).
const REACH_DEG: float = 1.0
## A shot is "settled" when its cannon is this close to the pose that puts its line on P.
const SETTLED_DEG: float = 0.05
const LAND_FIRE_TICK: int = 75
const LAND_END_TICK: int = 100

enum PMode { CAMERA, CHASSIS, WORLD }

## Per-tick checks since reset_checks().
## Largest angle between a barrel as set and the pose the rig says it has (chassis basis x pose), on every tick.
var barrel_err_max_deg: float = 0.0
## Shots fired with the cannon settled on P (live) and their largest angle to the line pivot -> P. A shot fired while
## the cannon still swings is counted in shots_unsettled and not measured.
var shots_checked: int = 0
var shots_unsettled: int = 0
var shot_err_max_deg: float = 0.0
var shot_frames: PackedInt32Array = PackedInt32Array()
var shots_by_weapon: Array[int] = [0, 0, 0]
## Hit flash runs (ticks the ring stroke stayed flashed), since reset_checks().
var flash_runs: int = 0
var flash_run_min_ticks: int = 0
var flash_run_max_ticks: int = 0
## Ticks watched, and ticks with any cannon gray (begin_watch).
var watch_ticks: int = 0
var watch_gray: int = 0

## The swing / assist / hold probe on cannon 0 (swing_to, begin_track).
var track_ticks: int = 0
var track_reach_ticks: int = -1
var track_err_max_deg: float = 0.0
var track_step_yaw_max_deg: float = 0.0
var track_step_pitch_max_deg: float = 0.0
var track_yaw_rate_max_dps: float = 0.0
## The probe's start-to-end angle (deg) from the pose at the start to the wanted pose at the end.
var track_swing_deg: float = 0.0

## The shot-lands-at-P probe (begin_land).
var land_done: bool = false
var land_shots: int = 0
var land_impacts: int = 0
var land_err_max_deg: float = 0.0

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

## True while the tree is frozen by freeze_on_hit() (for the hit flash shot).
var frozen: bool = false

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
var gray_share: float:
	get:
		return float(watch_gray) / float(maxi(watch_ticks, 1))
var target_hits: int:
	get:
		return _last_target.hits() if _last_target != null and is_instance_valid(_last_target) else 0
var target_hp: float:
	get:
		return _last_target.health.hp if _last_target != null and is_instance_valid(_last_target) else 0.0
var target_flash_s: float:
	get:
		return _last_target.flash_left_s if _last_target != null and is_instance_valid(_last_target) else 0.0
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
## Distance between cannon 0's drawn (interpolated) position and the transform it was given on the last tick.
var barrel_interp_gap_m: float:
	get:
		return (_rig.barrel_drawn_transform(0).origin - _rig.barrel_transform(0).origin).length()
var weapon0_flashing: bool:
	get:
		return _rig.weapon_flashing(0)
var cannons: int:
	get:
		return _rig.cannon_count()
var gray_cannons: int:
	get:
		return _rig.gray_count
## Cannon 0's chassis-frame pitch and yaw (deg) as of the last tick.
var pose_pitch_deg: float:
	get:
		return _rig.pose_deg(0).y
var pose_yaw_deg: float:
	get:
		return _rig.pose_deg(0).x
var wanted_yaw_deg: float:
	get:
		return _rig.wanted_pose_deg(0).x
var live_0: bool:
	get:
		return _rig.is_live(0)
var live_1: bool:
	get:
		return _rig.is_live(1)
var shots_w0: int:
	get:
		return shots_by_weapon[0]
var shots_w1: int:
	get:
		return shots_by_weapon[1]
var shots_total: int:
	get:
		return shots_by_weapon[0] + shots_by_weapon[1] + shots_by_weapon[2]
## Current error (deg) between cannon 0 and the pose that puts its line on P.
var pose_err_deg: float:
	get:
		return _pose_err(0)
# What the marks show (refresh them first with log_marks, or rely on the frame's own refresh).
var rings_visible: int:
	get:
		return _marks.visible_ring_count()
var chevrons: int:
	get:
		return _marks.chevron_count()
var rings_dashed: int:
	get:
		var n: int = 0
		for ring in _marks.rings:
			n += 1 if ring.dashed else 0
		return n
var rings_thick: int:
	get:
		var n: int = 0
		for ring in _marks.rings:
			n += 1 if ring.thick else 0
		return n
var rings_flashing: int:
	get:
		var n: int = 0
		for ring in _marks.rings:
			n += 1 if ring.flashing else 0
		return n
var ring_to_dot_max_px: float:
	get:
		var worst: float = 0.0
		for ring in _marks.rings:
			worst = maxf(worst, ring.to_dot_px)
		return worst
var ring_to_dot_min_px: float:
	get:
		var best: float = INF
		for ring in _marks.rings:
			best = minf(best, ring.to_dot_px)
		return best
## Largest angle (deg, seen from the pivot) between a ring's world point and where its weapon's line hits.
var ring_line_err_deg: float:
	get:
		var worst: float = 0.0
		_rig.update_reticle()
		for i in _rig.cannon_count():
			var pivot: Vector3 = _rig.pivot_position(i)
			var to_ring: Vector3 = _rig.reticle_point(i) - pivot
			var to_line: Vector3 = (_rig.weapon_state(i)["aim_point"] as Vector3) - pivot
			worst = maxf(worst, AimMath.angle_between_deg(to_ring, to_line))
		return worst

var _targets: Array[AimTarget] = []
var _slabs: Array[Hurtbox] = []
var _walls: Array[StaticBody3D] = []
var _last_target: AimTarget
var _flash_run: int = 0
var _freeze_pending: bool = false
var _watching: bool = false
var _cost_on: bool = false
var _rig_ms: PackedFloat32Array = PackedFloat32Array()
var _pool_ms: PackedFloat32Array = PackedFloat32Array()
var _p_mode: PMode = PMode.CAMERA
var _p_pose: Vector2 = Vector2.ZERO
var _p_dist: float = 50.0
var _p_point: Vector3 = Vector3.ZERO
var _tracking: bool = false
var _track_prev: Vector2 = Vector2.ZERO
var _land_tick: int = -1
var _land_p: Vector3 = Vector3.ZERO
var _land_p_set: bool = false
var _pre_rig_node: PreRig

@onready var _walker: WalkerBody = %Walker
@onready var _orbit: OrbitCamera = %OrbitCamera
@onready var _rig: WeaponRig = %WeaponRig
@onready var _marks: AimMarks = %AimMarks


## Runs before the rig (priority 50, after the walker): keeps a chassis-relative P on the chassis as it is this tick.
class PreRig:
	extends Node
	var host: AimRange

	func _physics_process(_delta: float) -> void:
		host._pre_rig()


func _ready() -> void:
	# After the walker (0), the rig (100) and the pool (200): reads this tick's results.
	process_physics_priority = 300
	_build_world()
	_pre_rig_node = PreRig.new()
	_pre_rig_node.host = self
	_pre_rig_node.process_physics_priority = 50
	add_child(_pre_rig_node)
	_rig.fired.connect(_on_fired)
	_rig.pool.impacted.connect(_on_impacted)


func _process(_delta: float) -> void:
	if _freeze_pending:
		# The flash was set in the physics tick; let the marks pick it up, then stop the world on it.
		_freeze_pending = false
		_marks.refresh()
		_marks.queue_redraw()
		frozen = true
		get_tree().paused = true


func _physics_process(_delta: float) -> void:
	if _rig.cannon_count() == 0:
		return
	var basis: Basis = _walker.body_pose().basis
	for i in _rig.cannon_count():
		var expected: Basis = AimMath.barrel_basis(basis, _rig.pose_deg(i))
		var actual: Basis = _rig.barrel_transform(i).basis
		barrel_err_max_deg = maxf(barrel_err_max_deg, AimMath.angle_between_deg(-expected.z, -actual.z))
		barrel_err_max_deg = maxf(barrel_err_max_deg, AimMath.angle_between_deg(expected.y, actual.y))
	if _watching:
		watch_ticks += 1
		watch_gray += 1 if _rig.gray_count > 0 else 0
	_track_tick()
	_land_tick_step()
	if _rig.weapon_flashing(0):
		_flash_run += 1
	elif _flash_run > 0:
		flash_runs += 1
		flash_run_min_ticks = _flash_run if flash_runs == 1 else mini(flash_run_min_ticks, _flash_run)
		flash_run_max_ticks = maxi(flash_run_max_ticks, _flash_run)
		_flash_run = 0
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
	clear_p()
	_stop_probes()
	_release_inputs()
	_rig.pool.clear()
	_walker.teleport(Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(0.0, SPAWN_Y, 0.0)))
	_walker.reset_physics_interpolation()
	_rig.reset_aim()
	_orbit.snap()
	_orbit.set_angles(yaw_deg, pitch_deg)
	reset_checks()


func reset_checks() -> void:
	barrel_err_max_deg = 0.0
	shots_checked = 0
	shots_unsettled = 0
	shot_err_max_deg = 0.0
	shot_frames = PackedInt32Array()
	shots_by_weapon = [0, 0, 0]
	flash_runs = 0
	flash_run_min_ticks = 0
	flash_run_max_ticks = 0
	_flash_run = 0
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


## A flat world wall (layer 1) 200 m wide, facing the walker, `distance_m` from the walker along camera yaw `yaw_deg`.
func add_wall(yaw_deg: float, distance_m: float) -> void:
	var wall := StaticBody3D.new()
	wall.collision_layer = CombatLayers.WORLD
	wall.collision_mask = 0
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 80.0, 0.5)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	wall.add_child(collider)
	add_child(wall)
	var dir: Vector3 = AimMath.heading(deg_to_rad(yaw_deg))
	wall.global_transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(yaw_deg)), _walker.global_position + dir * distance_m + Vector3(0.0, 20.0, 0.0)
	)
	_walls.append(wall)


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
	for wall in _walls:
		if is_instance_valid(wall):
			wall.queue_free()
	_walls.clear()


# --- Scenario helpers: P -----------------------------------------------------------------------------------------


## Pins P to a point `distance_m` from cannon 0's pivot along the chassis-frame pose (yaw, pitch), kept on the chassis
## as it moves and tilts (recomputed every tick before the rig).
func set_p_chassis(yaw_deg: float, pitch_deg: float, distance_m: float = 50.0) -> void:
	_p_mode = PMode.CHASSIS
	_p_pose = Vector2(yaw_deg, pitch_deg)
	_p_dist = distance_m
	_pre_rig()


## The same point, but fixed in the world from now on (the body may turn away from it).
func set_p_fixed(yaw_deg: float, pitch_deg: float, distance_m: float = 50.0) -> void:
	_p_pose = Vector2(yaw_deg, pitch_deg)
	_p_dist = distance_m
	_p_point = _chassis_point(0)
	_p_mode = PMode.WORLD
	_pre_rig()


## Pins P to a world point.
func set_p_world(point: Vector3) -> void:
	_p_point = point
	_p_mode = PMode.WORLD
	_pre_rig()


## P just right of and below the right-hand roof cannon, far enough from cannon 0 that top_1 is gray and top_0 is live:
## top_1 sees -22.8 deg, top_0 -18.8 deg (the pivots are 0.46 m apart).
func set_p_split() -> void:
	var pivot: Vector3 = _rig.pivot_now(1)
	set_p_world(pivot + _walker.body_pose().basis.orthonormalized() * Vector3(2.0, -0.84, 0.0))


func clear_p() -> void:
	_p_mode = PMode.CAMERA
	_rig.aim_override_active = false


## Steps P by (yaw, pitch) in the chassis frame from cannon 0's pivot (fixed in the world) and starts the probe. With
## `assist` the body turns toward P with A (turn_left) until stop_swing().
func swing_to(yaw_deg: float, pitch_deg: float, assist: bool = false) -> void:
	begin_track()
	var before: Vector2 = _rig.pose_deg(0)
	set_p_fixed(yaw_deg, pitch_deg, _p_dist)
	track_swing_deg = AimMath.pose_error_deg(before, Vector2(yaw_deg, pitch_deg))
	if assist:
		hold_action("turn_left" if yaw_deg > 0.0 else "turn_right", true)


func stop_swing() -> void:
	hold_action("turn_left", false)
	hold_action("turn_right", false)
	_tracking = false


func begin_track() -> void:
	track_ticks = 0
	track_reach_ticks = -1
	track_err_max_deg = 0.0
	track_step_yaw_max_deg = 0.0
	track_step_pitch_max_deg = 0.0
	track_yaw_rate_max_dps = 0.0
	_track_prev = _rig.pose_deg(0)
	_tracking = true


## The body turns with `action` ("turn_left" / "turn_right") from now (the hold test).
func turn_body(action: String) -> void:
	hold_action(action, true)


# --- Scenario helpers: scripted input ---------------------------------------------------------------------------


func hold_action(action: String, pressed: bool) -> void:
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


## Shot-lands-at-P probe: a fresh walker, a wall `distance_m` away along camera yaw `cam_yaw_deg`, the camera level on
## it, spread 0. The trigger goes down at tick 75 and up at tick 100; land_err_max_deg is the largest angle (seen from
## the shooting cannon's pivot) between where a bolt hit the wall and P as it was when that cannon fired.
func begin_land(cam_yaw_deg: float, distance_m: float) -> void:
	spawn(0.0, 0.0)
	set_spread(0.0)
	add_wall(cam_yaw_deg, distance_m)
	_orbit.set_angles(cam_yaw_deg, 0.0)
	land_done = false
	land_shots = 0
	land_impacts = 0
	land_err_max_deg = 0.0
	_land_p_set = false
	_land_tick = 0


## Risk 9: the target 12 m out and 6 m above the ground, the camera at pitch -20 behind the walker.
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
	risk9_ring_to_dot_px = ring_to_dot_min_px
	risk9_arm_m = _orbit.arm_length
	risk9_chassis_in_frame = _chassis_in_frame(camera)
	risk9_chassis_px = _project_ref(camera, _walker.body_pose() * Vector3(0.0, 0.3, 0.0))
	print(
		(
			"RISK9 %s pitch=%.2f shown=%.1f arm=%.2f ray_gap_m=%.2f dot_on_target=%s target_to_dot_px=%.1f target_radius_px=%.1f ring_to_dot_px=%.1f chassis_in_frame=%s chassis_px=(%.0f,%.0f) at 1920x1080, hits=%d"
			% [
				label, _orbit.pitch_deg, _orbit.shown_pitch_deg, risk9_arm_m, risk9_ray_gap_m, risk9_dot_on_target,
				risk9_target_to_dot_px, risk9_target_radius_px, risk9_ring_to_dot_px, risk9_chassis_in_frame,
				risk9_chassis_px.x, risk9_chassis_px.y, target_hits,
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
	var parts: PackedStringArray = PackedStringArray()
	for i in _marks.rings.size():
		var ring: AimMarks.Ring = _marks.rings[i]
		parts.append(
			"ring%d=(%.1f,%.1f) shown=%s live=%s dashed=%s thick=%s flash=%s chevron=%s at (%.1f,%.1f) to_dot=%.1f"
			% [
				i, ring.screen.x, ring.screen.y, ring.visible, ring.live, ring.dashed, ring.thick, ring.flashing,
				ring.chevron_visible, ring.chevron_screen.x, ring.chevron_screen.y, ring.to_dot_px,
			]
		)
	for i in _rig.cannon_count():
		print(
			"AIMPOSE %s cannon %d pose=(%.2f,%.2f) wanted=(%.2f,%.2f) live=%s P=%s line_hit=%s pivot=%s"
			% [
				label, i, _rig.pose_deg(i).x, _rig.pose_deg(i).y, _rig.wanted_pose_deg(i).x, _rig.wanted_pose_deg(i).y,
				_rig.is_live(i), _rig.aim_point, _rig.weapon_state(i)["aim_point"], _rig.pivot_now(i),
			]
		)
	print(
		"AIMMARKS %s size=(%.0f,%.0f) scale=%.3f dot=(%.1f,%.1f) gray=%d %s"
		% [
			label, _marks.view_size.x, _marks.view_size.y, _marks.ui_scale, _marks.dot_screen.x, _marks.dot_screen.y,
			_rig.gray_count, " | ".join(parts),
		]
	)


func log_checks(label: String) -> void:
	print(
		(
			"AIMCHECK %s flash_runs=%d flash_ticks=%d..%d barrel_err_max_deg=%.5f shots=%d unsettled=%d shot_err_max_deg=%.5f by_weapon=%s gaps=%d gap_min=%d gap_max=%d gap_mean_s=%.4f hits=%d spread=%.2f"
			% [
				label, flash_runs, flash_run_min_ticks, flash_run_max_ticks, barrel_err_max_deg, shots_checked,
				shots_unsettled, shot_err_max_deg, str(shots_by_weapon), gap_count, gap_min_ticks, gap_max_ticks,
				gap_mean_s, target_hits, _rig.spread_deg(),
			]
		)
	)


## Cannon 0's swing / assist / hold numbers, in ticks and seconds.
func log_track(label: String) -> void:
	print(
		(
			"AIMTRACK %s reach_ticks=%d (%.4f s) swing_deg=%.2f step_max_deg yaw=%.4f pitch=%.4f err_max_deg=%.4f body_yaw_rate_max_dps=%.1f rate_dps=%.1f"
			% [
				label, track_reach_ticks, float(track_reach_ticks) / float(Engine.physics_ticks_per_second),
				track_swing_deg, track_step_yaw_max_deg, track_step_pitch_max_deg, track_err_max_deg,
				track_yaw_rate_max_dps, _rig.traverse_rate_dps(),
			]
		)
	)


func log_land(label: String) -> void:
	print(
		"AIMLAND %s shots=%d impacts=%d err_max_deg=%.5f"
		% [label, land_shots, land_impacts, land_err_max_deg]
	)


## Counts ticks with any cannon gray from now on.
func begin_watch() -> void:
	watch_ticks = 0
	watch_gray = 0
	_watching = true


func end_watch(label: String) -> void:
	_watching = false
	print("GRAYWATCH %s ticks=%d gray_ticks=%d" % [label, watch_ticks, watch_gray])


## For the hit flash shot: stop the whole tree (the harness keeps running) on the frame after the first hit lands.
func freeze_on_hit() -> void:
	frozen = false
	_freeze_pending = false
	if not _rig.pool.impacted.is_connected(_freeze_once):
		_rig.pool.impacted.connect(_freeze_once)


func unfreeze() -> void:
	get_tree().paused = false
	frozen = false


## Moves the walker far away in one step (a teleport), to check that nothing is drawn streaking after it.
func jump_to(x: float, z: float) -> void:
	_walker.teleport(Transform3D(Basis(Vector3.UP, _walker.yaw_radians()), Vector3(x, SPAWN_Y, z)))
	_orbit.snap()


# --- Internals -------------------------------------------------------------------------------------------------


## Before the rig: P for this tick.
func _pre_rig() -> void:
	match _p_mode:
		PMode.CAMERA:
			_rig.aim_override_active = false
		PMode.CHASSIS:
			_rig.aim_override_point = _chassis_point(0)
			_rig.aim_override_active = true
		PMode.WORLD:
			_rig.aim_override_point = _p_point
			_rig.aim_override_active = true


func _chassis_point(index: int) -> Vector3:
	var direction: Vector3 = AimMath.barrel_basis(_walker.body_pose().basis, _p_pose) * Vector3.FORWARD
	return _rig.pivot_now(index) + direction * _p_dist


## Degrees between cannon `index` and the pose that puts its line on P (this tick, after the step).
func _pose_err(index: int) -> float:
	return AimMath.pose_error_deg(_rig.pose_deg(index), _rig.wanted_pose_deg(index))


func _track_tick() -> void:
	if not _tracking:
		return
	track_ticks += 1
	var pose: Vector2 = _rig.pose_deg(0)
	track_step_yaw_max_deg = maxf(track_step_yaw_max_deg, absf(wrapf(pose.x - _track_prev.x, -180.0, 180.0)))
	track_step_pitch_max_deg = maxf(track_step_pitch_max_deg, absf(pose.y - _track_prev.y))
	_track_prev = pose
	track_yaw_rate_max_dps = maxf(track_yaw_rate_max_dps, absf(_walker.yaw_rate_dps))
	var err: float = _pose_err(0)
	track_err_max_deg = maxf(track_err_max_deg, err)
	if track_reach_ticks < 0 and err <= REACH_DEG:
		track_reach_ticks = track_ticks


func _land_tick_step() -> void:
	if _land_tick < 0:
		return
	_land_tick += 1
	if _land_tick == LAND_FIRE_TICK:
		hold_action("fire", true)
	elif _land_tick == LAND_END_TICK:
		hold_action("fire", false)
		_land_tick = -1
		land_done = true


func _stop_probes() -> void:
	_tracking = false
	_land_tick = -1
	_land_p_set = false
	land_done = false


func _release_inputs() -> void:
	for action in ["turn_left", "turn_right", "strafe_left", "strafe_right", "move_forward", "move_back", "fire", "aim"]:
		Input.action_release(action)


func _freeze_once(_point: Vector3, _collider: Object, _projectile: Projectile, counted: bool) -> void:
	if not counted:
		return
	_freeze_pending = true
	_rig.pool.impacted.disconnect(_freeze_once)


func _on_fired(weapon: int, origin: Vector3, direction: Vector3) -> void:
	shot_frames.append(Engine.get_physics_frames())
	shots_by_weapon[weapon] += 1
	if _land_tick >= 0 and not _land_p_set:
		_land_p = _rig.aim_point
		_land_p_set = true
	if weapon == 0 and _land_tick >= 0:
		land_shots += 1
	var settled: bool = _rig.is_live(weapon) and _pose_err(weapon) <= SETTLED_DEG
	if not settled:
		shots_unsettled += 1
		return
	shots_checked += 1
	var pivot: Vector3 = _rig.pivot_position(weapon)
	shot_err_max_deg = maxf(shot_err_max_deg, AimMath.angle_between_deg(direction, _rig.aim_point - pivot))
	if origin.distance_to(pivot) > 1.0:
		push_error("AimRange: a muzzle more than 1 m from its pivot")


func _on_impacted(point: Vector3, _collider: Object, _projectile: Projectile, _counted: bool) -> void:
	if not _land_p_set:
		return
	land_impacts += 1
	var pivot: Vector3 = _rig.pivot_position(_projectile.weapon) if _projectile.weapon >= 0 else _rig.pivot_position(0)
	land_err_max_deg = maxf(land_err_max_deg, AimMath.angle_between_deg(point - pivot, _land_p - pivot))


func _add_target_at(position_world: Vector3) -> void:
	var target := AimTarget.new()
	add_child(target)
	target.global_position = position_world
	_targets.append(target)
	_last_target = target


func _chassis_in_frame(camera: Camera3D) -> bool:
	var box_size: Vector3 = _walker.chassis_size()
	if box_size == Vector3.ZERO:
		return false
	var chassis: Transform3D = _walker.body_pose() * Transform3D(Basis.IDENTITY, _walker.chassis_center())
	var half: Vector3 = box_size * 0.5
	for sx: float in [-1.0, 1.0]:
		for sy: float in [-1.0, 1.0]:
			for sz: float in [-1.0, 1.0]:
				var corner: Vector3 = chassis * (half * Vector3(sx, sy, sz))
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
