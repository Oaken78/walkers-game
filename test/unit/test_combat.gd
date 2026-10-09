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
	query.collide_with_bodies = false
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


func test_a_hit_on_a_wreck_does_nothing_and_signals_nothing() -> void:
	var box := Hurtbox.new()
	box.health = Health.new(45.0)
	_seen = []
	box.hit_taken.connect(func(damage: float, from: Node, point: Vector3) -> void: _seen.append([damage, from, point]))
	for i in 3:
		box.take_hit(15.0, null, Vector3.ZERO)
	assert_eq(box.health.hp, 0.0)
	assert_eq(_seen.size(), 3)
	box.take_hit(15.0, null, Vector3.ZERO)
	assert_eq(_seen.size(), 3, "a drone falling with its hurtbox on is not hit again")
	assert_eq(box.hits_taken, 3)
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
	# A chassis box 1.4 wide, 0.4 high and 2.0 long whose underside is 1.0 m up: its centre is at 1.2.
	box.set_box(Vector3(1.4, 0.4, 2.0))
	box.follow(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)))
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
	box.follow(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), Vector3(20.0, 0.2, 0.0)))
	await wait_physics_frames(2)
	var along: Dictionary = _ray(Vector3(10.0, 0.2, 0.0), Vector3(30.0, 0.2, 0.0), CombatLayers.PLAYER)
	assert_false(along.is_empty())
	assert_almost_eq((along["position"] as Vector3).x, 18.5, 0.01, "half of the 3 m length, now along X")
	var old_spot: Dictionary = _ray(Vector3(-5.0, 0.2, 0.0), Vector3(5.0, 0.2, 0.0), CombatLayers.PLAYER)
	assert_true(old_spot.is_empty(), "nothing is left at the origin")


func _walker_in_a_world(build: WalkerBuild) -> WalkerBody:
	var ground := StaticBody3D.new()
	ground.collision_layer = CombatLayers.WORLD
	var slab := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 2.0, 100.0)
	slab.shape = shape
	ground.add_child(slab)
	ground.position = Vector3(0.0, -1.0, 0.0)
	add_child_autofree(ground)
	var walker: WalkerBody = preload("res://scenes/walker/walker.tscn").instantiate()
	add_child_autofree(walker)
	walker.apply_build(build)
	walker.teleport(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))
	return walker


func test_the_player_hurtbox_on_a_real_walker_reads_the_chassis_and_follows_it() -> void:
	var walker: WalkerBody = _walker_in_a_world(WalkerBuild.scout())
	var box := PlayerHurtbox.new()
	box.walker = walker
	add_child_autofree(box)
	var chassis: MeshInstance3D = walker.get_node("Chassis")
	assert_eq(box.box_size(), (chassis.mesh as BoxMesh).size, "sized from the walker's chassis box")
	await wait_physics_frames(8)
	assert_true(
		box.global_transform.is_equal_approx(chassis.global_transform),
		"it sits where the chassis is drawn, with the chassis' own offset"
	)
	var pose: Transform3D = walker.body_pose()
	var centre: Vector3 = pose * Vector3(0.0, box.box_size().y * 0.5, 0.0)
	assert_lt(box.global_position.distance_to(centre), 0.001, "the body pose plus the chassis centre")


func test_the_player_hurtbox_resizes_when_the_walker_changes_build() -> void:
	var walker: WalkerBody = _walker_in_a_world(WalkerBuild.scout())
	var box := PlayerHurtbox.new()
	box.walker = walker
	add_child_autofree(box)
	var scout_size: Vector3 = box.box_size()
	walker.apply_build(WalkerBuild.strider())
	var strider_size: Vector3 = ((walker.get_node("Chassis") as MeshInstance3D).mesh as BoxMesh).size
	assert_eq(box.box_size(), strider_size)
	assert_ne(box.box_size(), scout_size, "a Strider's chassis is not a Scout's")


func test_a_shot_between_a_real_walkers_legs_misses_its_hurtbox() -> void:
	var walker: WalkerBody = _walker_in_a_world(WalkerBuild.scout())
	var box := PlayerHurtbox.new()
	box.walker = walker
	add_child_autofree(box)
	await wait_physics_frames(12)
	var chassis: Transform3D = (walker.get_node("Chassis") as MeshInstance3D).global_transform
	var low: Dictionary = _ray(Vector3(-6.0, 0.1, 0.0), Vector3(6.0, 0.1, 0.0), CombatLayers.PLAYER)
	assert_true(low.is_empty(), "at foot height there is no hurtbox")
	var at_chassis: Dictionary = _ray(
		Vector3(-6.0, chassis.origin.y, chassis.origin.z), Vector3(6.0, chassis.origin.y, chassis.origin.z), CombatLayers.PLAYER
	)
	assert_false(at_chassis.is_empty(), "at the chassis it is there")
