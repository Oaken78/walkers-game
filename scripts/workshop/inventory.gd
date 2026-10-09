class_name Inventory
extends RefCounted
## The parts the player owns (GDD 8.1 starting inventory, 8.6). Pure data, no nodes.
##
## Counts are owned parts in total, mounted ones included. A part is spare when it is owned and not on the build,
## so mounting and unmounting never create or lose a part: they only move it between "spare" and "mounted", and
## the build is the one place that says which. Buying is the only way the owned count grows.
## Legs go in mirrored pairs (GDD 8.1, M0): they are bought as a pair, mounted as a pair and taken off as a pair.

## Owned counts changed (a purchase).
signal changed

## part id -> owned count (mounted + spare).
var _owned: Dictionary = {}


func _init(start: Dictionary = PartCatalog.starting_inventory()) -> void:
	_owned = start.duplicate()


## "leg_l2" <-> "leg_r2". Empty for a top socket or anything else.
static func mirror_of(socket_id: StringName) -> StringName:
	var text := String(socket_id)
	if text.begins_with("leg_l"):
		return StringName("leg_r" + text.substr(5))
	if text.begins_with("leg_r"):
		return StringName("leg_l" + text.substr(5))
	return &""


static func mounted_count(build: WalkerBuild, part_id: StringName) -> int:
	var count := 0
	for mounted_part: StringName in build.parts().values():
		if mounted_part == part_id:
			count += 1
	return count


func owned(part_id: StringName) -> int:
	return _owned.get(part_id, 0)


func owned_counts() -> Dictionary:
	return _owned.duplicate()


## Owned and not on the build.
func spare(build: WalkerBuild, part_id: StringName) -> int:
	return owned(part_id) - mounted_count(build, part_id)


## False when the build carries more of a part than is owned (a bug in whoever edited the build directly).
func is_consistent(build: WalkerBuild) -> bool:
	var seen: Dictionary = build.parts()
	for part_id: StringName in seen.values():
		if spare(build, part_id) < 0:
			return false
	return true


# --- Buying ------------------------------------------------------------------------------------------------------


## "" when `part_id` can be bought now, else why not ("Not for sale", "Need 12 more").
func buy_blocker(part_id: StringName, economy: Economy) -> String:
	if not PartCatalog.has_part(part_id) or not PartCatalog.PARTS[part_id]["for_sale"]:
		return "Not for sale"
	var price: int = PartCatalog.PARTS[part_id]["price"]
	if not economy.can_afford(price):
		return "Need %d more" % (price - economy.banked_scrap)
	return ""


## Buys one purchase unit (a leg pair for the pair price, a top part singly) out of the bank.
func buy(part_id: StringName, economy: Economy) -> bool:
	if buy_blocker(part_id, economy) != "":
		return false
	var data: Dictionary = PartCatalog.PARTS[part_id]
	if not economy.spend(data["price"]):
		return false
	_owned[part_id] = owned(part_id) + int(data["units_per_purchase"])
	changed.emit()
	return true


# --- Mounting ----------------------------------------------------------------------------------------------------


## "" when `part_id` can go on `socket_id` (with its mirror for a leg), else why not.
func mount_reason(build: WalkerBuild, socket_id: StringName, part_id: StringName) -> String:
	if not PartCatalog.has_part(part_id):
		return "Unknown part"
	var kind := PartCatalog.socket_kind(part_id)
	if kind != PartCatalog.KIND_LEG and kind != PartCatalog.KIND_TOP:
		return "Not a part you can mount"
	var socket_kind := _socket_kind(build, socket_id)
	if socket_kind == &"":
		return "No such socket"
	var part_name: String = PartCatalog.PARTS[part_id]["display_name"]
	if socket_kind != kind:
		return "%s goes on a %s socket" % [part_name, kind]
	if build.part_at(socket_id) != &"":
		return "Socket is taken"
	if kind == PartCatalog.KIND_LEG:
		var mirror := mirror_of(socket_id)
		if mirror == &"" or not build.can_place(mirror, part_id):
			return "Mirror socket is taken"
	return spare_reason(build, part_id)


## "" when enough of `part_id` is spare to mount one (a leg pair for a leg), else why not.
func spare_reason(build: WalkerBuild, part_id: StringName) -> String:
	var part_name: String = PartCatalog.PARTS[part_id]["display_name"]
	var need := 2 if PartCatalog.socket_kind(part_id) == PartCatalog.KIND_LEG else 1
	var have := spare(build, part_id)
	if have >= need:
		return ""
	if need == 2 and have == 1:
		return "Legs go in pairs: 1 spare"
	return "No spare %s: buy one" % part_name.to_lower()


func can_mount(build: WalkerBuild, socket_id: StringName, part_id: StringName) -> bool:
	return mount_reason(build, socket_id, part_id) == ""


## Puts the part on the socket (a leg also on the mirror socket). False, and nothing changes, when it cannot.
func mount(build: WalkerBuild, socket_id: StringName, part_id: StringName) -> bool:
	if not can_mount(build, socket_id, part_id):
		return false
	build.place(socket_id, part_id)
	if PartCatalog.socket_kind(part_id) == PartCatalog.KIND_LEG:
		build.place(mirror_of(socket_id), part_id)
	return true


## "" when there is a part to take off `socket_id`, else why not.
func unmount_reason(build: WalkerBuild, socket_id: StringName) -> String:
	if _socket_kind(build, socket_id) == &"":
		return "No such socket"
	if build.part_at(socket_id) == &"":
		return "Nothing mounted here"
	return ""


## Takes the part off (a leg also takes its mirror off). The parts stay owned, so they are spare again.
func unmount(build: WalkerBuild, socket_id: StringName) -> bool:
	if unmount_reason(build, socket_id) != "":
		return false
	build.remove(socket_id)
	var mirror := mirror_of(socket_id)
	if mirror != &"":
		build.remove(mirror)
	return true


## What a place (`part_id` set) or a remove (`part_id` empty) would do, with the build untouched. Keys:
## ok, reason, before, after, delta (BuildStats.DELTA_KEYS), valid_after, invalid_reason_after.
func preview(build: WalkerBuild, socket_id: StringName, part_id: StringName = &"") -> Dictionary:
	var before := BuildStats.of(build)
	var scratch := build.copy()
	var reason := ""
	var ok := false
	if part_id == &"":
		reason = unmount_reason(scratch, socket_id)
		ok = reason == "" and unmount(scratch, socket_id)
	else:
		reason = mount_reason(scratch, socket_id, part_id)
		ok = reason == "" and mount(scratch, socket_id, part_id)
	var after := BuildStats.of(scratch)
	return {
		"ok": ok,
		"reason": reason,
		"before": before,
		"after": after,
		"delta": BuildStats.delta(before, after),
		"valid_after": scratch.is_valid(),
		"invalid_reason_after": scratch.invalid_reason(),
	}


## The chassis table knows every socket id; WalkerBuild keeps it private, so ask the catalog.
func _socket_kind(build: WalkerBuild, socket_id: StringName) -> StringName:
	for socket in PartCatalog.chassis_sockets(build.chassis_id):
		if socket["id"] == socket_id:
			return socket["kind"]
	return &""
