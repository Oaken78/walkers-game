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
## Low collider: bottom this far above the chassis underside (blocks above step-up stop the body).
const COLLIDER_BOTTOM: float = 0.02
## Stance guard: bottom this x mean reach above the chassis underside, radius = widest rest foot + margin. Stops at tall walls
## without catching rolling terrain.
const GUARD_BOTTOM_RATIO: float = 0.7
const GUARD_MARGIN: float = 0.25
## Fractions of the target lead tried in turn (legs about to lift only) when the ground at the full lead is out
## of reach and cannot be reached by lowering the body.
const LEAD_SCALES: Array[float] = [1.0, 0.5, 0.0]
const SINGLE_LEAD: Array[float] = [1.0]
## The body lowers at most this x leg reach toward a lower foothold (GDD 5).
const MAX_LOWER_RATIO: float = 0.25
## Reach used when asking "can the hip reach this lower foothold" so the landing has slack.
const LOWER_REACH_SLACK: float = 0.95
## A foot only lifts toward ground within this x of the reach limit, so it still lands in reach after the body moves.
const LIFT_REACH_SLACK: float = 1.0
## A planted foot further than this x its reach limit from its hip asks to step.
const REACH_STRESS: float = 0.93
## Contact normals of a round collider on a slope read steeper than the slope's face: this much slack on the grip.
const CONTACT_SLOPE_MARGIN_DEG: float = 12.0
## The sight ray from the hip stops this far short of the foothold.
const SIGHT_MARGIN: float = 0.1
## While the body lowers toward a footing it settles this x faster than the normal height spring.
const LOWER_SETTLE_SCALE: float = 1.0

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
@export var tilt_max_deg: float = 25.0
@export var tilt_smooth_time: float = 0.12
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
@export var rest_out_ratio: float = 0.5
## The front legs fan forward and the rear legs back by up to this x reach.
@export var rest_fan_ratio: float = 0.10
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
var teleport_count: int = 0
var rays_this_tick: int = 0
var max_rays_per_tick: int = 0

var _build: WalkerBuild
var _stats: Dictionary = {}
var _solver: GaitSolver
var _legs: Array[WalkerLeg] = []
var _needs_plant: bool = false
var _teleport_pending: bool = false
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
		apply_build(WalkerBuild.scout())


# --- Public contract -------------------------------------------------------------------------------------------


func apply_build(build: WalkerBuild) -> void:
	if build == null or not build.is_valid():
		push_error("WalkerBody.apply_build: invalid build, keeping the old one")
		return
	_build = build.copy()
	_stats = _build.stats()
	_rebuild()
	_needs_plant = true
	if is_inside_tree():
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


## Distance from leg i's hip to its rest foot, over that leg's reach (GDD 5: at most 0.75).
func rest_distance_ratio(leg: int) -> float:
	var l: WalkerLeg = _legs[leg]
	return l.hip_local.distance_to(l.rest_local) / l.reach


## True while a collider overlaps static geometry (used after teleport and apply_build).
func is_overlapping_world() -> bool:
	return _overlaps_world(global_transform)


## Largest planted-foot distance to its hip, as a fraction of that leg's reach (the 0.99 rule).
func max_planted_reach_ratio() -> float:
	var worst: float = 0.0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.PLANTED:
			var hip: Vector3 = _pose * _legs[i].hip_local
			worst = maxf(worst, hip.distance_to(_render[i]) / _legs[i].reach)
	return worst


