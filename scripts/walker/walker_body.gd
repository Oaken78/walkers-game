class_name WalkerBody
extends CharacterBody3D
## The walker: a kinematic body built from a WalkerBuild (GDD 8.2). Legs place their feet by raycast, step when
## GaitSolver says so and are posed by TwoBoneIK. The body has no gravity: its height and tilt come from the
## plane of the planted feet, and it never moves so far that a planted foot would be dragged (rule 5).
## Everything that moves runs in _physics_process at 60 Hz; the maths lives in static helpers (unit-tested).
##
## The node itself is the collision body: it follows the body's yaw and tilt at the hip height (no bob), with two
## cylinders (a low one the size of the chassis, a wide one for the stance that stops the body at tall walls).
## The bobbing chassis, the tops and the legs are drawn from `_pose` in world space.

signal foot_planted(leg: int, position: Vector3, normal: Vector3)
signal step_started(leg: int)
signal build_applied

enum SteerMode { TANK, CAMERA_YAW }

const LEG_SCENE: PackedScene = preload("res://scenes/walker/leg.tscn")
## A planted foot may never be further than this x reach from its hip (the IK clamp is at the same value).
const REACH_LIMIT: float = 0.99
const BISECT_STEPS: int = 9
## Mean of sin(PI * t) over a swing is 2 / PI: the bob offset is shifted by 2 x this so it averages out.
const BOB_MEAN_SHIFT: float = 1.2732395
## CAMERA_YAW: proportional band and dead band of the turn toward the yaw source (a mouse nudge must not step).
const CAMERA_YAW_TURN_BAND_DEG: float = 6.0
const CAMERA_YAW_DEAD_BAND_DEG: float = 1.0
const MOVE_INPUT_EPSILON: float = 0.01
## Low collider: bottom this far above the lowest hip.
const COLLIDER_BOTTOM: float = 0.0
## Stance guard: bottom this x mean reach above the chassis underside, radius = widest rest foot + margin. Stops at tall walls
## without catching rolling terrain.
const GUARD_BOTTOM_RATIO: float = 0.7
const GUARD_MARGIN: float = 0.25
## A hovering foot stops this far before a face.
const HOVER_FACE_GAP: float = 0.05
## Fractions of the target lead tried in turn (legs about to lift only) when the ground at the full lead is out
## of reach and cannot be reached by lowering the body.
const LEAD_SCALES: Array[float] = [1.0, 0.5, 0.0]
const SINGLE_LEAD: Array[float] = [1.0]
## Fractions of the way from the current foot to the target tried (farthest first) when the target is invalid.
const SHORTEN_FRACTIONS: Array[float] = [0.75, 0.5, 0.25]
## When no foothold on the line works: fractions of the line and sideways offsets (m) tried to step around a rock.
const SIDESTEP_LINE_FRACTIONS: Array[float] = [1.0, 0.6]
const SIDESTEP_OFFSETS: Array[float] = [0.4, -0.4, 0.8, -0.8]
## The body lowers at most this x leg reach toward a lower foothold (GDD 5).
const MAX_LOWER_RATIO: float = 0.25
## Reach used when asking "can the hip reach this lower foothold" so the landing has slack.
const LOWER_REACH_SLACK: float = 0.95
## A foot only lifts toward ground within this x of the reach limit, so it still lands in reach after the body moves.
## A planted foot further than this x its reach limit from its hip asks to step.
const REACH_STRESS: float = 0.93
## Contact normals of a round collider on a slope read steeper than the slope's face: this much slack on the grip.
## (Measured in round 3: the round collider's rim reads 48.7 degrees on a 38 degree slope. Used only to tell ground
## from a wall; an overlap is never ignored, ground overlaps push the body up.)
const CONTACT_SLOPE_MARGIN_DEG: float = 3.0
## Every hip stands at least this far above the ground below it (telemetry asserts 0.05).
const HIP_CLEARANCE: float = 0.07
## Radius of the small collision sphere on each hip (a strut).
const HIP_COLLIDER_RADIUS: float = 0.06
## The body rises at most this fast to keep its hips clear of the ground (m/s). A larger need slows the walk.
const MAX_PUSH_RATE: float = 1.5
## How strongly the tilt target leans toward the plane through the next footholds (0 = planted feet only).
const PITCH_AHEAD_WEIGHT: float = 0.7
const PITCH_MAX_DEG: float = 12.0
## Low-pass time of the ahead plane and its weight.
const PITCH_AHEAD_SMOOTH_TIME: float = 0.03
## The contact resolve (all counts are upper bounds on its work per candidate pose): passes that re-read the hip rays,
## pitch attempts, raises, and the margin added to a raise.
## The legs keep leading along a wall this many ticks after the last slide tick.
const SLIDE_MEMORY_TICKS: int = 20
## A slide that keeps less than this share of the move is head-on; against a rock it goes round at this share of
## the into-face speed. A wall counts as going on when rays this far to either side still find it.
const SLIDE_MIN_SHARE: float = 0.3
const SLIDE_AROUND_SHARE: float = 0.8
const FACE_PROBE_SIDE: float = 0.6
const FACE_PROBE_BACK: float = 0.2
const FACE_PROBE_SLACK: float = 0.1
## A move whose part toward a face is below this (m per tick) does not bring the walker closer to it.
const FACE_APPROACH_EPSILON: float = 0.001
## A go-round sidestep around a rock is at most this x top speed, and its side flips at most once per lock (ticks).
const GO_ROUND_MAX_RATIO: float = 0.5
const SIDE_FLIP_LOCK_TICKS: int = 120
## Steep ground must reach this far to both sides of a rest foot for the stance to count it as a face.
const STANCE_FACE_HALF_WIDTH: float = 0.7
## A slide takes the into-face part of the move out x this (more than 1 backs the body off the face a little, so
## the legs on the face side keep ground to step on).
const SLIDE_STANDOFF: float = 1.0
const RESOLVE_PASSES: int = 3
## A spawn resolves against the ground up to this many times before it gives up (and warns).
const PLANT_ATTEMPTS: int = 6
const PLANT_LIFT_STEPS: Array[int] = [0, 1, 2, 3, 4, 5]
const PITCH_PASSES: int = 3
const RAISE_PASSES: int = 3
const RAISE_MARGIN: float = 0.001
const HIP_RISE_EPSILON: float = 0.0005
## A pitch is the estimate (rise need over the contact's lever arm) x this + a little slack; the rest comes from the
## contacts that remain. Contacts whose normal is flatter than this count as steep as it for the rise they ask.
const PITCH_OVERSHOOT: float = 1.1
const PITCH_SLACK_DEG: float = 0.1
const MIN_RISE_NORMAL_Y: float = 0.2
const MIN_PITCH_LEVER: float = 0.25
## Candidate fractions tried when the whole step does not work (the first from the rise estimate, then shrinking).
const FRACTION_TRIES: int = 5
const FRACTION_RESOLUTION: float = 0.08
const FRACTION_SHRINK: float = 0.95
const MIN_FRACTION: float = 0.002
const REACH_SHRINK: float = 0.2
## Held for the same reason as last tick: fewer tries, starting from a small fraction (the slow crawl).
const REPEAT_TRIES: int = 3
const REPEAT_FRACTION: float = 0.25
## Contact buffers and the collide_shape query size of the overlap test.
const MAX_CONTACTS: int = 24
const SHAPE_MAX_PAIRS: int = 6
const CONTACT_QUERY_MARGIN: float = 0.001
## Wall probe: a horizontal ray at the feet plane + step-up + this lift runs from WALL_PROBE_BACK outside the contact
## to WALL_PROBE_LENGTH into the obstacle; any hit means the face is taller than the step-up. Answers are cached per
## tick by contact cell and direction.
const WALL_PROBE_LIFT: float = 0.01
const WALL_PROBE_BACK: float = 0.05
## Half the length (m) of the ray that reads the surface normal at a steep contact.
const SURFACE_PROBE: float = 0.15
const WALL_PROBE_LENGTH: float = 0.5
## The stance check looks further: a 40 degree face only reaches the Strider's step-up about 1 m inboard of its toe.
const WALL_PROBE_LENGTH_FACE: float = 1.2
const WALL_CACHE_CELLS_PER_M: float = 10.0
const WALL_CACHE_ANGLES_PER_RAD: float = 4.0
## The sight ray from the hip stops this far short of the foothold.
const SIGHT_MARGIN: float = 0.1
## While the body lowers toward a footing it settles this x faster than the normal height spring.

@export var steer_mode: SteerMode = SteerMode.TANK
@export var accel_time: float = 0.25
@export var decel_time: float = 0.20
@export var turn_ramp_time: float = 0.10
@export var strafe_ratio: float = 0.75
@export var aim_turn_factor: float = 0.6
@export var body_height_ratio: float = 0.6
## Each hip sits this x its own reach above the foot plane, on a strut under the chassis side.
@export var hip_height_ratio: float = 0.5
@export var height_settle_time: float = 0.15
## Body tilt clamp in degrees. Negative (default) = the build's slope grip (lowest max_slope of its legs), GDD 5.
@export var tilt_max_deg: float = -1.0
@export var tilt_smooth_time: float = 0.12
## Bob amplitude in metres per metre of mean leg reach (Klas: 4 cm x mean reach).
@export var bob_amplitude: float = 0.04
@export var bob_gain_time: float = 0.1
@export_group("Gait (copied into GaitSolver)")
@export var trigger_ratio: float = 0.5
## Step times at mean leg reach 1.0 m; scaled by sqrt(mean reach) (Strider slower, Crawler quicker).
@export var step_time_idle: float = 0.30
@export var step_time_top: float = 0.18
@export var handover_progress: float = 0.85
@export var hover_delay: float = 0.5
@export var lift_ratio: float = 0.25
## Extra step-time factor for gaits with 3+ groups (the 4-5 leg wave): short steps keep the long stance in reach.
@export var wave_step_scale: float = 0.6
@export_group("Stance")
## Rest foot distance out from the hip, x leg reach (0.3-0.45 keeps the stride inside the 0.99 reach sphere).
@export var rest_out_ratio: float = 0.43
## The front legs fan forward and the rear legs back by up to this x reach.
@export var rest_fan_ratio: float = 0.05
## Hip spacing along a side = base + per_reach x mean reach.
@export var hip_spacing_base: float = 0.5
@export var hip_spacing_per_reach: float = 0.3
@export var hip_lateral_base: float = 0.45
@export var hip_lateral_per_reach: float = 0.15
@export var ray_up_ratio: float = 2.0
@export var ray_length_ratio: float = 4.0

var input_enabled: bool = true
var yaw_source: Node3D

## Read-only state for telemetry and the camera rig.
var yaw_rate_dps: float = 0.0
var target_yaw_rate_dps: float = 0.0
var move_input_active: bool = false
var turn_input: float = 0.0
var held_this_tick: bool = false
## Why the last tick did not move as commanded: "" free, "wall", "face" (steep ground under the stance), "ground-left",
## "rise-cap", "reach", "legs".
var block_cause: String = ""
var teleport_count: int = 0
## Ticks on which a real collision zeroed the commanded velocity.
var velocity_resets: int = 0
## Rays cast by the last physics tick (every ray: targets, sight, hover, landing, hip clearance, wall probe).
var rays_this_tick: int = 0
var max_rays_per_tick: int = 0
## `body_test_motion` calls of the last physics tick (the walker makes none since the overlap test uses shape queries).
var test_motions_this_tick: int = 0
## `collide_shape` queries of the last physics tick (the overlap tests; about 3 microseconds each).
var shape_queries_this_tick: int = 0
## Wall time of the last `_physics_process` in microseconds, and whether it counts (false on the tick that
## planted the walker after a spawn, teleport or build change: that tick is not a walking tick).
var tick_usec: int = 0
var tick_counts: bool = false

