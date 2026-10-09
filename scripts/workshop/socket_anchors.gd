class_name SocketAnchors
extends RefCounted
## Where each chassis socket is in the world, read from outside the walker (its Chassis mesh, its Legs and Tops
## nodes and its public layout exports).
##
## A mounted part is anchored where it really is (the hip of its leg, the piece on top). A free socket is anchored at
## a fixed slot on the chassis: legs at the middle of the chassis flank, tops on the top face. The walker spaces the
## legs of a side evenly by how many are mounted and has no slot of its own for an empty socket, so a free slot cannot
## be where the leg will end up; the fixed slots keep every socket at its own place, and they sit at a different height
## from the hips, so a free slot and a mounted hip never share a spot. The walker API wish list has real socket slots.
## Each entry: {"pos": Vector3, "normal": Vector3 (outward), "kind": StringName, "mounted": bool}.

const FALLBACK_REACH: float = 1.0
## Height of the mark above the chassis top for a top socket (m).
const TOP_LIFT: float = 0.1
## Free leg slots sit at this fraction of the chassis height.
const FLANK_HEIGHT_FRACTION: float = 0.5


## `armed_part` (may be empty) sets the reach the free leg slots are spaced for: a longer leg spreads the hips.
static func compute(
	walker: WalkerBody, build: WalkerBuild, armed_part: StringName = &""
) -> Dictionary:
	var anchors: Dictionary = {}
	var pose: Transform3D = walker.body_pose()
	var chassis := walker.get_node("Chassis") as MeshInstance3D
	var box := chassis.mesh as BoxMesh
	var size: Vector3 = box.size if box != null else Vector3(1.2, 0.3, 2.3)
	# WalkerBody draws the chassis 2 x lateral - 0.15 wide.
	var lateral: float = (size.x + 0.15) * 0.5
	var spacing: float = _slot_spacing(walker, build, armed_part)
	var rows: PackedFloat32Array = WalkerBody.hip_z_positions(
		PartCatalog.LEG_SOCKETS_PER_SIDE, spacing
	)
	var hips: Dictionary = _mounted_hips(walker, build, pose)
	for socket in PartCatalog.chassis_sockets(build.chassis_id):
		var id: StringName = socket["id"]
		var entry: Dictionary = {"kind": socket["kind"], "mounted": build.part_at(id) != &""}
		var row: int = socket["row"]
		if socket["kind"] == PartCatalog.KIND_LEG:
			var side: int = socket["side"]
			entry["normal"] = (pose.basis * Vector3(float(side), 0.0, 0.0)).normalized()
			if hips.has(id):
				entry["pos"] = hips[id]
			else:
				var local := Vector3(
					float(side) * lateral, size.y * FLANK_HEIGHT_FRACTION, rows[row]
				)
				entry["pos"] = pose * local
		else:
			entry["normal"] = pose.basis.y.normalized()
			var slot := _top_slot(row, size)
			entry["pos"] = pose * Vector3(slot.x, size.y + TOP_LIFT, slot.y)
		anchors[id] = entry
	_anchor_mounted_tops(walker, build, anchors)
	return anchors


## Spacing of the four leg slots (m): the walker's hip spacing for the mean reach of the build with the armed leg
## pair added, the way it would space a full side.
static func _slot_spacing(walker: WalkerBody, build: WalkerBuild, armed_part: StringName) -> float:
	var stats: Dictionary = build.stats()
	var count: int = int(stats["leg_count"])
	var mean_reach: float = float(stats["reach"]) if count > 0 else FALLBACK_REACH
	var reach := mean_reach
	if PartCatalog.socket_kind(armed_part) == PartCatalog.KIND_LEG:
		var armed_reach: float = PartCatalog.PARTS[armed_part]["reach"]
		reach = (mean_reach * float(count) + 2.0 * armed_reach) / float(count + 2)
	return walker.hip_spacing_base + walker.hip_spacing_per_reach * reach


## Hips of the mounted legs by socket: build.mounted_legs() and the Legs children are in the same order.
static func _mounted_hips(walker: WalkerBody, build: WalkerBuild, pose: Transform3D) -> Dictionary:
	var hips: Dictionary = {}
	var legs_root: Node = walker.get_node("Legs")
	var mounted: Array[Dictionary] = build.mounted_legs()
	for i in mounted.size():
		if i >= legs_root.get_child_count():
			break
		var leg := legs_root.get_child(i) as WalkerLeg
		if leg != null:
			hips[mounted[i]["socket"]] = pose * leg.hip_local
	return hips


## (x, z) of a top slot in the body frame: the three-tops layout of WalkerBody (two side by side in front, one behind).
static func _top_slot(row: int, size: Vector3) -> Vector2:
	if row == 0:
		return Vector2(-size.x * 0.25, -size.z * 0.1)
	if row == 1:
		return Vector2(size.x * 0.25, -size.z * 0.1)
	return Vector2(0.0, size.z * 0.25)


## A mounted top part is drawn by WalkerBody at an index among the present tops (top_0, top_1, top_2 in order).
static func _anchor_mounted_tops(
	walker: WalkerBody, build: WalkerBuild, anchors: Dictionary
) -> void:
	var tops: Node = walker.get_node("Tops")
	var index := 0
	for socket_id: StringName in [&"top_0", &"top_1", &"top_2"]:
		if build.part_at(socket_id) == &"":
			continue
		if index < tops.get_child_count():
			var piece := tops.get_child(index) as Node3D
			if piece != null:
				anchors[socket_id]["pos"] = piece.global_position
		index += 1
