extends GutTest
## Unit tests for the pulse cannon (GDD 5, 8.3): FireClock (rate and even phases), ProjectilePool (cap, lifetime,
## damage once per projectile) and the catalog numbers the rig reads.

const TICK: float = 1.0 / 60.0

var _hits: int = 0


## Holds the trigger for `ticks` ticks from tick 0. Returns [tick, weapon] for every shot.
func _run(clock: FireClock, ticks: int, held_at: Callable = Callable()) -> Array[Vector2i]:
	var shots: Array[Vector2i] = []
	for tick in ticks:
		var held: bool = true if not held_at.is_valid() else bool(held_at.call(tick))
		for weapon in clock.update(float(tick) * TICK, held):
			shots.append(Vector2i(tick, weapon))
	return shots


func _pool(cap: int = 40) -> ProjectilePool:
	var pool := ProjectilePool.new()
	pool.cap = cap
	pool.auto_step = false
	add_child_autofree(pool)
	return pool


func _hurtbox(at: Vector3, radius: float = 0.6) -> Hurtbox:
	var box := Hurtbox.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape.shape = sphere
	box.add_child(shape)
	box.position = at
	box.hit_taken.connect(func(_damage: float, _source: Node, _point: Vector3) -> void: _hits += 1)
	add_child_autofree(box)
	return box


# --- Catalog ---------------------------------------------------------------------------------------------------


func test_the_pulse_cannon_is_4_shots_per_s_15_damage_60_m_per_s() -> void:
	var part: Dictionary = PartCatalog.get_part(PartCatalog.PULSE_CANNON)
	assert_eq(part["fire_rate"], 4.0)
	assert_eq(part["damage"], 15.0)
	assert_eq(part["projectile_speed"], 60.0)


# --- Fire rate and phases ---------------------------------------------------------------------------------


func test_one_cannon_fires_4_shots_in_the_first_second() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(1, 4.0), 60)
	assert_eq(shots.size(), 4, "ticks 0, 15, 30, 45")
	assert_eq(shots[0].x, 0, "the first shot leaves on the press tick")


func test_the_fire_rate_is_capped_at_4_per_s_per_cannon() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(1, 4.0), 600)
	assert_eq(shots.size(), 40, "10 s of held trigger is 40 shots")
	for i in range(1, shots.size()):
		assert_gte(shots[i].x - shots[i - 1].x, 15, "never two shots closer than 0.25 s")


func test_tapping_the_trigger_does_not_beat_the_cooldown() -> void:
	# Pressed for one tick in every three, released for two.
	var shots: Array[Vector2i] = _run(FireClock.new(1, 4.0), 120, func(tick: int) -> bool: return tick % 3 == 0)
	assert_lte(shots.size(), 8, "2 s of tapping is at most 8 shots")
	for i in range(1, shots.size()):
		assert_gte(shots[i].x - shots[i - 1].x, 15)


func test_releasing_and_pressing_again_keeps_the_cooldown() -> void:
	var clock := FireClock.new(1, 4.0)
	var shots: Array[Vector2i] = _run(clock, 20, func(tick: int) -> bool: return tick < 1 or tick >= 4)
	assert_eq(shots.size(), 2)
	assert_eq(shots[1].x, 15, "the second press waited for the first shot's cooldown")


func test_two_cannons_alternate_with_gaps_of_7_and_8_ticks() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 240)
	assert_eq(shots.size(), 32, "16 shots per cannon in 4 s")
	for i in shots.size():
		assert_eq(shots[i].y, i % 2, "cannon 0, then cannon 1, then cannon 0 again")
	var gaps: Array[int] = []
	for i in range(1, shots.size()):
		gaps.append(shots[i].x - shots[i - 1].x)
	for gap in gaps:
		assert_true(gap == 7 or gap == 8, "gap of %d ticks" % gap)
	assert_eq(gaps[0], 8, "cannon 1 follows 0.125 s (7.5 ticks) after cannon 0, on the 8th tick")
	assert_eq(gaps[1], 7)


func test_two_cannons_fire_0_125_s_apart_on_average() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 300)
	var span: int = shots[shots.size() - 1].x - shots[0].x
	var mean_s: float = float(span) / float(shots.size() - 1) * TICK
	assert_almost_eq(mean_s, 0.125, 0.01)


