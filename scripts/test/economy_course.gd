class_name EconomyCourse
extends Node3D
## Test course for the salvage economy (T08): the REAL valley (read-only) with a pickup at every ScrapSite, a Scout, an
## OrbitCamera at the workshop, and the helpers the economy_loop scenario calls. Wires the pieces the way T12 will:
## Collector on the walker, RecallHold on `interact`, death and recall teleport to the workshop.

const WALKER_SPEED_SCOUT: float = 4.5
const FIRST_PURCHASE_PRICE: int = 40

## Walk helper: stop this close to the target (m).
@export var walk_stop_distance: float = 0.4
## Ticks to wait after the last pickup arrived before the tour moves on.
@export var tour_settle_ticks: int = 6
## Drop height of a teleported walker above the floor (m); it settles by itself.
@export var spawn_height: float = 1.0

var economy: Economy = Economy.new()
var collector: Collector = null
var recall_hold: RecallHold = null

## Ticks between the last claim and its arrival (0.3 s is 18 ticks).
var last_magnet_ticks: int = -1
var recalls_fired: int = 0
var taps_seen: int = 0
var tour_done: bool = true
var physics_ticks: int = 0

var _tick: int = 0
var _claim_tick: int = 0
var _walk_target: Vector3 = Vector3.ZERO
var _walking: bool = false
var _tour: Array[String] = []
var _tour_index: int = 0
var _tour_wait: int = 0

@onready var _valley: Valley = $Valley
@onready var _walker: WalkerBody = %Walker
@onready var _orbit: OrbitCamera = $OrbitCamera
@onready var _field: SalvageField = $SalvageField

## Ledger numbers the scenario asserts on.
var carried: int:
	get:
		return economy.carried_scrap
var banked: int:
	get:
		return economy.banked_scrap
var cache: int:
	get:
		return economy.cache_amount
var lost: int:
	get:
		return economy.lost
var picked_total: int:
	get:
		return economy.total_picked_up
var conserved: bool:
	get:
		return economy.is_conserved()
## Wreck cache nodes alive in the scene (0 or 1).
var cache_nodes: int:
	get:
		return 1 if _field.cache() != null else 0
var site_count: int:
	get:
		return _field.pickups().size()
## Pickups mid-flight, and pickups doing per-tick work at all (idle ones must not).
var flying_count: int:
	get:
		var n: int = 0
		for p: ScrapPickup in _field.pickups():
			if p.is_flying():
				n += 1
		return n
var processing_pickups: int:
	get:
		var n: int = 0
		for p: ScrapPickup in _field.pickups():
			if p.is_physics_processing():
				n += 1
		return n
var ring0_visible: int:
	get:
		return ring_visible(0)
var ring1_visible: int:
	get:
		return ring_visible(1)
var ring2_visible: int:
	get:
		return ring_visible(2)
var collector_p99_usec: int:
	get:
		return collector.tick_p99_usec()
var collector_ticks_recorded: int:
	get:
		return collector.tick_usec.size()


func _ready() -> void:
	process_physics_priority = 50
	_orbit.capture_mouse = false
	collector = Collector.new()
	collector.name = "Collector"
	collector.target = _walker
	collector.economy = economy
	collector.record_timing = true
	collector.claimed.connect(_on_claimed)
	add_child(collector)
	recall_hold = RecallHold.new()
	recall_hold.name = "RecallHold"
	recall_hold.target = _walker
	recall_hold.recall_requested.connect(_on_recall_requested)
	recall_hold.tapped.connect(_on_tapped)
	add_child(recall_hold)
	_field.setup(economy)
	respawn()


func _physics_process(_delta: float) -> void:
	_tick += 1
	physics_ticks = _tick
	if _walking:
		_update_walk()
	if not tour_done:
		_update_tour()


# --- Scenario helpers ------------------------------------------------------------------------------------------


## "scout", "strider" or "crawler".
func use_build(build_name: String) -> void:
	match build_name:
		"scout":
			_walker.apply_build(WalkerBuild.scout())
		"strider":
			_walker.apply_build(WalkerBuild.strider())
		"crawler":
			_walker.apply_build(WalkerBuild.crawler())
		_:
			push_error("EconomyCourse.use_build: unknown build %s" % build_name)


