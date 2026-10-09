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

var _nominal_root_y: float = 0.0
var _tick: int = 0
var _mark: Vector3 = Vector3.ZERO

@onready var _walker: WalkerBody = %Walker
@onready var _telemetry: WalkerTelemetry = %Telemetry
@onready var _valley: Valley = $Valley

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


func mark() -> void:
	_mark = _walker.global_position


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


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
