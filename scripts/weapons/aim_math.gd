class_name AimMath
extends RefCounted
## Pure maths of the aim model (GDD 8.3). No nodes, so unit tests cover it directly.
## P is the camera centre ray's hit (or the point at 120 m). Every weapon aims from its pivot straight at P, within
## its mount's arc, which is measured in the chassis frame (yaw 0 = the face's outward direction, pitch 0 = the
## chassis plane, up positive). Poses are Vector2(yaw_deg, pitch_deg) in the chassis frame; yaw is the walker's
## convention (0 looks along -Z, positive turns left), so a chassis-frame yaw of +90 looks along -X.

## Tolerance on the arc limits, so a reticle sitting at the limit does not flicker between live and gray.
const ARC_TOLERANCE_DEG: float = 0.5
## A P closer than this to the pivot leaves the weapon holding its pose, gray.
const HOLD_RADIUS_M: float = 1.5
const TRAVERSE_CONSTANT: float = 7200.0
const TRAVERSE_MIN_DEG_S: float = 45.0
const TRAVERSE_MAX_DEG_S: float = 720.0

const FACE_TOP: StringName = &"top"
const FACE_BOTTOM: StringName = &"bottom"
const FACE_FRONT: StringName = &"front"
const FACE_BACK: StringName = &"back"
const FACE_LEFT: StringName = &"left"
const FACE_RIGHT: StringName = &"right"


