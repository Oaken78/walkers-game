class_name ValleyRun
extends Node3D
## The M0 proof runs on the REAL valley (T21): the valley, a walker, the orbit camera, the weapon rig, a DroneField and the
## helpers the scenarios call (the same style as DroneFight and ValleyPockets). Two jobs:
##   map_bounds    Scout, Strider and Crawler drive into the cliff walls at a ring of points, head-on and at 45 deg, for 6 s
##                 each. The three builds run side by side (walkers do not collide with each other), so one push of
##                 6 s covers all three; the world runs at several physics ticks per frame so the whole ring fits a
##                 scenario. The floor outline of ValleyLayout is the wall line (the cliff foot).
##   perf_4_drones the Scout with four engaged drones (two encounters), the no-lead tracker of DroneFight for 20 s, then a
##                 ring-2 view looking up-valley; plus the ledge-guard drone in the west wall's shadow.
## World frame as in ValleyLayout: down-valley is +Z, a walker yaw of 0 faces -Z (up-valley), +90 deg faces -X.

signal bounds_finished
signal fight_finished

enum Mode { NONE, BOUNDS, FIGHT, VIEW }
enum Phase { START, SETTLE, PUSH, BACK }

const WALKER_SCENE: PackedScene = preload("res://scenes/walker/walker.tscn")
const BUILD_NAMES: Array[String] = ["scout", "strider", "crawler"]
const SPAWN_LIFT: float = 1.0
const PLAYER_HP: float = 100000.0
## Drones that outlast a 20 s fight, so four stay in play (a death is topped up anyway, see TOPUP_AFTER_S).
const DRONE_HP: float = 2000.0
const TOPUP_AFTER_S: float = 1.5

## --- map_bounds ---------------------------------------------------------------------------------------------------
const MIN_EDGE_M: float = 5.0
const MAX_PIECE_M: float = 60.0
const HEAD_ON_START_M: float = 7.0
const DIAGONAL_START_M: float = 9.0
const START_CLEAR_M: float = 2.0
## A start on other ground than the wall point (the talus slope, the ledge lip) would test the climb, not the wall.
const START_LEVEL_M: float = 0.6
## Where the wall's own floor height is read: this far out from the wall point toward the start (the cell at the foot mixes in the cliff).
const LEVEL_PROBE_M: float = 3.0
const SETTLE_TICKS: int = 45
const PUSH_TICKS: int = 360
const BACK_TICKS: int = 180
## Backed out = the root is this far from where the push ended.
const BACK_OUT_M: float = 1.0
const END_WITHIN_M: float = 2.0

## --- Fight --------------------------------------------------------------------------------------------------------
const BAND_WALKER_S: float = 172.0
const VIEW_WALKER_S: float = 205.0
const GROUP_GAP_M: float = 22.0
const VIEW_DRONES_AHEAD_M: float = 26.0
const ORBIT_FIRST_M: float = 13.0
const ORBIT_STEP_M: float = 1.5
const LEDGE_WALKER_X: float = -66.0
const YAW_RAMP_S: float = 0.1
const STOP_MARGIN_DEG: float = 0.5
const VIEW_PITCH_DEG: float = 10.0
const FIGHT_PITCH_DEG: float = 20.0

## --- Results: map_bounds (all builds together; per-build lines go to the log) --------------------------------------
var bounds_points: int = 0
var bounds_skipped: int = 0
var bounds_pushes: int = 0
var bounds_outside_ticks: int = 0
var bounds_outside_max_m: float = 0.0
## Largest (rise above the floor under the root minus the build's climb); <= 0 means no build rose more than its climb.
var bounds_rise_excess_max: float = -INF
var bounds_rise_max: float = 0.0
var bounds_end_max_m: float = 0.0
var bounds_closest_min_m: float = INF
var bounds_stuck_count: int = 0
var scout_end_max_m: float = 0.0
var strider_end_max_m: float = 0.0
var crawler_end_max_m: float = 0.0
var bounds_done: bool = false

