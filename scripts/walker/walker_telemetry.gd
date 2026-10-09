class_name WalkerTelemetry
extends Node
## Observes one WalkerBody and measures the M0 numbers (GDD 4, 5, 8.2): speed, timings, drift, airborne limit.
## Scenarios assert on the public properties; report() prints one TELEMETRY line to the log.

const UNSET: float = -1.0
const UNSET_TICKS: int = 9999
const SPEED_STOP_MPS: float = 0.05
const MOTION_EPSILON_MPS: float = 0.01
const TOP_FRACTION: float = 0.98
const HEIGHT_WINDOW_TICKS: int = 60
const BOB_WINDOW_TICKS: int = 120

var top_speed_mps: float = 0.0
var time_to_top_s: float = UNSET
var stop_time_s: float = UNSET
var max_yaw_rate_dps: float = 0.0
var time_to_turn_rate_s: float = UNSET
var input_to_motion_ticks: int = UNSET_TICKS
var first_lift_ticks: int = UNSET_TICKS
var max_drift_m: float = 0.0
var airborne_violations: int = 0
var max_airborne: int = 0
var min_steps_per_leg: int = 0
var total_steps: int = 0
var held_ticks: int = 0
## Longest run of consecutive held ticks, in seconds.
var longest_hold_s: float = 0.0
var max_tilt_deg: float = 0.0
var body_height_m: float = 0.0
var bob_amplitude_m: float = 0.0
var max_step_up_m: float = 0.0
var current_speed_mps: float = 0.0
## Horizontal distance travelled since reset.
var distance_m: float = 0.0
## Largest gap between a planted foot and the ground straight below it, measured when the foot plants.
var max_plant_gap_m: float = 0.0
var max_rays_per_tick: int = 0
## Planted foot to hip, over that leg's reach: the 0.99 rule (IK never clamps, so drift alone cannot catch it).
var max_planted_reach_ratio: float = 0.0
## Lowest knee above its hip over the run, / reach.
var min_knee_rise_ratio: float = INF
## Smallest knee bend (distance from the hip-foot line on the pole side, / reach) over all legs and states.
var min_knee_bend_ratio: float = INF
## Lowest hip height above the ground below it (chassis clearance, reported).
var min_hip_clearance_m: float = INF
## Largest push-up (rise from ground contact) applied in one tick.
var max_push_rise_m: float = 0.0
## Largest tick-to-tick tilt change, and the slowest physics tick (ms) since the last reset.
var max_tilt_step_deg: float = 0.0
var max_physics_ms: float = 0.0
## Ticks on which a collision zeroed the commanded velocity.
var velocity_resets: int = 0
## Landings per leg per second since reset.
var steps_per_s: float = 0.0
## Steepest ground under any planted foot since reset.
var max_foot_slope_deg: float = 0.0
var ticks: int = 0

var walker: WalkerBody

var _stat_top: float = 4.5
var _was_input: bool = false
var _move_start_tick: int = -1
var _turn_start_tick: int = -1
var _stop_ticks: int = -1
var _hold_run: int = 0
var _plant_pos: PackedVector3Array = PackedVector3Array()
var _plant_known: PackedByteArray = PackedByteArray()
var _steps: PackedInt32Array = PackedInt32Array()
var _height_ring: PackedFloat32Array = PackedFloat32Array()
var _height_index: int = 0
var _height_count: int = 0
var _bob_ring: PackedFloat32Array = PackedFloat32Array()
var _bob_index: int = 0
var _bob_count: int = 0
var _teleports_seen: int = 0
var _resets_base: int = 0
var _gap_ray: PhysicsRayQueryParameters3D


func _ready() -> void:
	# Run after the walker so each tick is measured after the walker has moved.
	process_physics_priority = 100
	_height_ring.resize(HEIGHT_WINDOW_TICKS)
	_bob_ring.resize(BOB_WINDOW_TICKS)
	_gap_ray = PhysicsRayQueryParameters3D.new()
	_gap_ray.collision_mask = 1
	_gap_ray.hit_from_inside = false