## Places the walker `distance` m south (+z) of a site, facing it (bearing_deg turns the approach around the site).
func teleport_to_site(site_name: String, distance: float, bearing_deg: float = 0.0) -> void:
	var site: Vector3 = _site_position(site_name)
	var dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, deg_to_rad(bearing_deg))
	_place_walker(site + dir * distance, -dir)


## Faces the site and holds move_forward until the walker is at it.
func walk_toward_site(site_name: String) -> void:
	_walk_target = _site_position(site_name)
	var to: Vector3 = _walk_target - _walker.global_position
	to.y = 0.0
	_place_walker(_walker.global_position, to.normalized())
	_walking = true
	Input.action_press(&"move_forward")


func stop_walking() -> void:
	_walking = false
	Input.action_release(&"move_forward")


## Walks the walker onto every site up to `max_ring` (pockets only when asked), nearest to the workshop first,
## waiting for each pickup to arrive. `tour_done` turns true at the end.
func start_tour(max_ring: int, include_pockets: bool) -> void:
	var entries: Array = []
	var home: Vector3 = _workshop_position()
	for p: ScrapPickup in _field.pickups():
		if p.depleted or p.ring > max_ring or (p.in_pocket and not include_pockets):
			continue
		entries.append([p.global_position.distance_to(home), p.site_name])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	_tour.clear()
	for entry: Array in entries:
		_tour.append(entry[1])
	_tour_index = 0
	_tour_wait = 0
	tour_done = _tour.is_empty()


## Death: cache at the spot, respawn at the workshop. Mirrors the T12 flow.
func die_here() -> void:
	economy.die(_walker.global_position)
	respawn()


func recall_here() -> void:
	economy.recall(_walker.global_position)
	respawn()


func respawn() -> void:
	stop_walking()
	_place_walker(_workshop_position() + Vector3(0.0, 0.0, 3.0), Vector3(0.0, 0.0, -1.0))


func bank_now() -> int:
	return economy.bank()


## Puts the walker `distance` m from the wreck cache (inside 2.5 m it is reclaimed).
func teleport_to_cache(distance: float) -> void:
	_place_walker(economy.cache_position + Vector3(0.0, 0.0, distance), Vector3(0.0, 0.0, -1.0))


## Horizontal distance from the chassis to a site, as the collector measures it.
func distance_to_site(site_name: String) -> float:
	var d: Vector3 = _site_position(site_name) - collector.global_position
	return Vector2(d.x, d.z).length()


## Scrap nodes of a ring that are visible (not depleted), and all nodes of that ring.
func ring_visible(ring: int) -> int:
	var n: int = 0
	for p: ScrapPickup in _field.pickups():
		if p.ring == ring and not p.depleted:
			n += 1
	return n


func ring_nodes(ring: int) -> int:
	var n: int = 0
	for p: ScrapPickup in _field.pickups():
		if p.ring == ring:
			n += 1
	return n


func hold_action(action: String, pressed: bool) -> void:
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


## Orbit camera behind the walker (the shots use it): pitch deg, distance m, yaw offset deg.
func use_orbit_camera(pitch_deg: float = 20.0, distance: float = 8.0, yaw_offset_deg: float = 0.0) -> void:
	_orbit.camera().make_current()
	_orbit.distance = distance
	_orbit.recenter_enabled = false
	var yaw: float = OrbitMath.behind_yaw(-_walker.global_basis.z) + yaw_offset_deg
	_orbit.set_angles(yaw, pitch_deg)
	_walker.reset_physics_interpolation()
	_orbit.snap()


## Pocket node shot: the walker on the apron below the pocket, facing it.
func teleport_below_pocket(site_name: String, distance: float) -> void:
	var site: Vector3 = _site_position(site_name)
	var toward := Vector3(1.0, 0.0, 0.0) if site.x > 0.0 else Vector3(-1.0, 0.0, 0.0)
	var wall_x: float = ValleyLayout.WALL_RIGHT_X if site.x > 0.0 else ValleyLayout.WALL_LEFT_X
	_place_walker(Vector3(wall_x - toward.x * distance, 0.0, site.z), toward)


