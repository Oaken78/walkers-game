class_name OrbitCamera
extends Node3D
## Third-person orbit camera (GDD 5, 6 tank controls, 10 rule 1). Follows `target` with a short position lag,
## orbits with the mouse with no rotation lag, zooms on the wheel, narrows the FOV while aiming, pulls in
## against terrain with a spring arm and drifts back behind the target after the mouse has been idle.
## Hierarchy: OrbitCamera (yaw, top_level) > %Pitch > %Arm (SpringArm3D) > %Camera. All maths is in OrbitMath.

const WORLD_MASK: int = 1
const ENEMY_MASK: int = 4
## Time constant for smoothing the measured target speed (s), so 60 Hz physics steps do not flicker it.
const SPEED_SMOOTHING_S: float = 0.10

@export var target: Node3D
@export var target_offset: Vector3 = Vector3(0.0, 1.5, 0.0)
@export var distance: float = 8.0
@export var min_distance: float = 5.0
@export var max_distance: float = 12.0
@export var zoom_step: float = 1.0
@export var zoom_time: float = 0.10
@export var collision_min_distance: float = 2.0
@export var collision_radius: float = 0.3
@export var fov: float = 70.0
@export var aim_fov: float = 50.0
@export var aim_fov_time: float = 0.10
@export var sensitivity_deg_per_px: float = 0.15
@export var invert_y: bool = false
@export var pitch_min_deg: float = -10.0
@export var pitch_max_deg: float = 60.0
@export var start_pitch_deg: float = 20.0
@export var position_lag: float = 0.10
@export var recenter_enabled: bool = true
@export var recenter_delay: float = 1.5
@export var recenter_rate_deg: float = 90.0
@export var recenter_min_target_speed: float = 0.5
@export var capture_mouse: bool = true
## Descent floor (GDD 6): where the ground behind the walker rises (or drops just ahead) steeper than
## floor_slope_deg for a sustained run, the shown pitch is held at least (slope - floor_margin_deg). The player's
## pitch is never changed; the floor is shown as max(pitch_deg, eased floor).
@export var floor_slope_deg: float = 25.0
@export var floor_margin_deg: float = 5.0
## Seconds per floor_ease_span_deg of lift, smoothstep in (toward the floor) and out (back to the player's pitch).
@export var floor_in_time: float = 0.45
@export var floor_out_time: float = 0.8
@export var floor_ease_span_deg: float = 20.0
## A slope counts only as a run of at least floor_min_segments consecutive samples, each segment steeper than
## floor_slope_deg, with a total rise over floor_min_rise (m): taller than any step-up, so boulders, ledges and
## blocks never lift the camera.
@export var floor_min_segments: int = 2
@export var floor_min_rise: float = 1.2
## The run must start within this distance (m) of the walker: a slope that begins further back than the camera
## can be hidden by is no longer in the way (0.75 m per sample; the 40 deg talus face behind a walker 2.3 m past
## its foot starts 2.3 m back and tops out below the view line).
@export var floor_max_start_m: float = 1.5
## Ground samples (m apart, at least 0.1). Behind: out to the camera's horizontal distance, at most
## slope_sample_max. Ahead: this many samples along the camera's forward line.
@export var slope_sample_spacing: float = 0.75
@export var slope_sample_max: int = 20
@export var ahead_sample_count: int = 4

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var arm_length: float = 8.0
var current_fov: float = 70.0
## Read-only: ground rise angle (deg) between the walker and the camera, and the pitch actually shown.
var slope_behind_deg: float = 0.0
var slope_ahead_deg: float = 0.0
## Scenario trackers (reset_trackers): the largest floor lift and the shortest arm since the reset.
var lift_max_deg: float = 0.0
var arm_min_m: float = INF
var shown_pitch_deg: float = 0.0

var _shown_distance: float = 8.0
var _floor_progress: float = 0.0
var _floor_target_deg: float = 0.0
var _idle_s: float = 0.0
var _target_speed: float = 0.0
var _snap_frame: int = -1
var _last_target_pos: Vector3 = Vector3.ZERO
var _has_last_pos: bool = false
var _shake_elapsed: float = 0.0
var _shake_duration: float = 0.0
var _shake_amplitude: float = 0.0
var _rng := RandomNumberGenerator.new()
var _cast_shape := SphereShape3D.new()

