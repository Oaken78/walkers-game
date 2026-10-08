class_name PartCatalog
extends RefCounted
## Part catalog: the only place the GDD 8.1 part numbers live. Static functions only.

const CHASSIS_MEDIUM := &"chassis_medium"
const LEG_SHORT := &"leg_short"
const LEG_MEDIUM := &"leg_medium"
const LEG_LONG := &"leg_long"
const PULSE_CANNON := &"pulse_cannon"
const ARMOR_PLATE := &"armor_plate"

const KIND_CHASSIS := &"chassis"
const KIND_LEG := &"leg"
const KIND_TOP := &"top"

const LEG_SOCKETS_PER_SIDE := 4
const TOP_SOCKETS := 3

const PARTS := {
	&"chassis_medium":
	{
		"display_name": "Medium chassis",
		"socket": &"chassis",
		"mass": 125.0,
		"lift": 0.0,
		"reach": 0.0,
		"slope_grip": 0.0,
		"spread_factor": 0.0,
		"hp": 100.0,
		"fire_rate": 0.0,
		"damage": 0.0,
		"projectile_speed": 0.0,
		"price": 0,
		"units_per_purchase": 1,
		"for_sale": false,
	},
	&"leg_short":
	{
		"display_name": "Short leg",
		"socket": &"leg",
		"mass": 35.0,
		"lift": 110.0,
		"reach": 0.6,
		"slope_grip": 45.0,
		"spread_factor": 0.5,
		"hp": 0.0,
		"fire_rate": 0.0,
		"damage": 0.0,
		"projectile_speed": 0.0,
		"price": 40,
		"units_per_purchase": 2,
		"for_sale": true,
	},
	&"leg_medium":
	{
		"display_name": "Medium leg",
		"socket": &"leg",
		"mass": 25.0,
		"lift": 75.0,
		"reach": 1.0,
		"slope_grip": 35.0,
		"spread_factor": 1.0,
		"hp": 0.0,
		"fire_rate": 0.0,
		"damage": 0.0,
		"projectile_speed": 0.0,
		"price": 0,
		"units_per_purchase": 2,
		"for_sale": false,
	},
	&"leg_long":
	{
		"display_name": "Long leg",
		"socket": &"leg",
		"mass": 20.0,
		"lift": 85.0,
		"reach": 1.6,
		"slope_grip": 30.0,
		"spread_factor": 1.5,
		"hp": 0.0,
		"fire_rate": 0.0,
		"damage": 0.0,
		"projectile_speed": 0.0,
		"price": 70,
		"units_per_purchase": 2,
		"for_sale": true,
	},
	&"pulse_cannon":
	{
		"display_name": "Pulse cannon",
		"socket": &"top",
		"mass": 40.0,
		"lift": 0.0,
		"reach": 0.0,
		"slope_grip": 0.0,
		"spread_factor": 0.0,
		"hp": 0.0,
		"fire_rate": 4.0,
		"damage": 15.0,
		"projectile_speed": 60.0,
		"price": 80,
		"units_per_purchase": 1,
		"for_sale": true,
	},
	&"armor_plate":
	{
		"display_name": "Armor plate",
		"socket": &"top",
		"mass": 50.0,
		"lift": 0.0,
		"reach": 0.0,
		"slope_grip": 0.0,
		"spread_factor": 0.0,
		"hp": 40.0,
		"fire_rate": 0.0,
		"damage": 0.0,
		"projectile_speed": 0.0,
		"price": 50,
		"units_per_purchase": 1,
		"for_sale": true,
	},
}


static func has_part(id: StringName) -> bool:
	return PARTS.has(id)


static func get_part(id: StringName) -> Dictionary:
	if not PARTS.has(id):
		return {}
	return (PARTS[id] as Dictionary).duplicate()


static func part_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in PARTS:
		ids.append(id)
	return ids


static func socket_kind(part_id: StringName) -> StringName:
	if not PARTS.has(part_id):
		return &""
	return PARTS[part_id]["socket"]


## Sockets of a chassis. Rows are an order (0 = front), not positions.
static func chassis_sockets(chassis_id: StringName) -> Array[Dictionary]:
	var sockets: Array[Dictionary] = []
	if socket_kind(chassis_id) != KIND_CHASSIS:
		return sockets
	for row in LEG_SOCKETS_PER_SIDE:
		sockets.append({"id": StringName("leg_l%d" % row), "kind": KIND_LEG, "side": -1, "row": row})
	for row in LEG_SOCKETS_PER_SIDE:
		sockets.append({"id": StringName("leg_r%d" % row), "kind": KIND_LEG, "side": 1, "row": row})
	for row in TOP_SOCKETS:
		sockets.append({"id": StringName("top_%d" % row), "kind": KIND_TOP, "side": 0, "row": row})
	return sockets


static func starting_inventory() -> Dictionary:
	return {CHASSIS_MEDIUM: 1, LEG_MEDIUM: 6, PULSE_CANNON: 1}