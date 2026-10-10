class_name ViewProbe
extends Node
## Test probe (T17): measures how evenly the view moves per RENDERED frame at a chosen render rate.
## Our tools render at a fixed 60 fps, so the probe fakes other rates with Engine.time_scale (game time per
## frame = 1 / rate); uneven pacing alternates short and long frames with the same average rate.
## Per part it records the step from the previous rendered frame; read the stats with part_stats().
## It samples at the end of each frame's _process (the Tail node, priority 1000), after the camera has moved: the state that is drawn.

## Parts measured, in report order.
const PARTS: Array[String] = ["cam_pos", "cam_yaw", "cam_pitch", "arm", "root", "chassis", "foot", "root_in_cam", "walker_yaw", "root_raw"]

## Render rate to fake (Hz); 0 = leave the time scale alone.
@export var rate_hz: float = 0.0
## 0 = even frames; 0.5 = alternate frames of 0.5x and 1.5x the mean frame time.
@export var unevenness: float = 0.0
## Steady mouse turn (px per second of game time), injected before the camera runs, every rendered frame.
@export var mouse_px_per_s: float = 0.0
## The fixed render rate of the tools (--fixed-fps 60).
@export var base_fps: float = 60.0

var _orbit: OrbitCamera
var _walker: WalkerBody
var _recording: bool = false
var _skip: int = 0
var _flip: bool = false
var random_pacing: bool = false
var _rng := RandomNumberGenerator.new()
var _ticks_in_frame: int = 0
var _tick_counts: PackedInt32Array = PackedInt32Array()
var _fractions: PackedFloat64Array = PackedFloat64Array()
var _prev: Dictionary = {}
var _steps: Dictionary = {}
var _dts: PackedFloat64Array = PackedFloat64Array()
var _frame_dt: float = 0.0
var _t0_usec: int = 0
var _wall_log: PackedFloat64Array = PackedFloat64Array()
var _wall_last_usec: int = 0
const WALL_LOG_FRAMES: int = 900
var _proc_ms: PackedFloat64Array = PackedFloat64Array()
var _tick_ms: PackedFloat64Array = PackedFloat64Array()

## Read-only results for assert_prop.
var cam_dev: float:
	get:
		return part_stats("cam_pos")["dev"]
var yaw_dev: float:
	get:
		return part_stats("cam_yaw")["dev"]
var arm_step_max: float:
	get:
		return part_stats("arm")["max"]
var root_dev: float:
	get:
		return part_stats("root")["dev"]
var chassis_dev: float:
	get:
		return part_stats("chassis")["dev"]
var foot_dev: float:
	get:
		return part_stats("foot")["dev"]
var cam_speed_cv: float:
	get:
		return part_stats("cam_pos")["cv_speed"]
var yaw_speed_cv: float:
	get:
		return part_stats("cam_yaw")["cv_speed"]
var root_raw_dev: float:
	get:
		return part_stats("root_raw")["dev"]


func _ready() -> void:
	# Mouse look arrives before the camera's _process.
	process_priority = -100
	_rng.seed = 1234


func _find() -> void:
	if _orbit != null:
		return
	_orbit = get_parent().find_child("OrbitCamera", true, false)
	_walker = get_parent().find_child("Walker", true, false)


## Fakes a render rate. `uneven` as in `unevenness`.
func set_rate(hz: float, uneven: float = 0.0, random: bool = false) -> void:
	rate_hz = hz
	unevenness = uneven
	random_pacing = random
	_flip = false
	_apply_scale()


## Pauses or resumes the tree (tests that the F-keys work while paused).
func set_paused(paused: bool) -> void:
	get_tree().paused = paused


func set_mouse(px_per_s: float) -> void:
	mouse_px_per_s = px_per_s


## Emulates a display at rate_hz on the fixed 60 fps tools: one rendered frame lasts k / rate_hz of GAME time
## (time_scale = 60 k / rate_hz) and every physics tick lasts 1/60 s of game time, so a frame runs
## 60 k / rate_hz ticks on average (0.42 at 144 Hz). That needs physics_ticks_per_second = 3600 k / rate_hz
## (the tick accumulator runs in real time, which is fixed at 1/60 s per frame). k is 1 for even pacing; uneven
## pacing changes k every frame, which also moves the tick phase.
func _apply_scale() -> void:
	if rate_hz <= 0.0:
		Engine.time_scale = 1.0
		Engine.physics_ticks_per_second = 60
		return
	var k: float = 1.0 + (unevenness if _flip else -unevenness)
	if random_pacing:
		k = 1.0 + _rng.randf_range(-unevenness, unevenness)
	Engine.time_scale = base_fps / rate_hz * k
	Engine.physics_ticks_per_second = maxi(1, roundi(60.0 * base_fps / rate_hz * k))


func _physics_process(_delta: float) -> void:
	_ticks_in_frame += 1

