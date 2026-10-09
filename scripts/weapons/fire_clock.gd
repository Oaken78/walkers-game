class_name FireClock
extends RefCounted
## When each mounted weapon fires (GDD 8.3): every weapon keeps its own rate, and the phases are spread evenly,
## weapon k of n firing k / (n x rate) s after the first. Two cannons at 4 shots/s fire every 0.125 s, which on a
## 60 Hz tick is a gap of 7 ticks then 8. Pure: time comes in as seconds, indices go out.
## A press latches a volley: every weapon gets one shot armed, and each fires on its phase even if the trigger is
## released before its turn, so a click fires every mounted weapon. Only the shots after that need the trigger held.

## Slack for float error in the accumulated tick time.
const EPSILON: float = 0.000001

var rate: float = 4.0
var count: int = 1

var _next_ready: PackedFloat64Array = PackedFloat64Array()
var _armed: PackedByteArray = PackedByteArray()
var _held: bool = false


func _init(weapon_count: int = 1, shots_per_s: float = 4.0) -> void:
	count = maxi(weapon_count, 0)
	rate = maxf(shots_per_s, 0.001)
	_next_ready.resize(count)
	_armed.resize(count)


func period() -> float:
	return 1.0 / rate


## Seconds between two weapons' phases.
func phase_gap() -> float:
	return 1.0 / (float(maxi(count, 1)) * rate)


## The cooldown and the trigger of the clock this one replaces (a rebuild with the trigger held must not skip the
## cooldown). The phases are laid out again from the latest moment any old weapon is ready, so two cannons stay a
## half period apart.
func carry_over(previous: FireClock) -> void:
	if previous.count == 0:
		return
	var base: float = -INF
	for j in previous.count:
		base = maxf(base, previous._next_ready[j] - float(j) * previous.phase_gap())
	for k in count:
		_next_ready[k] = base + float(k) * phase_gap()
		_armed[k] = previous._armed[k] if k < previous.count else 0
	_held = previous._held


## Drops every armed shot (input off, cannons unmounted): a volley armed before is not fired when the trigger returns.
func disarm() -> void:
	for k in count:
		_armed[k] = 0


## One tick. `now` is the tick's time in seconds, `held` the trigger. Returns the weapons that fire this tick.
func update(now: float, held: bool) -> PackedInt32Array:
	var fired := PackedInt32Array()
	if held and not _held:
		# A new press: the phases restart from the first moment every weapon is ready, so tapping the trigger
		# never beats a weapon's own cooldown. A shot already armed by an earlier press keeps its time.
		var base: float = now
		for k in count:
			base = maxf(base, _next_ready[k] - float(k) * phase_gap())
		for k in count:
			if _armed[k] == 0:
				_next_ready[k] = base + float(k) * phase_gap()
				_armed[k] = 1
	_held = held
	for k in count:
		if _armed[k] == 1 and now - _next_ready[k] > period():
			# Stale: nobody asked for this shot for longer than a whole period.
			_armed[k] = 0
		if _armed[k] == 0 and not held:
			continue
		if now + EPSILON < _next_ready[k]:
			continue
		fired.append(k)
		_armed[k] = 0
		var next: float = _next_ready[k]
		# After a long stall, do not fire a catch-up burst.
		if now - next > period():
			next = now
		_next_ready[k] = next + period()
	return fired
