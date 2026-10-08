class_name WalkerBuild
extends RefCounted
## A walker build as pure data: which part sits in which socket. Every stat is computed from the
## part list on each call (GDD 8.1), nothing is cached. Per-leg data keeps no pair assumption.

const SPEED_BASE := 4.5
const SPEED_LOAD_OFFSET := 1.7
const GAIT_FACTOR_4_LEGS := 0.85
const GAIT_FACTOR_DEFAULT := 1.0
const SPEED_MIN := 2.5
const SPEED_MAX := 7.0
const TURN_BASE := 250.0
const TURN_LOAD_FACTOR := 100.0
const TURN_PER_LEG := 10.0
const TURN_MIN := 60.0
const TURN_MAX := 180.0
const STEP_UP_PER_REACH := 0.6
const SPREAD_DEG_PER_FACTOR := 1.0
const FOUR_LEGS := 4
const VALID_LEG_COUNTS: Array[int] = [4, 6, 8]

var chassis_id: StringName

var _parts: Dictionary = {}  # socket id -> part id
var _sockets: Dictionary = {}  # socket id -> socket row dictionary


func _init(chassis: StringName = PartCatalog.CHASSIS_MEDIUM) -> void:
	chassis_id = chassis
	for socket in PartCatalog.chassis_sockets(chassis):
		_sockets[socket["id"]] = socket


static func scout() -> WalkerBuild:
	return _fixture(PartCatalog.LEG_MEDIUM, 3, [PartCatalog.PULSE_CANNON])


static func strider() -> WalkerBuild:
	return _fixture(PartCatalog.LEG_LONG, 3, [PartCatalog.PULSE_CANNON])


static func crawler() -> WalkerBuild:
	return _fixture(
		PartCatalog.LEG_SHORT,
		4,
		[PartCatalog.PULSE_CANNON, PartCatalog.PULSE_CANNON, PartCatalog.ARMOR_PLATE]
	)


static func _fixture(leg: StringName, legs_per_side: int, tops: Array) -> WalkerBuild:
	var build := WalkerBuild.new()
	for row in legs_per_side:
		build.place(StringName("leg_l%d" % row), leg)
		build.place(StringName("leg_r%d" % row), leg)
	for i in tops.size():
		build.place(StringName("top_%d" % i), tops[i])
	return build


func copy() -> WalkerBuild:
	var other := WalkerBuild.new(chassis_id)
	other._parts = _parts.duplicate()
	return other


func can_place(socket_id: StringName, part_id: StringName) -> bool:
	if not _sockets.has(socket_id) or not PartCatalog.has_part(part_id):
		return false
	if PartCatalog.socket_kind(part_id) != _sockets[socket_id]["kind"]:
		return false
	return not _parts.has(socket_id)


func place(socket_id: StringName, part_id: StringName) -> bool:
	if not can_place(socket_id, part_id):
		return false
	_parts[socket_id] = part_id
	return true


func remove(socket_id: StringName) -> StringName:
	if not _parts.has(socket_id):
		return &""
	var removed: StringName = _parts[socket_id]
	_parts.erase(socket_id)
	return removed


func part_at(socket_id: StringName) -> StringName:
	return _parts.get(socket_id, &"")


func parts() -> Dictionary:
	return _parts.duplicate()


func leg_count() -> int:
	return mounted_legs().size()


## One entry per mounted leg: left side front to back, then right side front to back.
func mounted_legs() -> Array[Dictionary]:
	var legs: Array[Dictionary] = []
	for side in [-1, 1]:
		var letter := "l" if side < 0 else "r"
		for row in PartCatalog.LEG_SOCKETS_PER_SIDE:
			var socket_id := StringName("leg_%s%d" % [letter, row])
			if not _parts.has(socket_id):
				continue
			var part_id: StringName = _parts[socket_id]
			var data := PartCatalog.get_part(part_id)
			var leg := {
				"socket": socket_id,
				"part": part_id,
				"side": side,
				"row": row,
				"mass": data["mass"],
				"lift": data["lift"],
				"reach": data["reach"],
				"slope_grip": data["slope_grip"],
				"spread_factor": data["spread_factor"],
			}
			legs.append(leg)
	return legs


func stats() -> Dictionary:
	var chassis := PartCatalog.get_part(chassis_id)
	var mass: float = chassis.get("mass", 0.0)
	var hp: float = chassis.get("hp", 0.0)
	var dps := 0.0
	for part_id: StringName in _parts.values():
		var data := PartCatalog.get_part(part_id)
		mass += data["mass"]
		hp += data["hp"]
		dps += data["fire_rate"] * data["damage"]
	var legs := mounted_legs()
	var count := legs.size()
	var lift := 0.0
	var reach_sum := 0.0
	var spread_sum := 0.0
	var slope := INF
	for leg in legs:
		lift += leg["lift"]
		reach_sum += leg["reach"]
		spread_sum += leg["spread_factor"]
		slope = minf(slope, leg["slope_grip"])
	var result := {
		"mass": mass,
		"lift": lift,
		"load": 0.0,
		"reach": 0.0,
		"top_speed": 0.0,
		"turn_rate": 0.0,
		"step_up": 0.0,
		"max_slope": 0.0,
		"spread": 0.0,
		"hp": hp,
		"dps": dps,
		"leg_count": count,
	}
	if count == 0 or lift <= 0.0:
		return result
	var load_ratio := mass / lift
	var reach := reach_sum / count
	var gait := GAIT_FACTOR_4_LEGS if count == FOUR_LEGS else GAIT_FACTOR_DEFAULT
	result["load"] = load_ratio
	result["reach"] = reach
	result["top_speed"] = clampf(
		SPEED_BASE * sqrt(reach) * gait * (SPEED_LOAD_OFFSET - load_ratio), SPEED_MIN, SPEED_MAX
	)
	result["turn_rate"] = clampf(
		TURN_BASE - TURN_LOAD_FACTOR * load_ratio - TURN_PER_LEG * count, TURN_MIN, TURN_MAX
	)
	result["step_up"] = STEP_UP_PER_REACH * reach
	result["max_slope"] = slope
	result["spread"] = SPREAD_DEG_PER_FACTOR * spread_sum / count
	return result


func is_valid() -> bool:
	return invalid_reason() == ""


func invalid_reason() -> String:
	var left := 0
	var right := 0
	for leg in mounted_legs():
		if leg["side"] < 0:
			left += 1
		else:
			right += 1
	if not VALID_LEG_COUNTS.has(left + right):
		return "Needs 4, 6 or 8 legs"
	if left != right:
		return "Legs unbalanced"
	var s := stats()
	if s["mass"] > s["lift"]:
		return "Overloaded: %d/%d kg" % [roundi(s["mass"]), roundi(s["lift"])]
	return ""