func test_each_cannon_keeps_its_own_4_shots_per_s_when_two_fire() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 600)
	var per_weapon: Array[int] = [0, 0]
	for shot in shots:
		per_weapon[shot.y] += 1
	assert_eq(per_weapon[0], 40)
	assert_eq(per_weapon[1], 40)


func test_the_phase_gap_is_k_over_n_times_rate() -> void:
	assert_almost_eq(FireClock.new(2, 4.0).phase_gap(), 0.125, 0.000001)
	assert_almost_eq(FireClock.new(3, 4.0).phase_gap(), 1.0 / 12.0, 0.000001)
	assert_almost_eq(FireClock.new(1, 4.0).phase_gap(), 0.25, 0.000001)


func test_a_stall_does_not_fire_a_catch_up_burst() -> void:
	var clock := FireClock.new(1, 4.0)
	assert_eq(clock.update(0.0, true).size(), 1)
	assert_eq(clock.update(5.0, true).size(), 1, "one shot after a 5 s stall")
	assert_eq(clock.update(5.0 + TICK, true).size(), 0, "and not another on the next tick")


func test_a_click_fires_every_cannon_even_when_released_before_its_phase() -> void:
	# Pressed for 6 ticks, released for 12, again and again for 2 s.
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 120, func(tick: int) -> bool: return tick % 18 < 6)
	var per_weapon: Array[int] = [0, 0]
	var last: Array[int] = [-100, -100]
	for shot in shots:
		per_weapon[shot.y] += 1
		assert_gte(shot.x - last[shot.y], 15, "no two shots of cannon %d closer than 15 ticks" % shot.y)
		last[shot.y] = shot.x
	assert_gt(per_weapon[0], 0)
	assert_eq(per_weapon[1], per_weapon[0], "cannon 1 fires as often as cannon 0, click after click")


func test_one_click_of_a_few_ticks_fires_both_cannons_in_phase() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 30, func(tick: int) -> bool: return tick < 3)
	assert_eq(shots.size(), 2, "one click, one shot from each cannon")
	assert_eq(shots[0], Vector2i(0, 0))
	assert_eq(shots[1], Vector2i(8, 1), "cannon 1 after 0.125 s, although the trigger is long released")


func test_a_pending_shot_is_not_doubled_by_clicking_again() -> void:
	var shots: Array[Vector2i] = _run(FireClock.new(2, 4.0), 12, func(tick: int) -> bool: return tick % 2 == 0)
	assert_eq(shots.size(), 2, "ten presses before cannon 1's turn still fire it once")


func test_a_stale_armed_shot_is_not_fired_when_updates_resume() -> void:
	var clock := FireClock.new(2, 4.0)
	assert_eq(clock.update(0.0, true).size(), 1, "cannon 0 fires, cannon 1 is armed for 0.125 s")
	# Input was off for 2 s (no updates), then the trigger is up.
	assert_eq(clock.update(2.0, false).size(), 0, "the old volley is gone")
	assert_eq(clock.update(2.0 + TICK, false).size(), 0)


func test_disarm_drops_a_pending_volley() -> void:
	var clock := FireClock.new(2, 4.0)
	clock.update(0.0, true)
	clock.disarm()
	var shots: Array[Vector2i] = []
	for tick in range(1, 30):
		for weapon in clock.update(float(tick) * TICK, false):
			shots.append(Vector2i(tick, weapon))
	assert_eq(shots.size(), 0, "cannon 1's armed shot was dropped, and the trigger is up")


func test_disarm_keeps_the_cooldown() -> void:
	var clock := FireClock.new(1, 4.0)
	clock.update(0.0, true)
	clock.disarm()
	assert_eq(clock.update(5.0 * TICK, true).size(), 0, "a new press 5 ticks later still waits for the cooldown")


func test_a_rebuild_keeps_the_cooldown_and_the_trigger() -> void:
	var before := FireClock.new(1, 4.0)
	assert_eq(before.update(0.0, true).size(), 1)
	var after := FireClock.new(2, 4.0)
	after.carry_over(before)
	var shots: Array[Vector2i] = []
	for tick in range(1, 30):
		for weapon in after.update(float(tick) * TICK, true):
			shots.append(Vector2i(tick, weapon))
	assert_eq(shots[0], Vector2i(15, 0), "the trigger was held across the rebuild and the cooldown still runs")
	assert_eq(shots[1], Vector2i(23, 1), "and the two cannons are a half period apart again")