@onready var _pitch: Node3D = %Pitch
@onready var _arm: SpringArm3D = %Arm
@onready var _camera: Camera3D = %Camera


func _ready() -> void:
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_pitch.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_arm.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_rng.seed = 1234
	# The rig owns the camera position: it casts the collision sphere itself every rendered frame, so the
	# SpringArm3D (which only updates in the physics tick) is kept for the hierarchy but switched off.
	_arm.collision_mask = WORLD_MASK
	_arm.set_physics_process_internal(false)
	_cast_shape.radius = collision_radius
	_arm.shape = _cast_shape
	_camera.make_current()
	distance = clampf(distance, min_distance, max_distance)
	_shown_distance = distance
	current_fov = fov
	_camera.fov = current_fov
	if is_instance_valid(target):
		set_angles(OrbitMath.behind_yaw(-target.global_basis.z), start_pitch_deg)
		snap()
	else:
		set_angles(0.0, start_pitch_deg)
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Mouse look is read in _input so a HUD Control under the cursor cannot swallow it.
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		orbit_event(event)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("zoom_in"):
		zoom(1)
	elif event.is_action_pressed("zoom_out"):
		zoom(-1)
	elif event.is_action_pressed("pause"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif capture_mouse and event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	_follow(delta)
	_idle_s += delta
	if is_aiming():
		_idle_s = 0.0
	if recenter_enabled and is_instance_valid(target):
		var behind: float = OrbitMath.behind_yaw(-target.global_basis.z)
		yaw_deg = OrbitMath.recenter_step(
			yaw_deg,
			behind,
			_idle_s,
			_target_speed,
			delta,
			recenter_delay,
			recenter_rate_deg,
			recenter_min_target_speed,
			is_aiming()
		)
	_ease_zoom_and_fov(delta)
	_ease_floor(delta)
	_apply_rotation()
	_apply_arm_and_shake(delta)
	lift_max_deg = maxf(lift_max_deg, lift_deg())
	arm_min_m = minf(arm_min_m, arm_length)


func reset_trackers() -> void:
	lift_max_deg = 0.0
	arm_min_m = INF


## A mouse motion event, in physical pixels (screen_relative). Goes through orbit(), so the idle reset is shared.
func orbit_event(event: InputEventMouseMotion) -> void:
	var px: Vector2 = OrbitMath.motion_px(event)
	orbit(px.x, px.y)


## Mouse motion in pixels. Rotation shows on this same frame (no smoothing).
func orbit(dx_px: float, dy_px: float) -> void:
	var angles: Vector2 = OrbitMath.mouse_to_angles(
		yaw_deg,
		pitch_deg,
		dx_px,
		dy_px,
		sensitivity_deg_per_px,
		invert_y,
		pitch_min_deg,
		pitch_max_deg
	)
	yaw_deg = angles.x
	pitch_deg = angles.y
	_idle_s = 0.0
	_apply_rotation()


func set_angles(yaw: float, pitch: float) -> void:
	yaw_deg = wrapf(yaw, -180.0, 180.0)
	pitch_deg = clampf(pitch, pitch_min_deg, pitch_max_deg)
	_idle_s = 0.0
	_apply_rotation()


## +1 = one step closer.
func zoom(steps: int) -> void:
	distance = OrbitMath.zoom_distance(distance, steps, zoom_step, min_distance, max_distance)


## The rendered Camera3D at the end of the arm (screen projection, make_current).
func camera() -> Camera3D:
	return _camera


func is_aiming() -> bool:
	return Input.is_action_pressed("aim")


## Crosshair ray hit point (world and enemies), else the point max_range along the view.
func aim_point(max_range: float = 300.0) -> Vector3:
	# Start at the pivot (on the view ray), so things between the camera and the player are never hit.
	var from: Vector3 = global_position
	var to: Vector3 = from - _camera.global_basis.z * max_range
	var query := PhysicsRayQueryParameters3D.create(from, to, WORLD_MASK | ENEMY_MASK)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return to
	return hit["position"]


func add_shake(duration: float = 0.15, amplitude: float = 0.15) -> void:
	var remaining: float = OrbitMath.shake_envelope(_shake_elapsed, _shake_duration) * _shake_amplitude
	if amplitude >= remaining:
		_shake_elapsed = 0.0
		_shake_duration = duration
		_shake_amplitude = amplitude


## One report line for scenarios: the player's pitch, the pitch shown, the slope behind and the lift between them.
func log_state(label: String) -> void:
	print(
		"CAMSTATE %s player_pitch=%.1f shown_pitch=%.1f slope_behind=%.1f slope_ahead=%.1f lift=%.1f arm=%.2f"
		% [label, pitch_deg, shown_pitch_deg, slope_behind_deg, slope_ahead_deg, lift_deg(), arm_length]
	)


## Jump to the target with no lag (spawn, teleport). Reads the target's real transform: outside a physics
## tick the interpolated one still shows the target where it was drawn last frame, before the teleport.
func snap() -> void:
	if not is_instance_valid(target):
		return
	global_position = target.global_position + target_offset
	_last_target_pos = target.global_position
	_has_last_pos = true
	_target_speed = 0.0
	_snap_frame = Engine.get_process_frames()
	_reset_floor()
	_apply_rotation()


func _follow(delta: float) -> void:
	if not is_instance_valid(target) or delta <= 0.0:
		return
	# In the frame of a snap the interpolated transform still holds the pre-teleport position.
	if Engine.get_process_frames() == _snap_frame:
		return
	var pos: Vector3 = target.get_global_transform_interpolated().origin
	if _has_last_pos:
		var raw: float = pos.distance_to(_last_target_pos) / delta
		_target_speed = lerpf(_target_speed, raw, OrbitMath.follow_factor(delta, SPEED_SMOOTHING_S))
	_last_target_pos = pos
	_has_last_pos = true
	global_position = OrbitMath.follow(global_position, pos + target_offset, delta, position_lag)


func _ease_zoom_and_fov(delta: float) -> void:
	_shown_distance = OrbitMath.ease_linear(
		_shown_distance, distance, zoom_step, zoom_time, delta
	)
	var fov_goal: float = aim_fov if is_aiming() else fov
	current_fov = OrbitMath.ease_linear(current_fov, fov_goal, fov - aim_fov, aim_fov_time, delta)
	_camera.fov = current_fov


func _apply_rotation() -> void:
	shown_pitch_deg = clampf(maxf(pitch_deg, _floor_shown_deg()), pitch_min_deg, pitch_max_deg)
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_pitch.rotation_degrees = Vector3(-shown_pitch_deg, 0.0, 0.0)


## Degrees the floor currently adds on top of the player's pitch.
func lift_deg() -> float:
	return maxf(shown_pitch_deg - pitch_deg, 0.0)


## The eased floor as a pitch: the player's pitch at progress 0, the floor target at 1 (smoothstep between).
func _floor_shown_deg() -> float:
	return lerpf(pitch_deg, _floor_target_deg, smoothstep(0.0, 1.0, _floor_progress))


## Pitch the descent floor asks for: none (-INF) at or below `threshold`, else slope - margin, capped at `cap`.
static func floor_pitch(slope: float, threshold: float, margin: float, cap: float) -> float:
	if slope <= threshold:
		return -INF
	return minf(slope - margin, cap)


## Sustained steep slope (deg) in a ground profile: `base` is the height under the walker and heights[i] the
## height at (i + 1) * spacing along the line. A run is `min_segments` or more consecutive segments, each rising
## steeper than `threshold` deg, with a total rise over `min_rise`. Returns the mean segment angle of the steepest
## qualifying run, else 0. A drop ahead is measured by passing negated heights.
static func slope_from_heights(
	base: float,
	heights: PackedFloat32Array,
	spacing: float,
	threshold: float = 25.0,
	min_segments: int = 2,
	min_rise: float = 1.2,
	max_start: float = INF
) -> float:
	var best: float = 0.0
	var run_len: int = 0
	var run_sum: float = 0.0
	var run_rise: float = 0.0
	var run_start: float = 0.0
	var prev: float = base
	for i in range(heights.size() + 1):
		var angle: float = -1.0
		var rise: float = 0.0
		if i < heights.size():
			rise = heights[i] - prev
			angle = rad_to_deg(atan2(rise, spacing))
			prev = heights[i]
		if angle > threshold:
			if run_len == 0:
				run_start = float(i) * spacing
			run_len += 1
			run_sum += angle
			run_rise += rise
		else:
			if run_len >= min_segments and run_rise > min_rise and run_start <= max_start + 0.001:
				best = maxf(best, run_sum / float(run_len))
			run_len = 0
			run_sum = 0.0
			run_rise = 0.0
	return best


## One floor step. `measured` (deg) replaces the ground measurement when given (tests).
func _ease_floor(delta: float, measured: float = NAN) -> void:
	var slope: float = measured
	if is_nan(slope):
		_measure_slopes()
		slope = maxf(slope_behind_deg, slope_ahead_deg)
	else:
		slope_behind_deg = slope
		slope_ahead_deg = 0.0
	var wanted: float = floor_pitch(slope, floor_slope_deg, floor_margin_deg, pitch_max_deg)
	var active: bool = not is_inf(wanted) and not is_aiming()
	if active:
		_floor_target_deg = wanted
	var time: float = floor_in_time if active else floor_out_time
	var lift: float = maxf(_floor_target_deg - pitch_deg, 5.0)
	var rate: float = floor_ease_span_deg / (maxf(time, 0.001) * lift)
	_floor_progress = move_toward(_floor_progress, 1.0 if active else 0.0, rate * delta)


## Recomputes the floor from a fresh measurement and jumps to it (spawn, teleport: no stale lift).
func _reset_floor() -> void:
	_measure_slopes()
	var wanted: float = floor_pitch(
		maxf(slope_behind_deg, slope_ahead_deg), floor_slope_deg, floor_margin_deg, pitch_max_deg
	)
	var active: bool = not is_inf(wanted) and not is_aiming()
	if active:
		_floor_target_deg = wanted
	_floor_progress = 1.0 if active else 0.0


## Downward world rays: behind the walker out to the camera's horizontal distance, and ahead along the
## camera's forward line. Sets slope_behind_deg and slope_ahead_deg.
func _measure_slopes() -> void:
	slope_behind_deg = 0.0
	slope_ahead_deg = 0.0
	if not is_instance_valid(target) or not is_inside_tree():
		return
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var spacing: float = maxf(slope_sample_spacing, 0.1)
	var origin: Vector3 = target.global_position
	var back: Vector3 = OrbitMath.camera_offset(yaw_deg, 0.0, 1.0)
	var base: float = _ground_y(space, origin)
	if is_nan(base):
		return
	var reach: float = _shown_distance * cos(deg_to_rad(pitch_deg))
	var behind := PackedFloat32Array()
	var ahead := PackedFloat32Array()
	var count: int = clampi(ceili(reach / spacing), 1, maxi(slope_sample_max, 1))
	for i in range(1, count + 1):
		var y: float = _ground_y(space, origin + back * spacing * float(i))
		behind.append(base if is_nan(y) else y)
	for i in range(1, maxi(ahead_sample_count, 0) + 1):
		var y: float = _ground_y(space, origin - back * spacing * float(i))
		ahead.append(base if is_nan(y) else -y)
	slope_behind_deg = slope_from_heights(
		base, behind, spacing, floor_slope_deg, floor_min_segments, floor_min_rise, floor_max_start_m
	)
	slope_ahead_deg = slope_from_heights(
		-base, ahead, spacing, floor_slope_deg, floor_min_segments, floor_min_rise, floor_max_start_m
	)


func _ground_y(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(at.x, at.y + 6.0, at.z), Vector3(at.x, at.y - 40.0, at.z), WORLD_MASK
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return NAN
	return hit["position"].y


func _apply_arm_and_shake(delta: float) -> void:
	_arm.spring_length = _shown_distance
	arm_length = OrbitMath.arm_length(_cast_arm(), _shown_distance, collision_min_distance)
	_camera.position = Vector3(0.0, 0.0, arm_length)
	if _shake_duration > 0.0:
		_shake_elapsed += delta
		var offset: Vector2 = OrbitMath.shake_offset(
			_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-1.0, 1.0),
			_shake_elapsed,
			_shake_duration,
			_shake_amplitude
		)
		_camera.h_offset = offset.x
		_camera.v_offset = offset.y
		if _shake_elapsed >= _shake_duration:
			_shake_duration = 0.0
	else:
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0


## Free length of the arm along the current view direction: a layer-1 sphere cast from the pivot, done in
## this frame after the pivot and the angles moved. Returns the wanted distance when nothing is in the way.
func _cast_arm() -> float:
	var dir: Vector3 = OrbitMath.camera_offset(yaw_deg, shown_pitch_deg, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _cast_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = dir * _shown_distance
	query.collision_mask = WORLD_MASK
	var result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	if result.is_empty():
		return _shown_distance
	return result[0] * _shown_distance