## --- Results: fight -----------------------------------------------------------------------------------------------
var fight_done: bool = false
var drone_cliff_min_m: float = INF
var drone_cliff_at: Vector3 = Vector3.ZERO
var bolts_live_max: int = 0
var enemy_bolts_live_max: int = 0
var active_max: int = 0
var alive_min: int = 99
var topups: int = 0
var ledge_drone_luma: float = -1.0
var ledge_drone_bg_luma: float = -1.0
var ledge_walker_luma: float = -1.0
var ledge_walker_bg_luma: float = -1.0

var economy: Economy = Economy.new()

var _mode: Mode = Mode.NONE
var _floor: PackedVector2Array = PackedVector2Array()
var _fast: int = 1
## map_bounds
var _rigs: Array[Dictionary] = []
var _pushes: Array[Dictionary] = []
var _push_index: int = 0
var _phase: Phase = Phase.START
var _phase_tick: int = 0
var _per_build: Dictionary = {}
## fight
var _drones: Array[Drone] = []
var _fight_ticks: int = 0
var _fight_limit: int = 0
var _fire: bool = true
var _dead_s: float = 0.0

@onready var _walker: WalkerBody = %Walker
@onready var _orbit: OrbitCamera = %OrbitCamera
@onready var _rig: WeaponRig = %WeaponRig
@onready var _player_box: PlayerHurtbox = %PlayerHurtbox
@onready var _collector: Collector = %Collector
@onready var _field: DroneField = %DroneField
@onready var _valley: Valley = %Valley

## Drones of the field that are alive and inside the camera's view right now.
var drones_in_view: int:
	get:
		var camera: Camera3D = _orbit.camera()
		var count: int = 0
		for drone in _drones:
			if not is_instance_valid(drone) or drone.is_dead():
				continue
			var at: Vector3 = drone.global_position
			if not camera.is_position_behind(at) and camera.is_position_in_frustum(at):
				count += 1
		return count
var alive_drones: int:
	get:
		return _field.alive_count()
var engaged_drones: int:
	get:
		var count: int = 0
		for drone in _drones:
			if is_instance_valid(drone) and DroneBrain.is_engaged(drone.brain.state):
				count += 1
		return count
var bolts_live: int:
	get:
		return _field.bolts.live + _rig.pool.live


func _ready() -> void:
	# After the walkers (0), the drones (50), the rig (100) and the pools (200): reads this tick's results.
	process_physics_priority = 300
	_floor = ValleyLayout.outline()
	_orbit.capture_mouse = false
	_collector.target = _walker
	_collector.economy = economy
	_player_box.health = Health.new(PLAYER_HP)
	_field.target = _walker


func _physics_process(delta: float) -> void:
	match _mode:
		Mode.BOUNDS:
			_bounds_tick()
		Mode.FIGHT:
			_fight_tick(delta)
		Mode.VIEW:
			_view_tick(delta)


# --- Shared helpers -----------------------------------------------------------------------------------------------


func use_build(build_name: String) -> void:
	_walker.apply_build(_make_build(build_name))


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _make_build(build_name: String) -> WalkerBuild:
	match build_name:
		"scout":
			return WalkerBuild.scout()
		"strider":
			return WalkerBuild.strider()
		"crawler":
			return WalkerBuild.crawler()
	push_error("ValleyRun: unknown build %s" % build_name)
	return WalkerBuild.scout()


func _release_inputs() -> void:
	for action in ["turn_left", "turn_right", "strafe_left", "strafe_right", "move_forward", "move_back", "fire", "aim"]:
		Input.action_release(action)


func _floor_y(x: float, z: float) -> float:
	return _valley.floor_height(x, z)