# --- Projectile pool -----------------------------------------------------------------------------------------


func test_at_most_40_projectiles_are_live_and_refusals_are_counted() -> void:
	var pool: ProjectilePool = _pool()
	var accepted: int = 0
	for i in 45:
		if pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0):
			accepted += 1
	assert_eq(accepted, 40)
	assert_eq(pool.live, 40)
	assert_eq(pool.refused_count, 5)
	assert_eq(pool.spawned_count, 40)


func test_a_slot_frees_when_a_projectile_expires() -> void:
	var pool: ProjectilePool = _pool(2)
	assert_true(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0))
	assert_true(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0))
	assert_false(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0))
	for i in 121:
		pool.step(TICK)
	assert_eq(pool.live, 0)
	assert_true(pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0), "the pool reuses the bolt")


func test_a_projectile_flies_at_60_m_per_s_and_lives_2_s() -> void:
	var pool: ProjectilePool = _pool(1)
	pool.fire(Vector3(0.0, 50.0, 0.0), Vector3.UP, 60.0, 15.0)
	var bolt: Projectile = pool.get_child(0) as Projectile
	pool.step(TICK)
	assert_almost_eq(bolt.position.y, 51.0, 0.0001, "1 m per 60 Hz tick")
	for i in 118:
		pool.step(TICK)
	assert_eq(pool.live, 1, "still flying at 119 ticks")
	assert_almost_eq(bolt.position.y, 169.0, 0.001)
	pool.step(TICK)
	assert_eq(pool.live, 0, "gone after 2 s")
	assert_almost_eq(bolt.travelled, 120.0, 0.001, "120 m of range")


func test_the_projectile_speed_is_the_cannons_alone() -> void:
	var pool: ProjectilePool = _pool(1)
	pool.fire(Vector3.ZERO + Vector3(0.0, 50.0, 0.0), Vector3(0.0, 0.0, -1.0), 60.0, 15.0)
	var bolt: Projectile = pool.get_child(0) as Projectile
	assert_eq(bolt.velocity, Vector3(0.0, 0.0, -60.0), "no walker velocity is added")


func test_a_hit_damages_once_and_ends_the_projectile() -> void:
	var pool: ProjectilePool = _pool()
	var box: Hurtbox = _hurtbox(Vector3(0.0, 0.0, -5.0))
	box.health = Health.new(45.0)
	await wait_physics_frames(2)
	pool.fire(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 60.0, 15.0)
	for i in 8:
		pool.step(TICK)
	assert_eq(box.health.hp, 30.0, "15 damage")
	assert_eq(box.hits_taken, 1)
	assert_eq(pool.live, 0)
	assert_eq(pool.impact_count, 1)


func test_damage_is_applied_once_even_where_hurtboxes_overlap() -> void:
	var pool: ProjectilePool = _pool()
	_hits = 0
	var inner: Hurtbox = _hurtbox(Vector3(0.0, 0.0, -5.0), 0.6)
	var outer: Hurtbox = _hurtbox(Vector3(0.0, 0.0, -5.2), 0.8)
	inner.health = Health.new(45.0)
	outer.health = Health.new(45.0)
	await wait_physics_frames(2)
	pool.fire(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 60.0, 15.0)
	for i in 12:
		pool.step(TICK)
	assert_eq(_hits, 1, "one hit in all, not one per overlapping hurtbox")
	assert_eq(inner.health.hp + outer.health.hp, 75.0, "15 damage taken between them")


func test_a_projectile_is_stopped_by_the_world_and_does_no_damage() -> void:
	var pool: ProjectilePool = _pool()
	var wall := StaticBody3D.new()
	wall.collision_layer = CombatLayers.WORLD
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(10.0, 10.0, 1.0)
	shape.shape = box
	wall.add_child(shape)
	wall.position = Vector3(0.0, 0.0, -4.0)
	add_child_autofree(wall)
	var behind: Hurtbox = _hurtbox(Vector3(0.0, 0.0, -8.0))
	behind.health = Health.new(45.0)
	await wait_physics_frames(2)
	pool.fire(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 60.0, 15.0)
	for i in 12:
		pool.step(TICK)
	assert_eq(pool.live, 0)
	assert_eq(behind.health.hp, 45.0, "the wall kept the shot off the target behind it")


