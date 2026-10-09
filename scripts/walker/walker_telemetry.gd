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
const STALL_FRACTION: float = 0.1
## A stall longer than this is logged as a STALL line.
const STALL_LOG_S: float = 0.4
## A pad box is checked this far above its foot point, so the ground it stands on is not an overlap.
const PAD_CHECK_LIFT: float = 0.03
## Stands for "no gap on this axis" in `box_gap` (the vertical axis is left out of the pad separation).
const PAD_SEP_NO_AXIS: float = 1000.0
## Two same-side pads overlap this much fore-aft (m) or more: stacked on one spot (a whole pad length is 0.34).
const STACKED_OVERLAP_M: float = 0.3
## `ahead_rise` scans heights from AHEAD_STEP to AHEAD_MAX in these steps (m).
const AHEAD_STEP: float = 0.1
const AHEAD_MAX: float = 3.0
## How far ahead (m) `ahead_rise` looks: a tall walker stops a reach (up to 2.5 m for a long build) short of a face.
const AHEAD_DISTANCE: float = 2.5

var top_speed_mps: float = 0.0
var time_to_top_s: float = UNSET
var stop_time_s: float = UNSET
var max_yaw_rate_dps: float = 0.0
var time_to_turn_rate_s: float = UNSET
var input_to_motion_ticks: int = UNSET_TICKS
var first_lift_ticks: int = UNSET_TICKS
var max_drift_m: float = 0.0
## Highest a planted pad was lifted above where it was planted (m): the IK folds a leg no tighter than its fold distance and
## pushes the pad up when the hip comes down on it (a descent). The whole 3D slide is `max_drift_m`.
var max_fold_lift_m: float = 0.0
var airborne_violations: int = 0
var max_airborne: int = 0
var min_steps_per_leg: int = 0
var total_steps: int = 0
var held_ticks: int = 0
## Ticks per cause of not moving as commanded (WalkerBody.block_cause) since reset.
var hold_causes: Dictionary = {}
## Longest run of consecutive held ticks, in seconds.
var longest_hold_s: float = 0.0
var max_tilt_deg: float = 0.0
var body_height_m: float = 0.0
var bob_amplitude_m: float = 0.0
var max_step_up_m: float = 0.0
## Highest block every foot stood on the top of (a climb: reach up and haul), set by the test course.
var max_climb_m: float = 0.0
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
var max_landing_snap_m: float = 0.0
var max_landing_slide_m: float = 0.0
## Largest tick-to-tick tilt change, and the slowest physics tick (ms) since the last reset.
var max_tilt_step_deg: float = 0.0
var max_physics_ms: float = 0.0
## Ticks on which a collision zeroed the commanded velocity.
var velocity_resets: int = 0
## Longest run of consecutive ticks (seconds) below STALL_FRACTION of the commanded speed while input is held.
## A hold (`longest_hold_s`) is only reported; a stall is what the player sees as the walker stopping.
var longest_stall_s: float = 0.0
## Largest pitch the contact resolve applied in one tick, apart from the smoothed tilt step (degrees).
var max_resolve_pitch_deg: float = 0.0
## Set by the test course on ticks that must not count as a stall (the walker has reached the end of the lane).
var stall_exempt: bool = false
## Smallest fore-aft distance between two planted pads on one side, less one pad length (m). INF until two are planted.
var min_pad_gap_m: float = INF
## Smallest separation of two planted pad boxes on one side in 2D, lateral and fore-aft (m): positive = apart, negative = the boxes overlap
## (how deep). Unlike `min_pad_gap_m` it counts the sideways offset too, so it does not sit at a -0.34 floor.
var min_pad_sep_m: float = INF
## Ticks in which two planted pads of one side stand (almost) on one spot (their fore-aft overlap is at least STACKED_OVERLAP_M).
var stacked_pad_ticks: int = 0
## Longest run of consecutive ticks (seconds) in which the progress along the wanted direction (horizontal, vertical
## rise does not count) stayed below STALL_FRACTION of the wanted speed while input is held.
var longest_input_stall_s: float = 0.0
## Since reset: reach-up swings, step-up swings, and ticks with a leg hanging for a rise or drop beyond a stride.
## Largest nose-up or nose-down pitch of the body (degrees), and the largest rise of the body root in one tick (m).
var max_pitch_deg: float = 0.0
## The most nose-down pitch (negative degrees; 0 when the body never pitched down): the descent's lean.
var min_pitch_deg: float = 0.0
var max_root_rise_tick_m: float = 0.0
## Smallest centre-of-mass margin inside the planted feet's polygon over the mean reach, over ticks with a leg hanging.
var min_support_margin_ratio: float = INF
## Ticks on which a pad (a box 3 cm above its foot point) overlapped the world: a reaching or hanging pad must never.
var pad_inside_ticks: int = 0
## Prints the first PADIN lines (debugging).
## Highest a hanging foot got above the ground below it, over its reach (hanging legs only).
var max_hang_rise_ratio: float = 0.0
var reach_ups: int = 0
var step_ups: int = 0
var hang_ticks: int = 0
## `min_pad_sep_m` (2D: lateral and fore-aft, not the vertical axis) as it stood at the last report() (an assert one frame later would see another tick).
var pad_gap_at_report_m: float = 9.0
## Walker cost per physics tick since reset, spawn ticks excluded: ms percentiles and the worst call counts.
var max_test_motions_per_tick: int = 0
var max_shape_queries_per_tick: int = 0
var max_rays_cast_per_tick: int = 0
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
var _stall_run: int = 0
var _input_stall_run: int = 0
var _stall_delta: float = 1.0 / 60.0
var _stall_start: Vector3 = Vector3.ZERO
var _stall_causes: Dictionary = {}
var _stall_last: Vector3 = Vector3.ZERO
var _stall_step: Vector3 = Vector3.ZERO
var _stall_known: bool = false
var _stall_teleports: int = 0
var _tick_ms: PackedFloat32Array = PackedFloat32Array()
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
## True on the tick a teleport (spawn, rebuild) happened: root rise and pad checks skip it.
var _teleported_now: bool = false
var _resets_base: int = 0
var _last_root_y: float = 0.0
var _pad_shape: BoxShape3D
var _pad_query: PhysicsShapeQueryParameters3D
var _reach_base: int = 0
var _step_base: int = 0
var _hang_base: int = 0
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
	max_fold_lift_m = 0.0
	airborne_violations = 0
	max_airborne = 0
	min_steps_per_leg = 0
	total_steps = 0
	held_ticks = 0
	hold_causes = {}
	longest_hold_s = 0.0
	max_tilt_deg = 0.0
	body_height_m = 0.0
	bob_amplitude_m = 0.0
	max_step_up_m = 0.0
	max_climb_m = 0.0
	current_speed_mps = 0.0
	distance_m = 0.0
	max_plant_gap_m = 0.0
	max_rays_per_tick = 0
	max_planted_reach_ratio = 0.0
	min_knee_rise_ratio = INF
	min_knee_bend_ratio = INF
	min_hip_clearance_m = INF
	max_push_rise_m = 0.0
	max_landing_snap_m = 0.0
	max_landing_slide_m = 0.0
	max_tilt_step_deg = 0.0
	max_physics_ms = 0.0
	if walker != null:
		walker.max_push_rise = 0.0
		walker.max_landing_snap = 0.0
		walker.max_landing_slide = 0.0
		walker.max_tilt_step_deg = 0.0
		walker.max_resolve_pitch_deg = 0.0
	velocity_resets = 0
	longest_stall_s = 0.0
	max_resolve_pitch_deg = 0.0
	min_pad_gap_m = INF
	min_pad_sep_m = INF
	stacked_pad_ticks = 0
	longest_input_stall_s = 0.0
	_input_stall_run = 0
	max_test_motions_per_tick = 0
	max_shape_queries_per_tick = 0
	max_rays_cast_per_tick = 0
	_tick_ms.resize(0)
	_end_stall()
	_stall_known = false
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
		_reach_base = walker.reach_ups
		_step_base = walker.step_ups
		_hang_base = walker.hang_ticks
	reach_ups = 0
	step_ups = 0
	hang_ticks = 0
	max_pitch_deg = 0.0
	min_pitch_deg = 0.0
	max_root_rise_tick_m = 0.0
	min_support_margin_ratio = INF
	pad_inside_ticks = 0
	max_hang_rise_ratio = 0.0


