class_name AimMath
extends RefCounted
## Pure maths of the aim model (GDD 8.3). No nodes, so unit tests cover it directly. Angles passed as `yaw` are
## radians with the walker's convention (0 looks along -Z, positive turns left); `*_deg` values are degrees.
##   P  the camera centre ray's hit (or the point at 120 m)
##   d  horizontal range from the body origin to P, clamped to 4-120 m;  h  P's height
##   Q  d metres along the body's heading from the body origin, at height h
## Each weapon's yaw is the heading; its elevation is the angle from its muzzle to Q, clamped to -10..+45 deg
## world-relative and slewed at 360 deg/s.

const RANGE_MIN_M: float = 4.0
const RANGE_MAX_M: float = 120.0
const ELEVATION_MIN_DEG: float = -10.0
const ELEVATION_MAX_DEG: float = 45.0
const SLEW_DEG_PER_S: float = 360.0
## d and h hold while the camera yaw is more than this far off the heading.
const HOLD_YAW_DEG: float = 90.0
## The muzzle moves with the elevation, so the elevation is solved by a few fixed-point passes (the muzzle arm is
## under 1 m and Q at least 4 m away: each pass shrinks the error by about 5x).
const MUZZLE_PASSES: int = 4


## Horizontal unit vector of a heading.
static func heading(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


static func horizontal_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(b.x - a.x, b.z - a.z).length()


static func clamp_range(distance: float) -> float:
	return clampf(distance, RANGE_MIN_M, RANGE_MAX_M)


static func convergence_point(origin: Vector3, yaw: float, range_m: float, height: float) -> Vector3:
	var along: Vector3 = heading(yaw) * range_m
	return Vector3(origin.x + along.x, height, origin.z + along.z)


## Angle (deg, 0..180) between the camera's yaw and the body's heading.
static func yaw_gap_deg(camera_yaw_deg: float, body_yaw: float) -> float:
	return absf(wrapf(camera_yaw_deg - rad_to_deg(body_yaw), -180.0, 180.0))


static func holds(camera_yaw_deg: float, body_yaw: float) -> bool:
	return yaw_gap_deg(camera_yaw_deg, body_yaw) > HOLD_YAW_DEG


## The (d, h) pair for this tick: from P within 90 deg of the heading, else the previous pair.
static func range_and_height(
	previous: Vector2, p: Vector3, origin: Vector3, camera_yaw_deg: float, body_yaw: float
) -> Vector2:
	if holds(camera_yaw_deg, body_yaw):
		return previous
	return Vector2(clamp_range(horizontal_distance(origin, p)), p.y)


## World rotation of a barrel: yaw about up, then elevation (deg, up positive) about its own right axis. The
## barrel points along -Z; there is no roll, whatever the body does.
static func barrel_basis(yaw: float, elevation_deg: float) -> Basis:
	return Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(elevation_deg))


static func muzzle_position(pivot: Vector3, yaw: float, elevation_deg: float, muzzle_local: Vector3) -> Vector3:
	return pivot + barrel_basis(yaw, elevation_deg) * muzzle_local


## Elevation (deg, up positive) of the straight line from `from` to `to`.
static func elevation_to(from: Vector3, to: Vector3) -> float:
	var flat: float = horizontal_distance(from, to)
	return rad_to_deg(atan2(to.y - from.y, flat))


## The elevation (deg, unclamped) at which a barrel pivoting at `pivot` points from its own muzzle at `q`.
static func solve_elevation(pivot: Vector3, muzzle_local: Vector3, yaw: float, q: Vector3) -> float:
	var elevation: float = elevation_to(pivot, q)
	for i in MUZZLE_PASSES:
		elevation = elevation_to(muzzle_position(pivot, yaw, elevation, muzzle_local), q)
	return elevation


static func clamp_elevation(elevation_deg: float) -> float:
	return clampf(elevation_deg, ELEVATION_MIN_DEG, ELEVATION_MAX_DEG)


static func is_limited(wanted_deg: float) -> bool:
	return wanted_deg < ELEVATION_MIN_DEG or wanted_deg > ELEVATION_MAX_DEG


static func slew(current_deg: float, target_deg: float, delta: float) -> float:
	return move_toward(current_deg, target_deg, SLEW_DEG_PER_S * delta)


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