var _build: WalkerBuild
var _stats: Dictionary = {}
var _solver: GaitSolver
var _legs: Array[WalkerLeg] = []
var _needs_plant: bool = false
var _teleport_pending: bool = false
var _defer_plant: bool = false
var _ray: PhysicsRayQueryParameters3D
var _shape_query: PhysicsShapeQueryParameters3D
var _sight: PhysicsRayQueryParameters3D
var _top_speed: float = 4.5
var _turn_rate: float = 120.0
var _step_up: float = 0.6
var _max_slope: float = 35.0
var _mean_reach: float = 1.0
var _min_reach: float = 1.0
var last_bob: float = 0.0
var _yaw: float = 0.0
var _yaw_rate_cmd: float = 0.0
var _tilt_n: Vector3 = Vector3.UP
var _base_y: float = 0.0
## The drawn body origin: x, z of the node, y = eased base + bob.
var _origin: Vector3 = Vector3.ZERO
var _pose: Transform3D = Transform3D.IDENTITY
var _chassis_center: Vector3 = Vector3.ZERO
## The rear (or front) support the body pitches about: lowest hip height, outermost hip.
var _pivot_z: float = 0.0
var _pivot_y: float = 0.0
var _velocity_h: Vector3 = Vector3.ZERO
var _target_velocity: Vector3 = Vector3.ZERO
var _bob_gain: float = 0.0
var _height_above_plane: float = 0.0
var _lower_to_y: float = INF
var _in_forward: float = 0.0
var _in_strafe: float = 0.0
var _in_turn: float = 0.0
var _aim: bool = false
var _was_input: bool = false
# Per-leg buffers (sized in _rebuild, reused every tick).
var _hips_local: PackedVector3Array = PackedVector3Array()
var _limits: PackedFloat32Array = PackedFloat32Array()
var _foot: PackedVector3Array = PackedVector3Array()
var _render: PackedVector3Array = PackedVector3Array()
var _from: PackedVector3Array = PackedVector3Array()
var _to: PackedVector3Array = PackedVector3Array()
var _to_normal: PackedVector3Array = PackedVector3Array()
var _target: PackedVector3Array = PackedVector3Array()
var _target_normal: PackedVector3Array = PackedVector3Array()
var _errors: PackedFloat32Array = PackedFloat32Array()
var _valid: Array[bool] = []
var _planted: PackedByteArray = PackedByteArray()
var _stand_y: PackedFloat32Array = PackedFloat32Array()
var _fit_ahead: PackedVector3Array = PackedVector3Array()
## Rule 5 inputs: planted feet where they stand, swinging feet at their landing point.
var _check_feet: PackedVector3Array = PackedVector3Array()
var _check_flags: PackedByteArray = PackedByteArray()
var _fit: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	_make_queries()
	if _teleport_pending:
		# teleport() came before the node entered the tree: keep that placement.
		_teleport_pending = false
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), _origin)
	else:
		_origin = global_position
		_base_y = global_position.y
	if _build == null:
		# Static bodies added in the same frame cannot be queried yet: plant on the first physics tick.
		_defer_plant = true
		apply_build(WalkerBuild.scout())
		_defer_plant = false


# --- Public contract -------------------------------------------------------------------------------------------


func apply_build(build: WalkerBuild) -> void:
	if build == null or not build.is_valid():
		push_error("WalkerBody.apply_build: invalid build, keeping the old one")
		return
	_build = build.copy()
	_stats = _build.stats()
	_rebuild()
	_needs_plant = true
	if is_inside_tree() and not _defer_plant:
		_plant_all_at_rest()
	build_applied.emit()


func get_build() -> WalkerBuild:
	return _build.copy()


func stats() -> Dictionary:
	return _stats.duplicate()


func teleport(xform: Transform3D) -> void:
	var forward: Vector3 = -xform.basis.z
	_yaw = atan2(-forward.x, -forward.z)
	_origin = xform.origin
	_base_y = xform.origin.y
	if is_inside_tree():
		global_transform = Transform3D(Basis(Vector3.UP, _yaw), xform.origin)
	else:
		_teleport_pending = true
	_tilt_n = Vector3.UP
	_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw_rate_dps = 0.0
	_yaw_rate_cmd = 0.0
	_slide_ticks = 0
	_held_state = 0
	_slide_side = 1.0
	_flip_lock = 0
	teleport_count += 1
	_needs_plant = true
	if is_inside_tree():
		_plant_all_at_rest()


func leg_count() -> int:
	return _legs.size()


func foot_position(leg: int) -> Vector3:
	return _render[leg]


func gait() -> GaitSolver:
	return _solver


## Rest foot of leg i in the body frame (the stance the legs return to).
func rest_local_position(leg: int) -> Vector3:
	return _legs[leg].rest_local


## Distance from leg i's hip to its rest foot, over that leg's reach (GDD 5: at most 0.75).
func rest_distance_ratio(leg: int) -> float:
	var l: WalkerLeg = _legs[leg]
	return l.hip_local.distance_to(l.rest_local) / l.reach


## True while a collider overlaps static geometry (used after teleport and apply_build).
func is_overlapping_world() -> bool:
	return _overlap_state(global_transform) != 0


## The speed the held input asks for (the target of the acceleration ramp), m/s.
func input_speed() -> float:
	return _target_velocity.length()


## The horizontal unit direction the held input asks for (ZERO without move input).
func input_direction() -> Vector3:
	var flat := Vector3(_target_velocity.x, 0.0, _target_velocity.z)
	return flat.normalized() if flat.length() > 0.0001 else Vector3.ZERO


## The speed the body is being driven at (commanded), m/s.
func commanded_speed() -> float:
	return _velocity_h.length()


## Largest planted-foot distance to its hip, as a fraction of that leg's reach (the 0.99 rule).
func max_planted_reach_ratio() -> float:
	var worst: float = 0.0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.PLANTED:
			var hip: Vector3 = _pose * _legs[i].hip_local
			worst = maxf(worst, hip.distance_to(_render[i]) / _legs[i].reach)
	return worst


## Lowest knee rise (knee above its hip in the body frame, / reach) over planted feet within 0.5 x reach fore-aft
## of their rest foot (GDD 5: at least 0.10). INF when no foot qualifies.
func min_knee_rise_ratio() -> float:
	var lowest: float = INF
	var inverse: Transform3D = _pose.affine_inverse()
	for i in _legs.size():
		if _solver.state_of(i) != GaitSolver.LegState.PLANTED:
			continue
		var leg: WalkerLeg = _legs[i]
		var foot_local: Vector3 = inverse * _render[i]
		if absf(foot_local.z - leg.rest_local.z) > 0.5 * leg.reach:
			continue
		var knee_local: Vector3 = inverse * leg.knee
		lowest = minf(lowest, (knee_local.y - leg.hip_local.y) / leg.reach)
	return lowest


## Smallest knee bend over all legs and states: the knee's distance from the hip-foot line on the pole side, / reach.
## Near zero or negative means a knee flipped or the leg straightened.
func min_knee_bend_ratio() -> float:
	var lowest: float = INF
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var hip: Vector3 = _pose * leg.hip_local
		var chord: Vector3 = (leg.foot - hip).normalized()
		var pole: Vector3 = _pose.basis * leg.pole_local
		var side: Vector3 = pole - chord * pole.dot(chord)
		if side.length() < 0.0001:
			return 0.0
		side = side.normalized()
		var off: Vector3 = leg.knee - hip
		off -= chord * off.dot(chord)
		lowest = minf(lowest, off.dot(side) / leg.reach)
	return lowest


## The hip of leg i in world space (the drawn pose).
func hip_position(leg: int) -> Vector3:
	return _pose * _legs[leg].hip_local


func leg_side(leg: int) -> int:
	return _legs[leg].side


## Lowest hip height above the ground straight below it (chassis clearance on a steep slope, telemetry).
func min_hip_clearance() -> float:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var lowest: float = INF
	for i in _legs.size():
		var hip: Vector3 = _pose * _legs[i].hip_local
		_sight.from = hip + Vector3.UP * 3.0
		_sight.to = hip + Vector3.DOWN * 3.0
		var hit: Dictionary = space.intersect_ray(_sight)
		if not hit.is_empty():
			lowest = minf(lowest, hip.y - hit["position"].y)
	return lowest


## Perpendicular distance of the body origin above the planted-feet plane (telemetry).
func height_above_plane() -> float:
	return _height_above_plane


func yaw_radians() -> float:
	return _yaw


## Angle between the drawn body's up axis and world up (telemetry).
func tilt_degrees() -> float:
	return rad_to_deg(_tilt_n.angle_to(Vector3.UP))


## The drawn body pose (tilted, with bob), world space.
func body_pose() -> Transform3D:
	return _pose


## A point just above the highest part of the drawn body (screen-extent checks).
func top_point() -> Vector3:
	return _pose * Vector3(0.0, _chassis_center.y * 2.0 + 0.3, 0.0)


## Step times after the cadence scaling, as the solver uses them: [top, idle].
func step_times() -> Vector2:
	return Vector2(_solver.step_time_top, _solver.step_time_idle)


# --- Pure helpers (unit-tested) --------------------------------------------------------------------------------


## Least-squares plane y = a x + b z + c through the first `count` points (all when count < 0).
## Fewer than 3 points, or points on a line, give a level plane at the mean height.
static func fit_plane(points: PackedVector3Array, count: int = -1) -> Plane:
	var n: int = points.size() if count < 0 else mini(count, points.size())
	if n == 0:
		return Plane(Vector3.UP, 0.0)
	var centroid := Vector3.ZERO
	for i in n:
		centroid += points[i]
	centroid /= float(n)
	var sxx: float = 0.0
	var sxz: float = 0.0
	var szz: float = 0.0
	var sxy: float = 0.0
	var szy: float = 0.0
	for i in n:
		var dx: float = points[i].x - centroid.x
		var dy: float = points[i].y - centroid.y
		var dz: float = points[i].z - centroid.z
		sxx += dx * dx
		sxz += dx * dz
		szz += dz * dz
		sxy += dx * dy
		szy += dz * dy
	var det: float = sxx * szz - sxz * sxz
	var scale: float = sxx + szz
	if n < 3 or absf(det) <= 0.000001 * scale * scale:
		return Plane(Vector3.UP, centroid.y)
	var slope_x: float = (sxy * szz - sxz * szy) / det
	var slope_z: float = (sxx * szy - sxz * sxy) / det
	var normal := Vector3(-slope_x, 1.0, -slope_z).normalized()
	return Plane(normal, normal.dot(centroid))


## Height of the plane above world (x, z).
static func plane_height(plane: Plane, x: float, z: float) -> float:
	return (plane.d - plane.normal.x * x - plane.normal.z * z) / plane.normal.y


static func target_velocity(
	facing: Vector3,
	right: Vector3,
	forward_input: float,
	strafe_input: float,
	top_speed: float,
	strafe: float
) -> Vector3:
	var v: Vector3 = facing * (forward_input * top_speed) + right * (strafe_input * strafe * top_speed)
	if v.length() > top_speed:
		v = v.normalized() * top_speed
	return v


## Linear ramp: top_speed / accel_time while speeding up, top_speed / decel_time while slowing down.
static func approach_velocity(
	current: Vector3, target: Vector3, top_speed: float, accel: float, decel: float, delta: float
) -> Vector3:
	var rate: float = top_speed / accel if target.length() >= current.length() else top_speed / decel
	return current.move_toward(target, rate * delta)


## Yaw rate in deg/s moving toward input x turn_rate (x aim factor while aiming) at turn_rate / ramp deg/s^2.
static func approach_yaw_rate(
	current: float,
	input: float,
	turn_rate: float,
	aiming: bool,
	ramp: float,
	aim_factor: float,
	delta: float
) -> float:
	var target: float = input * turn_rate * (aim_factor if aiming else 1.0)
	return move_toward(current, target, turn_rate / ramp * delta)


## Frame-rate independent easing: factor 1 - exp(-delta / tau).
static func ease_toward(current: float, target: float, delta: float, tau: float) -> float:
	return current + (target - current) * ease_factor(delta, tau)


