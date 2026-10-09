extends GutTest
## Pickups, Collector and SalvageField without a walker: pulls are driven tick by tick by calling the pickup's
## _physics_process by hand, and claims go through Collector.try_claim (the collector's own scan is off).

const TICK: float = 1.0 / 60.0

var eco: Economy
var field: SalvageField
var collector: Collector


func _setup(site_amounts: Dictionary = {}) -> void:
	eco = Economy.new()
	for site_name: String in site_amounts.keys():
		var site := ScrapSite.new()
		site.name = site_name
		site.amount = site_amounts[site_name]
		site.ring = 1
		add_child_autofree(site)
		site.position = Vector3(5.0, 0.0, 0.0)
	field = SalvageField.new()
	add_child_autofree(field)
	field.setup(eco)
	collector = Collector.new()
	collector.enabled = false
	collector.economy = eco
	add_child_autofree(collector)


func _tick(pickup: Pickup, count: int) -> void:
	for i in range(count):
		pickup._physics_process(TICK)


func test_a_cache_pull_in_flight_cannot_reclaim_the_cache_the_same_death_makes() -> void:
	_setup()
	eco.collect_loose(20)
	eco.die(Vector3(30, 0, 0))
	await wait_frames(2)
	var old: WreckCache = field.cache()
	assert_not_null(old)
	collector.global_position = Vector3(30, 0, 0)
	assert_true(collector.try_claim(old))
	_tick(old, 17)
	eco.collect_loose(10)
	eco.die(Vector3(60, 0, 0))
	_tick(old, 1)
	assert_eq(eco.cache_amount, 10, "the new cache survives the old pull")
	assert_eq(eco.carried_scrap, 0)
	assert_eq(eco.lost, 20)
	assert_true(eco.is_conserved())
	await wait_frames(2)


func test_a_retired_cache_in_flight_delivers_nothing_even_without_a_death() -> void:
	_setup()
	eco.collect_loose(20)
	eco.die(Vector3(30, 0, 0))
	await wait_frames(2)
	var old: WreckCache = field.cache()
	collector.global_position = Vector3(30, 0, 0)
	assert_true(collector.try_claim(old))
	_tick(old, 5)
	old.retire()
	_tick(old, 30)
	assert_eq(eco.cache_amount, 20, "the ledger still holds the cache")
	assert_eq(eco.carried_scrap, 0)


func test_a_stale_cache_id_cannot_reclaim_a_newer_cache() -> void:
	_setup()
	eco.collect_loose(20)
	eco.die(Vector3.ZERO)
	var old_id: int = eco.cache_id
	eco.collect_loose(5)
	eco.die(Vector3.ZERO)
	assert_eq(eco.reclaim(old_id), 0)
	assert_eq(eco.cache_amount, 5)
	assert_eq(eco.reclaim(eco.cache_id), 5)
	await wait_frames(2)


func test_a_pull_in_flight_is_cancelled_by_a_death_and_the_node_stays_collectable() -> void:
	_setup({"S1": 10})
	var pickup: ScrapPickup = field.pickup_for("S1")
	collector.global_position = Vector3(5, 0, 1)
	assert_true(collector.try_claim(pickup))
	_tick(pickup, 5)
	eco.die(Vector3(5, 0, 1))
	assert_false(pickup.is_flying())
	_tick(pickup, 30)
	assert_eq(eco.carried_scrap, 0)
	assert_true(pickup.visible)
	assert_false(pickup.depleted)
	assert_true(pickup.is_collectable())
	assert_eq(pickup.global_position, Vector3(5, 0, 0))


func test_a_pull_with_no_ledger_goes_home_instead_of_losing_the_node() -> void:
	_setup({"S1": 10})
	var pickup: ScrapPickup = field.pickup_for("S1")
	collector.global_position = Vector3(5, 0, 1)
	assert_true(collector.try_claim(pickup))
	collector.economy = null
	_tick(pickup, 30)
	assert_false(pickup.depleted)
	assert_true(pickup.is_collectable())
	assert_eq(eco.total_picked_up, 0)


func test_a_pull_whose_collector_was_freed_goes_home() -> void:
	_setup({"S1": 10})
	var pickup: ScrapPickup = field.pickup_for("S1")
	collector.global_position = Vector3(5, 0, 1)
	assert_true(collector.try_claim(pickup))
	collector.free()
	_tick(pickup, 30)
	assert_false(pickup.depleted)
	assert_true(pickup.is_collectable())
	assert_eq(eco.total_picked_up, 0)


func test_an_arriving_pull_counts_the_node_once() -> void:
	_setup({"S1": 10})
	var pickup: ScrapPickup = field.pickup_for("S1")
	collector.global_position = Vector3(5, 0, 1)
	assert_true(collector.try_claim(pickup))
	assert_false(collector.try_claim(pickup), "a second claim is refused while flying")
	_tick(pickup, 19)
	assert_eq(eco.carried_scrap, 10)
	assert_true(pickup.depleted)
	assert_false(collector.try_claim(pickup))
	assert_eq(eco.carried_scrap, 10)


func test_setup_twice_makes_no_duplicates_and_keeps_depleted_nodes_hidden() -> void:
	eco = Economy.new()
	var site := ScrapSite.new()
	site.name = "S1"
	site.amount = 10
	site.ring = 1
	add_child_autofree(site)
	eco.pick_up("S1", 10)
	field = SalvageField.new()
	add_child_autofree(field)
	field.setup(eco)
	field.setup(eco)
	assert_eq(field.pickups().size(), 1)
	assert_eq(field.get_child_count(), 1)
	assert_true(field.pickup_for("S1").depleted)
	assert_false(field.pickup_for("S1").visible)


func test_bank_brings_a_depleted_node_back() -> void:
	_setup({"S1": 10})
	var pickup: ScrapPickup = field.pickup_for("S1")
	collector.global_position = Vector3(5, 0, 1)
	collector.try_claim(pickup)
	_tick(pickup, 19)
	eco.bank()
	assert_false(pickup.depleted)
	assert_true(pickup.visible)


func test_a_fresh_cache_under_the_collector_is_not_claimable_until_it_has_left() -> void:
	_setup()
	collector.global_position = Vector3.ZERO
	eco.collect_loose(10)
	eco.die(Vector3(1, 0, 0))
	await wait_frames(2)
	var cache: WreckCache = field.cache()
	assert_not_null(cache)
	assert_true(cache.is_inside_tree(), "the cache is added after the deferred call")
	assert_false(collector.try_claim(cache))
	collector.global_position = Vector3(10, 0, 0)
	collector.update_cache_grace()
	collector.global_position = Vector3(1, 0, 0)
	assert_true(collector.try_claim(cache))


func test_the_collector_shape_uses_the_exported_radius() -> void:
	var c := Collector.new()
	c.broad_radius = 6.0
	add_child_autofree(c)
	var shape: CollisionShape3D = c.get_child(0)
	assert_eq((shape.shape as SphereShape3D).radius, 6.0)