## Prints the valley numbers the packet asks for (work item 7). Not a gate.
func report_valley_numbers() -> void:
	var by_ring: Dictionary = {}
	var pocket_total: int = 0
	var s01: Array[ScrapPickup] = []
	var total01: int = 0
	var ring1_total: int = 0
	for p: ScrapPickup in _field.pickups():
		if p.in_pocket:
			pocket_total += p.amount
			continue
		by_ring[p.ring] = int(by_ring.get(p.ring, 0)) + p.amount
		if p.ring <= 1:
			s01.append(p)
			total01 += p.amount
			if p.ring == 1:
				ring1_total += p.amount
	for p: ScrapPickup in _field.pickups():
		print("ECON_NUMBERS site %s ring %d amount %d at (%.1f, %.1f, %.1f)" % [p.site_name, p.ring, p.amount, p.global_position.x, p.global_position.y, p.global_position.z])
	print("ECON_NUMBERS scrap per ring (no pockets): %s, pockets: %d" % [str(by_ring), pocket_total])
	# Greedy nearest-neighbour walk over the ring 0-1 nodes, starting at the workshop.
	var pos: Vector3 = _workshop_position()
	var pending: Array[ScrapPickup] = s01.duplicate()
	while not pending.is_empty():
		var best: ScrapPickup = pending[0]
		for p: ScrapPickup in pending:
			if _flat(p.global_position - pos) < _flat(best.global_position - pos):
				best = p
		var d: float = _flat(best.global_position - pos)
		print("ECON_NUMBERS leg to %s ring %d: %.1f m, %.1f s" % [best.site_name, best.ring, d, d / WALKER_SPEED_SCOUT])
		pos = best.global_position
		pending.erase(best)
	var pair_times: Array = []
	for i in range(s01.size()):
		for j in range(i + 1, s01.size()):
			var t: float = _flat(s01[i].global_position - s01[j].global_position) / WALKER_SPEED_SCOUT
			pair_times.append("%s-%s %.1f" % [s01[i].site_name, s01[j].site_name, t])
	print("ECON_NUMBERS ring 0-1 pair walking times (s): %s" % str(pair_times))
	var expeditions: int = 1
	var banked_so_far: int = total01
	while banked_so_far < FIRST_PURCHASE_PRICE:
		banked_so_far += ring1_total
		expeditions += 1
	print("ECON_NUMBERS ring 0-1 total %d, ring 1 refills %d per trip, first %d-scrap purchase after expedition %d" % [total01, ring1_total, FIRST_PURCHASE_PRICE, expeditions])


# --- Internals -------------------------------------------------------------------------------------------------


func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


func _workshop_position() -> Vector3:
	return (_valley.get_node("WorkshopSite") as Marker3D).global_position


func _site_position(site_name: String) -> Vector3:
	var p: ScrapPickup = _field.pickup_for(site_name)
	return p.global_position if p != null else Vector3.ZERO


func _place_walker(at: Vector3, forward: Vector3) -> void:
	var yaw: float = atan2(-forward.x, -forward.z)
	var y: float = _valley.floor_height(at.x, at.z) + spawn_height
	_walker.teleport(Transform3D(Basis(Vector3.UP, yaw), Vector3(at.x, y, at.z)))


func _update_walk() -> void:
	var to: Vector3 = _walk_target - _walker.global_position
	if _flat(to) <= walk_stop_distance:
		stop_walking()


func _update_tour() -> void:
	if flying_count > 0:
		_tour_wait = 0
		return
	_tour_wait += 1
	if _tour_wait < tour_settle_ticks:
		return
	if _tour_index >= _tour.size():
		tour_done = true
		return
	var site_name: String = _tour[_tour_index]
	_tour_index += 1
	_tour_wait = 0
	_place_walker(_site_position(site_name) + Vector3(0.0, 0.0, 0.5), Vector3(0.0, 0.0, -1.0))


func _on_claimed(pickup: Pickup) -> void:
	_claim_tick = _tick
	if not pickup.arrived.is_connected(_on_arrived):
		pickup.arrived.connect(_on_arrived)


func _on_arrived(_pickup: Pickup) -> void:
	last_magnet_ticks = _tick - _claim_tick


func _on_tapped() -> void:
	taps_seen += 1


func _on_recall_requested(position: Vector3) -> void:
	recalls_fired += 1
	economy.recall(position)
	respawn()
