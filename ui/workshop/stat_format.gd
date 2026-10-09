class_name StatFormat
extends RefCounted
## What the stat panel shows and how numbers read (GDD 12).
## Each stat has a fixed number of decimals (whole degrees for turn and slope, HP and DPS whole, the rest two), and
## its delta uses the same decimals. A delta carries its sign and a drawn up/down mark, and it says better or worse:
## HIGHER_IS_BETTER is the polarity table (higher is better for speed, turn, step-up, climb, slope, HP and DPS; lower
## is better for spread and load). The mark is filled in the accent for better and hollow in grey for worse.

## The panel rows in order: stats key, label, unit, decimals.
const ROWS: Array[Dictionary] = [
	{"key": "top_speed", "label": "Speed", "unit": "m/s", "decimals": 2},
	{"key": "turn_rate", "label": "Turn", "unit": "deg/s", "decimals": 0},
	{"key": "step_up", "label": "Step-up", "unit": "m", "decimals": 2},
	{"key": "climb", "label": "Climb", "unit": "m", "decimals": 2},
	{"key": "max_slope", "label": "Slope", "unit": "deg", "decimals": 0},
	{"key": "hp", "label": "HP", "unit": "", "decimals": 0},
	{"key": "dps", "label": "DPS", "unit": "", "decimals": 0},
	{"key": "spread", "label": "Spread", "unit": "deg", "decimals": 2},
	{"key": "load", "label": "Load", "unit": "", "decimals": 2},
]
## Polarity per stat: true when a higher number is better.
const HIGHER_IS_BETTER: Dictionary = {
	"top_speed": true,
	"turn_rate": true,
	"step_up": true,
	"climb": true,
	"max_slope": true,
	"hp": true,
	"dps": true,
	"spread": false,
	"load": false,
}
## Load above this is overloaded: the Load row shows a "!".
const OVERLOAD_RATIO: float = 1.0


static func decimals_of(key: String) -> int:
	for entry in ROWS:
		if entry["key"] == key:
			return entry["decimals"]
	return 2


## The value as the panel shows it: its stat's decimals, nothing else.
static func value_text(key: String, value: float) -> String:
	return "%.*f" % [decimals_of(key), value]


## The value rounded the way the panel rounds it, as a number.
static func shown_number(key: String, value: float) -> float:
	return snappedf(value, pow(10.0, -float(decimals_of(key))))


## A change is shown when it still reads as a change at the stat's decimals.
static func is_changed(key: String, delta: float) -> bool:
	return absf(shown_number(key, delta)) > 0.0


## "+0.58" or "-7": the sign and the stat's decimals. Empty when the change rounds to nothing.
static func delta_text(key: String, delta: float) -> String:
	if not is_changed(key, delta):
		return ""
	var sign_text := "+" if delta > 0.0 else "-"
	return sign_text + value_text(key, absf(delta))


## 1 up, -1 down, 0 no change.
static func delta_direction(key: String, delta: float) -> int:
	if not is_changed(key, delta):
		return 0
	return 1 if delta > 0.0 else -1


## True when `delta` of `key` is a better change (by the polarity table).
static func is_better(key: String, delta: float) -> bool:
	var higher: bool = HIGHER_IS_BETTER.get(key, true)
	return (delta > 0.0) == higher


## 1 better, -1 worse, 0 no shown change.
static func delta_quality(key: String, delta: float) -> int:
	if not is_changed(key, delta):
		return 0
	return 1 if is_better(key, delta) else -1


## "325 / 464 kg": the load as mass over lift.
static func load_detail(stats: Dictionary) -> String:
	return "%d / %d kg" % [roundi(float(stats["mass"])), roundi(float(stats["lift"]))]


static func is_overloaded(stats: Dictionary) -> bool:
	return float(stats["load"]) > OVERLOAD_RATIO
