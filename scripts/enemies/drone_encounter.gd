class_name DroneEncounter
extends Node3D
## The drones of one site (GDD 8.4, 9.1): it rolls how many (min to max) from a seeded generator, spawns them around the
## site, keeps their wind-up starts >= 0.4 s apart so their holds rarely overlap and the walker swings between them,
## and forwards their deaths. A drone asks `can_wind_up(now)` every tick and calls `note_wind_up(now)` when it starts.
## `respawn()` frees everything left of the group and rolls a fresh group (the field calls it on bank).

signal drone_died(position: Vector3)

const DRONE_SCENE: PackedScene = preload("res://scenes/enemies/drone.tscn")
## Wind-up starts of drones in one encounter are at least this far apart.
const STAGGER_S: float = 0.4
const TIMER_EPSILON: float = 0.000001
## Several drones of a site hover on a circle of this radius around it.
const SPREAD_RADIUS_M: float = 2.5
const GROUND_PROBE_UP_M: float = 30.0
const GROUND_PROBE_DOWN_M: float = 200.0

@export var min_drones: int = 1
@export var max_drones: int = 2
@export var seed_value: int = 1

## The site's ground point.
var anchor: Vector3 = Vector3.ZERO
var field: DroneField = null
var target: Node3D = null
var bolts: DroneBoltPool = null
var drones: Array[Drone] = []
## Time of the last wind-up start in this encounter (seconds of physics time).
var last_wind_up_s: float = -INF

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seeded: bool = false


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY


## Physics time in seconds, the same for every drone in a tick.
static func now_s() -> float:
	return float(Engine.get_physics_frames()) / float(Engine.physics_ticks_per_second)


## True when a drone may start its wind-up at `now` without crowding the previous start.
func can_wind_up(now: float) -> bool:
	return now - last_wind_up_s >= STAGGER_S - TIMER_EPSILON


func note_wind_up(now: float) -> void:
	last_wind_up_s = now


## Rolls the count and spawns the group (call respawn() to start over).
func populate() -> void:
	if not _seeded:
		_seeded = true
		_rng.seed = seed_value
	var count: int = _rng.randi_range(mini(min_drones, max_drones), maxi(min_drones, max_drones))
	var phase: float = _rng.randf() * TAU
	for i in count:
		var drone: Drone = DRONE_SCENE.instantiate()
		drone.configure(_rng.randi())
		drone.target = target
		drone.bolts = bolts
		drone.encounter = self
		drone.field = field
		drone.drop_parent = self
		drone.died.connect(_on_drone_died)
		add_child(drone)
		var spot: Vector3 = anchor
		if count > 1:
			var angle: float = phase + TAU * float(i) / float(count)
			spot += Vector3(cos(angle), 0.0, sin(angle)) * SPREAD_RADIUS_M
		drone.place(_ground_at(spot))
		drones.append(drone)


## Frees the group (dead husks too) and rolls a new one: full health, back at the site.
func respawn() -> void:
	clear()
	populate()


func clear() -> void:
	for drone in drones:
		if is_instance_valid(drone):
			if field != null:
				field.set_engaged(drone, false)
			# queue_free() takes effect at the end of the frame: until then the old drone must not think, fire or step.
			drone.ai_enabled = false
			drone.auto_step = false
			drone.queue_free()
	drones.clear()
	last_wind_up_s = -INF


## Drones still alive.
func alive_count() -> int:
	var count: int = 0
	for drone in drones:
		if is_instance_valid(drone) and not drone.is_dead():
			count += 1
	return count


## Hands a new walker to every drone.
func set_target(walker: Node3D) -> void:
	target = walker
	for drone in drones:
		if is_instance_valid(drone):
			drone.target = walker


func _ground_at(spot: Vector3) -> Vector3:
	var query := PhysicsRayQueryParameters3D.create(
		spot + Vector3.UP * GROUND_PROBE_UP_M, spot + Vector3.DOWN * GROUND_PROBE_DOWN_M, CombatLayers.WORLD
	)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return spot
	return hit["position"]


func _on_drone_died(_drone: Drone, position: Vector3) -> void:
	drone_died.emit(position)