static func ease_factor(delta: float, tau: float) -> float:
	if tau <= 0.0:
		return 1.0
	return 1.0 - exp(-delta / tau)


static func clamp_tilt(normal: Vector3, max_deg: float) -> Vector3:
	var n: Vector3 = normal.normalized()
	var angle: float = n.angle_to(Vector3.UP)
	if angle <= deg_to_rad(max_deg):
		return n
	var axis: Vector3 = Vector3.UP.cross(n)
	if axis.length_squared() < 0.0000001:
		return Vector3.UP
	return Vector3.UP.rotated(axis.normalized(), deg_to_rad(max_deg))


## Body pose from its origin, yaw and the (tilted) up axis.
static func pose_transform(origin: Vector3, yaw: float, tilt_normal: Vector3) -> Transform3D:
	var tilt := Basis(Quaternion(Vector3.UP, tilt_normal))
	return Transform3D(tilt * Basis(Vector3.UP, yaw), origin)


## True when every planted foot is within its limit of its hip in pose `t`. A foot that is already beyond its
## limit in `current` may not get further away (so a body that starts out of reach can still back off).
static func feet_in_reach(
	t: Transform3D,
	current: Transform3D,
	hips_local: PackedVector3Array,
	feet: PackedVector3Array,
	planted: PackedByteArray,
	limits: PackedFloat32Array
) -> bool:
	for i in hips_local.size():
		if planted[i] == 0:
			continue
		# Within the limit is fine; beyond it a foot may only get no further away than it already is (no creep).
		var now: float = (t * hips_local[i]).distance_to(feet[i])
		if now > limits[i] + 0.00001 and now > (current * hips_local[i]).distance_to(feet[i]):
			return false
	return true


## Rule 5: the largest fraction (0..1) of the step from the current pose to the desired one that keeps every
## planted foot within its limit. Translation, yaw, height and tilt are blended together.
static func safe_fraction(
	cur_origin: Vector3,
	cur_yaw: float,
	cur_normal: Vector3,
	des_origin: Vector3,
	des_yaw: float,
	des_normal: Vector3,
	hips_local: PackedVector3Array,
	feet: PackedVector3Array,
	planted: PackedByteArray,
	limits: PackedFloat32Array
) -> float:
	var current: Transform3D = pose_transform(cur_origin, cur_yaw, cur_normal)
	var desired: Transform3D = pose_transform(des_origin, des_yaw, des_normal)
	if feet_in_reach(desired, current, hips_local, feet, planted, limits):
		return 1.0
	var low: float = 0.0
	var high: float = 1.0
	for step in BISECT_STEPS:
		var mid: float = (low + high) * 0.5
		var t: Transform3D = pose_transform(
			cur_origin.lerp(des_origin, mid),
			lerpf(cur_yaw, des_yaw, mid),
			cur_normal.slerp(des_normal, mid)
		)
		if feet_in_reach(t, current, hips_local, feet, planted, limits):
			low = mid
		else:
			high = mid
	return low


## Hip height relative to the body origin (the chassis underside, body_height x mean reach above the foot plane):
## the hip hangs hip_ratio x its own reach above the foot plane, so it is at or below the underside.
static func hip_local_y(body_ratio: float, mean_reach: float, hip_ratio: float, own_reach: float) -> float:
	return hip_ratio * own_reach - body_ratio * mean_reach


## z of each hip along one side, front (-Z) to back, evenly spaced and centred: no gap at an empty socket.
static func hip_z_positions(count: int, spacing: float) -> PackedFloat32Array:
	var zs := PackedFloat32Array()
	for i in count:
		zs.append((float(i) - float(count - 1) * 0.5) * spacing)
	return zs


## Stride room before the 0.99 x reach limit, from a leg's rest foot, in units of reach: the rest foot is `out_ratio`
## out and `fan_ratio` fore-aft of its hip (fanned end legs lose that much on one side). GDD 5: at least 0.65.
static func fore_aft_room_ratio(hip_ratio: float, out_ratio: float, fan_ratio: float) -> float:
	return sqrt(0.99 * 0.99 - hip_ratio * hip_ratio - out_ratio * out_ratio) - fan_ratio


## Cadence scales with the square root of the shortest mounted leg reach (Scout 1.0, Strider ~1.26, Crawler ~0.77).
static func cadence_scale(reach: float) -> float:
	return sqrt(maxf(reach, 0.01) / 1.0)


## A swing can only land on a physics tick: round the step time to whole ticks (just under, so the last tick
## lands it). Without this a 0.139 s step takes 9 ticks (0.150 s) and the felt step rate gain shrinks.
static func quantized_step_time(seconds: float, tick: float) -> float:
	return float(maxi(roundi(seconds / tick), 1)) * tick * 0.999


## Step time for a base time (defined at 1.0 m reach) and a mean reach.
static func scaled_step_time(base_time: float, mean_reach: float) -> float:
	return base_time * cadence_scale(mean_reach)


## CAMERA_YAW turn input from the yaw error in degrees: nothing inside the dead band, proportional to the band.
static func yaw_turn_input(error_deg: float, band_deg: float, dead_deg: float) -> float:
	if absf(error_deg) < dead_deg:
		return 0.0
	return clampf(error_deg / band_deg, -1.0, 1.0)


## Highest hip y that still reaches a foothold: ground + sqrt(reach^2 - horizontal^2); -INF when too far.
static func hip_height_for_reach(ground_y: float, horizontal: float, reach_limit: float) -> float:
	if horizontal >= reach_limit:
		return -INF
	return ground_y + sqrt(reach_limit * reach_limit - horizontal * horizontal)


static func _top_spot(index: int, count: int, width: float, length: float) -> Vector3:
	if count == 1:
		return Vector3(0.0, 0.0, -length * 0.05)
	if index == 0:
		return Vector3(-width * 0.25, 0.0, -length * 0.1)
	if index == 1:
		return Vector3(width * 0.25, 0.0, -length * 0.1)
	return Vector3(0.0, 0.0, length * 0.25)


# --- Build ---------------------------------------------------------------------------------------------------------


func _tilt_limit() -> float:
	return _max_slope if tilt_max_deg < 0.0 else tilt_max_deg


func _make_queries() -> void:
	if _ray != null:
		return
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1
	_ray.hit_from_inside = true
	_ray.collide_with_areas = false
	_sight = PhysicsRayQueryParameters3D.new()
	_sight.collision_mask = 1
	_sight.hit_from_inside = false
	_shape_query = PhysicsShapeQueryParameters3D.new()
	_shape_query.collision_mask = 1
	_shape_query.margin = CONTACT_QUERY_MARGIN
	_contact_point.resize(MAX_CONTACTS)
	_contact_normal.resize(MAX_CONTACTS)
	_contact_depth.resize(MAX_CONTACTS)


func _rebuild() -> void:
	_make_queries()
	var legs_root: Node3D = get_node("Legs")
	for child in legs_root.get_children():
		legs_root.remove_child(child)
		child.queue_free()
	_legs.clear()
	var mounted: Array[Dictionary] = _build.mounted_legs()
	var count: int = mounted.size()
	var sides := PackedInt32Array()
	var reaches := PackedFloat32Array()
	var per_side: Dictionary = {-1: 0, 1: 0}
	var reach_sum: float = 0.0
	for leg_data in mounted:
		var leg_side: int = leg_data["side"]
		sides.append(leg_side)
		reaches.append(leg_data["reach"])
		per_side[leg_side] += 1
		reach_sum += leg_data["reach"]
	_mean_reach = reach_sum / float(maxi(count, 1))
	_min_reach = _mean_reach
	for r in reaches:
		_min_reach = minf(_min_reach, r)
	_top_speed = _stats["top_speed"]
	_turn_rate = _stats["turn_rate"]
	_step_up = _stats["step_up"]
	_max_slope = _stats["max_slope"]
	var spacing: float = hip_spacing_base + hip_spacing_per_reach * _mean_reach
	var lateral: float = hip_lateral_base + hip_lateral_per_reach * _mean_reach
	var seen: Dictionary = {-1: 0, 1: 0}
	_hips_local.resize(count)
	_limits.resize(count)
	var stance_radius: float = 0.0
	for i in count:
		var side: int = sides[i]
		var index: int = seen[side]
		seen[side] += 1
		var side_count: int = per_side[side]
		var reach: float = reaches[i]
		var hip_y: float = hip_local_y(body_height_ratio, _mean_reach, hip_height_ratio, reach)
		var hip := Vector3(float(side) * lateral, hip_y, hip_z_positions(side_count, spacing)[index])
		var mid: float = float(side_count - 1) * 0.5
		var fan: float = 0.0 if mid <= 0.0 else (float(index) - mid) / mid
		var rest := Vector3(
			hip.x + float(side) * rest_out_ratio * reach,
			-body_height_ratio * _mean_reach,
			hip.z + rest_fan_ratio * reach * fan
		)
		var leg: WalkerLeg = LEG_SCENE.instantiate()
		legs_root.add_child(leg)
		leg.setup(side, reach, hip, rest)
		_legs.append(leg)
		stance_radius = maxf(stance_radius, Vector2(rest.x, rest.z).length())
		_hips_local[i] = hip
		_limits[i] = REACH_LIMIT * reach
	_foot.resize(count)
	_render.resize(count)
	_from.resize(count)
	_to.resize(count)
	_to_normal.resize(count)
	_target.resize(count)
	_target_normal.resize(count)
	_errors.resize(count)
	_errors.fill(0.0)
	_valid.resize(count)
	_planted.resize(count)
	_stand_y.resize(count)
	_fit_ahead.resize(count)
	_check_feet.resize(count)
	_check_flags.resize(count)
	_fit.resize(count)
	_solver = GaitSolver.new(sides, reaches)
	var cadence: float = cadence_scale(_min_reach)
	if _solver.group_count() > 2:
		cadence *= wave_step_scale
	_solver.trigger_ratio = trigger_ratio
	var tick: float = 1.0 / float(Engine.physics_ticks_per_second)
	_solver.step_time_idle = quantized_step_time(step_time_idle * cadence, tick)
	_solver.step_time_top = quantized_step_time(step_time_top * cadence, tick)
	_solver.handover_progress = handover_progress
	_solver.hover_delay = hover_delay
	_solver.lift_ratio = lift_ratio
	_solver.step_started.connect(_on_step_started)
	_solver.foot_planted.connect(_on_foot_planted)
	_build_body_meshes(per_side, spacing, lateral, stance_radius)


