class_name FrameReadout
extends CanvasLayer
## Frame-time readout (T17), toggled with F9 by the DevHarness autoload. Panel in the top-left corner with:
## screen index, its refresh rate, window mode and vsync mode; fps; frame time (now / p95 / max over the last 2 s);
## script physics time per frame (only `_physics_process` of scripts, summed over the ticks in that frame) and the
## engine's full physics time (Performance.TIME_PHYSICS_PROCESS, refreshed about once a second); the share of
## frames with 0, 1 and 2+ physics ticks; and how many frames took longer than hitch_ms since F9.
## Frame time is wall-clock time between two rendered frames, so a missed vsync shows as a spike.
## The node is created on the first F9 and freed on the second: while it is off it costs nothing and draws nothing.

## Length of the window for p95 and max (s).
@export var window_s: float = 2.0
## How often the text is rebuilt (s); the samples are taken every frame.
@export var refresh_s: float = 0.1
@export var font_size: int = 16
@export var margin_px: float = 8.0
## A frame longer than this counts as a hitch (ms).
@export var hitch_ms: float = 25.0
## Plate behind the text: #14161A at 60 %, so it reads on the pale horizon band too.
@export var plate_color: Color = Color(0.0784, 0.0863, 0.1020, 0.6)
## Shows fixed demo numbers instead of live ones (scenario screenshots).
@export var fixed_sample: bool = false

## Window mode before the last F11, so F11 restores it.
static var _mode_before_fullscreen: int = DisplayServer.WINDOW_MODE_WINDOWED

var hitches: int = 0

var _label: Label
var _last_usec: int = 0
var _since_refresh: float = 1000.0
var _times_s: PackedFloat64Array = PackedFloat64Array()
var _frame_ms: PackedFloat64Array = PackedFloat64Array()
var _phys_ms: PackedFloat64Array = PackedFloat64Array()
var _tick_counts: PackedInt32Array = PackedInt32Array()
var _phys_accum_ms: float = 0.0
var _tick_start_usec: int = 0
var _ticks_this_frame: int = 0


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Process after everything else, so the frame time includes the game's own work.
	process_priority = 1000000
	var plate := PanelContainer.new()
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = plate_color
	style.set_content_margin_all(6.0)
	plate.add_theme_stylebox_override("panel", style)
	plate.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, int(margin_px))
	add_child(plate)
	_label = Label.new()
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", font_size)
	_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 4)
	plate.add_child(_label)
	# Physics tick timers: one node before and one after every other physics callback.
	_marker(-1000000000, _on_tick_begin)
	_marker(1000000000, _on_tick_end)
	_last_usec = Time.get_ticks_usec()
	if fixed_sample:
		_label.text = fixed_text()


func _process(_delta: float) -> void:
	if fixed_sample:
		return
	var now_usec: int = Time.get_ticks_usec()
	var now_s: float = float(now_usec) / 1000000.0
	var frame_ms: float = float(now_usec - _last_usec) / 1000.0
	_times_s.append(now_s)
	_frame_ms.append(frame_ms)
	_phys_ms.append(_phys_accum_ms)
	_tick_counts.append(_ticks_this_frame)
	if frame_ms > hitch_ms and _times_s.size() > 1:
		hitches += 1
	_phys_accum_ms = 0.0
	_ticks_this_frame = 0
	_last_usec = now_usec
	while not _times_s.is_empty() and _times_s[0] < now_s - window_s:
		_times_s.remove_at(0)
		_frame_ms.remove_at(0)
		_phys_ms.remove_at(0)
		_tick_counts.remove_at(0)
	_since_refresh += frame_ms / 1000.0
	if _since_refresh >= refresh_s:
		_since_refresh = 0.0
		_label.text = text_for(
			DisplayServer.screen_get_refresh_rate(DisplayServer.window_get_current_screen()),
			DisplayServer.window_get_vsync_mode(),
			DisplayServer.window_get_current_screen(),
			DisplayServer.window_get_mode(),
			Engine.get_frames_per_second(),
			_frame_ms,
			_phys_ms,
			_tick_counts,
			hitches,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		)


## p95, max and mean of a window of samples.
static func window_stats(values: PackedFloat64Array) -> Dictionary:
	var out := {"p95": 0.0, "max": 0.0, "mean": 0.0, "n": values.size()}
	if values.is_empty():
		return out
	var sorted: PackedFloat64Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for v in sorted:
		total += v
	out["p95"] = sorted[mini(int(0.95 * sorted.size()), sorted.size() - 1)]
	out["max"] = sorted[sorted.size() - 1]
	out["mean"] = total / sorted.size()
	return out


## Share of frames (0..1) with 0, 1 and 2 or more physics ticks.
static func tick_shares(counts: PackedInt32Array) -> Vector3:
	if counts.is_empty():
		return Vector3.ZERO
	var zero: int = 0
	var one: int = 0
	var more: int = 0
	for c in counts:
		if c == 0:
			zero += 1
		elif c == 1:
			one += 1
		else:
			more += 1
	var n: float = float(counts.size())
	return Vector3(zero / n, one / n, more / n)


