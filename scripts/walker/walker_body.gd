class_name WalkerBody
extends CharacterBody3D
## The walker: a kinematic body built from a WalkerBuild (GDD 8.2). Legs place their feet by raycast, step when
## GaitSolver says so and are posed by TwoBoneIK. The body has no gravity: its height and tilt come from the
## plane of the planted feet, and it never moves so far that a planted foot would be dragged (rule 5).
## Everything that moves runs in _physics_process at 60 Hz; the maths lives in static helpers (unit-tested).

signal foot_planted(leg: int, position: Vector3, normal: Vector3)
signal build_applied

enum SteerMode { TANK, CAMERA_YAW }

const LEG_SCENE: PackedScene = preload("res://scenes/walker/leg.tscn")
## A planted foot may never be further than this x reach from its hip (the IK clamp is at the same value).
const REACH_LIMIT: float = 0.99
const BISECT_STEPS: int = 9
## Mean of sin(PI * t) over a swing is 2 / PI: the bob offset is shifted by 2 x this so it averages out.
const BOB_MEAN_SHIFT: float = 1.2732395
const CAMERA_YAW_TURN_BAND_DEG: float = 8.0
const MOVE_INPUT_EPSILON: float = 0.01
## Collider radius = widest rest foot distance + this (a foot pad and a little air).
const COLLIDER_MARGIN: float = 0.25
## Fractions of the target lead tried in turn when the ground at the full lead is out of reach.
const LEAD_SCALES: Array[float] = [1.0, 0.5, 0.0]

@export var steer_mode: SteerMode = SteerMode.TANK
@export var accel_time: float = 0.25
@export var decel_time: float = 0.20
@export var turn_ramp_time: float = 0.10
@export var strafe_ratio: float = 0.75
@export var aim_turn_factor: float = 0.6
@export var body_height_ratio: float = 0.6
@export var height_settle_time: float = 0.15
@export var tilt_max_deg: float = 25.0
@export var tilt_smooth_time: float = 0.12
@export var bob_amplitude: float = 0.04
@export var bob_gain_time: float = 0.1
@export_group("Gait (copied into GaitSolver)")
@export var trigger_ratio: float = 0.5
@export var step_time_idle: float = 0.30
@export var step_time_top: float = 0.18
@export var handover_progress: float = 0.85
@export var hover_delay: float = 0.5
@export var lift_ratio: float = 0.25
@export_group("Stance")
## Rest foot distance out from the hip, x leg reach (0.3-0.45 keeps the stride inside the 0.99 reach sphere).
@export var rest_out_ratio: float = 0.38
## The front legs fan forward and the rear legs back by up to this x reach.
@export var rest_fan_ratio: float = 0.12
## Hip spacing along a side = base + per_reach x mean reach.
@export var hip_spacing_base: float = 0.5
@export var hip_spacing_per_reach: float = 0.3
@export var hip_lateral_base: float = 0.45
@export var hip_lateral_per_reach: float = 0.15
@export var ray_up_ratio: float = 0.5
@export var ray_length_ratio: float = 3.0

var input_enabled: bool = true
var yaw_source: Node3D

## Read-only state for telemetry and the camera rig.
var yaw_rate_dps: float = 0.0
var target_yaw_rate_dps: float = 0.0
var move_input_active: bool = false
var turn_input: float = 0.0
var held_this_tick: bool = false
var teleport_count: int = 0

var _build: WalkerBuild
var _stats: Dictionary = {}
var _solver: GaitSolver
var _legs: Array[WalkerLeg] = []
var _needs_plant: bool = false
var _ray: PhysicsRayQueryParameters3D
var _top_speed: float = 4.5
var _turn_rate: float = 120.0
var _step_up: float = 0.6
var _max_slope: float = 35.0
var _mean_reach: float = 1.0
var _yaw: float = 0.0
var _tilt_n: Vector3 = Vector3.UP
var _base_y: float = 0.0
var _velocity_h: Vector3 = Vector3.ZERO
var _target_velocity: Vector3 = Vector3.ZERO
var _bob_gain: float = 0.0
var _height_above_plane: float = 0.0
var _in_forward: float = 0.0
var _in_strafe: float = 0.0
var _in_turn: float = 0.0
var _aim: bool = false
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
var _fit: PackedVector3Array = PackedVector3Array()