func _build_body_meshes(
	per_side: Dictionary, spacing: float, lateral: float, stance_radius: float
) -> void:
	var side_count: int = maxi(per_side[-1], per_side[1])
	var length: float = float(maxi(side_count - 1, 0)) * spacing + 0.7
	var width: float = 2.0 * lateral - 0.15
	var height: float = 0.2 + 0.12 * _mean_reach
	var bottom: float = 0.0
	_chassis_center = Vector3(0.0, bottom + height * 0.5, 0.0)
	_pivot_z = length * 0.5
	_pivot_y = bottom
	for hip in _hips_local:
		_pivot_z = maxf(_pivot_z, absf(hip.z))
		_pivot_y = minf(_pivot_y, hip.y)
	# Collider shaped to the real parts: the chassis box at the underside, and a small sphere on every hip.
	var shape := BoxShape3D.new()
	shape.size = Vector3(width, height, length)
	var collider: CollisionShape3D = get_node("Collider")
	collider.shape = shape
	collider.position = _chassis_center
	for old in get_children():
		if old is CollisionShape3D and String(old.name).begins_with("HipShape"):
			remove_child(old)
			old.queue_free()
	for i in _hips_local.size():
		var hip_shape := CollisionShape3D.new()
		hip_shape.name = "HipShape%d" % i
		var ball := SphereShape3D.new()
		ball.radius = HIP_COLLIDER_RADIUS
		hip_shape.shape = ball
		hip_shape.position = _hips_local[i]
		add_child(hip_shape)
	# Stance guard: as wide as the stance, high enough to pass over rolling ground.
	var guard_node: CollisionShape3D = get_node_or_null("Guard")
	if guard_node == null:
		guard_node = CollisionShape3D.new()
		guard_node.name = "Guard"
		add_child(guard_node)
	var guard := CylinderShape3D.new()
	guard.radius = stance_radius + GUARD_MARGIN
	guard.height = 1.5
	guard_node.shape = guard
	guard_node.position = Vector3(0.0, GUARD_BOTTOM_RATIO * _mean_reach + 0.75, 0.0)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, length)
	var chassis: MeshInstance3D = get_node("Chassis")
	chassis.top_level = true
	chassis.mesh = mesh
	chassis.material_override = WalkerLeg.body_material()
	var tops: Node3D = get_node("Tops")
	tops.top_level = true
	for child in tops.get_children():
		tops.remove_child(child)
		child.queue_free()
	var parts: Dictionary = _build.parts()
	var present: Array[StringName] = []
	for socket: StringName in [&"top_0", &"top_1", &"top_2"]:
		if parts.has(socket):
			present.append(socket)
	var top_y: float = bottom + height
	for index in present.size():
		var spot: Vector3 = _top_spot(index, present.size(), width, length)
		var part: StringName = parts[present[index]]
		var piece := MeshInstance3D.new()
		if part == PartCatalog.ARMOR_PLATE:
			var slab := BoxMesh.new()
			slab.size = Vector3(width * 0.7, 0.12, length * 0.6)
			piece.mesh = slab
			piece.position = Vector3(spot.x, top_y + 0.06, spot.z)
		else:
			var barrel := CylinderMesh.new()
			barrel.top_radius = 0.08
			barrel.bottom_radius = 0.1
			barrel.height = 1.0
			barrel.radial_segments = 10
			piece.mesh = barrel
			# Lying along -Z: the barrel points where the body faces.
			piece.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)
			piece.position = Vector3(spot.x, top_y + 0.18, spot.z - 0.35)
		piece.material_override = WalkerLeg.body_material()
		tops.add_child(piece)
	_cache_shapes()


# --- Planting ------------------------------------------------------------------------------------------------------


func _plant_all_at_rest(depth: int = 0) -> void:
	_needs_plant = false
	if _legs.is_empty() or not is_inside_tree():
		return
	_make_queries()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var flat := Transform3D(Basis(Vector3.UP, _yaw), _origin)
	var start_y: float = _origin.y + 3.0 * _mean_reach
	var fallback_y: float = _origin.y - body_height_ratio * _mean_reach
	for i in _legs.size():
		var rest: Vector3 = flat * _legs[i].rest_local
		_ray.from = Vector3(rest.x, start_y, rest.z)
		_ray.to = Vector3(rest.x, start_y - 10.0 * _mean_reach, rest.z)
		var hit: Dictionary = space.intersect_ray(_ray)
		var ground := Vector3(rest.x, fallback_y, rest.z)
		var normal := Vector3.UP
		if not hit.is_empty():
			ground = hit["position"]
			normal = hit["normal"]
		_foot[i] = ground
		_render[i] = ground
		_from[i] = ground
		_to[i] = ground
		_to_normal[i] = normal
		_planted[i] = 1
		_stand_y[i] = ground.y
	var plane: Plane = fit_plane(_foot)
	_tilt_n = clamp_tilt(plane.normal, _tilt_limit())
	var x: float = _origin.x
	var z: float = _origin.z
	_base_y = plane_height(plane, x, z) + body_height_ratio * _mean_reach / plane.normal.y
	_origin = Vector3(x, _base_y, z)
	_ref_plane = plane
	_wall_cache.clear()
	_surface_cache.clear()
	_ahead_n = _tilt_n
	_ahead_weight = PITCH_AHEAD_WEIGHT
	_slide_ticks = 0
	_held_state = 0
	# Hips clear of the ground and the colliders clear of the terrain (pitch first, raise second), as every tick does.
	# An overlapping pose is never accepted: ground left over is resolved again; a wall is left to _depenetrate.
	var placed: int = 2
	for attempt in PLANT_ATTEMPTS:
		placed = _resolve(_origin, _base_y, _yaw, _tilt_n, 10.0, false, false)
		if placed == 2:
			break
		_origin = _r_origin
		_base_y = _r_base
		_tilt_n = _r_tilt
		if placed == 0:
			break
	if placed == 2:
		# A rock under the body that also touches it steeply: lift the body clear of whatever lies under it first
		# (a wall beside it is left to _depenetrate).
		for lift in PLANT_LIFT_STEPS:
			if _overlap_state(Transform3D(pose_transform(Vector3(_origin.x, _base_y, _origin.z), _yaw, _tilt_n))) == 0:
				break
			if _contact_rise_need() <= 0.0:
				break
			var need: float = _contact_rise_need() + RAISE_MARGIN
			_origin.y += need
			_base_y += need

	_height_above_plane = plane.distance_to(_origin)
	_bob_gain = 0.0
	_velocity_h = Vector3.ZERO
	yaw_rate_dps = 0.0
	_yaw_rate_cmd = 0.0
	_solver.reset()
	_apply_transforms()
	# A new build (or a teleport) can put the colliders inside a wall: push the body out and plant again.
	if depth < 3 and _depenetrate():
		_plant_all_at_rest(depth + 1)
		return
	if _overlap_state(global_transform) != 0:
		push_warning("WalkerBody: spawn pose still overlaps the world after %d attempts" % PLANT_ATTEMPTS)
	_pose_legs()
	reset_physics_interpolation()


## Root = collision body (yaw only, at the base height); chassis and tops follow the drawn pose.
func _apply_transforms() -> void:
	_pose = pose_transform(_origin, _yaw, _tilt_n)
	global_transform = pose_transform(Vector3(_origin.x, _base_y, _origin.z), _yaw, _tilt_n)
	var chassis: MeshInstance3D = get_node("Chassis")
	chassis.global_transform = _pose * Transform3D(Basis.IDENTITY, _chassis_center)
	var tops: Node3D = get_node("Tops")
	tops.global_transform = _pose


func _pose_legs() -> void:
	var pad_basis := Basis(Vector3.UP, _yaw)
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var hip: Vector3 = _pose * leg.hip_local
		var pole: Vector3 = _pose.basis * leg.pole_local
		var strut_top: Vector3 = _pose * Vector3(leg.hip_local.x * 0.8, 0.1, leg.hip_local.z)
		leg.pose(hip, _foot[i], pole, pad_basis, strut_top)
		_render[i] = leg.foot


# --- Per tick ----------------------------------------------------------------------------------------------------


func _physics_process(delta: float) -> void:
	if _legs.is_empty():
		return
	var started_usec: int = Time.get_ticks_usec()
	rays_this_tick = 0
	test_motions_this_tick = 0
	shape_queries_this_tick = 0
	_wall_cache.clear()
	_surface_cache.clear()
	var spawn_tick: bool = _needs_plant
	if _needs_plant:
		_plant_all_at_rest()
	_read_input()
	var facing := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
	var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
	_target_velocity = target_velocity(facing, right, _in_forward, _in_strafe, _top_speed, strafe_ratio)
	_velocity_h = approach_velocity(
		_velocity_h, _target_velocity, _top_speed, accel_time, decel_time, delta
	)
	_yaw_rate_cmd = approach_yaw_rate(
		_yaw_rate_cmd, _in_turn, _turn_rate, _aim, turn_ramp_time, aim_turn_factor, delta
	)
	target_yaw_rate_dps = _in_turn * _turn_rate * (aim_turn_factor if _aim else 1.0)

	var speed_ratio: float = _update_targets()
	_homing_swings()
	_solver.update(delta, move_input_active, speed_ratio, _errors, _valid)
	_apply_move(delta)
	_update_swing_feet()
	_pose_legs()
	_was_input = move_input_active
	max_rays_per_tick = maxi(max_rays_per_tick, rays_this_tick)
	tick_usec = Time.get_ticks_usec() - started_usec
	tick_counts = not spawn_tick


func _read_input() -> void:
	var forward: float = 0.0
	var strafe: float = 0.0
	var turn: float = 0.0
	_aim = false
	if input_enabled:
		forward = Input.get_axis("move_back", "move_forward")
		var crab: float = Input.get_axis("strafe_left", "strafe_right")
		var steer: float = Input.get_axis("turn_right", "turn_left")
		_aim = Input.is_action_pressed("aim")
		if steer_mode == SteerMode.TANK:
			strafe = crab
			turn = steer
		else:
			strafe = clampf(crab - steer, -1.0, 1.0)
			if yaw_source != null and is_instance_valid(yaw_source):
				var heading: Vector3 = -yaw_source.global_transform.basis.z
				var wanted: float = atan2(-heading.x, -heading.z)
				var error_deg: float = rad_to_deg(wrapf(wanted - _yaw, -PI, PI))
				turn = yaw_turn_input(error_deg, CAMERA_YAW_TURN_BAND_DEG, CAMERA_YAW_DEAD_BAND_DEG)
	_in_forward = forward
	_in_strafe = strafe
	_in_turn = turn
	turn_input = turn
	move_input_active = (
		absf(forward) > MOVE_INPUT_EPSILON
		or absf(strafe) > MOVE_INPUT_EPSILON
		or absf(turn) > MOVE_INPUT_EPSILON
	)


