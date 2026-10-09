class_name StatFormat
extends RefCounted
## What the stat panel shows and how numbers read. Values and deltas use two decimals (whole numbers show as
## integers). Deltas carry a sign and, in the panel, a drawn ▲/▼ mark, so a change reads without colour.

## The panel rows in order: stats key, label, unit.
const ROWS: Array[Dictionary] = [
	{"key": "top_speed", "label": "Speed", "unit": "m/s"},
	{"key": "turn_rate", "label": "Turn", "unit": "deg/s"},
	{"key": "step_up", "label": "Step-up", "unit": "m"},
	{"key": "climb", "label": "Climb", "unit": "m"},
	{"key": "max_slope", "label": "Slope", "unit": "deg"},
	{"key": "hp", "label": "HP", "unit": ""},
	{"key": "dps", "label": "DPS", "unit": ""},
	{"key": "spread", "label": "Spread", "unit": "deg"},
	{"key": "load", "label": "Load", "unit": ""},
]
## A change smaller than this is not shown (the displayed numbers have two decimals).
const CHANGE_EPSILON: float = 0.005


static func value_text(value: float) -> String:
	if is_equal_approx(value, roundf(value)):
		return "%d" % roundi(value)
	return "%.2f" % value


static func is_changed(delta: float) -> bool:
	return absf(delta) >= CHANGE_EPSILON


## "+0.58" or "-1.20". Empty when the change is too small to show.
static func delta_text(delta: float) -> String:
	if not is_changed(delta):
		return ""
	var sign_text := "+" if delta > 0.0 else "-"
	return sign_text + value_text(absf(delta))


## 1 up, -1 down, 0 no change.
static func delta_direction(delta: float) -> int:
	if not is_changed(delta):
		return 0
	return 1 if delta > 0.0 else -1


## "325 / 464 kg": the load as mass over lift.
static func load_detail(stats: Dictionary) -> String:
	return "%d / %d kg" % [roundi(float(stats["mass"])), roundi(float(stats["lift"]))]
