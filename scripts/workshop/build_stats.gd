class_name BuildStats
extends RefCounted
## Stats the workshop shows: everything WalkerBuild.stats() returns, plus `climb` (GDD 8.1: 0.9 x the reach of the
## shortest mounted leg, 0.9 x reach for a build of one leg type). WalkerBuild has no climb key yet; once it has one,
## that value wins.

const CLIMB_PER_REACH: float = 0.9
## Keys whose before/after difference is worth showing as a delta.
const DELTA_KEYS: Array[String] = [
	"top_speed",
	"turn_rate",
	"step_up",
	"climb",
	"max_slope",
	"hp",
	"dps",
	"spread",
	"load",
	"mass",
	"lift",
	"reach",
	"leg_count",
]


static func of(build: WalkerBuild) -> Dictionary:
	var stats: Dictionary = build.stats()
	if not stats.has("climb"):
		stats["climb"] = CLIMB_PER_REACH * shortest_reach(build)
	return stats


## Reach of the shortest mounted leg (m), 0 with no legs.
static func shortest_reach(build: WalkerBuild) -> float:
	var shortest := INF
	for leg in build.mounted_legs():
		shortest = minf(shortest, float(leg["reach"]))
	return 0.0 if shortest == INF else shortest


## after - before for every key in DELTA_KEYS.
static func delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in DELTA_KEYS:
		result[key] = float(after.get(key, 0.0)) - float(before.get(key, 0.0))
	return result
