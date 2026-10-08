class_name TwoBoneIK
extends RefCounted
## Analytic two-bone IK (GDD 8.2). Pure maths: a hip, a target and two bone lengths give a knee and a foot.
## The foot is clamped to [min distance, 0.99 x reach] so the leg never fully straightens or folds flat.

const MAX_STRETCH: float = 0.99
const MIN_FOLD_RATIO: float = 0.01
const PARALLEL_EPSILON: float = 0.0001


class Solution:
	extends RefCounted
	var knee: Vector3 = Vector3.ZERO
	var foot: Vector3 = Vector3.ZERO
	var reached: bool = false


## `pole` is a direction (outward + up for a spider leg), not a point.
static func solve(
	hip: Vector3, target: Vector3, upper: float, lower: float, pole: Vector3
) -> Solution:
	var result := Solution.new()
	var reach: float = upper + lower
	var max_dist: float = MAX_STRETCH * reach
	var min_dist: float = absf(upper - lower) + MIN_FOLD_RATIO * reach
	var to_target: Vector3 = target - hip
	var dist: float = to_target.length()
	var dir: Vector3 = Vector3.DOWN
	if dist > 0.000001:
		dir = to_target / dist
	var d: float = dist
	result.reached = true
	if dist > max_dist:
		d = max_dist
		result.reached = false
	elif dist < min_dist:
		d = min_dist
		result.reached = false
	result.foot = hip + dir * d

	# Knee on the circle of points `upper` from the hip and `lower` from the foot.
	var along: float = (upper * upper - lower * lower + d * d) / (2.0 * d)
	var height: float = sqrt(maxf(upper * upper - along * along, 0.0))
	var bend: Vector3 = _bend_direction(dir, pole)
	result.knee = hip + dir * along + bend * height
	return result


## Unit vector perpendicular to `dir`, on the pole side. Falls back to world up, then world forward.
static func _bend_direction(dir: Vector3, pole: Vector3) -> Vector3:
	var perp: Vector3 = pole - dir * pole.dot(dir)
	if perp.length() > PARALLEL_EPSILON * maxf(pole.length(), 1.0):
		return perp.normalized()
	perp = Vector3.UP - dir * Vector3.UP.dot(dir)
	if perp.length() > PARALLEL_EPSILON:
		return perp.normalized()
	perp = Vector3.FORWARD - dir * Vector3.FORWARD.dot(dir)
	return perp.normalized()
