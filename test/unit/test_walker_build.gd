extends GutTest
## Unit tests for PartCatalog and WalkerBuild (GDD 8.1): one behaviour per test.

const TOL := 0.01
const LEG_TYPES: Array[StringName] = [
	PartCatalog.LEG_SHORT, PartCatalog.LEG_MEDIUM, PartCatalog.LEG_LONG
]
const TOP_CHOICES: Array[StringName] = [&"", PartCatalog.PULSE_CANNON, PartCatalog.ARMOR_PLATE]


func _build_with_legs(left: int, right: int, leg: StringName, cannons: int = 1) -> WalkerBuild:
	var b := WalkerBuild.new()
	for row in left:
		b.place(StringName("leg_l%d" % row), leg)
	for row in right:
		b.place(StringName("leg_r%d" % row), leg)
	for i in cannons:
		b.place(StringName("top_%d" % i), PartCatalog.PULSE_CANNON)
	return b


func _assert_row(b: WalkerBuild, expected: Dictionary) -> void:
	var s := b.stats()
	for key: String in expected:
		assert_almost_eq(float(s[key]), float(expected[key]), TOL, key)


func test_catalog_rows_match_gdd_8_1() -> void:
	# [id, socket, mass, lift, reach, grip, spread, hp, rate, dmg, speed, price, units, sale]
	var rows := [
		[&"chassis_medium", &"chassis", 125, 0, 0, 0, 0, 100, 0, 0, 0, 0, 1, false],
		[&"leg_short", &"leg", 35, 110, 0.6, 45, 0.5, 0, 0, 0, 0, 40, 2, true],
		[&"leg_medium", &"leg", 25, 75, 1.0, 35, 1.0, 0, 0, 0, 0, 0, 2, false],
		[&"leg_long", &"leg", 20, 85, 1.6, 30, 1.5, 0, 0, 0, 0, 70, 2, true],
		[&"pulse_cannon", &"top", 40, 0, 0, 0, 0, 0, 4.0, 15, 60.0, 80, 1, true],
		[&"armor_plate", &"top", 50, 0, 0, 0, 0, 40, 0, 0, 0, 50, 1, true],
	]
	var keys := [
		"socket",
		"mass",
		"lift",
		"reach",
		"slope_grip",
		"spread_factor",
		"hp",
		"fire_rate",
		"damage",
		"projectile_speed",
		"price",
		"units_per_purchase",
		"for_sale",
	]
	assert_eq(PartCatalog.part_ids().size(), rows.size())
	for row in rows:
		var part := PartCatalog.get_part(row[0])
		assert_true(part.has("display_name"), "%s display_name" % row[0])
		for i in keys.size():
			var want = row[i + 1]
			if want is float or want is int:
				assert_almost_eq(float(part[keys[i]]), float(want), 0.0001, "%s %s" % [row[0], keys[i]])
			else:
				assert_eq(part[keys[i]], want, "%s %s" % [row[0], keys[i]])


func test_medium_chassis_has_8_leg_and_3_top_sockets() -> void:
	var sockets := PartCatalog.chassis_sockets(PartCatalog.CHASSIS_MEDIUM)
	assert_eq(sockets.size(), 11)
	for row in 4:
		assert_eq(sockets[row], {"id": StringName("leg_l%d" % row), "kind": &"leg", "side": -1, "row": row})
		assert_eq(
			sockets[4 + row], {"id": StringName("leg_r%d" % row), "kind": &"leg", "side": 1, "row": row}
		)
	for row in 3:
		assert_eq(
			sockets[8 + row], {"id": StringName("top_%d" % row), "kind": &"top", "side": 0, "row": row}
		)


func test_starting_inventory_is_the_scout() -> void:
	var inv := PartCatalog.starting_inventory()
	assert_eq(inv, {&"chassis_medium": 1, &"leg_medium": 6, &"pulse_cannon": 1})


func test_scout_matches_reference_row() -> void:
	var b := WalkerBuild.scout()
	_assert_row(
		b,
		{
			"mass": 315,
			"lift": 450,
			"load": 0.700,
			"reach": 1.0,
			"top_speed": 4.5,
			"turn_rate": 120.0,
			"step_up": 0.6,
			"max_slope": 35,
			"spread": 1.0,
			"hp": 100,
			"dps": 60,
		}
	)
	assert_true(b.is_valid())


func test_strider_matches_reference_row() -> void:
	var b := WalkerBuild.strider()
	_assert_row(
		b,
		{
			"mass": 285,
			"lift": 510,
			"load": 0.559,
			"reach": 1.6,
			"top_speed": 6.496,
			"turn_rate": 134.118,
			"step_up": 0.96,
			"max_slope": 30,
			"spread": 1.5,
			"hp": 100,
			"dps": 60,
		}
	)
	assert_true(b.is_valid())


