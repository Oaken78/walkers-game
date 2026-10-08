class_name GaitSolver
extends RefCounted
## Decides every physics tick which legs lift, how far each swing is, and which legs are blocked (GDD 5, 8.2).
## Pure logic: T03 feeds it foot errors and target validity and reads the states back.
## 6+ legs walk as two alternating tripods; 4-5 legs walk a wave gait (one leg per group, cycling).

signal step_started(leg: int)
signal foot_planted(leg: int)

enum LegState { PLANTED, SWINGING, HOVERING }

const TIME_EPSILON: float = 0.000001

## A leg wants to step when foot error > trigger_ratio x reach.
var trigger_ratio: float = 0.5
var step_time_idle: float = 0.30
var step_time_top: float = 0.18
var handover_progress: float = 0.85
## Seconds blocked before a leg hovers at its rest pose.
var hover_delay: float = 0.5
var lift_ratio: float = 0.25

var _count: int = 0
var _group_count: int = 1
var _gait_limit: int = 0
var _active_group: int = 0
var _was_moving: bool = false
var _reaches: PackedFloat32Array = PackedFloat32Array()
var _groups: PackedInt32Array = PackedInt32Array()
var _states: PackedInt32Array = PackedInt32Array()
var _progress: PackedFloat32Array = PackedFloat32Array()
var _durations: PackedFloat32Array = PackedFloat32Array()
var _blocked_time: PackedFloat32Array = PackedFloat32Array()
var _blocked: PackedByteArray = PackedByteArray()
var _wants: PackedByteArray = PackedByteArray()


func _init(sides: PackedInt32Array, reaches: PackedFloat32Array) -> void:
	if sides.size() != reaches.size():
		push_error("GaitSolver: sides and reaches differ in size")
	_count = mini(sides.size(), reaches.size())
	_reaches = reaches
	_groups.resize(_count)
	if _count >= 6:
		_group_count = 2
		_gait_limit = _count / 2
		for i in _count:
			var pos: int = 0
			for j in i:
				if sides[j] == sides[i]:
					pos += 1
			_groups[i] = (pos + (0 if sides[i] < 0 else 1)) % 2
	else:
		_group_count = maxi(_count, 1)
		_gait_limit = mini(_count, 1)
		for i in _count:
			# Rank in the order: left rear to front, then right rear to front.
			var rank: int = 0
			for j in _count:
				if j == i:
					continue
				if sides[j] < sides[i] or (sides[j] == sides[i] and j > i):
					rank += 1
			_groups[i] = rank
	_states.resize(_count)
	_progress.resize(_count)
	_durations.resize(_count)
	_blocked_time.resize(_count)
	_blocked.resize(_count)
	_wants.resize(_count)
	reset()


func reset() -> void:
	_active_group = 0
	_was_moving = false
	for i in _count:
		_states[i] = LegState.PLANTED
		_progress[i] = 0.0
		_durations[i] = step_time_idle
		_blocked_time[i] = 0.0
		_blocked[i] = 0
		_wants[i] = 0


func update(
	delta: float,
	moving: bool,
	speed_ratio: float,
	foot_errors: PackedFloat32Array,
	targets_valid: Array[bool]
) -> void:
	if foot_errors.size() != _count or targets_valid.size() != _count:
		push_error("GaitSolver.update: array sizes must equal leg_count() (%d)" % _count)
		return
	var kick: bool = moving and not _was_moving
	_was_moving = moving

	# 1. Advance swings.
	for i in _count:
		if _states[i] != LegState.SWINGING:
			continue
		_progress[i] += delta / _durations[i]
		if _progress[i] >= 1.0 - TIME_EPSILON:
			_progress[i] = 0.0
			_states[i] = LegState.PLANTED
			foot_planted.emit(i)

	# 2 + 3 + 5. Who wants to step (the start kick counts), who is blocked, who hovers.
	for i in _count:
		_wants[i] = 0
		_blocked[i] = 0
		if _states[i] == LegState.SWINGING:
			_blocked_time[i] = 0.0
			continue
		var valid: bool = targets_valid[i]
		var wants: bool = foot_errors[i] > trigger_ratio * _reaches[i]
		if kick and _groups[i] == _active_group:
			wants = true
		if _states[i] == LegState.HOVERING and valid:
			# A hovering foot is mid-air: it always swings on to a valid target.
			wants = true
		if wants:
			_wants[i] = 1
		if wants and not valid:
			_blocked[i] = 1
			_blocked_time[i] += delta
			if (
				_states[i] == LegState.PLANTED
				and _blocked_time[i] >= hover_delay - TIME_EPSILON
				and airborne_count() < _gait_limit
			):
				_states[i] = LegState.HOVERING
		else:
			_blocked_time[i] = 0.0

	# 4. Turn.
	if not _group_holds_turn(targets_valid):
		_active_group = (_active_group + 1) % _group_count

	# 6. Lift, largest error first, only into free airborne slots (hovering legs need none).
	while true:
		var best: int = -1
		for i in _count:
			if _groups[i] != _active_group or _wants[i] == 0 or not targets_valid[i]:
				continue
			if _states[i] == LegState.PLANTED and airborne_count() >= _gait_limit:
				continue
			if best < 0 or foot_errors[i] > foot_errors[best]:
				best = i
		if best < 0:
			break
		_states[best] = LegState.SWINGING
		_progress[best] = 0.0
		_durations[best] = step_duration(speed_ratio)
		_blocked_time[best] = 0.0
		_wants[best] = 0
		step_started.emit(best)


func leg_count() -> int:
	return _count


func gait_limit() -> int:
	return _gait_limit


func group_count() -> int:
	return _group_count


func group_of(leg: int) -> int:
	return _groups[leg]


func active_group() -> int:
	return _active_group


func state_of(leg: int) -> int:
	return _states[leg]


func swing_progress(leg: int) -> float:
	if _states[leg] != LegState.SWINGING:
		return 0.0
	return _progress[leg]


func is_blocked(leg: int) -> bool:
	return _blocked[leg] != 0


## SWINGING plus HOVERING legs.
func airborne_count() -> int:
	var n: int = 0
	for i in _count:
		if _states[i] != LegState.PLANTED:
			n += 1
	return n


func step_duration(speed_ratio: float) -> float:
	return lerpf(step_time_idle, step_time_top, clampf(speed_ratio, 0.0, 1.0))


func lift_height(reach: float) -> float:
	return lift_ratio * reach


static func swing_point(from: Vector3, to: Vector3, t: float, lift: float) -> Vector3:
	var u: float = clampf(t, 0.0, 1.0)
	return from.lerp(to, smoothstep(0.0, 1.0, u)) + Vector3.UP * lift * sin(PI * u)


static func target_lead(velocity: Vector3, duration: float) -> Vector3:
	return velocity * duration * 0.5


static func is_target_valid(
	rise: float, normal: Vector3, step_up: float, max_slope_deg: float
) -> bool:
	if rise > step_up:
		return false
	if normal.length_squared() < 0.000001:
		return false
	return rad_to_deg(normal.normalized().angle_to(Vector3.UP)) <= max_slope_deg


func _group_holds_turn(targets_valid: Array[bool]) -> bool:
	for i in _count:
		if _groups[i] != _active_group:
			continue
		if _states[i] == LegState.SWINGING:
			if _progress[i] < handover_progress:
				return true
		elif _states[i] == LegState.PLANTED and _wants[i] != 0 and targets_valid[i]:
			# Wants to lift: either lifts this tick or is held by the airborne limit.
			# HOVERING and blocked legs never hold the turn.
			return true
	return false