## One ray per leg through rest + lead (more for legs about to lift whose lead ground is out of reach). Fills
## targets, validity and foot errors, and the height the body should lower to for a step down. Returns the
## speed ratio.
func _update_targets() -> float:
	var gt: Transform3D = _pose
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var yaw_rad: float = deg_to_rad(target_yaw_rate_dps)
	var ray_up: float = ray_up_ratio * _mean_reach
	var ray_len: float = ray_length_ratio * _mean_reach + ray_up
	var fastest: float = 0.0
	var kick_pending: bool = move_input_active and not _was_input
	var lead_groups: float = float(maxi(_solver.group_count() - 1, 1))
	var planted_count: int = 0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.PLANTED:
			_fit[planted_count] = _foot[i]
			planted_count += 1
	var plane: Plane = fit_plane(_fit, planted_count) if planted_count >= 3 else Plane(Vector3.UP, gt.origin.y - body_height_ratio * _mean_reach)
	_lower_to_y = INF
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var leg_state: int = _solver.state_of(i)
		var rest: Vector3 = gt * leg.rest_local
		# Sliding along a wall: the feet look ahead along the slide, not into the face.
		var lead_velocity: Vector3 = _target_velocity
		if _slide_ticks > 0:
			lead_velocity = _target_velocity.slide(_slide_n)
		var rest_velocity: Vector3 = lead_velocity + Vector3.UP.cross(rest - gt.origin) * yaw_rad
		var rest_speed: float = rest_velocity.length()
		fastest = maxf(fastest, rest_speed)
		# Foot lands on a live target; the stance after landing lasts (groups - 1) swings, so the lead covers it.
		var lead: Vector3 = GaitSolver.target_lead(
			rest_velocity, _solver.step_duration(rest_speed / _top_speed) * lead_groups
		)
		var hip_world: Vector3 = gt * leg.hip_local
		var about_to_lift: bool = (
			leg_state != GaitSolver.LegState.SWINGING
			and (
				kick_pending
				or leg_state == GaitSolver.LegState.HOVERING
				or _errors[i] > 0.7 * trigger_ratio * leg.reach
			)
		)
		var scales: Array[float] = LEAD_SCALES if about_to_lift else SINGLE_LEAD
		var limit: float = _limits[i]
		var floor_y: float = (
			plane_height(plane, hip_world.x, hip_world.z)
			+ (hip_height_ratio - MAX_LOWER_RATIO) * leg.reach
		)
		var hit: Dictionary = {}
		var aim_x: float = rest.x + lead.x
		var aim_z: float = rest.z + lead.z
		var needs_y: float = INF
		for lead_scale in scales:
			aim_x = rest.x + lead.x * lead_scale
			aim_z = rest.z + lead.z * lead_scale
			_ray.from = Vector3(aim_x, gt.origin.y + ray_up, aim_z)
			_ray.to = Vector3(aim_x, gt.origin.y + ray_up - ray_len, aim_z)
			hit = space.intersect_ray(_ray)
			rays_this_tick += 1
			if hit.is_empty():
				continue
			var ground: Vector3 = hit["position"]
			if hip_world.distance_to(ground) <= limit:
				needs_y = INF
				break
			# Out of reach: could the body lower toward it (a step down)?
			var horizontal: float = Vector2(hip_world.x - ground.x, hip_world.z - ground.z).length()
			var lowest_hip: float = hip_height_for_reach(
				ground.y, horizontal, limit * LOWER_REACH_SLACK
			)
			if lowest_hip < floor_y:
				# A deep step down: only then use the whole reach (the GDD step-down of 0.6 x reach needs it).
				lowest_hip = hip_height_for_reach(ground.y, horizontal, limit)
			if lowest_hip >= floor_y and lowest_hip < hip_world.y:
				needs_y = lowest_hip + (gt.origin.y - hip_world.y)
				break
		if hit.is_empty():
			_target[i] = Vector3(aim_x, rest.y, aim_z)
			_target_normal[i] = Vector3.UP
			_valid[i] = false
			_errors[i] = _foot[i].distance_to(_target[i])
			continue
		var position: Vector3 = hit["position"]
		var normal: Vector3 = hit["normal"]
		_target[i] = position
		_target_normal[i] = normal
		_errors[i] = _foot[i].distance_to(position)
		_lower_to_y = minf(_lower_to_y, needs_y)
		# Rise is measured from the height the foot stands (or stood) on: the ground under it while planted, and the
		# last planted height while it hovers or swings (never from the lifted arc, nor from a body-fixed rest point
		# that a tilted body carries well above the ground).
		var stand_y: float = _foot[i].y
		if leg_state == GaitSolver.LegState.PLANTED:
			_stand_y[i] = _foot[i].y
		else:
			stand_y = _stand_y[i]
		var checked: bool = about_to_lift or leg_state == GaitSolver.LegState.SWINGING
		var valid_now: bool = _foothold_valid(position, normal, stand_y, hip_world, limit, space, checked)
		if not valid_now and about_to_lift:
			# Too high, too steep or out of reach: take the farthest valid foothold between the current foot and
			# the target (a shorter step). The leg blocks only when none is valid (GDD 8.2).
			for fraction in SHORTEN_FRACTIONS:
				var sx: float = lerpf(_foot[i].x, position.x, fraction)
				var sz: float = lerpf(_foot[i].z, position.z, fraction)
				_ray.from = Vector3(sx, gt.origin.y + ray_up, sz)
				_ray.to = Vector3(sx, gt.origin.y + ray_up - ray_len, sz)
				var shorter: Dictionary = space.intersect_ray(_ray)
				rays_this_tick += 1
				if shorter.is_empty():
					continue
				var candidate: Vector3 = shorter["position"]
				var candidate_normal: Vector3 = shorter["normal"]
				if _foothold_valid(candidate, candidate_normal, stand_y, hip_world, limit, space, true):
					_target[i] = candidate
					_target_normal[i] = candidate_normal
					_errors[i] = _foot[i].distance_to(candidate)
					valid_now = true
					break
			if not valid_now:
				# A rock in the way of the whole line (a steep or too tall flank): step around it. Footholds to the
				# sides of the target, then to the sides of the halfway point, nearest to the line first.
				var across: Vector3 = gt.basis * Vector3.RIGHT
				across = Vector3(across.x, 0.0, across.z).normalized()
				for side_scale in SIDESTEP_LINE_FRACTIONS:
					var line_x: float = lerpf(_foot[i].x, position.x, side_scale)
					var line_z: float = lerpf(_foot[i].z, position.z, side_scale)
					for offset in SIDESTEP_OFFSETS:
						var ox: float = line_x + across.x * offset
						var oz: float = line_z + across.z * offset
						_ray.from = Vector3(ox, gt.origin.y + ray_up, oz)
						_ray.to = Vector3(ox, gt.origin.y + ray_up - ray_len, oz)
						var beside: Dictionary = space.intersect_ray(_ray)
						rays_this_tick += 1
						if beside.is_empty():
							continue
						if _foothold_valid(beside["position"], beside["normal"], stand_y, hip_world, limit, space, true):
							_target[i] = beside["position"]
							_target_normal[i] = beside["normal"]
							_errors[i] = _foot[i].distance_to(beside["position"])
							valid_now = true
							break
					if valid_now:
						break
		_valid[i] = valid_now
		if leg_state == GaitSolver.LegState.PLANTED and hip_world.distance_to(_foot[i]) > limit * REACH_STRESS:
			# A planted foot near the end of its reach is about to stop the body (rule 5): it must step now,
			# even if its own target happens to be close (a dip under the foot).
			_errors[i] = maxf(_errors[i], (trigger_ratio + 0.05) * leg.reach)
	return clampf(fastest / _top_speed, 0.0, 1.0)


## Step-up, slope, reach and line of sight for one foothold.
func _foothold_valid(
	position: Vector3,
	normal: Vector3,
	stand_y: float,
	hip_world: Vector3,
	limit: float,
	space: PhysicsDirectSpaceState3D,
	check_sight: bool
) -> bool:
	if not GaitSolver.is_target_valid(position.y - stand_y, normal, _step_up, _max_slope):
		return false
	if hip_world.distance_to(position) > limit:
		return false
	if check_sight:
		# The hip must see the foothold: a foot never lands behind a thin wall its ray started above.
		# (From the hip, or from just above the foothold when that is higher: a block taller than the hip
		# must still be climbable, a thin wall must still hide what is behind it.)
		var eye := Vector3(hip_world.x, maxf(hip_world.y, position.y + SIGHT_MARGIN), hip_world.z)
		var toward: Vector3 = (eye - position).normalized()
		_sight.from = eye
		_sight.to = position + toward * SIGHT_MARGIN
		rays_this_tick += 1
		if not space.intersect_ray(_sight).is_empty():
			return false
	return true


## A swinging foot homes on its live target, so it lands where the rest point has moved to.
func _homing_swings() -> void:
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING and _valid[i]:
			_to[i] = _target[i]
			_to_normal[i] = _target_normal[i]


## Collects the body's collider shapes and their local transforms (after the build's shapes were made).
func _cache_shapes() -> void:
	_shape_nodes.clear()
	_shape_local.clear()
	for child in get_children():
		if child is CollisionShape3D and not child.is_queued_for_deletion():
			_shape_nodes.append(child)
			_shape_local.append(Transform3D(Basis.IDENTITY, child.position))


## Pushes the body horizontally out of any static geometry its colliders overlap. True when it moved.
func _depenetrate() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var moved: bool = false
	for attempt in 6:
		var push := Vector3.ZERO
		var root: Transform3D = global_transform
		for k in _shape_nodes.size():
			_shape_query.shape = _shape_nodes[k].shape
			_shape_query.transform = root * _shape_local[k]
			var contacts: PackedVector3Array = space.collide_shape(_shape_query, 16)
			for c in range(0, contacts.size() - 1, 2):
				var along: Vector3 = contacts[c + 1] - contacts[c]
				along.y = 0.0
				if along.length() > push.length():
					push = along
		if push.length() < 0.0005:
			break
		_origin += push + push.normalized() * 0.01
		global_transform = Transform3D(global_transform.basis, global_transform.origin + push + push.normalized() * 0.01)
		moved = true
	return moved


## Where the world touches the body in pose `root`: fills the contact buffers (point on the world, push-out
## normal, depth) and classifies them. 0 = clear, 1 = overlapping ground inside the grip (the body must rise),
## 2 = overlapping a wall or block face (`_wall_n` is then the horizontal normal of the deepest wall contact).
## Overlap with ground the walker can walk on (a slope inside its grip, a crest) is not a collision. Every contact
## counts; none is ignored. One `collide_shape` query per collider shape (a `body_test_motion` costs about 0.5 to 2 ms
## here, these about 3 microseconds each), with the same 1 mm margin the body test used.
func _overlap_state(root: Transform3D) -> int:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	_contact_count = 0
	var state: int = 0
	var wall_depth: float = -1.0
	for k in _shape_nodes.size():
		_shape_query.shape = _shape_nodes[k].shape
		_shape_query.transform = root * _shape_local[k]
		var pairs: PackedVector3Array = space.collide_shape(_shape_query, SHAPE_MAX_PAIRS)
		shape_queries_this_tick += 1
		for i in range(0, pairs.size() - 1, 2):
			if _contact_count >= MAX_CONTACTS:
				break
			var push: Vector3 = pairs[i + 1] - pairs[i]
			var depth: float = push.length()
			var normal: Vector3 = push / depth if depth > 0.000001 else Vector3.UP
			var point: Vector3 = pairs[i + 1]
			_contact_point[_contact_count] = point
			_contact_normal[_contact_count] = normal
			_contact_depth[_contact_count] = depth
			_contact_count += 1
			if _contact_is_wall(normal, point):
				state = 2
				if depth > wall_depth:
					wall_depth = depth
					_wall_n = _horizontal(normal, _wall_n)
					_wall_pt = point
			elif state == 0:
				state = 1
	return state


## The horizontal unit direction of `normal`; `fallback` when it points (almost) straight up or down.
static func _horizontal(normal: Vector3, fallback: Vector3) -> Vector3:
	var flat := Vector3(normal.x, 0.0, normal.z)
	if flat.length_squared() < 0.000001:
		return fallback
	return flat.normalized()


## How far the body must rise to clear every ground contact of the last `_overlap_state`: depth over the normal's
## upward part, the worst contact.
func _contact_rise_need() -> float:
	var need: float = 0.0
	for k in _contact_count:
		need = maxf(need, _contact_depth[k] / maxf(_contact_normal[k].y, MIN_RISE_NORMAL_Y))
	return need


## The pitch (radians) that lifts the worst ground contact clear: its rise need over its lever arm from the pivot.
func _pitch_need(inverse_root: Transform3D, pivot_z: float) -> float:
	var angle: float = 0.0
	for k in _contact_count:
		var lever: float = maxf(absf((inverse_root * _contact_point[k]).z - pivot_z), MIN_PITCH_LEVER)
		var need: float = _contact_depth[k] / maxf(_contact_normal[k].y, MIN_RISE_NORMAL_Y)
		angle = maxf(angle, need / lever)
	return angle


## How far the pose must rise for every hip to stand at least HIP_CLEARANCE above the ground straight below it.
## Ground that is steeper than the grip and would have to be ridden over sets `_clear_wall` and `_wall_n`.
func _clearance_rise(pose: Transform3D) -> float:
	_clear_wall = false
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var rise: float = 0.0
	for i in _legs.size():
		var hip: Vector3 = pose * _hips_local[i]
		_sight.from = hip + Vector3.UP * (0.6 * _legs[i].reach)
		_sight.to = hip + Vector3.DOWN * 2.0
		var hit: Dictionary = space.intersect_ray(_sight)
		rays_this_tick += 1
		if not hit.is_empty():
			var need: float = hit["position"].y + HIP_CLEARANCE - hip.y
			if need > 0.0 and _is_wall(hit["normal"]):
				# Ground steeper than the grip is a wall: the body does not ride up it (a free move away from it may).
				var flat: Vector3 = _horizontal(hit["normal"], _wall_n)
				if not _free_active or _free_motion.dot(flat) < -FACE_APPROACH_EPSILON:
					_clear_wall = true
					_wall_n = flat
			rise = maxf(rise, need)
	return rise