## Horizontal unit vector of a heading.
static func heading(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


## Yaw (radians, the walker's convention) of the horizontal bearing from `from` to `to`.
static func bearing_to(from: Vector3, to: Vector3) -> float:
	return atan2(-(to.x - from.x), -(to.z - from.z))


# --- Mount arcs ----------------------------------------------------------------------------------------------------


## The arc of a socket face: {unlimited (360 deg yaw), face_yaw_deg (the face's outward direction in the chassis
## frame), yaw_half_deg (when limited), pitch_min_deg, pitch_max_deg}. Only the top is mounted in M0.
static func mount_arc(face: StringName) -> Dictionary:
	match face:
		FACE_TOP:
			return {"unlimited": true, "face_yaw_deg": 0.0, "yaw_half_deg": 180.0, "pitch_min_deg": -20.0, "pitch_max_deg": 75.0}
		FACE_BOTTOM:
			return {"unlimited": true, "face_yaw_deg": 0.0, "yaw_half_deg": 180.0, "pitch_min_deg": -75.0, "pitch_max_deg": 20.0}
		FACE_FRONT:
			return _side_arc(0.0)
		FACE_LEFT:
			return _side_arc(90.0)
		FACE_BACK:
			return _side_arc(180.0)
		FACE_RIGHT:
			return _side_arc(-90.0)
	push_error("AimMath.mount_arc: unknown face %s" % face)
	return mount_arc(FACE_TOP)


static func _side_arc(face_yaw_deg: float) -> Dictionary:
	return {
		"unlimited": false,
		"face_yaw_deg": face_yaw_deg,
		"yaw_half_deg": 90.0,
		"pitch_min_deg": -90.0,
		"pitch_max_deg": 90.0,
	}


## deg/s, in yaw and in pitch: clamp(7200 / m, 45, 720).
static func traverse_rate(mass_kg: float) -> float:
	if mass_kg <= 0.0:
		return TRAVERSE_MAX_DEG_S
	return clampf(TRAVERSE_CONSTANT / mass_kg, TRAVERSE_MIN_DEG_S, TRAVERSE_MAX_DEG_S)


# --- Solve -------------------------------------------------------------------------------------------------------


## The pose (yaw deg, pitch deg) in the chassis frame of a world direction.
static func pose_of_direction(chassis_basis: Basis, direction: Vector3) -> Vector2:
	var local: Vector3 = chassis_basis.orthonormalized().inverse() * direction.normalized()
	var yaw: float = rad_to_deg(atan2(-local.x, -local.z))
	var pitch: float = rad_to_deg(asin(clampf(local.y, -1.0, 1.0)))
	return Vector2(yaw, pitch)


## World rotation of a barrel at a chassis-frame pose: yaw about the chassis up, then pitch about its own right axis.
## The barrel points along -Z and never rolls against the chassis.
static func barrel_basis(chassis_basis: Basis, pose: Vector2) -> Basis:
	return (
		chassis_basis.orthonormalized()
		* Basis(Vector3.UP, deg_to_rad(pose.x))
		* Basis(Vector3.RIGHT, deg_to_rad(pose.y))
	)


static func _relative_yaw(yaw_deg: float, arc: Dictionary) -> float:
	return wrapf(yaw_deg - float(arc["face_yaw_deg"]), -180.0, 180.0)


## The pose inside the arc nearest to `pose`: the pitch clamped, the yaw clamped on a limited mount.
static func clamp_to_arc(pose: Vector2, arc: Dictionary) -> Vector2:
	var pitch: float = clampf(pose.y, float(arc["pitch_min_deg"]), float(arc["pitch_max_deg"]))
	if bool(arc["unlimited"]):
		return Vector2(wrapf(pose.x, -180.0, 180.0), pitch)
	var half: float = float(arc["yaw_half_deg"])
	var relative: float = clampf(_relative_yaw(pose.x, arc), -half, half)
	return Vector2(wrapf(relative + float(arc["face_yaw_deg"]), -180.0, 180.0), pitch)


static func is_inside(pose: Vector2, arc: Dictionary, tolerance_deg: float = ARC_TOLERANCE_DEG) -> bool:
	if pose.y < float(arc["pitch_min_deg"]) - tolerance_deg or pose.y > float(arc["pitch_max_deg"]) + tolerance_deg:
		return false
	if bool(arc["unlimited"]):
		return true
	return absf(_relative_yaw(pose.x, arc)) <= float(arc["yaw_half_deg"]) + tolerance_deg


## One weapon's solve for this tick. Returns {hold, live, wanted (the pose that puts the line on P), target (the pose
## to swing toward: wanted, or the nearest reachable pose when gray)}. `current` is the held pose.
static func solve(pivot: Vector3, chassis_basis: Basis, p: Vector3, arc: Dictionary, current: Vector2) -> Dictionary:
	if pivot.distance_to(p) < HOLD_RADIUS_M:
		return {"hold": true, "live": false, "wanted": current, "target": current}
	var wanted: Vector2 = pose_of_direction(chassis_basis, p - pivot)
	var live: bool = is_inside(wanted, arc)
	return {"hold": false, "live": live, "wanted": wanted, "target": clamp_to_arc(wanted, arc)}


# --- Step --------------------------------------------------------------------------------------------------------


## Each axis moves at most `rate_dps * delta` toward `target`, on its own, with no ramp. A 360 deg mount takes the
## shortest way round; a limited mount moves linearly inside its arc, never through its dead zone (the target is
## inside the arc, so the straight move stays inside it).
static func step(current: Vector2, target: Vector2, rate_dps: float, delta: float, arc: Dictionary) -> Vector2:
	var max_step: float = rate_dps * delta
	var yaw: float
	if bool(arc["unlimited"]):
		var gap: float = wrapf(target.x - current.x, -180.0, 180.0)
		yaw = wrapf(current.x + clampf(gap, -max_step, max_step), -180.0, 180.0)
	else:
		var face: float = float(arc["face_yaw_deg"])
		var relative: float = move_toward(_relative_yaw(current.x, arc), _relative_yaw(target.x, arc), max_step)
		yaw = wrapf(relative + face, -180.0, 180.0)
	var pitch: float = move_toward(current.y, target.y, max_step)
	return Vector2(yaw, pitch)


## Degrees between two poses' directions seen from the pivot, for tests and checks.
static func pose_error_deg(a: Vector2, b: Vector2) -> float:
	var da: Vector3 = barrel_basis(Basis.IDENTITY, a) * Vector3.FORWARD
	var db: Vector3 = barrel_basis(Basis.IDENTITY, b) * Vector3.FORWARD
	return angle_between_deg(da, db)


## `direction` turned by up to `spread_deg` (a cone half-angle, uniform over the disc) from two random numbers in 0..1.
static func spread_direction(direction: Vector3, spread_deg: float, u_angle: float, u_azimuth: float) -> Vector3:
	if spread_deg <= 0.0:
		return direction
	var side: Vector3 = direction.cross(Vector3.UP)
	if side.length_squared() < 0.0001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var up: Vector3 = side.cross(direction).normalized()
	var angle: float = deg_to_rad(spread_deg) * sqrt(u_angle)
	var azimuth: float = TAU * u_azimuth
	var axis: Vector3 = (side * cos(azimuth) + up * sin(azimuth)).normalized()
	return direction.rotated(axis, angle).normalized()


static func angle_between_deg(a: Vector3, b: Vector3) -> float:
	return rad_to_deg(a.angle_to(b))
