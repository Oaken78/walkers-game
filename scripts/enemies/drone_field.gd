class_name DroneField
extends Node3D
## The drones of the whole map, the API T12 calls (GDD 8.4, 9.1):
##   field.target = walker                 the walker the drones hunt (its `Chassis` is the aim point)
##   field.spawn_sites()                   one DroneEncounter per DroneSite in group `drone_sites`, min to max drones each
##   field.respawn_all()                   on Economy.banked: every group back at its site, full health, bolts cleared
##   field.drone_died(position)            one signal per death, with the place it died
## At most 4 drones are active at once (engaged: alert, orbiting or holding to shoot); a fifth stays at home until a
## slot frees. The field owns the bolt pool (`bolts`); the bolts damage whatever hurtbox is on layer 2.

signal drone_died(position: Vector3)

const MAX_ACTIVE: int = 4
const SITES_GROUP: StringName = &"drone_sites"
const SEED_STEP: int = 1000

@export var seed_value: int = 1
@export var bolt_cap: int = 8

## The walker the drones hunt. Setting it hands it to every drone.
var target: Node3D = null:
	set(value):
		target = value
		for encounter in encounters:
			encounter.set_target(value)
var bolts: DroneBoltPool
var encounters: Array[DroneEncounter] = []
## Drones that ever died, for scenarios.
var deaths: int = 0

var _engaged: Dictionary = {}


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	bolts = DroneBoltPool.new()
	bolts.name = "Bolts"
	bolts.cap = bolt_cap
	add_child(bolts)


## One encounter at every DroneSite marker in the tree. Returns how many drones there are afterwards.
func spawn_sites() -> int:
	for node: Node in get_tree().get_nodes_in_group(SITES_GROUP):
		var site := node as DroneSite
		if site != null:
			add_encounter(site.global_position, site.min_drones, site.max_drones)
	return drone_count()


## An encounter at `anchor` (a ground point) with min to max drones, populated at once.
func add_encounter(anchor: Vector3, min_drones: int, max_drones: int) -> DroneEncounter:
	var encounter := DroneEncounter.new()
	encounter.name = "Encounter%d" % encounters.size()
	encounter.anchor = anchor
	encounter.min_drones = min_drones
	encounter.max_drones = max_drones
	encounter.seed_value = seed_value + SEED_STEP * encounters.size()
	encounter.field = self
	encounter.target = target
	encounter.bolts = bolts
	encounter.drone_died.connect(_on_drone_died)
	add_child(encounter)
	encounter.populate()
	encounters.append(encounter)
	return encounter


## Every group back at its site with full health; bolts in flight are removed.
func respawn_all() -> void:
	_engaged.clear()
	bolts.clear()
	for encounter in encounters:
		encounter.respawn()


## Removes every encounter, drone, scrap drop and bolt (a new game, a test).
func clear_all() -> void:
	_engaged.clear()
	bolts.clear()
	for encounter in encounters:
		# A husk still falling must not think, fire or step in the frame before the free (DroneEncounter.clear does it).
		encounter.clear()
		encounter.queue_free()
	encounters.clear()


## True when `drone` may be (or already is) one of the active drones.
func can_engage(drone: Object) -> bool:
	return _engaged.has(drone) or active_count() < MAX_ACTIVE


func set_engaged(drone: Object, engaged: bool) -> void:
	if engaged:
		_engaged[drone] = true
	else:
		_engaged.erase(drone)


func active_count() -> int:
	for drone: Object in _engaged.keys():
		if not is_instance_valid(drone):
			_engaged.erase(drone)
	return _engaged.size()


## Drones in the field, dead husks that have not yet been removed included.
func drone_count() -> int:
	var count: int = 0
	for encounter in encounters:
		for drone in encounter.drones:
			if is_instance_valid(drone):
				count += 1
	return count


func alive_count() -> int:
	var count: int = 0
	for encounter in encounters:
		count += encounter.alive_count()
	return count


func _on_drone_died(position: Vector3) -> void:
	deaths += 1
	drone_died.emit(position)
