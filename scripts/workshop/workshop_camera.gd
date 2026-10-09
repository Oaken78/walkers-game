class_name WorkshopCamera
extends Node3D
## The workshop camera (GDD 12): it circles the stand by itself, MMB drag turns it by hand and the wheel zooms.
## The cursor is never captured. Frame-rate independent: every move is scaled by the frame time.
## Rig: this node sits on the stand's look-at point and turns (yaw, then pitch); the Camera3D hangs `distance` behind.

## Point the camera looks at (m), roughly the middle of the walker.
@export var look_at_point: Vector3 = Vector3(0.0, 0.9, 0.0)
## Automatic orbit speed (deg/s). 0 stops it.
@export var auto_orbit_deg_per_s: float = 8.0
@export var distance: float = 5.5
@export var min_distance: float = 4.0
@export var max_distance: float = 9.0
## Metres per wheel notch.
@export var zoom_step: float = 0.5
## Seconds for the shown distance to catch up with `distance` (frame-rate independent ease).
@export var zoom_ease_time: float = 0.12
## Degrees of turn per pixel of MMB drag.
@export var drag_deg_per_px: float = 0.15
@export var pitch_min_deg: float = 5.0
@export var pitch_max_deg: float = 60.0
@export var start_yaw_deg: float = 35.0
@export var start_pitch_deg: float = 20.0
@export var fov: float = 50.0

## While true the automatic orbit holds still (the cursor is on a socket or a panel).
var orbit_paused: bool = false
var yaw_deg: float = 0.0
var pitch_deg: float = 0.0

var _dragging: bool = false
var _shown_distance: float = 5.5
var _camera: Camera3D


func _ready() -> void:
	# Moved every rendered frame, not every physics tick: interpolation would lag it and give identity on frame 0.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = fov
	_camera.far = 200.0
	add_child(_camera)
	_camera.make_current()
	yaw_deg = start_yaw_deg
	pitch_deg = start_pitch_deg
	distance = clampf(distance, min_distance, max_distance)
	_shown_distance = distance
	_apply()


func camera() -> Camera3D:
	return _camera


func is_dragging() -> bool:
	return _dragging


func _process(delta: float) -> void:
	if not orbit_paused and not _dragging:
		yaw_deg = wrapf(yaw_deg + auto_orbit_deg_per_s * delta, -180.0, 180.0)
	var catch_up := WalkerBody.ease_factor(delta, zoom_ease_time)
	_shown_distance = lerpf(_shown_distance, distance, catch_up)
	_apply()


## A MMB press starts a drag and the wheel zooms. Events a panel consumed never get here.
func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton:
		return
	var button: InputEventMouseButton = event
	if button.button_index == MOUSE_BUTTON_MIDDLE and button.pressed:
		_dragging = true
	elif event.is_action_pressed("zoom_in"):
		zoom(-1)
	elif event.is_action_pressed("zoom_out"):
		zoom(1)


## A drag goes on, and ends, even when the cursor crosses a panel.
func _input(event: InputEvent) -> void:
	if not _dragging:
		return
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.button_index == MOUSE_BUTTON_MIDDLE and not button.pressed:
			_dragging = false
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		orbit_by_pixels(motion.relative)


func orbit_by_pixels(relative: Vector2) -> void:
	yaw_deg = wrapf(yaw_deg - relative.x * drag_deg_per_px, -180.0, 180.0)
	pitch_deg = clampf(pitch_deg + relative.y * drag_deg_per_px, pitch_min_deg, pitch_max_deg)


## Wheel notches: positive zooms out, negative zooms in. Clamped to the allowed range.
func zoom(notches: int) -> void:
	distance = clampf(distance + float(notches) * zoom_step, min_distance, max_distance)


## Puts the camera at a pose at once (scenarios, T12).
func set_view(yaw: float, pitch: float, dist: float) -> void:
	yaw_deg = wrapf(yaw, -180.0, 180.0)
	pitch_deg = clampf(pitch, pitch_min_deg, pitch_max_deg)
	distance = clampf(dist, min_distance, max_distance)
	_shown_distance = distance
	_apply()


func _apply() -> void:
	var yaw := Basis(Vector3.UP, deg_to_rad(yaw_deg))
	var turn := yaw * Basis(Vector3.RIGHT, deg_to_rad(-pitch_deg))
	global_transform = Transform3D(turn, look_at_point)
	if _camera != null:
		_camera.position = Vector3(0.0, 0.0, _shown_distance)