func test_crawler_matches_reference_row() -> void:
	var b := WalkerBuild.crawler()
	_assert_row(
		b,
		{
			"mass": 535,
			"lift": 880,
			"load": 0.608,
			"reach": 0.6,
			"top_speed": 3.807,
			"turn_rate": 109.205,
			"step_up": 0.36,
			"max_slope": 45,
			"spread": 0.5,
			"hp": 140,
			"dps": 120,
		}
	)
	assert_true(b.is_valid())


func test_strider_is_at_least_40_percent_faster_than_crawler() -> void:
	var a := WalkerBuild.strider().stats()["top_speed"] as float
	var c := WalkerBuild.crawler().stats()["top_speed"] as float
	assert_gte((a - c) / a, 0.4)


func test_strider_steps_up_at_least_40_percent_higher_than_crawler() -> void:
	var a := WalkerBuild.strider().stats()["step_up"] as float
	var c := WalkerBuild.crawler().stats()["step_up"] as float
	assert_gte((a - c) / a, 0.4)


func test_reference_builds_are_not_speed_clamped() -> void:
	for b in [WalkerBuild.strider(), WalkerBuild.crawler()]:
		var speed := (b as WalkerBuild).stats()["top_speed"] as float
		assert_gt(speed, 2.5)
		assert_lt(speed, 7.0)


func test_crawler_dps_times_hp_is_at_least_1_8x_strider() -> void:
	var a := WalkerBuild.strider().stats()
	var c := WalkerBuild.crawler().stats()
	assert_gte(float(c["dps"]) * float(c["hp"]), 1.8 * float(a["dps"]) * float(a["hp"]))


func test_no_armed_build_with_6_or_8_legs_hits_the_speed_clamp() -> void:
	var checked := 0
	for total in [6, 8]:
		for n_short in range(total + 1):
			for n_medium in range(total + 1 - n_short):
				var n_long: int = total - n_short - n_medium
				var legs: Array[StringName] = []
				for i in n_short:
					legs.append(PartCatalog.LEG_SHORT)
				for i in n_medium:
					legs.append(PartCatalog.LEG_MEDIUM)
				for i in n_long:
					legs.append(PartCatalog.LEG_LONG)
				for t0 in TOP_CHOICES:
					for t1 in TOP_CHOICES:
						for t2 in TOP_CHOICES:
							var tops := [t0, t1, t2]
							if not tops.has(PartCatalog.PULSE_CANNON):
								continue
							var b := WalkerBuild.new()
							for i in legs.size():
								var side_letter := "l" if i % 2 == 0 else "r"
								b.place(StringName("leg_%s%d" % [side_letter, i / 2]), legs[i])
							for i in 3:
								if tops[i] != &"":
									b.place(StringName("top_%d" % i), tops[i])
							if not b.is_valid():
								continue
							checked += 1
							var speed := b.stats()["top_speed"] as float
							assert_true(speed > 2.5 and speed < 7.0, "%s %s" % [b.parts(), speed])
	assert_gt(checked, 0)


func test_four_legs_use_gait_factor_0_85() -> void:
	var b := _build_with_legs(2, 2, PartCatalog.LEG_LONG)
	assert_almost_eq(b.stats()["top_speed"] as float, 4.739, 0.001)


func test_speed_clamps_at_7_for_an_unarmed_8_long_leg_build() -> void:
	var b := _build_with_legs(4, 4, PartCatalog.LEG_LONG, 0)
	var unclamped := (
		WalkerBuild.SPEED_BASE
		* sqrt(1.6)
		* (WalkerBuild.SPEED_LOAD_OFFSET - (b.stats()["load"] as float))
	)
	assert_almost_eq(unclamped, 7.291, 0.001)
	assert_eq(b.stats()["top_speed"], 7.0)


func test_leg_part_does_not_fit_a_top_socket() -> void:
	var b := WalkerBuild.new()
	assert_false(b.can_place(&"top_0", PartCatalog.LEG_SHORT))
	assert_false(b.place(&"top_0", PartCatalog.LEG_SHORT))
	assert_eq(b.part_at(&"top_0"), &"")


func test_top_part_does_not_fit_a_leg_socket() -> void:
	var b := WalkerBuild.new()
	assert_false(b.place(&"leg_l0", PartCatalog.PULSE_CANNON))
	assert_false(b.place(&"leg_r0", PartCatalog.ARMOR_PLATE))
	assert_eq(b.parts().size(), 0)


func test_unknown_socket_or_part_is_rejected() -> void:
	var b := WalkerBuild.new()
	assert_false(b.place(&"leg_l9", PartCatalog.LEG_SHORT))
	assert_false(b.place(&"leg_l0", &"leg_gold"))
	assert_false(b.place(&"leg_l0", PartCatalog.CHASSIS_MEDIUM))
	assert_eq(b.remove(&"nope"), &"")
	assert_eq(b.parts().size(), 0)