func _ready() -> void:
	_make_ray()
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
	global_position = xform.origin
	_base_y = xform.origin.y
	_tilt_n = Vector3.UP
	_velocity_h = Vector3.ZERO
	velocity = Vector3.ZERO
	yaw_rate_dps = 0.0
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


## Perpendicular distance of the body origin above the planted-feet plane (telemetry).
func height_above_plane() -> float:
	return _height_above_plane


func yaw_radians() -> float:
	return _yaw


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
		var allowed: float = maxf(limits[i], (current * hips_local[i]).distance_to(feet[i]))
		if (t * hips_local[i]).distance_to(feet[i]) > allowed + 0.00001:
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


## z of each hip along one side, front (-Z) to back, evenly spaced and centred: no gap at an empty socket.
static func hip_z_positions(count: int, spacing: float) -> PackedFloat32Array:
	var zs := PackedFloat32Array()
	for i in count:
		zs.append((float(i) - float(count - 1) * 0.5) * spacing)
	return zs


static func _top_spot(index: int, count: int, width: float, length: float) -> Vector3:
	if count == 1:
		return Vector3(0.0, 0.0, -length * 0.05)
	if index == 0:
		return Vector3(-width * 0.25, 0.0, -length * 0.1)
	if index == 1:
		return Vector3(width * 0.25, 0.0, -length * 0.1)
	return Vector3(0.0, 0.0, length * 0.25)


# --- Build ---------------------------------------------------------------------------------------------------------


func _make_ray() -> void:
	if _ray != null:
		return
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = 1
	_ray.hit_from_inside = true
	_ray.collide_with_areas = false


