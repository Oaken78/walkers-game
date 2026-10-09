class_name OrbitMath
extends RefCounted
## Pure maths for the orbit camera (GDD 5, 6, 10). No nodes, so unit tests cover the behaviour directly.
## Angles are degrees. Yaw 0 looks along -Z; positive yaw turns the view left (same as rotation.y).
## Pitch > 0 puts the camera above the pivot looking down; -10 is low, looking up.


## Mouse motion in pixels to new (yaw, pitch). Mouse right turns the view right (yaw falls); mouse up tilts the
## view up (pitch falls toward pitch_min) unless invert_y. Pitch is clamped, yaw wraps to -180..180.
static func mouse_to_angles(
	yaw: float,
	pitch: float,
	dx_px: float,
	dy_px: float,
	deg_per_px: float,
	invert_y: bool,
	pitch_min: float,
	pitch_max: float
) -> Vector2:
	var y_sign: float = -1.0 if invert_y else 1.0
	var new_yaw: float = wrapf(yaw - dx_px * deg_per_px, -180.0, 180.0)
	var new_pitch: float = clampf(pitch + dy_px * deg_per_px * y_sign, pitch_min, pitch_max)
	return Vector2(new_yaw, new_pitch)


## New goal distance after zooming by steps (+1 = one step closer), clamped to the allowed range.
static func zoom_distance(
	current: float, steps: int, step_m: float, min_m: float, max_m: float
) -> float:
	return clampf(current - float(steps) * step_m, min_m, max_m)


## Exponential follow factor for one frame: the share of the remaining gap closed. time_constant 0 = no lag.
static func follow_factor(delta: float, time_constant: float) -> float:
	if time_constant <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / time_constant)


## One follow step of the pivot toward its goal.
static func follow(pivot: Vector3, goal: Vector3, delta: float, time_constant: float) -> Vector3:
	return pivot + (goal - pivot) * follow_factor(delta, time_constant)


## Camera position relative to the pivot for the given yaw, pitch and arm length.
static func camera_offset(yaw: float, pitch: float, length: float) -> Vector3:
	var p: float = deg_to_rad(pitch)
	var local := Vector3(0.0, sin(p), cos(p)) * length
	return Basis(Vector3.UP, deg_to_rad(yaw)) * local


## World transform of the camera: looks along -Z of its basis, positioned behind and above the pivot.
static func camera_transform(pivot: Vector3, yaw: float, pitch: float, length: float) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(yaw)) * Basis(Vector3.RIGHT, -deg_to_rad(pitch))
	return Transform3D(basis, pivot + camera_offset(yaw, pitch, length))


## Arm length after collision: the shorter of the hit and the wanted length, but never under min_len.
static func arm_length(hit_length: float, wanted: float, min_len: float) -> float:
	return maxf(minf(hit_length, wanted), minf(min_len, wanted))


## Linear move of a value toward a goal so that a full `span` takes `time` seconds.
static func ease_linear(current: float, goal: float, span: float, time: float, delta: float) -> float:
	if time <= 0.0:
		return goal
	return move_toward(current, goal, absf(span) / time * delta)


## Yaw the camera takes to sit behind something that faces `forward` (world vector, y ignored).
static func behind_yaw(forward: Vector3) -> float:
	return rad_to_deg(atan2(-forward.x, -forward.z))


## One recentre step. Turns yaw toward behind_yaw at rate_deg once the mouse has been idle for delay_s and the
## target moves faster than min_speed (min_speed 0 = also while standing). Returns the new yaw.
static func recenter_step(
	yaw: float,
	behind: float,
	idle_s: float,
	target_speed: float,
	delta: float,
	delay_s: float,
	rate_deg: float,
	min_speed: float
) -> float:
	if idle_s < delay_s:
		return yaw
	if min_speed > 0.0 and target_speed <= min_speed:
		return yaw
	var gap: float = wrapf(behind - yaw, -180.0, 180.0)
	var step: float = clampf(gap, -rate_deg * delta, rate_deg * delta)
	return wrapf(yaw + step, -180.0, 180.0)


## Shake strength 1 -> 0 over its duration (linear), 0 outside it.
static func shake_envelope(elapsed: float, duration: float) -> float:
	if duration <= 0.0 or elapsed >= duration:
		return 0.0
	return clampf(1.0 - elapsed / duration, 0.0, 1.0)


## Shake offset for one frame from two random numbers in -1..1. Each axis stays within amplitude.
static func shake_offset(rx: float, ry: float, elapsed: float, duration: float, amplitude: float) -> Vector2:
	return Vector2(rx, ry) * amplitude * shake_envelope(elapsed, duration)


## Pinhole projection of a world point to pixels (origin top-left). fov_deg is vertical (Godot keep-height).
## Points behind the camera return Vector2(INF, INF).
static func project(
	point: Vector3, cam: Transform3D, fov_deg: float, view_w: float, view_h: float
) -> Vector2:
	var local: Vector3 = cam.affine_inverse() * point
	if local.z >= -0.001:
		return Vector2(INF, INF)
	var focal: float = 0.5 * view_h / tan(deg_to_rad(fov_deg) * 0.5)
	return Vector2(
		0.5 * view_w + focal * local.x / -local.z, 0.5 * view_h - focal * local.y / -local.z
	)
