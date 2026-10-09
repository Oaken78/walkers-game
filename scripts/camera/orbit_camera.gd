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

var yaw_deg: float = 0.0
var pitch_deg: float = 0.0
var arm_length: float = 8.0
var current_fov: float = 70.0

var _shown_distance: float = 8.0
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
	rotation_degrees = Vector3(0.0, yaw_deg, 0.0)
	_pitch.rotation_degrees = Vector3(-pitch_deg, 0.0, 0.0)


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
	var dir: Vector3 = OrbitMath.camera_offset(yaw_deg, pitch_deg, 1.0)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _cast_shape
	query.transform = Transform3D(Basis.IDENTITY, global_position)
	query.motion = dir * _shown_distance
	query.collision_mask = WORLD_MASK
	var result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
	if result.is_empty():
		return _shown_distance
	return result[0] * _shown_distance
