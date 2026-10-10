class_name ValleyPockets
extends Node3D
## Drives the walker at the REAL valley's two pockets (GDD 9.1, T05 geometry instanced read-only): the ledge pocket's
## 0.8 m ledge on the west wall and the talus on the east wall. The scenario valley_pockets asserts which builds get in
## (only the Strider onto the ledge floor, only the Crawler up to the talus shelf) and that the others are blocked and
## recover. Helpers mirror GaitCourse (use_build, hold_action, mark) so the scenarios read the same.

## The walker starts this far in front of the pocket entrance (m) on the apron pad.
const START_DISTANCE: float = 8.0
## Pocket floor checks: how far into the ledge alcove the body must be, and how far up the talus the shelf starts.
const LEDGE_INSIDE: float = 1.0
const SHELF_MARGIN: float = 0.5
## A foot or body this far past the entrance counts as having gone in (m).
const ENTRANCE_MARGIN: float = 0.3

## Which pocket the walker was last placed at ("ledge" or "talus").
var pocket: String = "ledge"
## Running maxima since the last spawn: planted foot rise above the apron, body root rise over its nominal height.
var foot_rise_max: float = -INF
var root_rise_max: float = -INF
## The lowest visible-sight-line count at the last log_foot_vis (chassis and terrain only).
var min_foot_vis: int = 5

var _nominal_root_y: float = 0.0
var _freeze_lip: float = -1.0
var _freeze_paw: float = -1.0
var _tick: int = 0
var _mark: Vector3 = Vector3.ZERO

@onready var _walker: WalkerBody = %Walker
@onready var _telemetry: WalkerTelemetry = %Telemetry
@onready var _valley: Valley = $Valley
@onready var _orbit: OrbitCamera = $OrbitCamera

## True when the whole body stands on the ledge pocket floor (inside the alcove, at the ledge height).
var on_ledge_floor: bool:
	get:
		return (
			_walker.global_position.x < ValleyLayout.WALL_LEFT_X - LEDGE_INSIDE
			and _walker.global_position.y > ValleyLayout.ledge_floor_y() + 0.2
		)
## True when the whole body is on the talus shelf, above the slope.
var on_talus_shelf: bool:
	get:
		return (
			_walker.global_position.x
			> ValleyLayout.WALL_RIGHT_X + ValleyLayout.TALUS_SLOPE_LEN + SHELF_MARGIN
			and _walker.global_position.y > ValleyLayout.talus_apron_y() + 3.0
		)
## True when the walker body or any foot has gone past the pocket entrance.
var past_entrance: bool:
	get:
		return _past_entrance()
## Straight-line distance moved since mark().
var moved_since_mark: float:
	get:
		return _walker.global_position.distance_to(_mark)


func _ready() -> void:
	process_physics_priority = 50
	_orbit.capture_mouse = false
	_telemetry.observe(_walker)


func _physics_process(_delta: float) -> void:
	if _walker.gait() == null:
		return
	_tick += 1
	if _tick == 5:
		_nominal_root_y = _walker.global_position.y
	var apron: float = _apron_y()
	for i in _walker.leg_count():
		if _walker.gait().state_of(i) == GaitSolver.LegState.PLANTED:
			foot_rise_max = maxf(foot_rise_max, _walker.foot_position(i).y - apron)
	if _tick > 5:
		root_rise_max = maxf(root_rise_max, _walker.global_position.y - _nominal_root_y)
	if _freeze_lip >= 0.0 and _lip_distance() <= _freeze_lip:
		get_tree().paused = true
		_freeze_lip = -1.0
	if _freeze_paw >= 0.0:
		for i in _walker.leg_count():
			if _walker.is_leg_hanging(i) and _walker.foot_position(i).y - _apron_y() >= _freeze_paw * _walker.leg_reach(i):
				get_tree().paused = true
				_freeze_paw = -1.0
				break


## "scout", "strider" or "crawler".
func use_build(build_name: String) -> void:
	var build: WalkerBuild
	match build_name:
		"scout":
			build = WalkerBuild.scout()
		"strider":
			build = WalkerBuild.strider()
		"crawler":
			build = WalkerBuild.crawler()
		_:
			push_error("ValleyPockets.use_build: unknown build %s" % build_name)
			return
	_walker.apply_build(build)


