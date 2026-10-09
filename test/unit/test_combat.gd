extends GutTest
## Unit tests for scripts/combat/: Health, Hurtbox and PlayerHurtbox (the damage contract, GDD 5 and 13).

var _changes: Array[Vector2] = []
var _depleted: int = 0
var _seen: Array = []


func _watch(health: Health) -> void:
	_changes.clear()
	_depleted = 0
	health.changed.connect(func(hp: float, max_hp: float) -> void: _changes.append(Vector2(hp, max_hp)))
	health.depleted.connect(func() -> void: _depleted += 1)


func _ray(from: Vector3, to: Vector3, mask: int) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.collide_with_areas = true
	return get_viewport().world_3d.direct_space_state.intersect_ray(query)


# --- Health ---------------------------------------------------------------------------------------------------


func test_health_starts_full() -> void:
	var health := Health.new(45.0)
	assert_eq(health.hp, 45.0)
	assert_eq(health.max_hp, 45.0)


func test_damage_lowers_hp_and_signals_changed() -> void:
	var health := Health.new(45.0)
	_watch(health)
	health.damage(15.0)
	assert_eq(health.hp, 30.0)
	assert_eq(_changes, [Vector2(30.0, 45.0)] as Array[Vector2])
	assert_eq(_depleted, 0)


func test_three_pulse_hits_deplete_a_45_hp_drone_once() -> void:
	var health := Health.new(45.0)
	_watch(health)
	for i in 3:
		health.damage(15.0)
	assert_eq(health.hp, 0.0)
	assert_eq(_depleted, 1)
	health.damage(15.0)
	assert_eq(_depleted, 1, "depleted fires once, not again for a hit on the wreck")
	assert_eq(_changes.size(), 3, "and the wreck does not change")


func test_overkill_stops_at_zero() -> void:
	var health := Health.new(10.0)
	health.damage(500.0)
	assert_eq(health.hp, 0.0)
	assert_true(health.is_depleted())


func test_zero_and_negative_damage_do_nothing() -> void:
	var health := Health.new(10.0)
	_watch(health)
	health.damage(0.0)
	health.damage(-5.0)
	assert_eq(health.hp, 10.0, "no healing through damage()")
	assert_eq(_changes.size(), 0)


func test_repair_full_restores_hp_signals_and_re_arms_depleted() -> void:
	var health := Health.new(100.0)
	health.damage(100.0)
	_watch(health)
	health.repair_full()
	assert_eq(health.hp, 100.0)
	assert_eq(_changes, [Vector2(100.0, 100.0)] as Array[Vector2])
	health.damage(100.0)
	assert_eq(_depleted, 1, "dying again after a repair signals again")


func test_repair_at_full_hp_is_silent() -> void:
	var health := Health.new(100.0)
	_watch(health)
	health.repair_full()
	assert_eq(_changes.size(), 0)


func test_a_new_maximum_keeps_the_share_of_hp() -> void:
	var health := Health.new(100.0)
	health.damage(50.0)
	health.set_max_hp(140.0)
	assert_eq(health.max_hp, 140.0)
	assert_almost_eq(health.hp, 70.0, 0.0001)


# --- Hurtbox ---------------------------------------------------------------------------------------------------


func test_a_hurtbox_is_an_enemy_area_on_layer_3_that_looks_at_nothing() -> void:
	var box := Hurtbox.new()
	assert_eq(box.collision_layer, CombatLayers.ENEMY)
	assert_eq(box.collision_layer, 4, "layer 3 is bit value 4")
	assert_eq(box.collision_mask, 0)
	box.free()


func test_take_hit_signals_with_the_damage_source_and_point() -> void:
	var box := Hurtbox.new()
	var source := Node.new()
	_seen = []
	box.hit_taken.connect(func(damage: float, from: Node, point: Vector3) -> void: _seen = [damage, from, point])
	box.take_hit(15.0, source, Vector3(1.0, 2.0, 3.0))
	assert_eq(_seen, [15.0, source, Vector3(1.0, 2.0, 3.0)])
	assert_eq(box.hits_taken, 1)
	source.free()
	box.free()


func test_take_hit_damages_the_health_when_one_is_attached() -> void:
	var box := Hurtbox.new()
	box.health = Health.new(45.0)
	box.take_hit(15.0, null, Vector3.ZERO)
	assert_eq(box.health.hp, 30.0)
	box.free()


# --- PlayerHurtbox ---------------------------------------------------------------------------------------------


func test_the_player_hurtbox_sits_on_layer_2() -> void:
	var box := PlayerHurtbox.new()
	assert_eq(box.collision_layer, CombatLayers.PLAYER)
	assert_eq(box.collision_layer, 2)
	box.free()


func test_a_shot_between_the_legs_misses_the_player_hurtbox_and_one_at_the_chassis_hits() -> void:
	var box := PlayerHurtbox.new()
	add_child_autofree(box)
	# A chassis box 1.4 wide, 0.4 high and 2.0 long whose underside is 1.0 m up.
	box.set_box(Vector3(1.4, 0.4, 2.0))
	box.follow(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	await wait_physics_frames(2)
	var through_the_legs: Dictionary = _ray(Vector3(-5.0, 0.5, 0.0), Vector3(5.0, 0.5, 0.0), CombatLayers.PLAYER)
	assert_true(through_the_legs.is_empty(), "foot height: nothing there to hit")
	var at_the_chassis: Dictionary = _ray(Vector3(-5.0, 1.2, 0.0), Vector3(5.0, 1.2, 0.0), CombatLayers.PLAYER)
	assert_false(at_the_chassis.is_empty(), "chassis height: hit")
	assert_eq(at_the_chassis["collider"], box)
	assert_almost_eq((at_the_chassis["position"] as Vector3).x, -0.7, 0.01)


func test_the_player_hurtbox_follows_the_body_pose() -> void:
	var box := PlayerHurtbox.new()
	add_child_autofree(box)
	box.set_box(Vector3(1.0, 0.4, 3.0))
	# Yawed a quarter turn and moved: the long axis now runs along X.
	box.follow(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(20.0, 0.0, 0.0)))
	await wait_physics_frames(2)
	var along: Dictionary = _ray(Vector3(10.0, 0.2, 0.0), Vector3(30.0, 0.2, 0.0), CombatLayers.PLAYER)
	assert_false(along.is_empty())
	assert_almost_eq((along["position"] as Vector3).x, 18.5, 0.01, "half of the 3 m length, now along X")
	var old_spot: Dictionary = _ray(Vector3(-5.0, 0.2, 0.0), Vector3(5.0, 0.2, 0.0), CombatLayers.PLAYER)
	assert_true(old_spot.is_empty(), "nothing is left at the origin")