## The label text. refresh_hz <= 0 means the display did not report a rate. engine_phys_ms is the engine's own
## physics time per frame (all physics work, not only scripts).
static func text_for(
	refresh_hz: float,
	vsync_mode: int,
	screen: int,
	window_mode: int,
	fps: float,
	frame_ms: PackedFloat64Array,
	phys_ms: PackedFloat64Array,
	tick_counts: PackedInt32Array,
	hitch_count: int,
	engine_phys_ms: float
) -> String:
	var frame: Dictionary = window_stats(frame_ms)
	var phys: Dictionary = window_stats(phys_ms)
	var shares: Vector3 = tick_shares(tick_counts)
	var current: float = frame_ms[frame_ms.size() - 1] if not frame_ms.is_empty() else 0.0
	var phys_now: float = phys_ms[phys_ms.size() - 1] if not phys_ms.is_empty() else 0.0
	var hz: String = "%.2f Hz" % refresh_hz if refresh_hz > 0.0 else "? Hz"
	return (
		"screen %d  %s  %s  vsync %s\nfps %.0f\nframe ms  now %.1f  p95 %.1f  max %.1f\nscript physics ms  now %.2f  p95 %.2f  max %.2f\nengine physics ms  %.2f\nticks per frame  0: %.0f%%  1: %.0f%%  2+: %.0f%%\nhitches > 25 ms since F9: %d"
		% [
			screen, hz, window_mode_name(window_mode), vsync_name(vsync_mode), fps,
			current, frame["p95"], frame["max"],
			phys_now, phys["p95"], phys["max"],
			engine_phys_ms,
			shares.x * 100.0, shares.y * 100.0, shares.z * 100.0,
			hitch_count,
		]
	)


## Fixed numbers for scenario screenshots.
static func fixed_text() -> String:
	return text_for(
		144.0,
		DisplayServer.VSYNC_ENABLED,
		0,
		DisplayServer.WINDOW_MODE_WINDOWED,
		144.0,
		PackedFloat64Array([6.9, 6.9, 7.0, 6.9, 7.4]),
		PackedFloat64Array([0.0, 0.3, 0.0, 0.0, 0.3]),
		PackedInt32Array([0, 1, 0, 0, 1]),
		0,
		0.25
	)


static func vsync_name(mode: int) -> String:
	match mode:
		DisplayServer.VSYNC_ENABLED:
			return "enabled"
		DisplayServer.VSYNC_ADAPTIVE:
			return "adaptive"
		DisplayServer.VSYNC_MAILBOX:
			return "mailbox"
	return "disabled"


static func window_mode_name(mode: int) -> String:
	match mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			return "windowed"
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return "minimized"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "maximized"
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "borderless fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "exclusive fullscreen"
	return "mode %d" % mode


## F10: the vsync mode after `mode` in the cycle enabled, adaptive, mailbox, disabled.
static func next_vsync(mode: int) -> int:
	var cycle: Array[int] = [
		DisplayServer.VSYNC_ENABLED,
		DisplayServer.VSYNC_ADAPTIVE,
		DisplayServer.VSYNC_MAILBOX,
		DisplayServer.VSYNC_DISABLED,
	]
	var at: int = cycle.find(mode)
	return cycle[(at + 1) % cycle.size()]


## F11: the window mode to switch to from `current` (exclusive fullscreen, or back to what it was before).
static func fullscreen_target(current: int, previous: int) -> int:
	if current == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		if previous == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return DisplayServer.WINDOW_MODE_WINDOWED
		return previous
	return DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## F11: exclusive fullscreen on the current screen, or back to the window mode it had before.
static func toggle_fullscreen() -> void:
	var current: int = DisplayServer.window_get_mode()
	var target: int = fullscreen_target(current, _mode_before_fullscreen)
	if current != DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
		_mode_before_fullscreen = current
	DisplayServer.window_set_mode(target)


## F10: next vsync mode.
static func cycle_vsync() -> void:
	DisplayServer.window_set_vsync_mode(next_vsync(DisplayServer.window_get_vsync_mode()))


func _marker(priority: int, callback: Callable) -> Node:
	var marker := _TickMarker.new()
	marker.process_physics_priority = priority
	marker.process_mode = Node.PROCESS_MODE_ALWAYS
	marker.ticked.connect(callback)
	add_child(marker)
	return marker


func _on_tick_begin() -> void:
	_tick_start_usec = Time.get_ticks_usec()


func _on_tick_end() -> void:
	_phys_accum_ms += float(Time.get_ticks_usec() - _tick_start_usec) / 1000.0
	_ticks_this_frame += 1


## Emits once per physics tick at the priority it was given.
class _TickMarker:
	extends Node
	signal ticked

	func _physics_process(_delta: float) -> void:
		ticked.emit()