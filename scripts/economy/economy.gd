class_name Economy
extends RefCounted
## The salvage ledger (GDD 8.5): carried scrap is the stake, banked scrap is safe, a wreck cache is the second chance.
## Pure data, no nodes. Conservation holds after every call:
## carried_scrap + banked_scrap + cache_amount + spent + lost == total_picked_up.
## Repair on bank is not here: whoever owns the player's Health listens to `banked`.

## Carried scrap moved to the bank (also emitted for 0, so a bank with nothing carried still repairs and refills).
signal banked(amount: int)
## Any number changed.
signal changed
## A wreck cache appeared, moved or disappeared (reclaimed or destroyed).
signal cache_changed
## Depleted nodes that bank just refilled (names of the sites).
signal nodes_refilled(names: PackedStringArray)
## Death or recall, emitted first (before the cache changes) so collectors can drop their pulls in flight.
signal dropped(position: Vector3)

var carried_scrap: int = 0
var banked_scrap: int = 0
## Scrap given up for purchases.
var spent: int = 0
## Scrap destroyed with an older wreck cache.
var lost: int = 0
## Everything ever added by pick_up and collect_loose.
var total_picked_up: int = 0
## Wreck cache: 0 means none.
var cache_amount: int = 0
var cache_position: Vector3 = Vector3.ZERO
## Counts the caches ever made; the current cache is the one with this id.
var cache_id: int = 0
## Depleted scrap node names (site name -> true).
var depleted: Dictionary = {}

## Site name -> true for nodes that never refill (ring 0, or a site with respawns off).
var _never_refill: Dictionary = {}


## Tells the ledger whether a site refills on bank. A site that is never registered refills.
func register_site(node_name: String, ring: int, respawns: bool) -> void:
	if ring < 1 or not respawns:
		_never_refill[node_name] = true
	else:
		_never_refill.erase(node_name)


## Takes a scrap node. False (and nothing added) when the node is already depleted or the amount is not positive.
## An empty node name is loose scrap (drone drops), which is never depleted.
func pick_up(node_name: String, amount: int) -> bool:
	if amount <= 0:
		return false
	if node_name != "":
		if depleted.has(node_name):
			return false
		depleted[node_name] = true
	carried_scrap += amount
	total_picked_up += amount
	changed.emit()
	return true


## Loose scrap with no node (drone drops).
func collect_loose(amount: int) -> bool:
	return pick_up("", amount)


func is_depleted(node_name: String) -> bool:
	return depleted.has(node_name)


func has_cache() -> bool:
	return cache_amount > 0


## Moves carried to banked and refills the depleted nodes whose site respawns (never ring 0). Returns the amount banked.
func bank() -> int:
	var amount: int = carried_scrap
	banked_scrap += amount
	carried_scrap = 0
	var refilled := PackedStringArray()
	for node_name: String in depleted.keys():
		if not _never_refill.has(node_name):
			refilled.append(node_name)
	for node_name: String in refilled:
		depleted.erase(node_name)
	changed.emit()
	banked.emit(amount)
	if not refilled.is_empty():
		nodes_refilled.emit(refilled)
	return amount


## Death: carried scrap becomes the wreck cache at `position`; an older cache is destroyed (counted in `lost`).
func die(position: Vector3) -> void:
	dropped.emit(position)
	var had_cache: bool = cache_amount > 0
	lost += cache_amount
	cache_amount = carried_scrap
	carried_scrap = 0
	cache_position = position
	if cache_amount > 0:
		cache_id += 1
	changed.emit()
	if had_cache or cache_amount > 0:
		cache_changed.emit()


## Recall to the workshop: for scrap the same as dying.
func recall(position: Vector3) -> void:
	die(position)


## Takes the wreck cache back, once. Returns the amount (0 when there is none). With `expected_id` (a pickup's own
## cache id) a stale cache cannot take a newer one.
func reclaim(expected_id: int = -1) -> int:
	var amount: int = cache_amount
	if amount <= 0:
		return 0
	if expected_id >= 0 and expected_id != cache_id:
		return 0
	carried_scrap += amount
	cache_amount = 0
	changed.emit()
	cache_changed.emit()
	return amount


## Purchases come out of the bank.
func can_afford(price: int) -> bool:
	return price >= 0 and banked_scrap >= price


func spend(price: int) -> bool:
	if not can_afford(price):
		return false
	banked_scrap -= price
	spent += price
	changed.emit()
	return true


func is_conserved() -> bool:
	return carried_scrap + banked_scrap + cache_amount + spent + lost == total_picked_up
