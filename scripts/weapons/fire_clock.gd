class_name FireClock
extends RefCounted
## When each mounted weapon fires (GDD 8.3): every weapon keeps its own rate, and the phases are spread evenly,
## weapon k of n firing k / (n x rate) s after the first. Two cannons at 4 shots/s fire every 0.125 s, which on a
## 60 Hz tick is a gap of 7 ticks then 8. Pure: time comes in as seconds, indices go out.

## Slack for float error in the accumulated tick time.
const EPSILON: float = 0.000001

var rate: float = 4.0
var count: int = 1

var _next_ready: PackedFloat64Array = PackedFloat64Array()
var _held: bool = false


func _init(weapon_count: int = 1, shots_per_s: float = 4.0) -> void:
	count = maxi(weapon_count, 0)
	rate = maxf(shots_per_s, 0.001)
	_next_ready.resize(count)


func period() -> float:
	return 1.0 / rate


## Seconds between two weapons' phases.
func phase_gap() -> float:
	return 1.0 / (float(maxi(count, 1)) * rate)


## One tick. `now` is the tick's time in seconds, `held` the trigger. Returns the weapons that fire this tick.
func update(now: float, held: bool) -> PackedInt32Array:
	var fired := PackedInt32Array()
	if held and not _held:
		# A new press: the phases restart from the first moment every weapon is ready, so tapping the trigger
		# never beats a weapon's own cooldown.
		var base: float = now
		for k in count:
			base = maxf(base, _next_ready[k] - float(k) * phase_gap())
		for k in count:
			_next_ready[k] = base + float(k) * phase_gap()
	_held = held
	if not held:
		return fired
	for k in count:
		if now + EPSILON < _next_ready[k]:
			continue
		fired.append(k)
		var next: float = _next_ready[k]
		# After a long stall, do not fire a catch-up burst.
		if now - next > period():
			next = now
		_next_ready[k] = next + period()
	return fired