## Lowest knee rise over the legs, (knee.y - hip.y) / reach (GDD 5: at least 0.10 while walking).
func min_knee_rise_ratio() -> float:
	var lowest: float = INF
	for i in _legs.size():
		var hip: Vector3 = _pose * _legs[i].hip_local
		lowest = minf(lowest, (_legs[i].knee.y - hip.y) / _legs[i].reach)
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
	# Low collider: round, as long as the chassis, so turning in place never swings a corner into a wall.
	var shape := CylinderShape3D.new()
	shape.radius = maxf(width, length) * 0.5
	shape.height = height
	var collider: CollisionShape3D = get_node("Collider")
	collider.shape = shape
	collider.position = Vector3(0.0, COLLIDER_BOTTOM + height * 0.5, 0.0)
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
	var plane: Plane = fit_plane(_foot)
	_tilt_n = clamp_tilt(plane.normal, tilt_max_deg)
	var x: float = _origin.x
	var z: float = _origin.z
	_base_y = plane_height(plane, x, z) + body_height_ratio * _mean_reach / plane.normal.y
	_origin = Vector3(x, _base_y, z)
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
	rays_this_tick = 0
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var leg_state: int = _solver.state_of(i)
		var rest: Vector3 = gt * leg.rest_local
		var rest_velocity: Vector3 = _target_velocity + Vector3.UP.cross(rest - gt.origin) * yaw_rad
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
		if leg_state == GaitSolver.LegState.PLANTED and hip_world.distance_to(_foot[i]) > limit * REACH_STRESS:
			# A planted foot near the end of its reach is about to stop the body (rule 5): it must step now,
			# even if its own target happens to be close (a dip under the foot).
			_errors[i] = maxf(_errors[i], (trigger_ratio + 0.05) * leg.reach)
		_lower_to_y = minf(_lower_to_y, needs_y)
		# Rise is measured from the height the foot stands (or stood) on, not from the lifted swing arc.
		var stand_y: float = _foot[i].y
		if leg_state == GaitSolver.LegState.SWINGING:
			stand_y = _from[i].y
		elif leg_state == GaitSolver.LegState.HOVERING:
			stand_y = _foot[i].y - _solver.lift_height(leg.reach)
		_valid[i] = (
			GaitSolver.is_target_valid(position.y - stand_y, normal, _step_up, _max_slope)
			and hip_world.distance_to(position) <= limit * LIFT_REACH_SLACK
		)
		if _valid[i] and (about_to_lift or leg_state == GaitSolver.LegState.SWINGING):
			# The hip must see the foothold: a foot never lands behind a thin wall its ray started above.
			# (From the hip, or from just above the foothold when that is higher: a block taller than the hip
			# must still be climbable, a thin wall must still hide what is behind it.)
			var eye := Vector3(hip_world.x, maxf(hip_world.y, position.y + SIGHT_MARGIN), hip_world.z)
			var toward: Vector3 = (eye - position).normalized()
			_sight.from = eye
			_sight.to = position + toward * SIGHT_MARGIN
			rays_this_tick += 1
			if not space.intersect_ray(_sight).is_empty():
				_valid[i] = false
	return clampf(fastest / _top_speed, 0.0, 1.0)


## A swinging foot homes on its live target, so it lands where the rest point has moved to.
func _homing_swings() -> void:
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING and _valid[i]:
			_to[i] = _target[i]
			_to_normal[i] = _target_normal[i]


## Pushes the body horizontally out of any static geometry its colliders overlap. True when it moved.
func _depenetrate() -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var moved: bool = false
	for attempt in 6:
		var push := Vector3.ZERO
		var root: Transform3D = global_transform
		for node_name in ["Collider", "Guard"]:
			var node: CollisionShape3D = get_node(node_name)
			_shape_query.shape = node.shape
			_shape_query.transform = root * Transform3D(Basis.IDENTITY, node.position)
			var contacts: PackedVector3Array = space.collide_shape(_shape_query, 16)
			for k in range(0, contacts.size() - 1, 2):
				var along: Vector3 = contacts[k + 1] - contacts[k]
				along.y = 0.0
				if along.length() > push.length():
					push = along
		if push.length() < 0.0005:
			break
		_origin += push + push.normalized() * 0.01
		global_transform = Transform3D(global_transform.basis, global_transform.origin + push + push.normalized() * 0.01)
		moved = true
	return moved


