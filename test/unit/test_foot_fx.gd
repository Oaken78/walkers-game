extends GutTest
## Unit tests for scripts/fx/foot_fx.gd: pools, timing, opacity, alignment. Time is stepped by hand with advance().

const DT: float = 1.0 / 60.0

var _fx: FootFx


## Stands in for a WalkerBody: only the teleport counter.
class FakeBody:
	extends Node3D
	signal foot_planted(leg: int, pos: Vector3, normal: Vector3)
	signal build_applied
	var teleport_count: int = 0
	var build: WalkerBuild = WalkerBuild.scout()

	func get_build() -> WalkerBuild:
		return build.copy()


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


func test_puff_lifetime_is_0_8s() -> void:
	_fx.plant(Vector3.ZERO, Vector3.UP)
	_ticks(47)
	assert_eq(_fx.live_puffs(), 1, "still there at 47 ticks")
	_ticks(1)
	assert_eq(_fx.live_puffs(), 0, "gone at 48 ticks (0.8 s)")


func test_width_for_the_three_builds_from_weight_per_leg() -> void:
	var expected := {&"scout": 0.5254, &"strider": 0.4753, &"crawler": 0.6698}
	var widths := {}
	for id: StringName in expected:
		var body := FakeBody.new()
		body.build = {&"scout": WalkerBuild.scout(), &"strider": WalkerBuild.strider(), &"crawler": WalkerBuild.crawler()}[id]
		add_child_autofree(body)
		var fx := FootFx.new()
		body.add_child(fx)
		widths[id] = fx.puff_width()
		assert_almost_eq(fx.puff_width(), expected[id], 0.005, "W of the %s" % id)
	assert_almost_eq(widths[&"crawler"] / widths[&"strider"], 1.41, 0.02)


func test_width_floor_and_cap() -> void:
	assert_almost_eq(_fx.puff_width_for(25.0), 0.25, 0.0001)
	assert_almost_eq(_fx.puff_width_for(10.0), 0.25, 0.0001, "below 25 kg per leg stays 0.25")
	assert_almost_eq(_fx.puff_width_for(100.0), 1.0, 0.0001)
	assert_almost_eq(_fx.puff_width_for(300.0), 1.0, 0.0001, "above 100 kg per leg stays 1.0")


func test_width_is_recomputed_after_build_applied() -> void:
	var body := FakeBody.new()
	add_child_autofree(body)
	var fx := FootFx.new()
	body.add_child(fx)
	assert_almost_eq(fx.puff_width(), 0.5254, 0.005)
	body.build = WalkerBuild.crawler()
	body.build_applied.emit()
	assert_almost_eq(fx.puff_width(), 0.6698, 0.005)
	fx.advance(0.3)
	fx.plant(Vector3.ZERO, Vector3.UP)
	assert_almost_eq(fx.puff_sprite_size(0), 0.6698 * 0.5, 0.003, "sprites are 0.5 W across")


func test_alpha_curve() -> void:
	assert_almost_eq(_fx.puff_alpha(0.08), 0.45, 0.001, "peak within 0.08 s")
	assert_true(_fx.puff_alpha(0.04) < 0.45)
	assert_true(_fx.puff_alpha(0.4) <= 0.25, "0.4 s")
	assert_almost_eq(_fx.puff_alpha(0.8), 0.0, 0.0001, "0 at the end")
	_fx.plant(Vector3.ZERO, Vector3.UP)
	_ticks(4)
	assert_almost_eq(_fx.puff_alpha(_fx.puff_age(0)), 0.45 * (4.0 * DT / 0.08), 0.01)


func test_five_sprites_start_within_0_3_w_of_the_pad_and_burst_out() -> void:
	var pad := Vector3(1, 2, 3)
	_fx.plant(pad, Vector3.UP)
	var w: float = _fx.puff_width()
	assert_eq(_fx.puff_sprites, 5)
	var far: float = 0.0
	for k in 5:
		var p: Vector3 = _fx.puff_sprite_position(0, k)
		var d: float = Vector2(p.x - pad.x, p.z - pad.z).length()
		assert_true(d <= 0.3 * w + 0.001, "sprite %d starts inside 0.3 W" % k)
		far = maxf(far, d)
	assert_true(far > 0.0, "not all on the pad")
	_ticks(24)
	for k in 5:
		var p2: Vector3 = _fx.puff_sprite_position(0, k)
		assert_true(Vector2(p2.x - pad.x, p2.z - pad.z).length() > 0.0)
	assert_almost_eq(_fx.puff_burst_distance(0.4), 0.16, 0.001, "0.8 m/s slowing to 0 by 0.4 s")
	assert_almost_eq(_fx.puff_burst_distance(0.8), 0.16, 0.001, "stops")


func test_puff_stays_where_it_was_planted_and_sinks_after_rising() -> void:
	_fx.plant(Vector3(1, 0, 3), Vector3.UP)
	var y_full: float = 0.0
	_ticks(18)
	y_full = _fx.puff_sprite_position(0, 0).y
	_ticks(29)
	assert_true(_fx.puff_sprite_position(0, 0).y < y_full, "sinks while it fades")
	assert_almost_eq(_fx.puff_height_share(0.3), 1.0, 0.001)
	assert_almost_eq(_fx.puff_height_share(0.8), 0.7, 0.001, "sinks by 30 %")


func test_sprite_texture_falls_off_to_nothing() -> void:
	var img: Image = _fx.make_puff_texture().get_image()
	var res: int = img.get_width()
	var centre: float = img.get_pixel(res / 2, res / 2).a
	assert_true(centre > 0.9)
	var at_09: float = img.get_pixel(res / 2 + int(0.9 * res * 0.5), res / 2).a
	assert_true(at_09 <= 0.1 * centre, "alpha at 0.9 radius")
	assert_eq(img.get_pixel(0, res / 2).a, 0.0, "0 at the rim")
	assert_eq(img.get_pixel(0, 0).a, 0.0)


func test_puff_is_one_multimesh_draw() -> void:
	assert_eq(_fx.puff_draw_calls, 1)
	var found: int = 0
	for c in _fx.get_children():
		if c is MultiMeshInstance3D:
			found += 1
			assert_eq((c as MultiMeshInstance3D).multimesh.instance_count, _fx.puff_pool_size * _fx.puff_sprites)
	assert_eq(found, 1)

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
	# The first puff's sprites now stand at the newest plant, with a fresh life.
	assert_almost_eq(_fx.puff_sprite_position(0, 0).x, float(count - 1), 0.5)
	_ticks(47)
	assert_true(_fx.puff_age(0) >= 0.0, "reused puff lives its own 0.8 s")
	_ticks(1)
	assert_true(_fx.puff_age(0) < 0.0)


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