func test_placing_on_an_occupied_socket_fails() -> void:
	var b := WalkerBuild.new()
	assert_true(b.place(&"leg_l0", PartCatalog.LEG_SHORT))
	assert_false(b.place(&"leg_l0", PartCatalog.LEG_LONG))
	assert_eq(b.part_at(&"leg_l0"), PartCatalog.LEG_SHORT)


func test_remove_returns_the_part_and_empties_the_socket() -> void:
	var b := WalkerBuild.new()
	b.place(&"top_1", PartCatalog.ARMOR_PLATE)
	assert_eq(b.remove(&"top_1"), PartCatalog.ARMOR_PLATE)
	assert_eq(b.part_at(&"top_1"), &"")
	assert_eq(b.remove(&"top_1"), &"")


func test_valid_build_has_empty_reason() -> void:
	var b := WalkerBuild.scout()
	assert_true(b.is_valid())
	assert_eq(b.invalid_reason(), "")


func test_leg_counts_other_than_4_6_8_need_4_6_or_8_legs() -> void:
	for pair in [[0, 0], [1, 1], [3, 2], [4, 3]]:
		var b := _build_with_legs(pair[0], pair[1], PartCatalog.LEG_MEDIUM)
		assert_false(b.is_valid())
		assert_eq(b.invalid_reason(), "Needs 4, 6 or 8 legs", str(pair))


func test_unequal_sides_are_unbalanced() -> void:
	var b := _build_with_legs(4, 2, PartCatalog.LEG_MEDIUM)
	assert_eq(b.invalid_reason(), "Legs unbalanced")


func test_overload_reason_shows_rounded_mass_and_lift() -> void:
	var b := _build_with_legs(2, 2, PartCatalog.LEG_MEDIUM, 3)
	assert_eq(b.invalid_reason(), "Overloaded: 345/300 kg")


func test_leg_count_reason_wins_over_overload() -> void:
	var b := _build_with_legs(1, 1, PartCatalog.LEG_MEDIUM, 3)
	assert_eq(b.invalid_reason(), "Needs 4, 6 or 8 legs")


func test_mixed_leg_types_are_valid_when_sides_match() -> void:
	var b := WalkerBuild.new()
	var types: Array[StringName] = [
		PartCatalog.LEG_LONG, PartCatalog.LEG_MEDIUM, PartCatalog.LEG_SHORT
	]
	for row in 3:
		b.place(StringName("leg_l%d" % row), types[row])
		b.place(StringName("leg_r%d" % row), types[row])
	b.place(&"top_0", PartCatalog.PULSE_CANNON)
	assert_true(b.is_valid(), b.invalid_reason())
	assert_eq(b.stats()["max_slope"], 30.0)


func test_removing_a_leg_is_allowed_and_makes_the_build_invalid() -> void:
	var b := WalkerBuild.scout()
	assert_eq(b.remove(&"leg_r2"), PartCatalog.LEG_MEDIUM)
	assert_eq(b.leg_count(), 5)
	assert_false(b.is_valid())
	assert_eq(b.invalid_reason(), "Needs 4, 6 or 8 legs")


func test_mounted_legs_are_ordered_left_then_right_front_to_back() -> void:
	var b := WalkerBuild.new()
	b.place(&"leg_r1", PartCatalog.LEG_LONG)
	b.place(&"leg_l2", PartCatalog.LEG_SHORT)
	b.place(&"leg_r0", PartCatalog.LEG_MEDIUM)
	b.place(&"leg_l0", PartCatalog.LEG_MEDIUM)
	var order: Array[StringName] = []
	for leg in b.mounted_legs():
		order.append(leg["socket"])
	assert_eq(order, [&"leg_l0", &"leg_l2", &"leg_r0", &"leg_r1"] as Array[StringName])
	var first := b.mounted_legs()[1]
	assert_eq(first["part"], PartCatalog.LEG_SHORT)
	assert_eq(first["side"], -1)
	assert_eq(first["row"], 2)
	assert_eq(first["lift"], 110.0)
	assert_eq(first["slope_grip"], 45.0)


func test_legless_build_stats_are_finite_and_zero() -> void:
	var s := WalkerBuild.new().stats()
	for key in ["lift", "load", "reach", "top_speed", "turn_rate", "step_up", "max_slope", "spread"]:
		assert_eq(s[key], 0.0, key)
		assert_true(is_finite(s[key]), key)
	assert_eq(s["mass"], 125.0)
	assert_eq(s["leg_count"], 0)


func test_copy_is_independent() -> void:
	var a := WalkerBuild.scout()
	var b := a.copy()
	b.remove(&"top_0")
	b.place(&"top_1", PartCatalog.ARMOR_PLATE)
	assert_eq(a.part_at(&"top_0"), PartCatalog.PULSE_CANNON)
	assert_eq(a.part_at(&"top_1"), &"")
	assert_eq(b.chassis_id, a.chassis_id)