func _rebuild() -> void:
	_make_ray()
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
		var hip := Vector3(float(side) * lateral, 0.0, hip_z_positions(side_count, spacing)[index])
		var mid: float = float(side_count - 1) * 0.5
		var fan: float = 0.0 if mid <= 0.0 else (float(index) - mid) / mid
		var rest := Vector3(
			hip.x + float(side) * rest_out_ratio * reach,
			-body_height_ratio * reach,
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
	_valid.resize(count)
	_planted.resize(count)
	_fit.resize(count)
	_solver = GaitSolver.new(sides, reaches)
	_solver.trigger_ratio = trigger_ratio
	_solver.step_time_idle = step_time_idle
	_solver.step_time_top = step_time_top
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
	var bottom: float = 0.05
	var center := Vector3(0.0, bottom + height * 0.5, 0.0)
	# A round collider as wide as the stance (plus a foot pad): turning in place against a wall never swings a
	# corner into it, and a wall stops the body before any rest foot can end up inside the wall.
	var shape := CylinderShape3D.new()
	shape.radius = stance_radius + COLLIDER_MARGIN
	shape.height = height
	var collider: CollisionShape3D = get_node("Collider")
	collider.shape = shape
	collider.position = center
	var mesh := BoxMesh.new()
	mesh.size = Vector3(width, height, length)
	var chassis: MeshInstance3D = get_node("Chassis")
	chassis.mesh = mesh
	chassis.material_override = WalkerLeg.body_material()
	chassis.position = center
	var tops: Node3D = get_node("Tops")
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


func _plant_all_at_rest() -> void:
	_needs_plant = false
	if _legs.is_empty() or not is_inside_tree():
		return
	_make_ray()
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var flat := Transform3D(Basis(Vector3.UP, _yaw), global_position)
	var start_y: float = global_position.y + 3.0 * _mean_reach
	var fallback_y: float = global_position.y - body_height_ratio * _mean_reach
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
	var x: float = global_position.x
	var z: float = global_position.z
	_base_y = plane_height(plane, x, z) + body_height_ratio * _mean_reach / plane.normal.y
	_height_above_plane = plane.distance_to(Vector3(x, _base_y, z))
	_bob_gain = 0.0
	_velocity_h = Vector3.ZERO
	yaw_rate_dps = 0.0
	global_transform = pose_transform(Vector3(x, _base_y, z), _yaw, _tilt_n)
	_solver.reset()
	_pose_legs()
	reset_physics_interpolation()


func _pose_legs() -> void:
	var t: Transform3D = global_transform
	var pad_basis := Basis(Vector3.UP, _yaw)
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var hip: Vector3 = t * leg.hip_local
		var pole: Vector3 = t.basis.x * (float(leg.side) * 0.7) + t.basis.y
		leg.pose(hip, _foot[i], pole, pad_basis)
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
	yaw_rate_dps = approach_yaw_rate(
		yaw_rate_dps, _in_turn, _turn_rate, _aim, turn_ramp_time, aim_turn_factor, delta
	)
	target_yaw_rate_dps = _in_turn * _turn_rate * (aim_turn_factor if _aim else 1.0)

	var speed_ratio: float = _update_targets()
	_homing_swings()
	_solver.update(delta, move_input_active, speed_ratio, _errors, _valid)
	_apply_move(delta)
	_update_swing_feet()
	_pose_legs()


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
				turn = clampf(error_deg / CAMERA_YAW_TURN_BAND_DEG, -1.0, 1.0)
	_in_forward = forward
	_in_strafe = strafe
	_in_turn = turn
	turn_input = turn
	move_input_active = (
		absf(forward) > MOVE_INPUT_EPSILON
		or absf(strafe) > MOVE_INPUT_EPSILON
		or absf(turn) > MOVE_INPUT_EPSILON
	)


## One ray per leg through rest point + lead. Fills targets, validity and foot errors; returns the speed ratio.
func _update_targets() -> float:
	var gt: Transform3D = global_transform
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var yaw_rad: float = deg_to_rad(target_yaw_rate_dps)
	var ray_up: float = ray_up_ratio * _mean_reach
	var ray_len: float = ray_length_ratio * _mean_reach + ray_up
	var fastest: float = 0.0
	for i in _legs.size():
		var leg: WalkerLeg = _legs[i]
		var rest: Vector3 = gt * leg.rest_local
		var rest_velocity: Vector3 = _target_velocity + Vector3.UP.cross(rest - gt.origin) * yaw_rad
		var rest_speed: float = rest_velocity.length()
		fastest = maxf(fastest, rest_speed)
		var lead: Vector3 = GaitSolver.target_lead(
			rest_velocity, _solver.step_duration(rest_speed / _top_speed)
		)
		var hip_world: Vector3 = gt * leg.hip_local
		var aim_x: float = rest.x + lead.x
		var aim_z: float = rest.z + lead.z
		var hit: Dictionary = {}
		# Aim through rest + lead; if the ground there is out of the hip's reach (a step down, a ridge), shorten
		# the lead so the foot lands closer instead of the leg blocking.
		for lead_scale in LEAD_SCALES:
			aim_x = rest.x + lead.x * lead_scale
			aim_z = rest.z + lead.z * lead_scale
			_ray.from = Vector3(aim_x, gt.origin.y + ray_up, aim_z)
			_ray.to = Vector3(aim_x, gt.origin.y + ray_up - ray_len, aim_z)
			hit = space.intersect_ray(_ray)
			if not hit.is_empty():
				var ground: Vector3 = hit["position"]
				if hip_world.distance_to(ground) <= _limits[i]:
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
		# Rise is measured from the height the foot stands (or stood) on, not from the lifted swing arc.
		var stand_y: float = _foot[i].y
		var leg_state: int = _solver.state_of(i)
		if leg_state == GaitSolver.LegState.SWINGING:
			stand_y = _from[i].y
		elif leg_state == GaitSolver.LegState.HOVERING:
			stand_y = _foot[i].y - _solver.lift_height(leg.reach)
		_valid[i] = (
			GaitSolver.is_target_valid(position.y - stand_y, normal, _step_up, _max_slope)
			and hip_world.distance_to(position) <= _limits[i]
		)
	return clampf(fastest / _top_speed, 0.0, 1.0)


## A swinging foot homes on its live target, so it lands where the rest point has moved to.
func _homing_swings() -> void:
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING and _valid[i]:
			_to[i] = _target[i]
			_to_normal[i] = _target_normal[i]


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
	if planted_count < 3:
		for i in count:
			_fit[i] = _foot[i]
		planted_count = count
	var plane: Plane = fit_plane(_fit, planted_count)

	var cur_pos: Vector3 = global_position
	var des_yaw: float = _yaw + deg_to_rad(yaw_rate_dps) * delta
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
	var des_base: float = ease_toward(_base_y, base_target, delta, height_settle_time)
	var des_origin := Vector3(des_x, des_base + _bob_offset(delta), des_z)

	var fraction: float = safe_fraction(
		cur_pos, _yaw, _tilt_n, des_origin, des_yaw, des_n, _hips_local, _foot, _planted, _limits
	)
	held_this_tick = fraction < 0.9999
	var origin: Vector3 = cur_pos.lerp(des_origin, fraction)
	var yaw: float = lerpf(_yaw, des_yaw, fraction)
	var tilt: Vector3 = des_n if fraction >= 1.0 else _tilt_n.slerp(des_n, fraction)
	if fraction > 0.0:
		var motion := Vector3(origin.x - cur_pos.x, 0.0, origin.z - cur_pos.z)
		if motion.length_squared() > 0.000000000001:
			var collision: KinematicCollision3D = move_and_collide(motion)
			if collision != null:
				var slide: Vector3 = collision.get_remainder().slide(collision.get_normal())
				slide.y = 0.0
				if slide.length_squared() > 0.0000000001:
					move_and_collide(slide)
		origin.x = global_position.x
		origin.z = global_position.z
	var current: Transform3D = pose_transform(cur_pos, _yaw, _tilt_n)
	var final_pose: Transform3D = pose_transform(origin, yaw, tilt)
	if not feet_in_reach(final_pose, current, _hips_local, _foot, _planted, _limits):
		# Sliding along a wall must never drag a planted foot: stay put instead.
		origin = cur_pos
		yaw = _yaw
		tilt = _tilt_n
		final_pose = current
		held_this_tick = true
	_velocity_h = Vector3((origin.x - cur_pos.x) / delta, 0.0, (origin.z - cur_pos.z) / delta)
	velocity = _velocity_h
	yaw_rate_dps = rad_to_deg(yaw - _yaw) / delta
	_base_y = lerpf(_base_y, des_base, fraction)
	_yaw = yaw
	_tilt_n = tilt
	global_transform = final_pose
	_height_above_plane = plane.distance_to(origin)


## Gait-synced bob: lowest as a group plants, highest mid-swing; fades in with speed.
func _bob_offset(delta: float) -> float:
	var speed_ratio: float = clampf(_velocity_h.length() / _top_speed, 0.0, 1.0)
	_bob_gain = ease_toward(_bob_gain, speed_ratio, delta, bob_gain_time)
	var air: float = 0.0
	for i in _legs.size():
		if _solver.state_of(i) == GaitSolver.LegState.SWINGING:
			air = maxf(air, sin(PI * _solver.swing_progress(i)))
	return bob_amplitude * _bob_gain * (2.0 * air - BOB_MEAN_SHIFT)


func _update_swing_feet() -> void:
	var t: Transform3D = global_transform
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


func _on_foot_planted(leg: int) -> void:
	# A target that went invalid mid-swing leaves a stale landing point: never plant out of reach, because
	# the IK clamp would then drag the rendered foot.
	var hip: Vector3 = global_transform * _legs[leg].hip_local
	var span: Vector3 = _to[leg] - hip
	var limit: float = _limits[leg] * 0.995
	if span.length() > limit:
		_to[leg] = hip + span.normalized() * limit
	_foot[leg] = _to[leg]
	foot_planted.emit(leg, _to[leg], _to_normal[leg])
