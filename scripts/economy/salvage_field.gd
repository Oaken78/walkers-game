class_name SalvageField
extends Node3D
## Puts the economy into the world: one ScrapPickup per ScrapSite (group `scrap_sites`) and the wreck cache where the
## ledger says it lies. Pickups hide when depleted and come back when bank refills their site.
## Usage: add it to the scene, then `setup(economy)` after the valley is built (a second call does nothing).

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


## Spawns a pickup at every scrap site and listens to the ledger. Nodes the ledger already marks depleted start hidden.
func setup(ledger: Economy) -> void:
	if economy != null:
		return
	economy = ledger
	for node: Node in get_tree().get_nodes_in_group("scrap_sites"):
		var site := node as ScrapSite
		if site == null:
			continue
		economy.register_site(String(site.name), site.ring, site.respawns)
		var pickup: ScrapPickup = SCRAP_SCENE.instantiate()
		add_child(pickup)
		pickup.setup(site)
		if economy.is_depleted(pickup.site_name):
			pickup.deplete()
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
		# The old pickup must stop at once: a pull still in flight would reclaim the new cache.
		_cache.retire()
		if _cache.is_inside_tree():
			_cache.queue_free()
		# A cache not yet added is freed by its own deferred _place_cache call.
	_cache = null
	if economy.has_cache():
		var fresh: WreckCache = CACHE_SCENE.instantiate()
		fresh.cache_id = economy.cache_id
		_cache = fresh
		# Deferred: this can run inside a physics callback (a body_entered bank, an area_entered kill).
		_place_cache.call_deferred(fresh, economy.cache_position, economy.cache_amount)


func _place_cache(fresh: WreckCache, at: Vector3, amount: int) -> void:
	if fresh != _cache:
		fresh.free()
		return
	add_child(fresh)
	fresh.global_position = ground_at(at) + Vector3.UP * cache_lift
	fresh.show_amount(amount)