func _process(delta: float) -> void:
	_find()
	_t0_usec = Time.get_ticks_usec()
	if _wall_log.size() < WALL_LOG_FRAMES:
		if _wall_last_usec > 0:
			_wall_log.append(float(_t0_usec - _wall_last_usec) / 1000.0)
		_wall_last_usec = _t0_usec
	_frame_dt = delta
	if mouse_px_per_s != 0.0:
		var ev := InputEventMouseMotion.new()
		ev.relative = Vector2(mouse_px_per_s * delta, 0.0)
		ev.screen_relative = ev.relative
		_orbit.orbit_event(ev)
	# The length of the NEXT frame.
	_flip = not _flip
	_apply_scale()


## Called by the tail node after all other _process work: script time of this frame (the camera is in it), and the
## walker's last physics tick time.
func mark_process_end() -> void:
	_sample()
	if not _recording or _skip >= 0:
		return
	_proc_ms.append(float(Time.get_ticks_usec() - _t0_usec) / 1000.0)
	_tick_ms.append(float(_walker.tick_usec) / 1000.0)


func _sample() -> void:
	if _recording and _skip <= 0:
		_tick_counts.append(_ticks_in_frame)
		_fractions.append(Engine.get_physics_interpolation_fraction())
	_ticks_in_frame = 0
	if not _recording or _orbit == null:
		return
	# use_build replaces the legs: look the parts up every sample.
	var cam: Camera3D = _orbit.camera()
	var cur: Dictionary = {
		"cam_pos": cam.global_position,
		"cam_yaw": _orbit.yaw_deg,
		"cam_pitch": _orbit.shown_pitch_deg,
		"arm": _orbit.arm_length,
		"root": _walker.get_global_transform_interpolated().origin,
		"chassis": _walker.drawn_chassis_position(),
		"foot": _walker.drawn_foot_position(0),
	}
	cur["root_raw"] = _walker.global_position
	cur["walker_yaw"] = OrbitMath.behind_yaw(-_walker.global_basis.z)
	cur["root_in_cam"] = cam.global_transform.affine_inverse() * (cur["root"] as Vector3)
	if not _prev.is_empty() and _skip <= 0 and _frame_dt > 0.0:
		for part: String in PARTS:
			var a: Variant = _prev[part]
			var b: Variant = cur[part]
			var step: float
			if a is Vector3:
				step = (b as Vector3).distance_to(a as Vector3)
			elif part == "cam_yaw" or part == "walker_yaw":
				step = rad_to_deg(absf(angle_difference(deg_to_rad(a), deg_to_rad(b))))
			else:
				step = absf(float(b) - float(a))
			var list: PackedFloat64Array = _steps[part]
			list.append(step)
			_steps[part] = list
		_dts.append(_frame_dt)
	_skip -= 1
	_prev = cur


## Clears and starts recording; the first `skip` frames are ignored.
func begin(skip: int = 10) -> void:
	_steps.clear()
	for part: String in PARTS:
		_steps[part] = PackedFloat64Array()
	_dts.clear()
	_tick_counts.clear()
	_fractions.clear()
	_proc_ms.clear()
	_tick_ms.clear()
	_prev = {}
	_skip = skip
	_recording = true


func end() -> void:
	_recording = false


## Stats of one part over the recorded frames. cv = std/mean of the step; max_ratio = largest step / mean;
## dev = largest |step - mean| / mean (the "varies by at most x % from its mean" measure);
## cv_speed uses step / frame time (a smooth part keeps a steady speed even when frames are uneven).
func part_stats(part: String) -> Dictionary:
	var out := {"n": 0, "mean": 0.0, "cv": 0.0, "max_ratio": 0.0, "dev": 0.0, "cv_speed": 0.0, "max": 0.0, "jit": 0.0}
	if not _steps.has(part):
		return out
	var steps: PackedFloat64Array = _steps[part]
	var n: int = steps.size()
	out["n"] = n
	if n < 2:
		return out
	var mean: float = 0.0
	var mx: float = 0.0
	var smean: float = 0.0
	for i in n:
		mean += steps[i]
		mx = maxf(mx, steps[i])
		smean += steps[i] / _dts[i]
	mean /= n
	smean /= n
	var var_sum: float = 0.0
	var svar: float = 0.0
	var dev: float = 0.0
	for i in n:
		var_sum += (steps[i] - mean) * (steps[i] - mean)
		dev = maxf(dev, absf(steps[i] - mean))
		var s: float = steps[i] / _dts[i]
		svar += (s - smean) * (s - smean)
	# jit: mean |change of speed| / (sum of neighbouring speeds) over moving frames: 0 = steady, 1 = zero then double steps.
	var jit_sum: float = 0.0
	var jit_n: int = 0
	for i in range(1, n):
		var s0: float = steps[i - 1] / _dts[i - 1]
		var s1: float = steps[i] / _dts[i]
		if s0 + s1 > 0.002:
			jit_sum += absf(s1 - s0) / (s0 + s1)
			jit_n += 1
	out["jit"] = jit_sum / jit_n if jit_n > 0 else 0.0
	out["mean"] = mean
	out["max"] = mx
	if mean > 1e-9:
		out["cv"] = sqrt(var_sum / n) / mean
		out["max_ratio"] = mx / mean
		out["dev"] = dev / mean
	if smean > 1e-9:
		out["cv_speed"] = sqrt(svar / n) / smean
	return out


