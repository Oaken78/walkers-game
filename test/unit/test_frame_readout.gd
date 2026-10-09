extends GutTest
## FrameReadout (T17): window statistics, text, and the F10 vsync cycle.


func test_window_stats_p95_and_max() -> void:
	var values := PackedFloat64Array()
	for i in range(100):
		values.append(float(i + 1))
	var stats: Dictionary = FrameReadout.window_stats(values)
	assert_eq(stats["max"], 100.0)
	assert_eq(stats["p95"], 96.0)
	assert_almost_eq(float(stats["mean"]), 50.5, 0.001)


func test_window_stats_empty_is_zero() -> void:
	var stats: Dictionary = FrameReadout.window_stats(PackedFloat64Array())
	assert_eq(stats["max"], 0.0)
	assert_eq(stats["n"], 0)


func test_text_shows_display_and_frame_numbers() -> void:
	var frames := PackedFloat64Array([6.9, 6.9, 14.0])
	var phys := PackedFloat64Array([0.0, 0.3, 0.0])
	var text: String = FrameReadout.text_for(
		59.99, DisplayServer.VSYNC_ENABLED, 1, DisplayServer.WINDOW_MODE_WINDOWED, 144.0, frames, phys
	)
	assert_string_contains(text, "screen 1")
	assert_string_contains(text, "59.99 Hz")
	assert_string_contains(text, "vsync enabled")
	assert_string_contains(text, "windowed")
	assert_string_contains(text, "now 14.0")
	assert_string_contains(text, "max 14.0")


func test_vsync_cycle_visits_all_four_modes() -> void:
	var mode: int = DisplayServer.VSYNC_ENABLED
	var seen: Array[int] = []
	for i in range(4):
		seen.append(mode)
		mode = FrameReadout.next_vsync(mode)
	assert_eq(mode, DisplayServer.VSYNC_ENABLED, "back to the start after four presses")
	assert_eq(seen.size(), 4)
	assert_eq(seen.count(DisplayServer.VSYNC_DISABLED), 1)
	assert_eq(seen.count(DisplayServer.VSYNC_MAILBOX), 1)
	assert_eq(seen.count(DisplayServer.VSYNC_ADAPTIVE), 1)