## Ground steeper than the grip and taller than the step-up under any rest foot of the pose: the stance would have to
## stand on a wall, so the body stops (and slides) there, a stance away from the face, and the legs on that side keep
## apron to step on. Sets `_clear_wall` and `_wall_n` like `_clearance_rise`.
func _stance_on_wall(pose: Transform3D) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var ray_up: float = ray_up_ratio * _mean_reach
	for i in _legs.size():
		var rest: Vector3 = pose * _legs[i].rest_local
		_sight.from = Vector3(rest.x, pose.origin.y + ray_up, rest.z)
		_sight.to = Vector3(rest.x, pose.origin.y + ray_up - ray_length_ratio * _mean_reach - ray_up, rest.z)
		var hit: Dictionary = space.intersect_ray(_sight)
		rays_this_tick += 1
		if not hit.is_empty() and _contact_is_wall(hit["normal"], hit["position"], WALL_PROBE_LENGTH_FACE):
			# A face, not a rock: steep ground a stance-width to both sides of the foot too (the stance guard
			# and the collider walls deal with boulders).
			var flat: Vector3 = _horizontal(hit["normal"], Vector3.ZERO)
			if _free_active and _free_motion.dot(flat) >= -FACE_APPROACH_EPSILON:
				# A move that does not bring the walker closer to this face may leave it; any other face still counts.
				continue
			var along := Vector3(flat.z, 0.0, -flat.x) * STANCE_FACE_HALF_WIDTH
			if _steep_ground_at(hit["position"] + along, ray_up) and _steep_ground_at(hit["position"] - along, ray_up):
				_clear_wall = true
				_wall_n = _horizontal(hit["normal"], _wall_n)
				_wall_pt = hit["position"]
				return


## True when the ground straight below (x, z) of `spot`, found from `ray_up` above its height, is steeper than the grip.
func _steep_ground_at(spot: Vector3, ray_up: float) -> bool:
	_sight.from = Vector3(spot.x, spot.y + ray_up, spot.z)
	_sight.to = Vector3(spot.x, spot.y - ray_up, spot.z)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(_sight)
	rays_this_tick += 1
	return not hit.is_empty() and _is_wall(hit["normal"])


## A surface steeper than the build's grip (plus the round collider's contact slack) is a wall.
func _is_wall(normal: Vector3) -> bool:
	return rad_to_deg(normal.angle_to(Vector3.UP)) > _max_slope + CONTACT_SLOPE_MARGIN_DEG


## The height of the wall probe at (x, z): the feet plane + the height the legs can overcome (today the step-up) + 1 cm.
## The one place that defines how tall an obstacle must be to count as a wall.
func _wall_probe_height(x: float, z: float) -> float:
	return plane_height(_ref_plane, x, z) + _step_up + WALL_PROBE_LIFT


## A steep contact is a wall only if the obstacle it belongs to stands taller than the legs' step-up above the
## feet's plane: a low rock, however round, is stepped onto (the body pitches and rises over it). The height of the
## face is measured, not the height of the contact: a horizontal ray at the feet plane + step-up + 1 cm runs from just
## outside the contact into the obstacle; any hit within WALL_PROBE_LENGTH means the face is taller. The answer is
## cached for the tick (the same contact is met by every candidate pose).
func _contact_is_wall(normal: Vector3, point: Vector3, probe_length: float = WALL_PROBE_LENGTH) -> bool:
	if not _is_wall(normal):
		return false
	var flat: Vector3 = _horizontal(normal, Vector3.ZERO)
	if flat == Vector3.ZERO:
		return true
	# The push-out direction of an edge or corner penetration is not the surface's normal: read the surface itself
	# at the contact, and let ground that is inside the grip stay ground. That answer depends on the contact's height
	# and normal, so its cache key holds both; the height probe below depends on the cell and direction only.
	var surface_key := Vector3i(
		roundi(point.x * WALL_CACHE_CELLS_PER_M),
		roundi(point.z * WALL_CACHE_CELLS_PER_M),
		(
			roundi(point.y * WALL_CACHE_CELLS_PER_M) * 4096
			+ (roundi(atan2(flat.x, flat.z) * WALL_CACHE_ANGLES_PER_RAD) + 16) * 32
			+ roundi((normal.y + 1.0) * 8.0)
		)
	)
	var ground: bool
	if _surface_cache.has(surface_key):
		ground = _surface_cache[surface_key]
	else:
		_sight.from = point + normal * SURFACE_PROBE
		_sight.to = point - normal * SURFACE_PROBE
		var surface: Dictionary = get_world_3d().direct_space_state.intersect_ray(_sight)
		rays_this_tick += 1
		ground = not surface.is_empty() and not _is_wall(surface["normal"])
		_surface_cache[surface_key] = ground
	if ground:
		return false
	var key := Vector3i(
		roundi(point.x * WALL_CACHE_CELLS_PER_M),
		roundi(point.z * WALL_CACHE_CELLS_PER_M),
		roundi(atan2(flat.x, flat.z) * WALL_CACHE_ANGLES_PER_RAD) + (100 if probe_length > WALL_PROBE_LENGTH else 0)
	)
	if _wall_cache.has(key):
		return _wall_cache[key]
	var height: float = _wall_probe_height(point.x, point.z)
	_sight.from = Vector3(point.x + flat.x * WALL_PROBE_BACK, height, point.z + flat.z * WALL_PROBE_BACK)
	_sight.to = Vector3(
		point.x - flat.x * probe_length, height, point.z - flat.z * probe_length
	)
	var taller: bool = not get_world_3d().direct_space_state.intersect_ray(_sight).is_empty()
	rays_this_tick += 1
	_wall_cache[key] = taller
	return taller


func _apply_move(delta: float) -> void:
	var count: int = _legs.size()
	var planted_count: int = 0
	for i in count:
		if _solver.state_of(i) == GaitSolver.LegState.PLANTED:
			_planted[i] = 1
			_fit[planted_count] = _foot[i]
			planted_count += 1
		else:
			_planted[i] = 0
		# A swinging foot must still be able to land in reach, so its landing point holds the body like a planted foot.
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING:
			_check_feet[i] = _to[i]
			_check_flags[i] = 1
		else:
			_check_feet[i] = _foot[i]
			_check_flags[i] = _planted[i]
	if planted_count < 3:
		for i in count:
			_fit[i] = _foot[i]
		planted_count = count
	var plane: Plane = fit_plane(_fit, planted_count)
	_ref_plane = plane

	var cur_pos: Vector3 = _origin
	var des_yaw: float = _yaw + deg_to_rad(_yaw_rate_cmd) * delta
	var des_x: float = cur_pos.x + _velocity_h.x * delta
	var des_z: float = cur_pos.z + _velocity_h.z * delta
	var tilt_target: Vector3 = clamp_tilt(plane.normal, _tilt_limit())
	# Pitch ahead: lean toward the plane through the ground the legs are about to step on (a slope's foot, a shelf
	# edge) before the feet get there. On even ground the two planes are the same.
	var ahead_count: int = 0
	for i in count:
		if _valid[i]:
			_fit_ahead[ahead_count] = _target[i]
			ahead_count += 1
	# The lean is weighted by the share of valid targets (one target flipping moves it by 1/legs of its weight, not
	# all of it) and the weight is low-passed.
	var ahead_goal: float = 0.0
	if ahead_count >= 3:
		var ahead_plane: Plane = fit_plane(_fit_ahead, ahead_count)
		var ahead_target: Vector3 = clamp_tilt(ahead_plane.normal, _tilt_limit())
		if (ahead_target - _ahead_n).length_squared() > 0.0000000001:
			_ahead_n = _ahead_n.slerp(ahead_target, ease_factor(delta, PITCH_AHEAD_SMOOTH_TIME)).normalized()
		ahead_goal = PITCH_AHEAD_WEIGHT * float(ahead_count) / float(count)
	_ahead_weight = ease_toward(_ahead_weight, ahead_goal, delta, PITCH_AHEAD_SMOOTH_TIME)
	if _ahead_weight > 0.001:
		tilt_target = clamp_tilt((tilt_target + _ahead_weight * _ahead_n).normalized(), _tilt_limit())
	var tilt_factor: float = ease_factor(delta, tilt_smooth_time)
	var des_n: Vector3 = _tilt_n
	if tilt_factor > 0.0 and (tilt_target - _tilt_n).length_squared() > 0.0000000001:
		des_n = _tilt_n.slerp(tilt_target, tilt_factor).normalized()
	var base_target: float = (
		plane_height(plane, des_x, des_z) + body_height_ratio * _mean_reach / plane.normal.y
	)
	# A foothold below the reach of the hip: lower the body toward it before the foot goes for it.
	base_target = minf(base_target, _lower_to_y)
	var des_base: float = ease_toward(_base_y, base_target, delta, height_settle_time)
	var des_origin := Vector3(des_x, des_base + _bob_offset(delta), des_z)

	var fraction: float = safe_fraction(
		cur_pos, _yaw, _tilt_n, des_origin, des_yaw, des_n, _hips_local, _check_feet, _check_flags, _limits
	)
	held_this_tick = fraction < 0.9999
	# Rule 5 on the whole step first. If it holds the body, the move (translation and yaw) and the height and
	# tilt each get their own fraction, so a held height cannot freeze the walk and a held walk cannot stop the
	# body lowering toward a foothold; the combination is checked again before it is used.
	var move_fraction: float = fraction
	var vertical_fraction: float = fraction
	if fraction < 1.0:
		var level := Vector3(des_origin.x, cur_pos.y, des_origin.z)
		var still := Vector3(cur_pos.x, des_origin.y, cur_pos.z)
		move_fraction = maxf(
			fraction,
			safe_fraction(
				cur_pos, _yaw, _tilt_n, level, des_yaw, _tilt_n, _hips_local, _check_feet, _check_flags, _limits
			)
		)
		vertical_fraction = maxf(
			fraction,
			safe_fraction(
				cur_pos, _yaw, _tilt_n, still, _yaw, des_n, _hips_local, _check_feet, _check_flags, _limits
			)
		)
	var origin := Vector3(
		lerpf(cur_pos.x, des_origin.x, move_fraction),
		lerpf(cur_pos.y, des_origin.y, vertical_fraction),
		lerpf(cur_pos.z, des_origin.z, move_fraction)
	)
	var yaw: float = lerpf(_yaw, des_yaw, move_fraction)
	var tilt: Vector3 = des_n if vertical_fraction >= 1.0 else _tilt_n.slerp(des_n, vertical_fraction)
	var base_y: float = lerpf(_base_y, des_base, vertical_fraction)
	if move_fraction > fraction or vertical_fraction > fraction:
		var composed: Transform3D = pose_transform(origin, yaw, tilt)
		var start: Transform3D = pose_transform(cur_pos, _yaw, _tilt_n)
		if not feet_in_reach(composed, start, _hips_local, _check_feet, _check_flags, _limits):
			move_fraction = fraction
			vertical_fraction = fraction
			origin = cur_pos.lerp(des_origin, fraction)
			yaw = lerpf(_yaw, des_yaw, fraction)
			tilt = des_n if fraction >= 1.0 else _tilt_n.slerp(des_n, fraction)
			base_y = lerpf(_base_y, des_base, fraction)
	# Resolve the pose against the ground: where in-grip ground touches the colliders the body pitches first and rises
	# second, no faster than MAX_PUSH_RATE; it never ends a tick overlapping anything. A wall at the new pose takes the
	# into-face part of the move away and keeps the along-face part (a slide). If the pose is out of reach or too fast a
	# push, the largest fraction of the step that works is taken; only when none does is the body held.
	var motion := Vector3(origin.x - cur_pos.x, 0.0, origin.z - cur_pos.z)
	_s_pose = pose_transform(cur_pos, _yaw, _tilt_n)
	_s_origin = cur_pos
	_s_base = _base_y
	_s_yaw = _yaw
	_s_tilt = _tilt_n
	_g_origin = origin
	_g_base = base_y
	_g_yaw = yaw
	_g_tilt = tilt
	var rise_cap: float = MAX_PUSH_RATE * delta
	var wall_hit: bool = false
	var face_blocked: bool = false
	var slid: bool = false
	_tick_delta = delta
	_flip_lock = maxi(_flip_lock - 1, 0)
	var state: int = _try_fraction(1.0, rise_cap)
	if state == 2:
		# A wall at the new pose: try the new position with the old tilt and height before sliding.
		_g_origin = Vector3(origin.x, cur_pos.y, origin.z)
		_g_base = _base_y
		_g_tilt = _tilt_n
		state = _try_fraction(1.0, rise_cap)
		var face: bool = state == 2 and _clear_wall
		if face and motion.dot(_wall_n) >= -FACE_APPROACH_EPSILON:
			# Not closer to the face (backing off, turning, strafing along it): allowed, whatever the stance stands
			# on. A walker that starts on a face must be able to walk off it. A second face the move enters (a
			# concave corner, two over-grip faces meeting) still blocks it: only faces the move approaches count.
			_free_motion = motion
			_free_active = true
			state = _try_fraction(1.0, rise_cap)
			_free_active = false
			face = state == 2 and _clear_wall
		_went_round = false
		if state == 2:
			state = _slide_along_wall(cur_pos, motion, rise_cap, face)
			if state == 2 and not face and motion.length_squared() > 0.0000001:
				# The slide is blocked too (a corner, another rock): step sideways, the side last used first. The
				# other side only after the lock ran out (a V between two rocks must not shuffle left and right).
				var tangent := Vector3(-_wall_n.z, 0.0, _wall_n.x)
				var step_length: float = minf(
					motion.length() * SLIDE_AROUND_SHARE, _top_speed * GO_ROUND_MAX_RATIO * delta
				)
				for attempt in 2:
					if attempt == 1 and _flip_lock > 0:
						break
					var sign_try: float = _slide_side if attempt == 0 else -_slide_side
					_g_origin = Vector3(
						cur_pos.x + tangent.x * sign_try * step_length,
						cur_pos.y,
						cur_pos.z + tangent.z * sign_try * step_length
					)
					state = _try_fraction(1.0, rise_cap)
					if state != 2:
						if attempt == 1:
							_flip_lock = SIDE_FLIP_LOCK_TICKS
						_slide_side = sign_try
						_went_round = true
						break
			slid = state == 0
			wall_hit = state == 2
			face_blocked = wall_hit and face
	_push_rise = 0.0
	var pitch_added: float = 0.0
	if state == 0:
		_push_rise = _r_rise
		pitch_added = _r_pitch
		yaw = _r_yaw
		origin = _r_origin
		base_y = _r_base
		tilt = _r_tilt
		_held_state = 0
	else:
		held_this_tick = true
		var found: bool = false
		if state != 2:
			# The same reason held the whole pose last tick: one probe, not the whole search.
			var tries: int = REPEAT_TRIES if state == _held_state else FRACTION_TRIES
			found = _search_fraction(state, _r_need if state == 1 else _r_rise, rise_cap, tries)
			if found:
				_push_rise = _b_rise
				pitch_added = _b_pitch
				yaw = _b_yaw
				origin = _b_origin
				base_y = _b_base
				tilt = _b_tilt
		if found:
			_held_state = 0
		else:
			_held_state = state
			origin = cur_pos
			base_y = _base_y
			tilt = _tilt_n
			yaw = _yaw
	block_cause = ""
	if wall_hit:
		block_cause = "face" if face_blocked else "wall"
	elif held_this_tick:
		match state:
			1:
				block_cause = "ground-left"
			3:
				block_cause = "rise-cap"
			4:
				block_cause = "reach"
			_:
				block_cause = "legs"
	var actual := Vector3((origin.x - cur_pos.x) / delta, 0.0, (origin.z - cur_pos.z) / delta)
	var commanded_len: float = _velocity_h.length()
	# A hold by the legs keeps the commanded speed (the body resumes at speed, no climb back up the ramp); a slide
	# keeps the commanded speed too (each tick removes its into-face part again; a collapsed speed would pin the walker
	# against a rock); only a wall that stops the retry too zeroes it.
	if wall_hit and commanded_len > 0.0001 and _velocity_h.dot(_wall_n) < 0.0:
		_velocity_h = actual
		velocity_resets += 1
	if slid:
		_slide_n = _wall_n
		_slide_ticks = SLIDE_MEMORY_TICKS
		var into_wall: float = _velocity_h.dot(_wall_n)
		if not _went_round and into_wall < 0.0:
			# Pressed into a wall that goes on: the commanded speed keeps only its along-face part (a rock is gone
			# round at the commanded speed, so that one is kept whole).
			_velocity_h -= _wall_n * into_wall
	else:
		_slide_ticks = maxi(_slide_ticks - 1, 0)
	velocity = actual
	var actual_rate: float = rad_to_deg(yaw - _yaw) / delta
	if wall_hit and absf(_yaw_rate_cmd) > 0.0001:
		_yaw_rate_cmd = actual_rate
	yaw_rate_dps = actual_rate
	_base_y = base_y
	_yaw = yaw
	max_tilt_step_deg = maxf(max_tilt_step_deg, rad_to_deg(_tilt_n.angle_to(tilt)))
	max_resolve_pitch_deg = maxf(max_resolve_pitch_deg, rad_to_deg(pitch_added))
	_tilt_n = tilt
	_origin = origin
	max_push_rise = maxf(max_push_rise, _push_rise)
	_apply_transforms()
	_height_above_plane = plane.distance_to(origin)