func test_a_projectile_passes_the_player_layer() -> void:
	var pool: ProjectilePool = _pool()
	var mine := PlayerHurtbox.new()
	add_child_autofree(mine)
	mine.set_box(Vector3(2.0, 2.0, 2.0))
	mine.follow(Transform3D(Basis.IDENTITY, Vector3(0.0, -1.0, -3.0)))
	mine.health = Health.new(100.0)
	await wait_physics_frames(2)
	pool.fire(Vector3.ZERO, Vector3(0.0, 0.0, -1.0), 60.0, 15.0)
	for i in 8:
		pool.step(TICK)
	assert_eq(mine.health.hp, 100.0, "the player's own shots mask layers 1 and 3 only")
	assert_eq(pool.live, 1, "and keep flying")


func test_projectiles_are_on_layer_4_and_hit_layers_1_and_3() -> void:
	var bolt := Projectile.new()
	assert_eq(bolt.collision_layer, 8, "layer 4")
	assert_eq(bolt.hit_mask, 5, "layers 1 and 3")
	bolt.free()


# --- Mount -------------------------------------------------------------------------------------------------------


func _mounted(build: WalkerBuild) -> Array:
	var walker: WalkerBody = preload("res://scenes/walker/walker.tscn").instantiate()
	add_child_autofree(walker)
	walker.apply_build(build)
	var rig := WeaponRig.new()
	rig.walker = walker
	add_child_autofree(rig)
	return [walker, rig]


func test_the_rig_mounts_one_barrel_per_pulse_cannon_and_hides_the_walkers_own() -> void:
	var scout: Array = _mounted(WalkerBuild.scout())
	var rig: WeaponRig = scout[1]
	assert_eq(rig.cannon_count(), 1)
	var tops: Node = (scout[0] as WalkerBody).get_node("Tops")
	assert_false((tops.get_child(0) as Node3D).visible, "the walker's static barrel is hidden")
	var crawler: Array = _mounted(WalkerBuild.crawler())
	assert_eq((crawler[1] as WeaponRig).cannon_count(), 2, "two cannons and an armor plate")
	var crawler_tops: Node = (crawler[0] as WalkerBody).get_node("Tops")
	assert_false((crawler_tops.get_child(0) as Node3D).visible)
	assert_false((crawler_tops.get_child(1) as Node3D).visible)
	assert_true((crawler_tops.get_child(2) as Node3D).visible, "the armor plate stays drawn")


func test_the_rig_remounts_when_the_build_changes() -> void:
	var mounted: Array = _mounted(WalkerBuild.scout())
	var walker: WalkerBody = mounted[0]
	var rig: WeaponRig = mounted[1]
	assert_eq(rig.cannon_count(), 1)
	walker.apply_build(WalkerBuild.crawler())
	assert_eq(rig.cannon_count(), 2)
	walker.apply_build(WalkerBuild.strider())
	assert_eq(rig.cannon_count(), 1)
	var tops: Node = walker.get_node("Tops")
	assert_false((tops.get_child(0) as Node3D).visible, "the new static barrel is hidden too")


func test_the_rig_shows_the_walkers_barrels_again_when_it_leaves() -> void:
	var mounted: Array = _mounted(WalkerBuild.scout())
	var tops: Node = (mounted[0] as WalkerBody).get_node("Tops")
	(mounted[1] as WeaponRig).free()
	assert_true((tops.get_child(0) as Node3D).visible)


func test_the_rig_reads_the_builds_spread() -> void:
	var strider: Array = _mounted(WalkerBuild.strider())
	assert_eq((strider[1] as WeaponRig).spread_deg(), 1.5)
	var crawler: Array = _mounted(WalkerBuild.crawler())
	assert_eq((crawler[1] as WeaponRig).spread_deg(), 0.5)
	(crawler[1] as WeaponRig).spread_override_deg = 0.0
	assert_eq((crawler[1] as WeaponRig).spread_deg(), 0.0, "a scenario can set the spread to 0")