## One SMOOTH line per part (the scenario log is grepped for these).
func report(label: String) -> void:
	for part: String in PARTS:
		var s: Dictionary = part_stats(part)
		print(
			"SMOOTH %s part=%s n=%d mean=%.5f max=%.5f cv=%.3f max_ratio=%.2f dev=%.3f cv_speed=%.3f jit=%.3f"
			% [label, part, s["n"], s["mean"], s["max"], s["cv"], s["max_ratio"], s["dev"], s["cv_speed"], s["jit"]]
		)


## WORK line: script time per frame (process, camera included) and the walker tick time, in ms.
func report_work(label: String) -> void:
	print("WORK %s proc_p50=%.3f proc_p95=%.3f proc_max=%.3f tick_p50=%.3f tick_p95=%.3f tick_max=%.3f" % [label, _pct(_proc_ms, 0.5), _pct(_proc_ms, 0.95), _pct(_proc_ms, 1.0), _pct(_tick_ms, 0.5), _pct(_tick_ms, 0.95), _pct(_tick_ms, 1.0)])


func _pct(values: PackedFloat64Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	return sorted[mini(int(q * sorted.size()), sorted.size() - 1)]


## Prints the first count recorded steps of a part next to the frame times (debug aid).
func dump(part: String, count: int = 16) -> void:
	var steps: PackedFloat64Array = _steps[part]
	var parts: PackedStringArray = []
	for i in mini(count, steps.size()):
		parts.append("%.4f/%.4f" % [steps[i], _dts[i]])
	print("DUMP ", part, " step/dt: ", " ".join(parts))


## COLD line: wall-clock frame times since this scene loaded (the first frames compile pipelines and shaders).
## Run with --fixed-fps and no vsync, so a frame time is pure work time.
func report_cold(label: String) -> void:
	var sorted: PackedFloat64Array = _wall_log.duplicate()
	sorted.sort()
	var over10: int = 0
	var over33: int = 0
	var first_ms: float = 0.0
	for v in _wall_log:
		over10 += 1 if v > 10.0 else 0
		over33 += 1 if v > 33.0 else 0
	if not _wall_log.is_empty():
		first_ms = _wall_log[0]
	var worst: PackedStringArray = []
	for i in range(_wall_log.size()):
		if _wall_log[i] > 10.0 and worst.size() < 8:
			worst.append("#%d:%.0fms" % [i, _wall_log[i]])
	print("COLD %s n=%d p50=%.2f p95=%.2f max=%.1f over10ms=%d over33ms=%d first=%.1f spikes=%s" % [label, sorted.size(), _pct(sorted, 0.5), _pct(sorted, 0.95), _pct(sorted, 1.0), over10, over33, first_ms, " ".join(worst)])

## TICKS line: physics ticks per rendered frame (mean and share of frames with 0, 1, 2+ ticks) and the interpolation
## fraction seen at the end of each frame (range, and how often it fell from one frame to the next = a tick ran).
## A valid 144 Hz case shows about 0.42 ticks per frame and a fraction that walks through 0..1.
func report_ticks(label: String) -> void:
	var n: int = _tick_counts.size()
	if n == 0:
		return
	var zero: int = 0
	var one: int = 0
	var two: int = 0
	var total: int = 0
	for c in _tick_counts:
		total += c
		zero += 1 if c == 0 else 0
		one += 1 if c == 1 else 0
		two += 1 if c >= 2 else 0
	var fmin: float = 1e9
	var fmax: float = -1e9
	var wraps: int = 0
	for i in range(n):
		fmin = minf(fmin, _fractions[i])
		fmax = maxf(fmax, _fractions[i])
		if i > 0 and _fractions[i] < _fractions[i - 1]:
			wraps += 1
	print(
		"TICKS %s frames=%d ticks_per_frame=%.3f share0=%.2f share1=%.2f share2plus=%.2f frac_min=%.2f frac_max=%.2f wraps=%d"
		% [label, n, float(total) / n, float(zero) / n, float(one) / n, float(two) / n, fmin, fmax, wraps]
	)


## Ticks per frame, as a property for assert_prop.
var ticks_per_frame: float:
	get:
		var total: int = 0
		for c in _tick_counts:
			total += c
		return float(total) / maxi(_tick_counts.size(), 1)
var frac_range: float:
	get:
		var lo: float = 1e9
		var hi: float = -1e9
		for v in _fractions:
			lo = minf(lo, v)
			hi = maxf(hi, v)
		return hi - lo if not _fractions.is_empty() else 0.0