## Set by `_clearance_rise` when a hip would have to rise over ground steeper than the grip.
var _clear_wall: bool = false
## The horizontal normal of the wall the last result named (a collider contact or steep ground under a hip), pointing
## out of the wall toward the walker. The move slides along it.
var _wall_n: Vector3 = Vector3.FORWARD
## Where the world touches the body at that wall, and which way round a rock the last head-on slide went.
var _wall_pt: Vector3 = Vector3.ZERO
var _slide_side: float = 1.0
## The plane of the planted feet this tick (the reference for 'how tall is this obstacle').
var _ref_plane: Plane = Plane(Vector3.UP, 0.0)
## Height-probe answers of this tick, by contact cell and direction (cleared every tick).
var _wall_cache: Dictionary = {}
## Surface-read answers of this tick, by contact cell, height and normal (cleared every tick).
var _surface_cache: Dictionary = {}
## While a move that leaves a face is resolved (`_free_active`): that move. Faces it does not approach do not block it.
var _free_motion: Vector3 = Vector3.ZERO
var _free_active: bool = false
## True when this tick's slide went round a rock (a sidestep), and ticks left before the go-round side may flip again.
var _went_round: bool = false
var _flip_lock: int = 0
var _tick_delta: float = 1.0 / 60.0
## Collider shapes of the body and their transforms relative to the node (cached when the build changes).
var _shape_nodes: Array[CollisionShape3D] = []
var _shape_local: Array[Transform3D] = []
## Contacts of the last `_overlap_state` (reused buffers).
var _contact_count: int = 0
var _contact_point: PackedVector3Array = PackedVector3Array()
var _contact_normal: PackedVector3Array = PackedVector3Array()
var _contact_depth: PackedFloat32Array = PackedFloat32Array()
## Start and goal poses of the tick's candidate search (`_try_fraction`).
var _s_pose: Transform3D = Transform3D.IDENTITY
var _s_origin: Vector3 = Vector3.ZERO
var _s_base: float = 0.0
var _s_yaw: float = 0.0
var _s_tilt: Vector3 = Vector3.UP
var _g_origin: Vector3 = Vector3.ZERO
var _g_base: float = 0.0
var _g_yaw: float = 0.0
var _g_tilt: Vector3 = Vector3.UP
var _r_yaw: float = 0.0
## Resolved pose of `_resolve` (members, to avoid allocating per tick).
var _r_origin: Vector3 = Vector3.ZERO
var _r_base: float = 0.0
var _r_tilt: Vector3 = Vector3.UP
var _r_rise: float = 0.0
## The total rise the resolve would need when it stopped at the rise cap (ground left over), and the pitch it added.
var _r_need: float = 0.0
var _r_pitch: float = 0.0
## The best candidate of the fraction search.
var _b_origin: Vector3 = Vector3.ZERO
var _b_base: float = 0.0
var _b_tilt: Vector3 = Vector3.UP
var _b_yaw: float = 0.0
var _b_rise: float = 0.0
var _b_pitch: float = 0.0
## Why the last tick held the whole pose (a `_try_fraction` code), 0 when it moved.
var _held_state: int = 0
## Ticks left of the memory of the last slide, and its wall normal: the legs lead along the face, not into it.
var _slide_ticks: int = 0
var _slide_n: Vector3 = Vector3.ZERO
## The push-up the last tick applied (telemetry: pop on crests).
var _push_rise: float = 0.0
var max_push_rise: float = 0.0
## Largest tick-to-tick change of the body tilt (degrees).
var max_tilt_step_deg: float = 0.0
## Largest pitch the contact resolve added in one tick (degrees), apart from the smoothed tilt.
var max_resolve_pitch_deg: float = 0.0
## Low-passed tilt of the plane through the next footholds, and how strongly it leans the body.
var _ahead_n: Vector3 = Vector3.UP
var _ahead_weight: float = PITCH_AHEAD_WEIGHT


## Hips and colliders against the ground at a pose: raise for hip clearance, then pitch (toward the contact, by the
## smallest angle that clears) and raise until nothing overlaps; hips are read again after a pitch or raise. Returns the
## final overlap state (0 clear, 1 ground, 2 wall) and fills `_r_*` (`may_pitch` false raises only: a spawn keeps the
## tilt of the ground under its feet). Ground steeper than the grip never raises the
## body: it is a wall. A rise beyond `rise_cap` is not applied: the state stays 1 and `_r_need` says how much it needs.
func _resolve(
	origin: Vector3,
	base_y: float,
	yaw: float,
	tilt: Vector3,
	rise_cap: float = 10.0,
	may_pitch: bool = true,
	block_on_faces: bool = true
) -> int:
	var applied: float = 0.0
	var tilt_in: Vector3 = tilt
	var state: int = 0
	var pitched: bool = not may_pitch
	var across: Vector3 = (Basis(Vector3.UP, yaw) * Vector3.RIGHT).normalized()
	_r_need = 0.0
	var last_changed: bool = false
	for pass_index in RESOLVE_PASSES:
		var rise: float = _clearance_rise(pose_transform(origin, yaw, tilt))
		if block_on_faces and not _clear_wall and pass_index == 0:
			_stance_on_wall(pose_transform(origin, yaw, tilt))
		if block_on_faces and _clear_wall:
			_store_resolved(origin, base_y, tilt, tilt_in, applied)
			return 2
		if pass_index > 0 and rise <= HIP_RISE_EPSILON:
			break
		if rise > HIP_RISE_EPSILON:
			origin.y += rise
			base_y += rise
			applied += rise
		state = _overlap_state(pose_transform(Vector3(origin.x, base_y, origin.z), yaw, tilt))
		var changed: bool = false
		if state == 1 and not pitched:
			pitched = true
			# A contact ahead of the centre pitches the nose up, a contact behind pitches it down. The body pitches
			# about the support on the far side of the contact (rear going up, front at an edge).
			var root: Transform3D = pose_transform(Vector3(origin.x, base_y, origin.z), yaw, tilt)
			var inverse: Transform3D = root.affine_inverse()
			var ahead: float = 0.0
			for k in _contact_count:
				ahead += (inverse * _contact_point[k]).z
			var direction: float = 1.0 if ahead < 0.0 else -1.0
			var pivot_local := Vector3(0.0, _pivot_y, direction * _pivot_z)
			var pivot_world: Vector3 = root * pivot_local
			var full_angle: float = deg_to_rad(PITCH_MAX_DEG)
			var angle: float = minf(
				_pitch_need(inverse, pivot_local.z) * PITCH_OVERSHOOT + deg_to_rad(PITCH_SLACK_DEG), full_angle
			)
			var tilt_zero: Vector3 = tilt
			for attempt in PITCH_PASSES:
				var candidate: Vector3 = clamp_tilt(
					tilt_zero.rotated(across, direction * angle), _tilt_limit()
				)
				if (candidate - tilt).length_squared() < 0.0000001:
					break
				var c_origin: Vector3 = _pivot_origin(pivot_world, pivot_local, yaw, candidate)
				var c_state: int = _overlap_state(pose_transform(c_origin, yaw, candidate))
				if c_state == 2:
					break
				var lift: float = c_origin.y - base_y
				applied += maxf(lift, 0.0)
				base_y += lift
				origin += Vector3(c_origin.x - origin.x, lift, c_origin.z - origin.z)
				tilt = candidate
				state = c_state
				changed = true
				if c_state == 0 or angle >= full_angle - 0.000001:
					break
				# Still touching: the new contacts say how much more.
				var rest_inverse: Transform3D = pose_transform(Vector3(origin.x, base_y, origin.z), yaw, tilt).affine_inverse()
				angle = minf(angle + _pitch_need(rest_inverse, pivot_local.z) * PITCH_OVERSHOOT, full_angle)
		var raised: int = 0
		while state == 1 and raised < RAISE_PASSES:
			var need: float = _contact_rise_need() + RAISE_MARGIN
			if applied + need > rise_cap + 0.0001:
				_r_need = applied + need
				break
			origin.y += need
			base_y += need
			applied += need
			raised += 1
			changed = true
			state = _overlap_state(pose_transform(Vector3(origin.x, base_y, origin.z), yaw, tilt))
		last_changed = changed
		if state != 0 or not changed:
			break
	if last_changed and state == 0:
		# The last pass moved the pose after the hip rays were read: read them again, and make sure a pitch did not
		# carry a rest foot onto a face.
		var again: float = _clearance_rise(pose_transform(origin, yaw, tilt))
		if block_on_faces and _clear_wall:
			_store_resolved(origin, base_y, tilt, tilt_in, applied)
			return 2
		if again > HIP_RISE_EPSILON:
			origin.y += again
			base_y += again
			applied += again
		if block_on_faces and tilt != tilt_in:
			_clear_wall = false
			_stance_on_wall(pose_transform(origin, yaw, tilt))
			if _clear_wall:
				_store_resolved(origin, base_y, tilt, tilt_in, applied)
				return 2
	_store_resolved(origin, base_y, tilt, tilt_in, applied)
	return state


