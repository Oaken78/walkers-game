extends GutTest
## Unit tests for scripts/fx/foot_fx.gd: pools, timing, opacity, alignment. Time is stepped by hand with advance().

const DT: float = 1.0 / 60.0

var _fx: FootFx


## Stands in for a WalkerBody: only the teleport counter.
class FakeBody:
	extends Node3D
	var teleport_count: int = 0


func before_each() -> void:
	_fx = FootFx.new()
	add_child_autofree(_fx)


func _ticks(count: int) -> void:
	for i in count:
		_fx.advance(DT)


func test_decal_opacity_falls_linearly_to_zero_at_2s() -> void:
	assert_true(_fx.plant(Vector3.ZERO, Vector3.UP))
	var decal: Decal = _fx.decal_nodes()[0]
	assert_almost_eq(decal.modulate.a, 1.0, 0.001, "full at the plant")
	_ticks(60)
	assert_almost_eq(decal.modulate.a, 0.5, 0.02, "half at 1 s")
	_ticks(30)
	assert_almost_eq(decal.modulate.a, 0.25, 0.02, "a quarter at 1.5 s")
	_ticks(30)
	assert_false(decal.visible, "gone at 2 s")
	assert_eq(_fx.live_decals(), 0)
	assert_eq(_fx.decals_expired, 1, "it ran out by itself")
	assert_eq(_fx.decal_ticks_min, 120)
	assert_eq(_fx.decal_ticks_max, 120)


func test_puff_lifetime_is_0_2s() -> void:
	_fx.plant(Vector3.ZERO, Vector3.UP)
	var puff: MeshInstance3D = _fx.puff_nodes()[0]
	_ticks(11)
	assert_true(puff.visible, "still there at 11 ticks")
	assert_eq(_fx.live_puffs(), 1)
	_ticks(1)
	assert_false(puff.visible, "gone at 12 ticks (0.2 s)")
	assert_eq(_fx.live_puffs(), 0)


func test_puff_is_0_6m_across_and_its_visible_top_is_at_most_0_3m_up() -> void:
	_fx.plant(Vector3(1, 2, 3), Vector3.UP)
	for t in [0, 3, 6, 9, 11]:
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var top: float = -INF
		for i in _fx.puff_discs:
			var disc: MeshInstance3D = _fx.puff_nodes()[i]
			var p := Vector2(disc.global_position.x, disc.global_position.z)
			lo = lo.min(p - Vector2.ONE * disc.scale.x * 0.5)
			hi = hi.max(p + Vector2.ONE * disc.scale.x * 0.5)
			# A billboard disc is vertical: its top is its centre plus half its size.
			top = maxf(top, disc.global_position.y + disc.scale.y * 0.5)
		assert_true(top - 2.0 <= 0.3 + 0.001, "visible top at tick %d" % t)
		if t == 11:
			assert_almost_eq(hi.x - lo.x, 0.6, 0.06, "about 0.6 m across at the end")
		_ticks(3 if t < 9 else 2)


func test_pool_reuses_oldest_at_capacity() -> void:
	var count: int = _fx.decal_pool_size
	for i in count:
		_fx.plant(Vector3(i, 0, 0), Vector3.UP)
		_fx.advance(DT)
	assert_eq(_fx.live_decals(), count)
	assert_eq(_fx.decal_nodes()[0].global_position.x, 0.0, "first decal still the first plant")
	var reused: Decal = _fx.decal_nodes()[0]
	assert_true(reused.modulate.a < 1.0, "the oldest is mid-fade")
	_fx.plant(Vector3(500, 0, 0), Vector3.UP)
	assert_eq(_fx.live_decals(), count, "no extra decal")
	assert_eq(reused.global_position.x, 500.0, "the oldest was reused")
	assert_eq(_fx.decal_nodes()[1].global_position.x, 1.0, "the others stay")
	assert_almost_eq(reused.modulate.a, 1.0, 0.0001, "back at full opacity")
	_ticks(119)
	assert_true(reused.visible, "alive at 119 ticks after the reuse")
	_ticks(1)
	assert_false(reused.visible, "expired 120 ticks after the reuse")