## Fraction of ticks the body was held by rule 5 (0..1).
func held_fraction() -> float:
	return float(held_ticks) / float(maxi(ticks, 1))


## Percentile (0..1) of the walker's physics-tick time in ms since reset (0 with no samples).
func tick_percentile_ms(fraction: float) -> float:
	if _tick_ms.is_empty():
		return 0.0
	var sorted: PackedFloat32Array = _tick_ms.duplicate()
	sorted.sort()
	return sorted[clampi(int(ceil(fraction * float(sorted.size()))) - 1, 0, sorted.size() - 1)]


var tick_p95_ms: float:
	get:
		return tick_percentile_ms(0.95)
var tick_p99_ms: float:
	get:
		return tick_percentile_ms(0.99)
var tick_max_ms: float:
	get:
		return tick_percentile_ms(1.0)


func report(label: String = "") -> void:
	pad_gap_at_report_m = snappedf(minf(min_pad_sep_m, 9.0), 0.0001)
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
		"max_fold_lift_m": snappedf(max_fold_lift_m, 0.001),
		"airborne_violations": airborne_violations,
		"max_airborne": max_airborne,
		"min_steps_per_leg": min_steps_per_leg,
		"total_steps": total_steps,
		"held_ticks": held_ticks,
		"held_fraction": snappedf(held_fraction(), 0.001),
		"hold_causes": hold_causes,
		"longest_hold_s": snappedf(longest_hold_s, 0.01),
		"max_tilt_deg": snappedf(max_tilt_deg, 0.01),
		"body_height_m": snappedf(body_height_m, 0.001),
		"bob_amplitude_m": snappedf(bob_amplitude_m, 0.0001),
		"max_step_up_m": snappedf(max_step_up_m, 0.001),
		"max_climb_m": snappedf(max_climb_m, 0.001),
		"distance_m": snappedf(distance_m, 0.01),
		"max_plant_gap_m": snappedf(max_plant_gap_m, 0.0001),
		"max_rays_per_tick": max_rays_per_tick,
		"max_planted_reach_ratio": snappedf(max_planted_reach_ratio, 0.0001),
		"min_knee_rise_ratio": snappedf(minf(min_knee_rise_ratio, 9.0), 0.0001),
		"min_knee_bend_ratio": snappedf(minf(min_knee_bend_ratio, 9.0), 0.0001),
		"min_hip_clearance_m": snappedf(minf(min_hip_clearance_m, 9.0), 0.001),
		"max_push_rise_m": snappedf(max_push_rise_m, 0.001),
		"max_landing_snap_m": snappedf(max_landing_snap_m, 0.001),
		"max_landing_slide_m": snappedf(max_landing_slide_m, 0.001),
		"max_tilt_step_deg": snappedf(max_tilt_step_deg, 0.01),
		"max_physics_ms": snappedf(max_physics_ms, 0.01),
		"velocity_resets": velocity_resets,
		"longest_stall_s": snappedf(longest_stall_s, 0.01),
		"max_resolve_pitch_deg": snappedf(max_resolve_pitch_deg, 0.01),
		"min_pad_gap_m": snappedf(minf(min_pad_gap_m, 9.0), 0.001),
		"min_pad_sep_m": snappedf(minf(min_pad_sep_m, 9.0), 0.001),
		"stacked_pad_ticks": stacked_pad_ticks,
		"longest_input_stall_s": snappedf(longest_input_stall_s, 0.01),
		"max_pitch_deg": snappedf(max_pitch_deg, 0.01),
		"min_pitch_deg": snappedf(min_pitch_deg, 0.01),
		"max_root_rise_tick_m": snappedf(max_root_rise_tick_m, 0.0001),
		"min_support_margin_ratio": snappedf(minf(min_support_margin_ratio, 9.0), 0.001),
		"pad_inside_ticks": pad_inside_ticks,
		"max_hang_rise_ratio": snappedf(max_hang_rise_ratio, 0.001),
		"reach_ups": reach_ups,
		"step_ups": step_ups,
		"hang_ticks": hang_ticks,
		"tick_p95_ms": snappedf(tick_p95_ms, 0.001),
		"tick_p99_ms": snappedf(tick_p99_ms, 0.001),
		"tick_max_ms": snappedf(tick_max_ms, 0.001),
		"tick_samples": _tick_ms.size(),
		"max_test_motions_per_tick": max_test_motions_per_tick,
		"max_shape_queries_per_tick": max_shape_queries_per_tick,
		"max_rays_cast_per_tick": max_rays_cast_per_tick,
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
	_teleported_now = walker.teleport_count != _teleports_seen
	if _teleported_now:
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
	if walker.block_cause != "":
		hold_causes[walker.block_cause] = int(hold_causes.get(walker.block_cause, 0)) + 1
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
	reach_ups = walker.reach_ups - _reach_base
	step_ups = walker.step_ups - _step_base
	hang_ticks = walker.hang_ticks - _hang_base
	min_hip_clearance_m = minf(min_hip_clearance_m, walker.min_hip_clearance())
	max_push_rise_m = maxf(max_push_rise_m, walker.max_push_rise)
	max_landing_snap_m = maxf(max_landing_snap_m, walker.max_landing_snap)
	max_landing_slide_m = maxf(max_landing_slide_m, walker.max_landing_slide)
	max_tilt_step_deg = maxf(max_tilt_step_deg, walker.max_tilt_step_deg)
	max_resolve_pitch_deg = maxf(max_resolve_pitch_deg, walker.max_resolve_pitch_deg)
	_track_stall(delta)
	_track_climb(delta)
	_track_pad_gap()
	_track_cost()
	max_physics_ms = maxf(max_physics_ms, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	steps_per_s = float(total_steps) / float(maxi(walker.leg_count(), 1)) / (float(ticks) * delta)
	_track_height(walker.height_above_plane())


## Pitch, root rise per tick, support margin, pads inside geometry and the height of hanging feet (T16).
func _track_climb(_delta: float) -> void:
	max_pitch_deg = maxf(max_pitch_deg, absf(walker.pitch_degrees()))
	min_pitch_deg = minf(min_pitch_deg, walker.pitch_degrees())
	var root_y: float = walker.global_position.y
	if not _teleported_now and ticks > 1:
		max_root_rise_tick_m = maxf(max_root_rise_tick_m, root_y - _last_root_y)
	_last_root_y = root_y
	var margin: float = walker.support_margin_ratio()
	if margin < INF:
		min_support_margin_ratio = minf(min_support_margin_ratio, margin)
	if _pad_shape == null:
		_pad_shape = BoxShape3D.new()
		_pad_shape.size = Vector3(WalkerLeg.PAD_SIZE.x, 0.12, WalkerLeg.PAD_SIZE.z)
		_pad_query = PhysicsShapeQueryParameters3D.new()
		_pad_query.shape = _pad_shape
		_pad_query.collision_mask = 1
	var space: PhysicsDirectSpaceState3D = walker.get_world_3d().direct_space_state
	var basis := Basis(Vector3.UP, walker.yaw_radians())
	var gait: GaitSolver = walker.gait()
	var inside: bool = false
	for i in walker.leg_count():
		var foot: Vector3 = walker.foot_position(i)
		var near_face: bool = walker.is_leg_hanging(i)
		if (near_face or walker.is_leg_climbing(i) or walker.leg_reached_up(i)) and not _teleported_now:
			# Only the pads that reach, step up, step down or hang (and the planted pads a reach-up put down) are checked, with the whole
			# pad's footprint (corners included) tilted to the pad's ground normal (a pad on a slope lies on it; a stride pad may touch a
			# rock it is stepping onto).
			var up: Vector3 = walker.foot_normal(i)
			var tilt: Basis = Basis(Quaternion(Vector3.UP, up)) * basis
			_pad_query.transform = Transform3D(tilt, foot + up * (PAD_CHECK_LIFT + 0.06))
			if not space.intersect_shape(_pad_query, 1).is_empty():
				inside = true
		if near_face:
			_gap_ray.from = foot + Vector3.UP * 0.5
			_gap_ray.to = foot + Vector3.DOWN * 3.0
			var hit: Dictionary = space.intersect_ray(_gap_ray)
			if not hit.is_empty():
				max_hang_rise_ratio = maxf(max_hang_rise_ratio, (foot.y - hit["position"].y) / walker.leg_reach(i))
	if inside:
		pad_inside_ticks += 1


## Progress counts vertical rise too (a slow haul up a ledge is not a stall): the speed of the body root in 3D.
func _track_stall(delta: float) -> void:
	var wanted: float = walker.input_speed()
	var here: Vector3 = walker.global_position
	var progress: float = here.distance_to(_stall_last) / delta if _stall_known else 0.0
	_stall_step = Vector3(here.x - _stall_last.x, 0.0, here.z - _stall_last.z) if _stall_known else Vector3.ZERO
	_stall_last = here
	_stall_known = true
	if walker.teleport_count != _stall_teleports:
		_stall_teleports = walker.teleport_count
		progress = INF
	if (
		not stall_exempt
		and walker.move_input_active
		and wanted > MOTION_EPSILON_MPS
		and progress < STALL_FRACTION * wanted
	):
		if _stall_run == 0:
			_stall_causes.clear()
			_stall_start = here
		_stall_run += 1
		_stall_delta = delta
		_stall_causes[walker.block_cause] = int(_stall_causes.get(walker.block_cause, 0)) + 1
		longest_stall_s = maxf(longest_stall_s, float(_stall_run) * delta)
	else:
		_end_stall()
	var direction: Vector3 = walker.input_direction()
	var along: float = _stall_step.dot(direction) / delta if direction != Vector3.ZERO else 0.0
	if (
		not stall_exempt
		and walker.move_input_active
		and wanted > MOTION_EPSILON_MPS
		and walker.teleport_count == _stall_teleports
		and along < STALL_FRACTION * wanted
	):
		_input_stall_run += 1
		longest_input_stall_s = maxf(longest_input_stall_s, float(_input_stall_run) * delta)
	else:
		_input_stall_run = 0


## Logs a finished stall over STALL_LOG_S: `STALL dur=.. pos=.. ahead_rise=.. causes=..` (ahead_rise: the tallest
## ground or face up to AHEAD_DISTANCE ahead of the body over the ground under it).
func _end_stall() -> void:
	if float(_stall_run) * _stall_delta > STALL_LOG_S:
		print(
			(
				"STALL dur=%.2f pos=%s ahead_rise=%.2f causes=%s"
				% [
					float(_stall_run) * _stall_delta,
					str(_stall_start.snapped(Vector3.ONE * 0.01)),
					_ahead_rise(_stall_start),
					str(_stall_causes)
				]
			)
		)
	_stall_run = 0


func _ahead_rise(from: Vector3) -> float:
	var space: PhysicsDirectSpaceState3D = walker.get_world_3d().direct_space_state
	var forward := Vector3(-sin(walker.yaw_radians()), 0.0, -cos(walker.yaw_radians()))
	var under: float = _ground_y(space, from)
	var tallest: float = 0.0
	for distance in [0.5, 1.0, 1.5, 2.0, 2.5]:
		tallest = maxf(tallest, _ground_y(space, from + forward * distance) - under)
	# A vertical face (or an overhang above the body, as in an alcove) hides from the downward rays: horizontal
	# rays 0.1 m apart in height, AHEAD_DISTANCE ahead, give the tallest height that is blocked.
	var height: float = AHEAD_STEP
	while height <= AHEAD_MAX:
		_gap_ray.from = Vector3(from.x, under + height, from.z)
		_gap_ray.to = _gap_ray.from + forward * AHEAD_DISTANCE
		if not space.intersect_ray(_gap_ray).is_empty():
			tallest = maxf(tallest, height)
		height += AHEAD_STEP
	return tallest


## Ground height under `at`: a ray from just above the walker root (not from 3 m up: an alcove roof would be hit).
func _ground_y(space: PhysicsDirectSpaceState3D, at: Vector3) -> float:
	_gap_ray.from = at + Vector3.UP * 0.3
	_gap_ray.to = at + Vector3.DOWN * 3.0
	var hit: Dictionary = space.intersect_ray(_gap_ray)
	return hit["position"].y if not hit.is_empty() else at.y


## Seconds of the stall in progress (0 when none).
var current_stall_s: float:
	get:
		return float(_stall_run) * _stall_delta


## Fore-aft distance between planted pads on one side, less a pad length (their drawn pads merge below 0.05).
func _track_pad_gap() -> void:
	var gait: GaitSolver = walker.gait()
	var forward: Vector3 = Vector3(-sin(walker.yaw_radians()), 0.0, -cos(walker.yaw_radians()))
	var right: Vector3 = Vector3(cos(walker.yaw_radians()), 0.0, -sin(walker.yaw_radians()))
	var count: int = walker.leg_count()
	var stacked: bool = false
	for i in count:
		if gait.state_of(i) != GaitSolver.LegState.PLANTED:
			continue
		for j in range(i + 1, count):
			if gait.state_of(j) != GaitSolver.LegState.PLANTED or walker.leg_side(i) != walker.leg_side(j):
				continue
			var offset: Vector3 = walker.foot_position(i) - walker.foot_position(j)
			var apart: float = absf(offset.dot(forward))
			min_pad_gap_m = minf(min_pad_gap_m, apart - WalkerLeg.PAD_SIZE.z)
			var lateral: float = absf(offset.dot(right)) - WalkerLeg.PAD_SIZE.x
			# Pads that overlap sideways are measured by how far they overlap fore-aft (down to a whole pad length when they sit
			# on one spot); pads beside each other by the length of their gaps.
			var sep: float = apart - WalkerLeg.PAD_SIZE.z if lateral < 0.0 else box_gap(lateral, -PAD_SEP_NO_AXIS, apart - WalkerLeg.PAD_SIZE.z)
			min_pad_sep_m = minf(min_pad_sep_m, sep)
			if sep <= -STACKED_OVERLAP_M:
				stacked = true
	if stacked and not _teleported_now:
		stacked_pad_ticks += 1


## Separation of two boxes from their per-axis gaps (centre distance less the summed half sizes): the length of the
## positive gaps when apart, else the shallowest overlap (negative).
static func box_gap(gap_x: float, gap_y: float, gap_z: float) -> float:
	var px: float = maxf(gap_x, 0.0)
	var py: float = maxf(gap_y, 0.0)
	var pz: float = maxf(gap_z, 0.0)
	if px > 0.0 or py > 0.0 or pz > 0.0:
		return sqrt(px * px + py * py + pz * pz)
	return maxf(gap_x, maxf(gap_y, gap_z))


func _track_cost() -> void:
	if not walker.tick_counts:
		return
	_tick_ms.append(float(walker.tick_usec) / 1000.0)
	max_test_motions_per_tick = maxi(max_test_motions_per_tick, walker.test_motions_this_tick)
	max_shape_queries_per_tick = maxi(max_shape_queries_per_tick, walker.shape_queries_this_tick)
	max_rays_cast_per_tick = maxi(max_rays_cast_per_tick, walker.rays_this_tick)


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
				max_fold_lift_m = maxf(max_fold_lift_m, foot.y - _plant_pos[i].y)
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