func _store_resolved(origin: Vector3, base_y: float, tilt: Vector3, tilt_in: Vector3, applied: float) -> void:
	_r_origin = origin
	_r_base = base_y
	_r_tilt = tilt
	_r_rise = applied
	_r_pitch = tilt_in.angle_to(tilt)
	if _r_need < applied:
		_r_need = applied


## Body origin after the tilt changes about a fixed pivot point (the pose root sits at the base height `base_y`).
func _pivot_origin(pivot_world: Vector3, pivot_local: Vector3, yaw: float, tilt: Vector3) -> Vector3:
	var basis: Basis = pose_transform(Vector3.ZERO, yaw, tilt).basis
	var moved: Vector3 = pivot_world - basis * pivot_local
	return moved


## One candidate for the tick: the fraction `f` of the way from the current pose (`_s_*`) to the swept goal (`_g_*`),
## resolved against the ground. 0 accepted; 1 ground left over; 2 wall; 3 the push-up is faster than the cap; 4 the
## feet cannot reach it. Fills `_r_*` and `_r_yaw`.
func _try_fraction(f: float, rise_cap: float, block_on_faces: bool = true) -> int:
	var origin: Vector3 = _s_origin.lerp(_g_origin, f)
	var yaw: float = lerpf(_s_yaw, _g_yaw, f)
	var tilt: Vector3 = _g_tilt if f >= 1.0 else _s_tilt.slerp(_g_tilt, f)
	var base_y: float = lerpf(_s_base, _g_base, f)
	var state: int = _resolve(origin, base_y, yaw, tilt, rise_cap, true, block_on_faces)
	if state != 0:
		return state
	if _r_rise > rise_cap + 0.0001:
		return 3
	if not feet_in_reach(
		pose_transform(_r_origin, yaw, _r_tilt), _s_pose, _hips_local, _check_feet, _check_flags, _limits
	):
		return 4
	_r_yaw = yaw
	return 0


## The goal failed at fraction 1 (`first_state`, needing `first_need` of rise): the largest fraction of the step that
## works, found from an estimate (the rise grows with the fraction) and then by bisecting between the best fraction
## that worked and the smallest that failed, `tries` candidates in all. Fills `_b_*`.
func _search_fraction(first_state: int, first_need: float, rise_cap: float, tries: int) -> bool:
	var f: float = 0.5
	if tries < FRACTION_TRIES:
		f = REPEAT_FRACTION
	elif first_need > rise_cap:
		f = clampf(rise_cap / first_need * FRACTION_SHRINK, MIN_FRACTION, 0.9)
	var low: float = -1.0
	var high: float = 1.0
	for attempt in tries:
		var state: int = _try_fraction(f, rise_cap)
		if state == 0:
			low = f
			_b_origin = _r_origin
			_b_base = _r_base
			_b_tilt = _r_tilt
			_b_yaw = _r_yaw
			_b_rise = _r_rise
			_b_pitch = _r_pitch
			if high - low < FRACTION_RESOLUTION:
				break
			f = (low + high) * 0.5
		else:
			high = f
			var shrink: float = 0.5
			if state == 4:
				# Out of reach: the feet allow little, and the smallest fractions are the ones that pass.
				shrink = REACH_SHRINK
			if state == 1 and _r_need > rise_cap:
				shrink = clampf(rise_cap / _r_need * FRACTION_SHRINK, 0.2, 0.9)
			elif state == 3 and _r_rise > rise_cap:
				shrink = clampf(rise_cap / _r_rise * FRACTION_SHRINK, 0.2, 0.9)
			if low >= 0.0:
				f = (low + high) * 0.5
			else:
				# The estimate assumes the need is proportional to the fraction; if it missed, back off harder.
				f = maxf(f * (minf(shrink, 0.6) if attempt > 0 else shrink), MIN_FRACTION)
	return low >= 0.0


## True when the wall of the last contact goes on to both sides (a flat wall or block, not a rock): horizontal rays
## 0.6 m to either side of the contact, at its height, hit a surface at about the same depth.
func _face_continues() -> bool:
	var tangent := Vector3(-_wall_n.z, 0.0, _wall_n.x)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for side in [1.0, -1.0]:
		var start: Vector3 = _wall_pt + tangent * (side * FACE_PROBE_SIDE) + _wall_n * FACE_PROBE_BACK
		_sight.from = start
		_sight.to = start - _wall_n * (FACE_PROBE_BACK * 2.0 + FACE_PROBE_SLACK)
		rays_this_tick += 1
		if space.intersect_ray(_sight).is_empty():
			return false
	return true


## A wall stops the move: the part into the face goes, the part along it stays (a second wall in a corner takes its
## part too). The goal keeps the old tilt and height. Returns the `_try_fraction` code of the slid goal.
func _slide_along_wall(cur_pos: Vector3, motion: Vector3, rise_cap: float, face: bool = false) -> int:
	var state: int = 2
	var moved: Vector3 = motion
	for attempt in 2:
		var into: float = moved.dot(_wall_n)
		if into >= 0.0:
			break
		moved -= _wall_n * into * SLIDE_STANDOFF
		if attempt == 0 and not face and moved.length() < SLIDE_MIN_SHARE * motion.length() and not _face_continues():
			# Head-on into a rock (not a wall that goes on): go round it, to the side its contact lies on.
			var tangent := Vector3(-_wall_n.z, 0.0, _wall_n.x)
			var side: float = signf(tangent.dot(_wall_pt - cur_pos))
			if is_zero_approx(side) or _slide_ticks > 0 or _flip_lock > 0:
				# Keep going round the same way while the slide lasts (the contact's side flips as the rock passes).
				side = _slide_side
			_slide_side = side
			var round_speed: float = minf(-into * SLIDE_AROUND_SHARE, _top_speed * GO_ROUND_MAX_RATIO * _tick_delta)
			moved += tangent * side * round_speed
			_went_round = true
		_g_origin = Vector3(cur_pos.x + moved.x, cur_pos.y, cur_pos.z + moved.z)
		# Along a face the stance is still checked for any other face the slid move enters.
		_free_motion = moved
		_free_active = face
		state = _try_fraction(1.0, rise_cap)
		_free_active = false
		if state != 2:
			break
	return state


## Gait-synced bob: lowest as a group plants, highest mid-swing; fades in with speed.
func _bob_offset(delta: float) -> float:
	var speed_ratio: float = clampf(velocity.length() / _top_speed, 0.0, 1.0)
	_bob_gain = ease_toward(_bob_gain, speed_ratio, delta, bob_gain_time)
	var air: float = 0.0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING:
			air = maxf(air, sin(PI * _solver.swing_progress(i)))
	last_bob = bob_amplitude * _mean_reach * _bob_gain * (2.0 * air - BOB_MEAN_SHIFT)
	return last_bob


func _update_swing_feet() -> void:
	var t: Transform3D = _pose
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var state: int = _solver.state_of(i)
		if state == GaitSolver.LegState.SWINGING:
			_foot[i] = GaitSolver.swing_point(
				_from[i], _to[i], _solver.swing_progress(i), _solver.lift_height(leg.reach)
			)
		elif state == GaitSolver.LegState.HOVERING:
			var hover: Vector3 = t * leg.rest_local + Vector3.UP * _solver.lift_height(leg.reach)
			# A hovering foot never paws inside a face: it stays on the hip's side of whatever stands in the way.
			var hip: Vector3 = t * leg.hip_local
			_ray.from = Vector3(hip.x, hover.y, hip.z)
			_ray.to = hover
			var blocked: Dictionary = get_world_3d().direct_space_state.intersect_ray(_ray)
			rays_this_tick += 1
			if not blocked.is_empty():
				var along: Vector3 = (hover - _ray.from).normalized()
				hover = blocked["position"] - along * HOVER_FACE_GAP
			_foot[i] = hover


func _on_step_started(leg: int) -> void:
	_from[leg] = _foot[leg]
	_to[leg] = _target[leg]
	_to_normal[leg] = _target_normal[leg]
	step_started.emit(leg)


func _on_foot_planted(leg: int) -> void:
	# A target that went invalid mid-swing leaves a stale landing point: never plant out of reach (the IK clamp
	# would drag the rendered foot). Slide the landing in toward the hip and re-find the ground there.
	var hip: Vector3 = _pose * _legs[leg].hip_local
	var limit: float = _limits[leg] * 0.995
	if hip.distance_to(_to[leg]) > limit:
		var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
		var span := Vector2(_to[leg].x - hip.x, _to[leg].z - hip.z)
		var landed: bool = false
		for fraction in [0.8, 0.6, 0.4, 0.2, 0.0]:
			var x: float = hip.x + span.x * fraction
			var z: float = hip.z + span.y * fraction
			_ray.from = Vector3(x, hip.y + ray_up_ratio * _mean_reach, z)
			_ray.to = Vector3(x, hip.y - ray_length_ratio * _mean_reach, z)
			var hit: Dictionary = space.intersect_ray(_ray)
			rays_this_tick += 1
			if hit.is_empty():
				continue
			var ground: Vector3 = hit["position"]
			if (
				hip.distance_to(ground) <= limit
				and _foothold_valid(ground, hit["normal"], _stand_y[leg], hip, _limits[leg], space, true)
			):
				_to[leg] = ground
				_to_normal[leg] = hit["normal"]
				landed = true
				break
		if not landed:
			var offset: Vector3 = _to[leg] - hip
			_to[leg] = hip + offset.normalized() * limit
	_foot[leg] = _to[leg]
	foot_planted.emit(leg, _to[leg], _to_normal[leg])