# --- Shots through the rig ---------------------------------------------------------------------------------------


var _directions: Array[Vector3] = []
var _fired_count: int = 0


func _rig_with_pool(build: WalkerBuild, cap: int = 40, spread: float = 1.5) -> WeaponRig:
	var pool := ProjectilePool.new()
	pool.cap = cap
	pool.auto_step = false
	add_child_autofree(pool)
	var walker: WalkerBody = preload("res://scenes/walker/walker.tscn").instantiate()
	add_child_autofree(walker)
	walker.apply_build(build)
	var rig := WeaponRig.new()
	rig.walker = walker
	rig.pool = pool
	rig.spread_override_deg = spread
	add_child_autofree(rig)
	return rig


func _collect(rig: WeaponRig) -> void:
	_directions.clear()
	_fired_count = 0
	rig.fired.connect(
		func(_weapon: int, _origin: Vector3, direction: Vector3) -> void:
			_directions.append(direction)
			_fired_count += 1
	)


func test_a_shot_the_pool_refuses_is_not_counted_or_signalled() -> void:
	var rig: WeaponRig = _rig_with_pool(WalkerBuild.scout(), 1)
	_collect(rig)
	assert_true(rig.shoot(0))
	assert_false(rig.shoot(0), "the pool is full")
	assert_eq(rig.shots_fired, 1)
	assert_eq(_fired_count, 1, "fired is emitted for the accepted shot only")
	assert_eq(rig.pool.refused_count, 1, "and the pool counted the refusal")


func test_each_weapon_draws_its_spread_from_its_own_seeded_generator() -> void:
	var first: WeaponRig = _rig_with_pool(WalkerBuild.crawler())
	_collect(first)
	for i in 6:
		first.shoot(0)
	var cannon0: Array[Vector3] = _directions.duplicate()
	_directions.clear()
	for i in 6:
		first.shoot(1)
	var cannon1: Array[Vector3] = _directions.duplicate()
	var second: WeaponRig = _rig_with_pool(WalkerBuild.crawler())
	_collect(second)
	for i in 6:
		second.shoot(0)
	assert_eq(_directions, cannon0, "the same build gives the same spread: the generator is seeded")
	var same: int = 0
	for i in 6:
		if cannon0[i] == cannon1[i]:
			same += 1
	assert_lt(same, 6, "the two cannons do not share one sequence")
	assert_ne(cannon0[0], cannon0[1], "and the spread is real")


func test_a_shot_leaves_the_muzzle_along_the_barrel_with_zero_spread() -> void:
	var rig: WeaponRig = _rig_with_pool(WalkerBuild.scout(), 40, 0.0)
	_collect(rig)
	rig.shoot(0)
	assert_eq(_directions[0], rig.muzzle_direction(0))
	var bolt: Projectile = rig.pool.get_child(0) as Projectile
	assert_lt(bolt.global_position.distance_to(rig.muzzle_position(0)), 0.0001, "from the muzzle as drawn")


func test_a_hit_on_a_wreck_does_not_flash_the_ring_and_a_hit_on_a_live_target_does() -> void:
	var rig: WeaponRig = _rig_with_pool(WalkerBuild.scout(), 40, 0.0)
	var direction: Vector3 = rig.muzzle_direction(0)
	var target := Hurtbox.new()
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.6
	shape.shape = sphere
	target.add_child(shape)
	target.health = Health.new(45.0)
	target.position = rig.muzzle_position(0) + direction * 5.0
	add_child_autofree(target)
	await wait_physics_frames(2)
	target.health.damage(45.0)
	assert_true(target.health.is_depleted())
	rig.shoot(0)
	for i in 8:
		rig.pool.step(TICK)
	assert_eq(rig.pool.impact_count, 1, "the bolt landed on the wreck's hurtbox")
	assert_false(rig.ring_flashing, "but a wreck gives no hit confirmation")
	target.health.repair_full()
	rig.shoot(0)
	for i in 8:
		rig.pool.step(TICK)
	assert_true(rig.ring_flashing, "a live target does")
