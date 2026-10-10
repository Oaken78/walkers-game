extends GutTest
## Unit tests for scripts/fx/foot_fx.gd: pools, timing, opacity, alignment. Time is stepped by hand with advance().

const DT: float = 1.0 / 60.0

var _fx: FootFx


func before_each() -> void:
	_fx = FootFx.new()
	add_child_autofree(_fx)


func _step(seconds: float) -> void:
	for i in roundi(seconds / DT):
		_fx.advance(DT)


func test_decal_opacity_falls_linearly_to_zero_at_2s() -> void:
	assert_true(_fx.plant(Vector3.ZERO, Vector3.UP))
	var decal: Decal = _fx.decal_nodes()[0]
	assert_almost_eq(decal.modulate.a, 1.0, 0.001, "full at the plant")
	_step(1.0)
	assert_almost_eq(decal.modulate.a, 0.5, 0.02, "half at 1 s")
	_step(0.5)
	assert_almost_eq(decal.modulate.a, 0.25, 0.02, "a quarter at 1.5 s")
	_step(0.5)
	assert_false(decal.visible, "gone at 2 s")
	assert_eq(_fx.live_decals(), 0)
	assert_eq(_fx.decal_ticks_min, 120)
	assert_eq(_fx.decal_ticks_max, 120)


func test_puff_lifetime_is_0_2s() -> void:
	_fx.plant(Vector3.ZERO, Vector3.UP)
	var puff: MeshInstance3D = _fx.puff_nodes()[0]
	_step(0.18)
	assert_true(puff.visible, "still there at 0.18 s")
	assert_eq(_fx.live_puffs(), 1)
	_step(DT * 3.0)
	assert_false(puff.visible, "gone by 0.2 s")
	assert_eq(_fx.live_puffs(), 0)


func test_puff_is_0_6m_across_and_rises_at_most_0_3m() -> void:
	_fx.plant(Vector3(1, 2, 3), Vector3.UP)
	_step(0.19)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var top: float = -INF
	for i in _fx.puff_discs:
		var disc: MeshInstance3D = _fx.puff_nodes()[i]
		var p := Vector2(disc.global_position.x, disc.global_position.z)
		lo = lo.min(p - Vector2.ONE * disc.scale.x * 0.5)
		hi = hi.max(p + Vector2.ONE * disc.scale.x * 0.5)
		top = maxf(top, disc.global_position.y)
	assert_almost_eq(hi.x - lo.x, 0.6, 0.06, "about 0.6 m across")
	assert_true(top - 2.0 <= 0.3 + 0.001, "rises at most 0.3 m")


func test_pool_reuses_oldest_at_capacity() -> void:
	var count: int = _fx.decal_pool_size
	for i in count:
		_fx.plant(Vector3(i, 0, 0), Vector3.UP)
		_fx.advance(DT)
	assert_eq(_fx.live_decals(), count)
	assert_eq(_fx.decal_nodes()[0].global_position.x, 0.0, "first decal still the first plant")
	_fx.plant(Vector3(500, 0, 0), Vector3.UP)
	assert_eq(_fx.live_decals(), count, "no extra decal")
	assert_eq(_fx.decal_nodes()[0].global_position.x, 500.0, "the oldest was reused")
	assert_eq(_fx.decal_nodes()[1].global_position.x, 1.0, "the others stay")


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


func test_plants_right_after_build_applied_are_ignored() -> void:
	_fx.call("_on_build_applied")
	assert_false(_fx.plant(Vector3.ZERO, Vector3.UP))
	assert_eq(_fx.plants_ignored, 1)
	assert_eq(_fx.live_decals(), 0)
	assert_eq(_fx.live_puffs(), 0)
	_step(0.21)
	assert_true(_fx.plant(Vector3.ZERO, Vector3.UP), "plants after the quiet time show")
	assert_eq(_fx.live_decals(), 1)
