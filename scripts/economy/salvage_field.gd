class_name SalvageField
extends Node3D
## Puts the economy into the world: one ScrapPickup per ScrapSite (group `scrap_sites`) and the wreck cache where the
## ledger says it lies. Pickups hide when depleted and come back when bank refills their site.
## Usage: add it to the scene, then `setup(economy)` after the valley is built.

const SCRAP_SCENE: PackedScene = preload("res://scenes/pickups/scrap_pickup.tscn")
const CACHE_SCENE: PackedScene = preload("res://scenes/pickups/wreck_cache.tscn")

## How far above the cache position the ground search starts and how far down it reaches (m).
@export var ground_probe_up: float = 3.0
@export var ground_probe_down: float = 12.0
## The cache rests this far above the ground (m).
@export var cache_lift: float = 0.05

var economy: Economy = null

var _pickups: Dictionary = {}
var _cache: WreckCache = null


## Spawns a pickup at every scrap site and listens to the ledger.
func setup(ledger: Economy) -> void:
	economy = ledger
	for node: Node in get_tree().get_nodes_in_group("scrap_sites"):
		var site := node as ScrapSite
		if site == null:
			continue
		economy.register_site(String(site.name), site.ring, site.respawns)
		var pickup: ScrapPickup = SCRAP_SCENE.instantiate()
		add_child(pickup)
		pickup.setup(site)
		_pickups[String(site.name)] = pickup
	economy.nodes_refilled.connect(_on_nodes_refilled)
	economy.cache_changed.connect(_on_cache_changed)
	_on_cache_changed()


func pickup_for(site_name: String) -> ScrapPickup:
	return _pickups.get(site_name)


func pickups() -> Array:
	return _pickups.values()


## The live wreck cache pickup, or null.
func cache() -> WreckCache:
	if is_instance_valid(_cache) and not _cache.is_queued_for_deletion():
		return _cache
	return null


func ground_at(position: Vector3) -> Vector3:
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		position + Vector3.UP * ground_probe_up, position + Vector3.DOWN * ground_probe_down, 1
	)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return position
	return hit["position"]


func _on_nodes_refilled(names: PackedStringArray) -> void:
	for node_name: String in names:
		var pickup: ScrapPickup = _pickups.get(node_name)
		if pickup != null:
			pickup.restore()


func _on_cache_changed() -> void:
	if _cache != null and is_instance_valid(_cache):
		_cache.monitorable = false
		_cache.visible = false
		_cache.queue_free()
	_cache = null
	if economy.has_cache():
		_cache = CACHE_SCENE.instantiate()
		add_child(_cache)
		_cache.global_position = ground_at(economy.cache_position) + Vector3.UP * cache_lift
		_cache.show_amount(economy.cache_amount)