## Distance (m, in the ground plane) from `p` to the nearest cliff foot, i.e. the nearest edge of the floor outline.
func _wall_distance(p: Vector2) -> float:
	var best: float = INF
	for k in _floor.size():
		var a: Vector2 = _floor[k]
		var b: Vector2 = _floor[(k + 1) % _floor.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


# --- map_bounds ---------------------------------------------------------------------------------------------------


## Runs the whole ring. `fast` physics ticks per rendered frame (the fixed 60 Hz tick is unchanged, only more of them
## run per frame); emits bounds_finished.
func run_bounds(fast: int = 6) -> void:
	_stop_mode()
	_fast = clampi(fast, 1, 8)
	_make_rigs()
	_make_points()
	bounds_pushes = 0
	bounds_outside_ticks = 0
	bounds_outside_max_m = 0.0
	bounds_rise_excess_max = -INF
	bounds_rise_max = 0.0
	bounds_end_max_m = 0.0
	bounds_closest_min_m = INF
	bounds_stuck_count = 0
	bounds_done = false
	_per_build.clear()
	for rig in _rigs:
		_per_build[rig["name"]] = {
			"pushes": 0, "closest_min": INF, "end_max": 0.0, "rise_max": 0.0, "excess_max": -INF, "outside": 0, "stuck": 0
		}
	_push_index = 0
	_phase = Phase.START
	_phase_tick = 0
	Engine.time_scale = float(_fast)
	Engine.physics_ticks_per_second = 60 * _fast
	_mode = Mode.BOUNDS


func _make_rigs() -> void:
	if _rigs.is_empty():
		for i in BUILD_NAMES.size():
			var body: WalkerBody = _walker
			if i > 0:
				body = WALKER_SCENE.instantiate() as WalkerBody
				body.name = "Walker%s" % BUILD_NAMES[i].capitalize()
				add_child(body)
			body.apply_build(_make_build(BUILD_NAMES[i]))
			_rigs.append({"name": BUILD_NAMES[i], "body": body})
	for rig in _rigs:
		var body: WalkerBody = rig["body"]
		rig["climb"] = float(body.stats().get("climb", 0.0))
		print("MAPBOUND build %s climb=%.3f top_speed=%.2f" % [rig["name"], rig["climb"], float(body.stats().get("top_speed", 0.0))])


## One point on each long enough stretch of the cliff foot (pieces of at most MAX_PIECE_M), two pushes per point.
func _make_points() -> void:
	_pushes.clear()
	bounds_points = 0
	bounds_skipped = 0
	var flip: float = 1.0
	for k in _floor.size():
		var a: Vector2 = _floor[k]
		var b: Vector2 = _floor[(k + 1) % _floor.size()]
		var length: float = a.distance_to(b)
		if length < MIN_EDGE_M:
			continue
		var pieces: int = maxi(1, ceili(length / MAX_PIECE_M))
		var dir: Vector2 = (b - a) / length
		for i in pieces:
			var p: Vector2 = a.lerp(b, (float(i) + 0.5) / float(pieces))
			var inward: Vector2 = Vector2(-dir.y, dir.x)
			if not ValleyLayout.point_in_polygon(p + inward, _floor):
				inward = -inward
			bounds_points += 1
			var label: String = "e%02d_%d" % [k, i]
			for kind in ["head_on", "diag45"]:
				var push: Dictionary = _plan_push(label, kind, p, inward, k, flip)
				if kind == "diag45":
					flip = -flip
				if push.is_empty():
					bounds_skipped += 1
					print("MAPBOUNDSKIP point=%s kind=%s no clear start" % [label, kind])
				else:
					_pushes.append(push)
	print("MAPBOUNDPOINTS points=%d pushes=%d skipped=%d" % [bounds_points, _pushes.size(), bounds_skipped])


func _plan_push(label: String, kind: String, wall: Vector2, inward: Vector2, edge: int, flip: float) -> Dictionary:
	var tries: Array[Vector2] = []
	if kind == "head_on":
		tries.append(Vector2(HEAD_ON_START_M, 0.0))
		tries.append(Vector2(HEAD_ON_START_M * 0.6, 0.0))
	else:
		for sign_value in [flip, -flip]:
			tries.append(Vector2(DIAGONAL_START_M, sign_value))
			tries.append(Vector2(DIAGONAL_START_M * 0.6, sign_value))
	for option in tries:
		var heading: Vector2 = -inward
		if kind == "diag45":
			heading = heading.rotated(PI * 0.25 * option.y)
		var start: Vector2 = wall - heading * option.x
		if _start_is_clear(start, wall, edge):
			return {"label": label, "kind": kind, "wall": wall, "start": start, "heading": heading, "edge": edge}
	return {}


func _start_is_clear(start: Vector2, wall: Vector2, edge: int) -> bool:
	if not ValleyLayout.point_in_polygon(start, _floor) or _wall_distance(start) < START_CLEAR_M:
		return false
	var beside: Vector2 = wall + (start - wall).normalized() * LEVEL_PROBE_M
	if absf(_floor_y(start.x, start.y) - _floor_y(beside.x, beside.y)) > START_LEVEL_M:
		return false
	# The straight way from the start to the wall point must not cross any other piece of cliff foot.
	for k in _floor.size():
		if k == edge:
			continue
		var a: Vector2 = _floor[k]
		var b: Vector2 = _floor[(k + 1) % _floor.size()]
		if Geometry2D.segment_intersects_segment(start, wall, a, b) != null:
			return false
	return true


func _bounds_tick() -> void:
	match _phase:
		Phase.START:
			_begin_push()
		Phase.SETTLE:
			_phase_tick += 1
			if _phase_tick >= SETTLE_TICKS:
				for rig in _rigs:
					var body: WalkerBody = rig["body"]
					var at: Vector3 = body.global_position
					rig["nominal"] = at.y - _floor_y(at.x, at.z)
				hold_action("move_forward", true)
				_phase = Phase.PUSH
				_phase_tick = 0
		Phase.PUSH:
			for rig in _rigs:
				_sample_rig(rig, true)
			_phase_tick += 1
			if _phase_tick >= PUSH_TICKS:
				for rig in _rigs:
					var body: WalkerBody = rig["body"]
					rig["end_pos"] = body.global_position
					rig["end_dist"] = _wall_distance(Vector2(body.global_position.x, body.global_position.z))
					rig["backed_tick"] = -1
				hold_action("move_forward", false)
				hold_action("move_back", true)
				_phase = Phase.BACK
				_phase_tick = 0
		Phase.BACK:
			var all_out: bool = true
			_phase_tick += 1
			for rig in _rigs:
				_sample_rig(rig, false)
				var body: WalkerBody = rig["body"]
				if rig["backed_tick"] < 0:
					if body.global_position.distance_to(rig["end_pos"]) >= BACK_OUT_M:
						rig["backed_tick"] = _phase_tick
					else:
						all_out = false
			if all_out or _phase_tick >= BACK_TICKS:
				_finish_push()


func _begin_push() -> void:
	if _push_index >= _pushes.size():
		_finish_bounds()
		return
	var push: Dictionary = _pushes[_push_index]
	var start: Vector2 = push["start"]
	var heading: Vector2 = push["heading"]
	var yaw: float = atan2(-heading.x, -heading.y)
	_release_inputs()
	for rig in _rigs:
		var body: WalkerBody = rig["body"]
		body.teleport(Transform3D(Basis(Vector3.UP, yaw), Vector3(start.x, _floor_y(start.x, start.y) + SPAWN_LIFT, start.y)))
		body.reset_physics_interpolation()
		rig["closest"] = INF
		rig["rise_max"] = -INF
		rig["outside_ticks"] = 0
		rig["outside_max"] = 0.0
		rig["nominal"] = 0.0
		rig["end_dist"] = INF
		rig["backed_tick"] = -1
	_orbit.snap()
	_orbit.set_angles(rad_to_deg(yaw), FIGHT_PITCH_DEG)
	_phase = Phase.SETTLE
	_phase_tick = 0


func _sample_rig(rig: Dictionary, pushing: bool) -> void:
	var body: WalkerBody = rig["body"]
	var at: Vector3 = body.global_position
	var flat: Vector2 = Vector2(at.x, at.z)
	var wall: float = _wall_distance(flat)
	if not ValleyLayout.point_in_polygon(flat, _floor):
		rig["outside_ticks"] += 1
		rig["outside_max"] = maxf(rig["outside_max"], wall)
	var rise: float = at.y - _floor_y(at.x, at.z) - float(rig["nominal"])
	rig["rise_max"] = maxf(rig["rise_max"], rise)
	if pushing:
		rig["closest"] = minf(rig["closest"], wall)


func _finish_push() -> void:
	var push: Dictionary = _pushes[_push_index]
	for rig in _rigs:
		var name_: String = rig["name"]
		var stuck: bool = rig["backed_tick"] < 0
		var excess: float = float(rig["rise_max"]) - float(rig["climb"])
		var back_s: float = -1.0 if stuck else float(rig["backed_tick"]) / 60.0
		print(
			(
				"MAPBOUND build=%s point=%s kind=%s closest_m=%.2f end_m=%.2f rise_m=%.3f climb_m=%.3f outside_ticks=%d outside_max_m=%.2f back_s=%.2f stuck=%s wall=(%.1f,%.1f)"
				% [
					name_, push["label"], push["kind"], rig["closest"], rig["end_dist"], rig["rise_max"], rig["climb"],
					rig["outside_ticks"], rig["outside_max"], back_s, stuck, push["wall"].x, push["wall"].y,
				]
			)
		)
		if stuck:
			var here: Vector3 = rig["body"].global_position
			var ended: Vector3 = rig["end_pos"]
			print(
				"MAPBOUNDSTUCK build=%s point=%s kind=%s wall=(%.1f,%.1f) end_pos=(%.1f,%.1f,%.1f) after_back_pos=(%.1f,%.1f,%.1f) hanging=%s"
				% [name_, push["label"], push["kind"], push["wall"].x, push["wall"].y, ended.x, ended.y, ended.z, here.x, here.y, here.z, rig["body"].is_hanging()]
			)
		var sums: Dictionary = _per_build[name_]
		sums["pushes"] += 1
		sums["closest_min"] = minf(sums["closest_min"], rig["closest"])
		sums["end_max"] = maxf(sums["end_max"], rig["end_dist"])
		sums["rise_max"] = maxf(sums["rise_max"], rig["rise_max"])
		sums["excess_max"] = maxf(sums["excess_max"], excess)
		sums["outside"] += rig["outside_ticks"]
		sums["stuck"] += 1 if stuck else 0
		bounds_outside_ticks += rig["outside_ticks"]
		bounds_outside_max_m = maxf(bounds_outside_max_m, rig["outside_max"])
		bounds_rise_excess_max = maxf(bounds_rise_excess_max, excess)
		bounds_rise_max = maxf(bounds_rise_max, rig["rise_max"])
		bounds_end_max_m = maxf(bounds_end_max_m, rig["end_dist"])
		bounds_closest_min_m = minf(bounds_closest_min_m, rig["closest"])
		bounds_stuck_count += 1 if stuck else 0
	bounds_pushes += 1
	_push_index += 1
	hold_action("move_back", false)
	_phase = Phase.START


func _finish_bounds() -> void:
	_release_inputs()
	_restore_time()
	_mode = Mode.NONE
	for rig in _rigs:
		var sums: Dictionary = _per_build[rig["name"]]
		print(
			(
				"MAPBOUNDSUM build=%s pushes=%d closest_min_m=%.2f end_max_m=%.2f rise_max_m=%.3f climb_m=%.3f rise_excess_max_m=%.3f outside_ticks=%d stuck=%d"
				% [
					rig["name"], sums["pushes"], sums["closest_min"], sums["end_max"], sums["rise_max"], rig["climb"],
					sums["excess_max"], sums["outside"], sums["stuck"],
				]
			)
		)
	scout_end_max_m = _per_build["scout"]["end_max"]
	strider_end_max_m = _per_build["strider"]["end_max"]
	crawler_end_max_m = _per_build["crawler"]["end_max"]
	bounds_done = true
	bounds_finished.emit()


# --- Fights -------------------------------------------------------------------------------------------------------


## The Scout in the ring-1 to ring-2 band, four drones from two encounters at the ring-1 wash site, engaged and
## orbiting the same way, so they stay in one sector of the view. Call start_fight next.
func setup_band_fight() -> void:
	_reset_fight()
	var site: Vector3 = _site_position("DroneSite_R1_Wash")
	var spot: Vector2 = ValleyLayout.wash_at(BAND_WALKER_S)
	var toward: Vector2 = Vector2(site.x, site.z) - spot
	_place_walker(spot, rad_to_deg(atan2(-toward.x, -toward.y)), FIGHT_PITCH_DEG)
	var second: Vector2 = Vector2(site.x, site.z) - _wash_tangent(148.0) * GROUP_GAP_M
	_add_group(site, 2)
	_add_group(Vector3(second.x, _floor_y(second.x, second.y), second.y), 2)
	_engage_all()
	print(
		(
			"PERFSETUP band walker=(%.1f,%.1f) ring=%d site=(%.1f,%.1f) second=(%.1f,%.1f) drones=%d"
			% [spot.x, spot.y, ValleyLayout.ring_of(spot.length()), site.x, site.z, second.x, second.y, _drones.size()]
		)
	)


## The ledge-guard drone (west wall shadow strip) and the Scout 18 m east of its site, facing the wall.
func setup_ledge_fight() -> void:
	_reset_fight()
	var site: Vector3 = _site_position("DroneSite_R2_LedgeGuard")
	_place_walker(Vector2(LEDGE_WALKER_X, site.z), 90.0, FIGHT_PITCH_DEG)
	_add_group(site, 1)
	_engage_all()
	print("PERFSETUP ledge walker=(%.1f,%.1f) site=(%.1f,%.1f) drones=%d" % [LEDGE_WALKER_X, site.z, site.x, site.z, _drones.size()])


## The no-lead tracker for `seconds`: the heading held on the nearest drone with A/D, the camera on it, fire held.
func start_fight(seconds: float, fire: bool = true) -> void:
	_fight_done_reset()
	_fire = fire
	_fight_ticks = 0
	_fight_limit = int(round(seconds * float(Engine.physics_ticks_per_second)))
	_mode = Mode.FIGHT


## The ring-2 view looking up-valley: the Scout moved to the ring-2 wash, standing still, camera along the valley, the
## four drones still on it (no return fire), for `seconds`.
func start_view(seconds: float) -> void:
	_release_inputs()
	var spot: Vector2 = ValleyLayout.wash_at(VIEW_WALKER_S)
	_place_walker(spot, 0.0, VIEW_PITCH_DEG)
	# The drones' homes are moved up-valley of the walker (the leash is 60 m from home), in a row across the valley.
	for i in _drones.size():
		var drone: Drone = _drones[i]
		var at: Vector2 = spot + Vector2((float(i) - 1.5) * 6.0, -VIEW_DRONES_AHEAD_M)
		drone.place(Vector3(at.x, _floor_y(at.x, at.y), at.y))
	_engage_all()
	_fight_done_reset()
	_fire = false
	_fight_ticks = 0
	_fight_limit = int(round(seconds * float(Engine.physics_ticks_per_second)))
	_mode = Mode.VIEW
	print("PERFSETUP view walker=(%.1f,%.1f) ring=%d" % [spot.x, spot.y, ValleyLayout.ring_of(spot.length())])


func end_fight() -> void:
	_stop_mode()
	fight_done = true


func _fight_done_reset() -> void:
	fight_done = false
	drone_cliff_min_m = INF
	bolts_live_max = 0
	enemy_bolts_live_max = 0
	active_max = 0
	alive_min = 99
	topups = 0
	_dead_s = 0.0


func _reset_fight() -> void:
	_stop_mode()
	_release_inputs()
	_field.clear_all()
	_drones.clear()
	economy = Economy.new()
	_collector.economy = economy
	_player_box.health = Health.new(PLAYER_HP)
	_player_box.hits_taken = 0
	_rig.pool.clear()
	_fight_done_reset()


func _stop_mode() -> void:
	if _mode == Mode.BOUNDS:
		_restore_time()
	_mode = Mode.NONE
	_release_inputs()


func _place_walker(spot: Vector2, yaw_deg: float, pitch_deg: float) -> void:
	_walker.teleport(
		Transform3D(Basis(Vector3.UP, deg_to_rad(yaw_deg)), Vector3(spot.x, _floor_y(spot.x, spot.y) + SPAWN_LIFT, spot.y))
	)
	_walker.reset_physics_interpolation()
	_orbit.snap()
	_orbit.set_angles(yaw_deg, pitch_deg)


func _site_position(site_name: String) -> Vector3:
	for node: Node in get_tree().get_nodes_in_group(DroneField.SITES_GROUP):
		if node.name == site_name:
			return (node as Node3D).global_position
	push_error("ValleyRun: no drone site %s" % site_name)
	return Vector3.ZERO


func _wash_tangent(s: float) -> Vector2:
	return (ValleyLayout.wash_at(s + 2.0) - ValleyLayout.wash_at(s - 2.0)).normalized()


func _add_group(anchor: Vector3, count: int) -> void:
	var encounter: DroneEncounter = _field.add_encounter(anchor, count, count)
	for drone in encounter.drones:
		drone.health.max_hp = DRONE_HP
		drone.health.hp = DRONE_HP
		_drones.append(drone)


## All drones orbiting the walker now, the same way round at slightly different radii.
func _engage_all() -> void:
	for i in _drones.size():
		var drone: Drone = _drones[i]
		if not is_instance_valid(drone):
			continue
		drone.orbit_sign = 1
		drone.orbit_radius_m = ORBIT_FIRST_M + ORBIT_STEP_M * float(i)
		drone.engage_now()


func _fight_tick(delta: float) -> void:
	_sample_drones()
	_top_up(delta)
	var nearest: Drone = _nearest_alive()
	if nearest != null:
		_turn_onto(nearest.global_position)
		_look_at(nearest)
	hold_action("fire", _fire and nearest != null)
	_count_tick()


func _view_tick(delta: float) -> void:
	_sample_drones()
	_top_up(delta)
	_count_tick()


func _count_tick() -> void:
	_fight_ticks += 1
	if _fight_limit > 0 and _fight_ticks >= _fight_limit:
		_stop_mode()
		fight_done = true
		fight_finished.emit()


func _sample_drones() -> void:
	bolts_live_max = maxi(bolts_live_max, bolts_live)
	enemy_bolts_live_max = maxi(enemy_bolts_live_max, _field.bolts.live)
	active_max = maxi(active_max, _field.active_count())
	alive_min = mini(alive_min, _field.alive_count())
	for drone in _drones:
		if not is_instance_valid(drone) or drone.is_dead():
			continue
		var at: Vector3 = drone.global_position
		var d: float = _wall_distance(Vector2(at.x, at.z))
		if d < drone_cliff_min_m:
			drone_cliff_min_m = d
			drone_cliff_at = at


## A killed drone is replaced (the whole field respawns and re-engages) so four stay in play.
func _top_up(delta: float) -> void:
	if _field.alive_count() >= _drones.size():
		_dead_s = 0.0
		return
	_dead_s += delta
	if _dead_s < TOPUP_AFTER_S:
		return
	_dead_s = 0.0
	topups += 1
	_field.respawn_all()
	_drones.clear()
	for encounter in _field.encounters:
		for drone in encounter.drones:
			drone.health.max_hp = DRONE_HP
			drone.health.hp = DRONE_HP
			_drones.append(drone)
	_engage_all()


func _nearest_alive() -> Drone:
	var best: Drone = null
	var best_d: float = INF
	for drone in _drones:
		if not is_instance_valid(drone) or drone.is_dead():
			continue
		var d: float = drone.global_position.distance_to(_walker.global_position)
		if d < best_d:
			best_d = d
			best = drone
	return best


## A/D toward `spot`'s bearing, released inside the stopping distance: the tracker's rule from DroneFight.
func _turn_onto(spot: Vector3) -> float:
	var bearing: float = rad_to_deg(AimMath.bearing_to(_walker.global_position, spot))
	var error: float = wrapf(bearing - rad_to_deg(_walker.yaw_radians()), -180.0, 180.0)
	var stop: float = absf(_walker.yaw_rate_dps) * YAW_RAMP_S * 0.5 + STOP_MARGIN_DEG
	hold_action("turn_left", error > stop)
	hold_action("turn_right", error < -stop)
	return error


func _look_at(drone: Drone) -> void:
	var to: Vector3 = drone.global_position - (_walker.global_position + _orbit.target_offset)
	var flat: float = Vector2(to.x, to.z).length()
	_orbit.set_angles(rad_to_deg(atan2(-to.x, -to.z)), -rad_to_deg(atan2(to.y, flat)))


# --- Logs and luma ------------------------------------------------------------------------------------------------


func log_perf(label: String) -> void:
	print(
		(
			"PERFRUN %s drones=%d alive_min=%d active_max=%d topups=%d bolts_live_max=%d enemy_bolts_max=%d drone_cliff_min_m=%.2f at=(%.1f,%.1f,%.1f) in_view=%d walker=(%.1f,%.1f)"
			% [
				label, _drones.size(), alive_min, active_max, topups, bolts_live_max, enemy_bolts_live_max, drone_cliff_min_m,
				drone_cliff_at.x, drone_cliff_at.y, drone_cliff_at.z, drones_in_view, _walker.global_position.x,
				_walker.global_position.z,
			]
		)
	)


## Windowed only: the mean luma of the drone's disc and of the ring round it, and the same for the walker's chassis, on
## the frame on screen now (the ledge-guard fight in the west wall's shadow). Headless there are no pixels.
func measure_ledge_luma() -> void:
	if DisplayServer.get_name() == "headless":
		print("LEDGELUMA skipped: headless")
		return
	var image: Image = get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		print("LEDGELUMA no image")
		return
	var drone: Drone = _nearest_alive()
	if drone == null:
		print("LEDGELUMA no drone")
		return
	var camera: Camera3D = _orbit.camera()
	var chassis: Node3D = _walker.get_node("Chassis") as Node3D
	var drone_pair: Vector2 = _disc_luma(image, camera, drone.global_position, Drone.HURT_RADIUS_M)
	var walker_pair: Vector2 = _disc_luma(image, camera, chassis.global_position, 1.0)
	ledge_drone_luma = drone_pair.x
	ledge_drone_bg_luma = drone_pair.y
	ledge_walker_luma = walker_pair.x
	ledge_walker_bg_luma = walker_pair.y
	var at: Vector3 = drone.global_position
	print(
		(
			"LEDGELUMA drone=%.3f drone_bg=%.3f drone_delta=%.3f walker=%.3f walker_bg=%.3f walker_delta=%.3f drone_at=(%.1f,%.1f,%.1f) drone_to_wall_m=%.1f"
			% [
				ledge_drone_luma, ledge_drone_bg_luma, ledge_drone_luma - ledge_drone_bg_luma, ledge_walker_luma,
				ledge_walker_bg_luma, ledge_walker_luma - ledge_walker_bg_luma, at.x, at.y, at.z,
				_wall_distance(Vector2(at.x, at.z)),
			]
		)
	)


## x: mean luma inside the disc of `radius_m` round `at`; y: mean luma of the ring from 1.6 to 2.6 radii.
func _disc_luma(image: Image, camera: Camera3D, at: Vector3, radius_m: float) -> Vector2:
	var scale: float = float(image.get_width()) / get_viewport().get_visible_rect().size.x
	var centre: Vector2 = camera.unproject_position(at) * scale
	var depth: float = -(camera.global_transform.affine_inverse() * at).z
	var focal: float = 0.5 * float(image.get_height()) / tan(deg_to_rad(camera.fov) * 0.5)
	var r: float = focal * radius_m / maxf(depth, 0.001)
	var inside: float = 0.0
	var inside_n: int = 0
	var ring: float = 0.0
	var ring_n: int = 0
	var reach: int = int(ceil(r * 2.6))
	for y in range(int(centre.y) - reach, int(centre.y) + reach + 1):
		for x in range(int(centre.x) - reach, int(centre.x) + reach + 1):
			if x < 0 or y < 0 or x >= image.get_width() or y >= image.get_height():
				continue
			var d: float = Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(centre)
			if d <= r:
				inside += image.get_pixel(x, y).get_luminance()
				inside_n += 1
			elif d >= r * 1.6 and d <= r * 2.6:
				ring += image.get_pixel(x, y).get_luminance()
				ring_n += 1
	return Vector2(inside / float(maxi(inside_n, 1)), ring / float(maxi(ring_n, 1)))


## Back to one 60 Hz tick per frame. A frame runs `fast` ticks of 1/60 s each: the tick rate is fast x 60 and the time
## scale divides the tick back to 1/60 s of game time (the tick accumulator runs in real time, fixed at 1/60 s a frame).
func _restore_time() -> void:
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