func test_puff_pool_reuses_oldest_at_capacity() -> void:
	var count: int = _fx.puff_pool_size + 1
	for i in count:
		_fx.plant(Vector3(i, 0, 0), Vector3.UP)
		_fx.advance(0.001)
	assert_eq(_fx.live_puffs(), _fx.puff_pool_size, "capacity, not more")
	# The first puff's discs now stand at the 17th plant (x = 16), with a fresh life.
	assert_almost_eq(_fx.puff_nodes()[0].global_position.x, 16.0, 0.5)
	_ticks(11)
	assert_true(_fx.puff_nodes()[0].visible, "reused puff lives its own 0.2 s")
	_ticks(1)
	assert_false(_fx.puff_nodes()[0].visible)


func test_no_nodes_created_after_warm_up() -> void:
	var children: int = _fx.get_child_count()
	var in_tree: int = get_tree().get_node_count()
	for i in 300:
		_fx.plant(Vector3(i * 0.1, 0, 0), Vector3.UP)
		_fx.advance(DT)
	assert_eq(_fx.get_child_count(), children)
	assert_eq(get_tree().get_node_count(), in_tree)
	assert_true(_fx.peak_live_decals <= _fx.decal_pool_size)


func test_decal_aligns_to_slope_normal() -> void:
	var normal: Vector3 = Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(30.0))
	_fx.plant(Vector3(0, 1, 0), normal)
	var decal: Decal = _fx.decal_nodes()[0]
	assert_almost_eq(rad_to_deg(decal.global_basis.y.angle_to(normal)), 0.0, 0.1)
	assert_almost_eq(decal.global_basis.determinant(), 1.0, 0.001, "a proper rotation, no flip")


func test_ledge_plant_counts_against_world_up() -> void:
	_fx.plant(Vector3(0, 1.08, 0), Vector3.UP)
	assert_eq(_fx.ledge_plants, 1)
	assert_almost_eq(_fx.ledge_align_err_deg, 0.0, 0.01)
	_fx.plant(Vector3(1, 1.08, 0), Vector3.UP.rotated(Vector3.RIGHT, deg_to_rad(20.0)))
	assert_almost_eq(_fx.ledge_align_err_deg, 20.0, 0.1, "a tilted decal on a flat top would fail the check")


func test_plants_right_after_build_applied_are_ignored() -> void:
	_fx.call("_on_build_applied")
	assert_false(_fx.plant(Vector3.ZERO, Vector3.UP))
	assert_eq(_fx.plants_ignored, 1)
	assert_eq(_fx.live_decals(), 0)
	assert_eq(_fx.live_puffs(), 0)
	_ticks(13)
	assert_true(_fx.plant(Vector3.ZERO, Vector3.UP), "plants after the quiet time show")
	assert_eq(_fx.live_decals(), 1)


func test_plant_right_after_a_teleport_is_ignored_even_before_the_next_tick() -> void:
	var body := FakeBody.new()
	add_child_autofree(body)
	var fx := FootFx.new()
	body.add_child(fx)
	body.teleport_count += 1
	assert_false(fx.plant(Vector3.ZERO, Vector3.UP), "same tick as the teleport")
	assert_eq(fx.plants_ignored, 1)
	for i in 13:
		fx.advance(DT)
	assert_true(fx.plant(Vector3.ZERO, Vector3.UP))


func test_release_freeze_disarms_a_pending_freeze() -> void:
	_fx.arm_freeze_after_plant(0.05)
	_fx.release_freeze()
	_fx.plant(Vector3.ZERO, Vector3.UP)
	_ticks(6)
	assert_false(get_tree().paused, "the released freeze never fires")
	get_tree().paused = false


func test_pending_snap_checks_are_cleared_by_build_applied_and_reset_counts() -> void:
	_fx.call("_on_build_applied")
	_fx.get("_checks").append([0, Vector3.ZERO, 0.1])
	_fx.call("_on_build_applied")
	assert_eq(_fx.get("_checks").size(), 0)
	_fx.get("_checks").append([0, Vector3.ZERO, 0.1])
	_fx.reset_counts()
	assert_eq(_fx.get("_checks").size(), 0)