func observe(target: WalkerBody) -> void:
	if walker != null and is_instance_valid(walker):
		walker.foot_planted.disconnect(_on_foot_planted)
		walker.build_applied.disconnect(_on_build_applied)
	walker = target
	walker.foot_planted.connect(_on_foot_planted)
	walker.build_applied.connect(_on_build_applied)
	_on_build_applied()


func reset() -> void:
	top_speed_mps = 0.0
	time_to_top_s = UNSET
	stop_time_s = UNSET
	max_yaw_rate_dps = 0.0
	time_to_turn_rate_s = UNSET
	input_to_motion_ticks = UNSET_TICKS
	first_lift_ticks = UNSET_TICKS
	max_drift_m = 0.0
	airborne_violations = 0
	max_airborne = 0
	min_steps_per_leg = 0
	total_steps = 0
	held_ticks = 0
	longest_hold_s = 0.0
	max_tilt_deg = 0.0
	body_height_m = 0.0
	bob_amplitude_m = 0.0
	max_step_up_m = 0.0
	current_speed_mps = 0.0
	distance_m = 0.0
	max_plant_gap_m = 0.0
	max_rays_per_tick = 0
	max_planted_reach_ratio = 0.0
	min_knee_rise_ratio = INF
	min_knee_bend_ratio = INF
	min_hip_clearance_m = INF
	max_push_rise_m = 0.0
	max_tilt_step_deg = 0.0
	max_physics_ms = 0.0
	if walker != null:
		walker.max_push_rise = 0.0
		walker.max_tilt_step_deg = 0.0
	velocity_resets = 0
	steps_per_s = 0.0
	max_foot_slope_deg = 0.0
	ticks = 0
	_was_input = false
	_move_start_tick = -1
	_turn_start_tick = -1
	_stop_ticks = -1
	_hold_run = 0
	_height_index = 0
	_height_count = 0
	_bob_index = 0
	_bob_count = 0
	_size_leg_buffers()
	if walker != null:
		_teleports_seen = walker.teleport_count
		walker.max_rays_per_tick = 0
		_resets_base = walker.velocity_resets


## Fraction of ticks the body was held by rule 5 (0..1).
func held_fraction() -> float:
	return float(held_ticks) / float(maxi(ticks, 1))