## Places the walker on the apron START_DISTANCE m in front of the pocket, facing into it.
func spawn_at(which: String) -> void:
	pocket = which
	var entrance: Vector2 = ValleyLayout.entrance_center(which)
	var x: float = entrance.x + (START_DISTANCE if which == "ledge" else -START_DISTANCE)
	var yaw: float = PI * 0.5 if which == "ledge" else -PI * 0.5
	var y: float = _valley.floor_height(x, entrance.y) + 1.0
	_tick = 0
	foot_rise_max = -INF
	root_rise_max = -INF
	_walker.teleport(Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, entrance.y)))
	mark()


## Orbit camera behind the walker at a pitch (degrees) and distance (m), as the T14 gate rig shots use.
func use_orbit_camera(pitch_deg: float = 20.0, distance: float = 8.0, yaw_offset_deg: float = 0.0) -> void:
	_orbit.camera().make_current()
	_orbit.distance = distance
	_orbit.set_angles(OrbitMath.behind_yaw(-_walker.global_basis.z) + yaw_offset_deg, pitch_deg)
	_walker.reset_physics_interpolation()
	_orbit.snap()


## Per pad: how many of 5 sight lines (top centre + 4 top corners) from the orbit camera reach it, against the world
## (layer 1) and the chassis box ONLY (same method and caveat as GaitCourse.log_foot_vis: legs, hip balls and pad side
## faces are not tested). `FOOTVIS(chassis+terrain) <tag> leg=i visible=k/5`.
func log_foot_vis(tag: String) -> void:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var eye: Vector3 = _orbit.camera().global_position
	var basis := Basis(Vector3.UP, _walker.yaw_radians())
	var half := WalkerLeg.PAD_SIZE * 0.5
	var top: float = WalkerLeg.PAD_SIZE.y
	var offsets: Array[Vector3] = [
		Vector3(0.0, top, 0.0),
		Vector3(-half.x, top, -half.z),
		Vector3(half.x, top, -half.z),
		Vector3(-half.x, top, half.z),
		Vector3(half.x, top, half.z)
	]
	var box_size: Vector3 = _walker.chassis_size()
	var to_local: Transform3D = (_walker.body_pose() * Transform3D(Basis.IDENTITY, _walker.chassis_center())).affine_inverse()
	var local_box := AABB(-box_size * 0.5, box_size)
	min_foot_vis = 5
	for i in _walker.leg_count():
		var foot: Vector3 = _walker.foot_position(i)
		var seen: int = 0
		for offset in offsets:
			var point: Vector3 = foot + basis * offset
			var end: Vector3 = point - (point - eye).normalized() * 0.02
			var blocked: bool = not space.intersect_ray(PhysicsRayQueryParameters3D.create(eye, end, 1)).is_empty()
			if not blocked and box_size != Vector3.ZERO:
				blocked = local_box.intersects_segment(to_local * eye, to_local * end) != null
			if not blocked:
				seen += 1
		min_foot_vis = mini(min_foot_vis, seen)
		print("FOOTVIS(chassis+terrain) %s leg=%d visible=%d/5" % [tag, i, seen])


func mark() -> void:
	_mark = _walker.global_position


## Pauses the game the first tick the walker's front foot (facing out of the pocket) is within `distance` m of the pocket's
## lip (the ledge's face, the talus shelf's edge): a still looking out over the drop. resume() continues.
func arm_lip_freeze(distance: float) -> void:
	_freeze_lip = distance


## Pauses the game the first tick a hanging pad is `ratio` x its reach above the apron (the top of a paw). resume() continues.
func arm_paw_freeze(ratio: float) -> void:
	_freeze_paw = ratio


func resume() -> void:
	get_tree().paused = false


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Distance (m) from the foot nearest the lip, facing out of the pocket, to the lip (negative once past it).
func _lip_distance() -> float:
	var nearest: float = INF
	for i in _walker.leg_count():
		var x: float = _walker.foot_position(i).x
		if pocket == "ledge":
			nearest = minf(nearest, ValleyLayout.WALL_LEFT_X - x)
		else:
			nearest = minf(nearest, x - (ValleyLayout.WALL_RIGHT_X + ValleyLayout.TALUS_SLOPE_LEN))
	return nearest


func _apron_y() -> float:
	return ValleyLayout.ledge_apron_y() if pocket == "ledge" else ValleyLayout.talus_apron_y()


func _past_entrance() -> bool:
	var entrance: Vector2 = ValleyLayout.entrance_center(pocket)
	var sign_in: float = -1.0 if pocket == "ledge" else 1.0
	if (_walker.global_position.x - entrance.x) * sign_in > ENTRANCE_MARGIN:
		return true
	for i in _walker.leg_count():
		if (_walker.foot_position(i).x - entrance.x) * sign_in > ENTRANCE_MARGIN:
			return true
	return false