## True when a collider overlaps static geometry it should not: walls, block faces, anything steeper than the
## build's grip. Overlap with ground the walker can walk on (a slope inside its grip, a crest) is not a collision.
func _overlaps_world(root: Transform3D) -> bool:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	for node_name in ["Collider", "Guard"]:
		var node: CollisionShape3D = get_node(node_name)
		_shape_query.shape = node.shape
		_shape_query.transform = root * Transform3D(Basis.IDENTITY, node.position)
		if space.intersect_shape(_shape_query, 1).is_empty():
			continue
		var rest: Dictionary = space.get_rest_info(_shape_query)
		if rest.is_empty():
			return true
		var normal: Vector3 = rest["normal"]
		if rad_to_deg(normal.angle_to(Vector3.UP)) > _max_slope + CONTACT_SLOPE_MARGIN_DEG:
			return true
	return false


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

	var cur_pos: Vector3 = _origin
	var des_yaw: float = _yaw + deg_to_rad(_yaw_rate_cmd) * delta
	var des_x: float = cur_pos.x + _velocity_h.x * delta
	var des_z: float = cur_pos.z + _velocity_h.z * delta
	var tilt_target: Vector3 = clamp_tilt(plane.normal, tilt_max_deg)
	var tilt_factor: float = ease_factor(delta, tilt_smooth_time)
	var des_n: Vector3 = _tilt_n
	if tilt_factor > 0.0 and (tilt_target - _tilt_n).length_squared() > 0.0000000001:
		des_n = _tilt_n.slerp(tilt_target, tilt_factor).normalized()
	var base_target: float = (
		plane_height(plane, des_x, des_z) + body_height_ratio * _mean_reach / plane.normal.y
	)
	# A foothold below the reach of the hip: lower the body toward it before the foot goes for it.
	base_target = minf(base_target, _lower_to_y)
	var settle: float = height_settle_time
	if _lower_to_y < _base_y:
		settle = height_settle_time * LOWER_SETTLE_SCALE
	var des_base: float = ease_toward(_base_y, base_target, delta, settle)
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
	var cur_root: Transform3D = pose_transform(Vector3(cur_pos.x, _base_y, cur_pos.z), _yaw, _tilt_n)
	global_transform = cur_root
	if move_fraction > 0.0:
		var motion := Vector3(origin.x - cur_pos.x, 0.0, origin.z - cur_pos.z)
		var end := Vector3(origin.x, 0.0, origin.z)
		if motion.length_squared() > 0.000000000001:
			# Test-only sweeps: the body is placed by hand so the physics recovery never nudges it.
			var collision: KinematicCollision3D = move_and_collide(motion, true)
			if collision != null:
				if rad_to_deg(collision.get_normal().angle_to(Vector3.UP)) > _max_slope + CONTACT_SLOPE_MARGIN_DEG:
					# A wall or block face: stop at the contact and slide along it.
					var travel: Vector3 = collision.get_travel()
					var slide: Vector3 = collision.get_remainder().slide(collision.get_normal())
					slide.y = 0.0
					end = Vector3(cur_pos.x + travel.x, 0.0, cur_pos.z + travel.z)
					global_position = Vector3(end.x, global_position.y, end.z)
					if slide.length_squared() > 0.0000000001:
						var second: KinematicCollision3D = move_and_collide(slide, true)
						var step: Vector3 = slide if second == null else second.get_travel()
						end += Vector3(step.x, 0.0, step.z)
				# else: ground the walker can walk on (a slope inside its grip): the body rises with its feet,
				# so the move goes on through the contact.
		origin.x = end.x
		origin.z = end.z
		global_position = Vector3(origin.x, global_position.y, origin.z)
	# The chassis must never end a tick inside static geometry (vertical and tilt moves are not swept).
	var new_root: Transform3D = pose_transform(Vector3(origin.x, base_y, origin.z), yaw, tilt)
	if _overlaps_world(new_root) and not _overlaps_world(cur_root):
		# First keep the new position and yaw but the old height and tilt (tilt alone must not freeze the body).
		tilt = _tilt_n
		new_root = pose_transform(Vector3(origin.x, _base_y, origin.z), yaw, tilt)
		base_y = _base_y
		origin.y = cur_pos.y
		if _overlaps_world(new_root):
			origin = cur_pos
			yaw = _yaw
			tilt = _tilt_n
			base_y = _base_y
			held_this_tick = true
	var current: Transform3D = pose_transform(cur_pos, _yaw, _tilt_n)
	var final_pose: Transform3D = pose_transform(origin, yaw, tilt)
	if not feet_in_reach(final_pose, current, _hips_local, _check_feet, _check_flags, _limits):
		# Sliding along a wall must never drag a planted foot: stay put instead.
		origin = cur_pos
		yaw = _yaw
		tilt = _tilt_n
		base_y = _base_y
		held_this_tick = true
	var actual := Vector3((origin.x - cur_pos.x) / delta, 0.0, (origin.z - cur_pos.z) / delta)
	var commanded_len: float = _velocity_h.length()
	# A small hold keeps the commanded speed (no climb back up the ramp); a big stop (wall) resets it.
	if commanded_len > 0.0001 and actual.length() < 0.5 * commanded_len:
		_velocity_h = actual
	velocity = actual
	var actual_rate: float = rad_to_deg(yaw - _yaw) / delta
	if absf(_yaw_rate_cmd) > 0.0001 and absf(actual_rate) < 0.5 * absf(_yaw_rate_cmd):
		_yaw_rate_cmd = actual_rate
	yaw_rate_dps = actual_rate
	_base_y = base_y
	_yaw = yaw
	_tilt_n = tilt
	_origin = origin
	_apply_transforms()
	_height_above_plane = plane.distance_to(origin)


## Gait-synced bob: lowest as a group plants, highest mid-swing; fades in with speed.
func _bob_offset(delta: float) -> float:
	var speed_ratio: float = clampf(velocity.length() / _top_speed, 0.0, 1.0)
	_bob_gain = ease_toward(_bob_gain, speed_ratio, delta, bob_gain_time)
	var air: float = 0.0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING:
			air = maxf(air, sin(PI * _solver.swing_progress(i)))
	last_bob = bob_amplitude * _bob_gain * (2.0 * air - BOB_MEAN_SHIFT)
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
			_foot[i] = t * leg.rest_local + Vector3.UP * _solver.lift_height(leg.reach)


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
			if hip.distance_to(ground) <= limit:
				_to[leg] = ground
				_to_normal[leg] = hit["normal"]
				landed = true
				break
		if not landed:
			var offset: Vector3 = _to[leg] - hip
			_to[leg] = hip + offset.normalized() * limit
	_foot[leg] = _to[leg]
	foot_planted.emit(leg, _to[leg], _to_normal[leg])



