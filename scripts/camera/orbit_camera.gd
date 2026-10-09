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
## Descent floor (GDD 6): while the ground behind the walker rises steeper than this, the shown pitch is held
## at least (slope - floor_margin_deg), so the edge behind never hides the walker. Flatter: the player's pitch.
@export var floor_slope_deg: float = 25.0
@export var floor_margin_deg: float = 5.0
## Seconds for the shown pitch to ease through floor_ease_span_deg toward the floor and back.
@export var floor_ease_time: float = 0.3
@export var floor_ease_span_deg: float = 20.0
## Ground samples behind the walker (m apart) and how many; reach = spacing * count, capped by the arm's ground run.
@export var slope_sample_spacing: float = 0.75
@export var slope_sample_count: int = 7

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var arm_length: float = 8.0
var current_fov: float = 70.0
## Read-only: ground rise angle (deg) between the walker and the camera, and the pitch actually shown.
var slope_behind_deg: float = 0.0
var shown_pitch_deg: float = 0.0

var _shown_distance: float = 8.0
var _floor_lift_deg: float = 0.0
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
		"CAMSTATE %s player_pitch=%.1f shown_pitch=%.1f slope_behind=%.1f lift=%.1f"
		% [label, pitch_deg, shown_pitch_deg, slope_behind_deg, _floor_lift_deg]
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
	shown_pitch_deg = clampf(pitch_deg + _floor_lift_deg, pitch_min_deg, pitch_max_deg)
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_pitch.rotation_degrees = Vector3(-shown_pitch_deg, 0.0, 0.0)


## Pitch the descent floor asks for: none (-INF) at or below `threshold`, else slope - margin, capped at `cap`.
static func floor_pitch(slope: float, threshold: float, margin: float, cap: float) -> float:
	if slope <= threshold:
		return -INF
	return minf(slope - margin, cap)


## Extra degrees on top of the player's pitch that the floor wants (0 when the player is already above it).
static func floor_lift_goal(pitch: float, slope: float, threshold: float, margin: float, cap: float) -> float:
	var wanted: float = floor_pitch(slope, threshold, margin, cap)
	if is_inf(wanted):
		return 0.0
	return maxf(wanted - pitch, 0.0)


## Steepest rise angle (deg) from the ground under the walker to the sampled ground behind it.
## `heights[i]` is the ground height at distance (i + 1) * spacing behind; `base` is the height under the walker.
static func slope_from_heights(base: float, heights: PackedFloat32Array, spacing: float) -> float:
	var best: float = 0.0
	for i in heights.size():
		var run: float = float(i + 1) * spacing
		best = maxf(best, rad_to_deg(atan2(heights[i] - base, run)))
	return best


func _ease_floor(delta: float) -> void:
	slope_behind_deg = _measure_slope_behind()
	var goal: float = floor_lift_goal(
		pitch_deg, slope_behind_deg, floor_slope_deg, floor_margin_deg, pitch_max_deg
	)
	_floor_lift_deg = OrbitMath.ease_linear(
		_floor_lift_deg, goal, floor_ease_span_deg, floor_ease_time, delta
	)


## Downward world rays along the horizontal line from the walker toward the camera.
func _measure_slope_behind() -> float:
	if not is_instance_valid(target) or not is_inside_tree():
		return 0.0
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var origin: Vector3 = target.global_position
	var back: Vector3 = OrbitMath.camera_offset(yaw_deg, 0.0, 1.0)
	var reach: float = minf(
		slope_sample_spacing * float(slope_sample_count), _shown_distance * cos(deg_to_rad(pitch_deg))
	)
	var base: float = _ground_y(space, origin)
	if is_nan(base):
		return 0.0
	var heights := PackedFloat32Array()
	var run: float = slope_sample_spacing
	while run <= reach + 0.001:
		var y: float = _ground_y(space, origin + back * run)
		heights.append(base if is_nan(y) else y)
		run += slope_sample_spacing
	return slope_from_heights(base, heights, slope_sample_spacing)


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