func report(label: String = "") -> void:
	var data: Dictionary = {
		"label": label,
		"legs": walker.leg_count() if walker != null else 0,
		"stat_top_speed": snappedf(_stat_top, 0.001),
		"top_speed_mps": snappedf(top_speed_mps, 0.001),
		"time_to_top_s": snappedf(time_to_top_s, 0.001),
		"stop_time_s": snappedf(stop_time_s, 0.001),
		"max_yaw_rate_dps": snappedf(max_yaw_rate_dps, 0.01),
		"time_to_turn_rate_s": snappedf(time_to_turn_rate_s, 0.001),
		"input_to_motion_ticks": input_to_motion_ticks,
		"first_lift_ticks": first_lift_ticks,
		"max_drift_m": snappedf(max_drift_m, 0.00001),
		"airborne_violations": airborne_violations,
		"max_airborne": max_airborne,
		"min_steps_per_leg": min_steps_per_leg,
		"total_steps": total_steps,
		"held_ticks": held_ticks,
		"held_fraction": snappedf(held_fraction(), 0.001),
		"longest_hold_s": snappedf(longest_hold_s, 0.01),
		"max_tilt_deg": snappedf(max_tilt_deg, 0.01),
		"body_height_m": snappedf(body_height_m, 0.001),
		"bob_amplitude_m": snappedf(bob_amplitude_m, 0.0001),
		"max_step_up_m": snappedf(max_step_up_m, 0.001),
		"distance_m": snappedf(distance_m, 0.01),
		"max_plant_gap_m": snappedf(max_plant_gap_m, 0.0001),
		"max_rays_per_tick": max_rays_per_tick,
		"max_planted_reach_ratio": snappedf(max_planted_reach_ratio, 0.0001),
		"min_knee_rise_ratio": snappedf(minf(min_knee_rise_ratio, 9.0), 0.0001),
		"min_knee_bend_ratio": snappedf(minf(min_knee_bend_ratio, 9.0), 0.0001),
		"min_hip_clearance_m": snappedf(minf(min_hip_clearance_m, 9.0), 0.001),
		"max_push_rise_m": snappedf(max_push_rise_m, 0.001),
		"max_tilt_step_deg": snappedf(max_tilt_step_deg, 0.01),
		"max_physics_ms": snappedf(max_physics_ms, 0.01),
		"velocity_resets": velocity_resets,
		"steps_per_s": snappedf(steps_per_s, 0.001),
		"max_foot_slope_deg": snappedf(max_foot_slope_deg, 0.01),
		"ticks": ticks,
	}
	if walker != null:
		data["yaw_deg"] = snappedf(rad_to_deg(walker.yaw_radians()), 0.1)
		var at: Vector3 = walker.global_position
		data["pos"] = [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
		var stats: Dictionary = walker.stats()
		data["stat_step_up"] = snappedf(stats["step_up"], 0.001)
		data["stat_turn_rate"] = snappedf(stats["turn_rate"], 0.01)
		var times: Vector2 = walker.step_times()
		data["step_time_top"] = snappedf(times.x, 0.001)
		data["step_time_idle"] = snappedf(times.y, 0.001)
	print("TELEMETRY " + JSON.stringify(data))


func _physics_process(delta: float) -> void:
	if walker == null or not is_instance_valid(walker) or walker.gait() == null:
		return
	if walker.teleport_count != _teleports_seen:
		_teleports_seen = walker.teleport_count
		_plant_known.fill(0)
	ticks += 1
	var speed: float = walker.velocity.length()
	current_speed_mps = speed
	top_speed_mps = maxf(top_speed_mps, speed)
	distance_m += speed * delta
	max_yaw_rate_dps = maxf(max_yaw_rate_dps, absf(walker.yaw_rate_dps))
	var input_now: bool = walker.move_input_active
	_track_timings(delta, speed, input_now)
	_track_gait()
	if walker.held_this_tick:
		held_ticks += 1
		_hold_run += 1
		longest_hold_s = maxf(longest_hold_s, float(_hold_run) * delta)
	else:
		_hold_run = 0
	max_tilt_deg = maxf(max_tilt_deg, walker.tilt_degrees())
	max_rays_per_tick = maxi(max_rays_per_tick, walker.max_rays_per_tick)
	max_planted_reach_ratio = maxf(max_planted_reach_ratio, walker.max_planted_reach_ratio())
	min_knee_rise_ratio = minf(min_knee_rise_ratio, walker.min_knee_rise_ratio())
	min_knee_bend_ratio = minf(min_knee_bend_ratio, walker.min_knee_bend_ratio())
	velocity_resets = walker.velocity_resets - _resets_base
	min_hip_clearance_m = minf(min_hip_clearance_m, walker.min_hip_clearance())
	max_push_rise_m = maxf(max_push_rise_m, walker.max_push_rise)
	max_tilt_step_deg = maxf(max_tilt_step_deg, walker.max_tilt_step_deg)
	max_physics_ms = maxf(max_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	steps_per_s = float(total_steps) / float(maxi(walker.leg_count(), 1)) / (float(ticks) * delta)
	_track_height(walker.height_above_plane())


func _track_timings(delta: float, speed: float, input_now: bool) -> void:
	if input_now and not _was_input:
		_move_start_tick = ticks
		_stop_ticks = -1
	if not input_now and _was_input and speed > SPEED_STOP_MPS:
		_stop_ticks = 0
	_was_input = input_now
	if _move_start_tick >= 0 and input_now:
		var since: int = ticks - _move_start_tick + 1
		if input_to_motion_ticks == UNSET_TICKS and speed > MOTION_EPSILON_MPS:
			input_to_motion_ticks = since
		if time_to_top_s == UNSET and speed >= TOP_FRACTION * _stat_top:
			time_to_top_s = float(since) * delta
		if first_lift_ticks == UNSET_TICKS and walker.gait().airborne_count() > 0:
			first_lift_ticks = since
	if _stop_ticks >= 0:
		_stop_ticks += 1
		if speed < SPEED_STOP_MPS:
			stop_time_s = float(_stop_ticks) * delta
			_stop_ticks = -1
	var turning: bool = absf(walker.turn_input) > 0.01
	if turning and _turn_start_tick < 0:
		_turn_start_tick = ticks
	elif not turning:
		_turn_start_tick = -1
	if turning and time_to_turn_rate_s == UNSET:
		var wanted: float = absf(walker.target_yaw_rate_dps)
		if wanted > 0.0 and absf(walker.yaw_rate_dps) >= TOP_FRACTION * wanted:
			time_to_turn_rate_s = float(ticks - _turn_start_tick + 1) * delta


func _track_gait() -> void:
	var gait: GaitSolver = walker.gait()
	var airborne: int = gait.airborne_count()
	max_airborne = maxi(max_airborne, airborne)
	if airborne > gait.gait_limit():
		airborne_violations += 1
	var fewest: int = 1 << 30
	for i in mini(gait.leg_count(), _plant_pos.size()):
		if gait.state_of(i) != GaitSolver.LegState.PLANTED:
			_plant_known[i] = 0
		else:
			var foot: Vector3 = walker.foot_position(i)
			if _plant_known[i] == 0:
				_plant_pos[i] = foot
				_plant_known[i] = 1
				_measure_plant_gap(foot)
			else:
				max_drift_m = maxf(max_drift_m, foot.distance_to(_plant_pos[i]))
		fewest = mini(fewest, _steps[i])
	min_steps_per_leg = 0 if fewest == (1 << 30) else fewest


## Planted foot against the ground straight below it.
func _measure_plant_gap(foot: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = walker.get_world_3d().direct_space_state
	_gap_ray.from = foot + Vector3.UP * 1.0
	_gap_ray.to = foot + Vector3.DOWN * 3.0
	var hit: Dictionary = space.intersect_ray(_gap_ray)
	if hit.is_empty():
		return
	var ground: Vector3 = hit["position"]
	max_plant_gap_m = maxf(max_plant_gap_m, absf(foot.y - ground.y))


func _track_height(height: float) -> void:
	_height_ring[_height_index] = height
	_height_index = (_height_index + 1) % HEIGHT_WINDOW_TICKS
	_height_count = mini(_height_count + 1, HEIGHT_WINDOW_TICKS)
	_bob_ring[_bob_index] = height
	_bob_index = (_bob_index + 1) % BOB_WINDOW_TICKS
	_bob_count = mini(_bob_count + 1, BOB_WINDOW_TICKS)
	var total: float = 0.0
	for i in _height_count:
		total += _height_ring[i]
	body_height_m = total / float(_height_count)
	var low: float = INF
	var high: float = -INF
	for i in _bob_count:
		low = minf(low, _bob_ring[i])
		high = maxf(high, _bob_ring[i])
	bob_amplitude_m = (high - low) * 0.5


func _size_leg_buffers() -> void:
	var count: int = walker.leg_count() if walker != null else 0
	_plant_pos.resize(count)
	_plant_known.resize(count)
	_plant_known.fill(0)
	_steps.resize(count)
	_steps.fill(0)


func _on_build_applied() -> void:
	_stat_top = walker.stats()["top_speed"]
	reset()


func _on_foot_planted(leg: int, _position: Vector3, normal: Vector3) -> void:
	total_steps += 1
	max_foot_slope_deg = maxf(max_foot_slope_deg, rad_to_deg(normal.angle_to(Vector3.UP)))
	if leg < _steps.size():
		_steps[leg] += 1
