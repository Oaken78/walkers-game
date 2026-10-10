extends GutTest
## Unit tests for the workshop (T09): Inventory (buy, mount, unmount, preview), the stat formatting, the camera
## limits and the build UI's layout and states. One behaviour per test.

const TOL := 0.0001
const LONG := PartCatalog.LEG_LONG
const MEDIUM := PartCatalog.LEG_MEDIUM
const SHORT := PartCatalog.LEG_SHORT
const CANNON := PartCatalog.PULSE_CANNON
const ARMOR := PartCatalog.ARMOR_PLATE

var economy: Economy
var inventory: Inventory
var build: WalkerBuild


func before_each() -> void:
	economy = _economy_with(200)
	inventory = Inventory.new()
	build = WalkerBuild.scout()


func _economy_with(scrap: int) -> Economy:
	var eco := Economy.new()
	eco.pick_up("", scrap)
	eco.bank()
	return eco


func _mounted_total(b: WalkerBuild) -> int:
	return b.parts().size()


# --- Inventory: the starting stock ---------------------------------------------------------------------------


func test_a_new_inventory_starts_from_the_catalog_starting_inventory() -> void:
	var start := PartCatalog.starting_inventory()
	for part_id: StringName in start:
		assert_eq(inventory.owned(part_id), start[part_id], str(part_id))


func test_the_scout_mounts_everything_it_owns_so_nothing_is_spare() -> void:
	assert_eq(inventory.spare(build, MEDIUM), 0)
	assert_eq(inventory.spare(build, CANNON), 0)
	assert_true(inventory.is_consistent(build))


func test_a_build_with_more_parts_than_owned_is_inconsistent() -> void:
	build.place(&"top_1", ARMOR)
	assert_false(inventory.is_consistent(build))


# --- Inventory: buying ---------------------------------------------------------------------------------------


func test_buying_a_leg_pair_adds_two_legs_for_the_pair_price() -> void:
	assert_true(inventory.buy(LONG, economy))
	assert_eq(inventory.owned(LONG), 2)
	assert_eq(economy.banked_scrap, 130)
	assert_eq(economy.spent, 70)


func test_buying_a_top_part_adds_one_for_its_price() -> void:
	assert_true(inventory.buy(ARMOR, economy))
	assert_eq(inventory.owned(ARMOR), 1)
	assert_eq(economy.banked_scrap, 150)


func test_buying_without_enough_scrap_changes_nothing() -> void:
	var poor := _economy_with(69)
	assert_false(inventory.buy(LONG, poor))
	assert_eq(inventory.owned(LONG), 0)
	assert_eq(poor.banked_scrap, 69)
	assert_eq(poor.spent, 0)


func test_the_buy_blocker_says_how_much_is_missing() -> void:
	var poor := _economy_with(60)
	assert_eq(inventory.buy_blocker(LONG, poor), "Need 10 more")
	assert_eq(inventory.buy_blocker(SHORT, poor), "")


func test_a_part_that_is_not_for_sale_cannot_be_bought() -> void:
	assert_eq(inventory.buy_blocker(MEDIUM, economy), "Not for sale")
	assert_false(inventory.buy(MEDIUM, economy))
	assert_false(inventory.buy(PartCatalog.CHASSIS_MEDIUM, economy))
	assert_false(inventory.buy(&"no_such_part", economy))
	assert_eq(economy.banked_scrap, 200)


func test_buying_announces_the_change() -> void:
	watch_signals(inventory)
	inventory.buy(SHORT, economy)
	assert_signal_emitted(inventory, "changed")
	inventory.buy(LONG, _economy_with(1))
	assert_signal_emit_count(inventory, "changed", 1)


# --- Inventory: mounting and unmounting ---------------------------------------------------------------------


func test_mirror_of_pairs_the_leg_sockets_and_ignores_the_rest() -> void:
	assert_eq(Inventory.mirror_of(&"leg_l2"), &"leg_r2")
	assert_eq(Inventory.mirror_of(&"leg_r0"), &"leg_l0")
	assert_eq(Inventory.mirror_of(&"top_1"), &"")


func test_mounting_a_leg_fills_the_socket_and_its_mirror() -> void:
	inventory.buy(LONG, economy)
	assert_true(inventory.mount(build, &"leg_l3", LONG))
	assert_eq(build.part_at(&"leg_l3"), LONG)
	assert_eq(build.part_at(&"leg_r3"), LONG)
	assert_eq(build.leg_count(), 8)
	assert_eq(inventory.spare(build, LONG), 0)
	assert_true(build.is_valid())


func test_mounting_a_leg_needs_two_spare() -> void:
	var one_short := Inventory.new({MEDIUM: 5, CANNON: 1})
	build.remove(&"leg_l2")
	build.remove(&"leg_r2")
	assert_eq(one_short.spare(build, MEDIUM), 1)
	assert_eq(one_short.mount_reason(build, &"leg_l2", MEDIUM), "Legs go in pairs: 1 spare")
	assert_false(one_short.mount(build, &"leg_l2", MEDIUM))
	assert_eq(build.part_at(&"leg_l2"), &"")


func test_mounting_with_none_spare_says_to_buy_one() -> void:
	assert_eq(inventory.mount_reason(build, &"leg_l3", LONG), "No spare long leg: buy one")
	assert_eq(inventory.mount_reason(build, &"top_1", ARMOR), "No spare armor plate: buy one")


func test_mount_refusals_give_their_reasons_and_leave_the_build_alone() -> void:
	inventory.buy(LONG, economy)
	inventory.buy(ARMOR, economy)
	var before := build.parts()
	assert_eq(inventory.mount_reason(build, &"leg_l0", LONG), "Socket is taken")
	assert_eq(inventory.mount_reason(build, &"top_1", LONG), "Long leg goes on a leg socket")
	assert_eq(inventory.mount_reason(build, &"leg_l3", ARMOR), "Armor plate goes on a top socket")
	assert_eq(inventory.mount_reason(build, &"nowhere", LONG), "No such socket")
	assert_eq(inventory.mount_reason(build, &"leg_l3", &"no_part"), "Unknown part")
	assert_eq(
		inventory.mount_reason(build, &"leg_l3", PartCatalog.CHASSIS_MEDIUM),
		"Not a part you can mount"
	)
	assert_false(inventory.mount(build, &"leg_l0", LONG))
	assert_false(inventory.mount(build, &"top_1", LONG))
	assert_eq(build.parts(), before)


func test_a_leg_is_refused_when_only_its_mirror_socket_is_taken() -> void:
	inventory.buy(LONG, economy)
	build.place(&"leg_r3", MEDIUM)
	assert_eq(inventory.mount_reason(build, &"leg_l3", LONG), "Mirror socket is taken")


func test_a_top_part_mounts_singly() -> void:
	inventory.buy(ARMOR, economy)
	assert_true(inventory.mount(build, &"top_1", ARMOR))
	assert_eq(build.part_at(&"top_1"), ARMOR)
	assert_eq(_mounted_total(build), 8)


func test_unmounting_a_leg_takes_the_pair_off_and_keeps_both_owned() -> void:
	assert_true(inventory.unmount(build, &"leg_r1"))
	assert_eq(build.part_at(&"leg_r1"), &"")
	assert_eq(build.part_at(&"leg_l1"), &"")
	assert_eq(build.leg_count(), 4)
	assert_eq(inventory.owned(MEDIUM), 6)
	assert_eq(inventory.spare(build, MEDIUM), 2)


func test_unmounting_an_empty_socket_is_refused() -> void:
	assert_eq(inventory.unmount_reason(build, &"leg_l3"), "Nothing mounted here")
	assert_eq(inventory.unmount_reason(build, &"nowhere"), "No such socket")
	assert_false(inventory.unmount(build, &"leg_l3"))
	assert_eq(build.leg_count(), 6)


func test_a_part_taken_off_can_be_mounted_again() -> void:
	inventory.unmount(build, &"leg_l2")
	assert_true(inventory.mount(build, &"leg_l2", MEDIUM))
	assert_eq(build.leg_count(), 6)
	assert_eq(inventory.spare(build, MEDIUM), 0)


# --- Validity and its reasons --------------------------------------------------------------------------------


func test_two_legs_give_the_leg_count_reason() -> void:
	inventory.unmount(build, &"leg_l2")
	inventory.unmount(build, &"leg_l1")
	assert_eq(build.leg_count(), 2)
	assert_eq(build.invalid_reason(), "Needs 4, 6 or 8 legs")
	assert_false(build.is_valid())


func test_four_legs_with_cannon_and_armor_are_overloaded() -> void:
	inventory.buy(ARMOR, economy)
	inventory.unmount(build, &"leg_l2")
	assert_true(build.is_valid())
	inventory.mount(build, &"top_1", ARMOR)
	assert_eq(build.invalid_reason(), "Overloaded: 315/300 kg")


func test_every_edit_keeps_the_legs_balanced() -> void:
	inventory.buy(LONG, economy)
	inventory.mount(build, &"leg_r3", LONG)
	assert_ne(build.invalid_reason(), "Legs unbalanced")
	inventory.unmount(build, &"leg_l0")
	assert_ne(build.invalid_reason(), "Legs unbalanced")


# --- Preview ---------------------------------------------------------------------------------------------------


func test_a_place_preview_equals_after_minus_before_and_leaves_the_build_alone() -> void:
	inventory.buy(LONG, economy)
	var parts_before := build.parts()
	var preview := inventory.preview(build, &"leg_l3", LONG)
	assert_true(preview["ok"])
	assert_eq(build.parts(), parts_before)
	var expected := WalkerBuild.scout()
	expected.place(&"leg_l3", LONG)
	expected.place(&"leg_r3", LONG)
	var before := BuildStats.of(WalkerBuild.scout())
	var after := BuildStats.of(expected)
	for key: String in BuildStats.DELTA_KEYS:
		var want := float(after[key]) - float(before[key])
		assert_almost_eq(float(preview["delta"][key]), want, TOL, key)
	assert_gt(float(preview["delta"]["top_speed"]), 0.0)
	assert_lt(float(preview["delta"]["turn_rate"]), 0.0)
	assert_true(preview["valid_after"])


func test_a_remove_preview_shows_the_loss_and_leaves_the_build_alone() -> void:
	var preview := inventory.preview(build, &"leg_l0")
	assert_true(preview["ok"])
	assert_eq(build.leg_count(), 6)
	assert_almost_eq(float(preview["delta"]["leg_count"]), -2.0, TOL)
	assert_lt(float(preview["delta"]["lift"]), 0.0)


func test_a_refused_preview_has_the_reason_and_no_change() -> void:
	var preview := inventory.preview(build, &"leg_l3", LONG)
	assert_false(preview["ok"])
	assert_eq(preview["reason"], "No spare long leg: buy one")
	for key: String in BuildStats.DELTA_KEYS:
		assert_almost_eq(float(preview["delta"][key]), 0.0, TOL, key)


func test_a_preview_flags_a_build_it_would_block() -> void:
	inventory.unmount(build, &"leg_l2")
	var preview := inventory.preview(build, &"leg_l1")
	assert_false(preview["valid_after"])
	assert_eq(preview["invalid_reason_after"], "Needs 4, 6 or 8 legs")


func test_the_climb_stat_is_nine_tenths_of_the_reach() -> void:
	assert_almost_eq(float(BuildStats.of(WalkerBuild.scout())["climb"]), 0.9, TOL)
	assert_almost_eq(float(BuildStats.of(WalkerBuild.strider())["climb"]), 1.44, TOL)


func test_a_mixed_build_climbs_as_far_as_its_shortest_leg() -> void:
	inventory.buy(LONG, economy)
	inventory.mount(build, &"leg_l3", LONG)
	assert_almost_eq(float(BuildStats.of(build)["climb"]), 0.9, TOL)
	assert_almost_eq(BuildStats.shortest_reach(build), 1.0, TOL)
	var short_pair := WalkerBuild.crawler()
	assert_almost_eq(float(BuildStats.of(short_pair)["climb"]), 0.54, TOL)
	assert_almost_eq(float(BuildStats.of(WalkerBuild.new())["climb"]), 0.0, TOL)


# --- Conservation over a long random sequence -------------------------------------------------------------------


func test_500_seeded_operations_never_create_or_lose_a_part_or_scrap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	var sockets: Array[StringName] = []
	for socket in PartCatalog.chassis_sockets(build.chassis_id):
		sockets.append(socket["id"])
	var parts: Array[StringName] = [SHORT, MEDIUM, LONG, CANNON, ARMOR]
	var start_owned := inventory.owned_counts()
	var bought: Dictionary = {}
	var paid := 0
	var problems := PackedStringArray()
	for step in 500:
		var roll := rng.randi_range(0, 9)
		var socket: StringName = sockets[rng.randi_range(0, sockets.size() - 1)]
		var part: StringName = parts[rng.randi_range(0, parts.size() - 1)]
		var mounted_before := _mounted_total(build)
		var parts_before := build.parts()
		if roll < 2:
			var price: int = PartCatalog.PARTS[part]["price"]
			var banked_before := economy.banked_scrap
			if inventory.buy(part, economy):
				var units: int = PartCatalog.PARTS[part]["units_per_purchase"]
				bought[part] = bought.get(part, 0) + units
				paid += price
			elif economy.banked_scrap != banked_before:
				problems.append("step %d: a refused buy cost scrap" % step)
		elif roll < 6:
			var is_leg := PartCatalog.socket_kind(part) == PartCatalog.KIND_LEG
			if inventory.mount(build, socket, part):
				if _mounted_total(build) != mounted_before + (2 if is_leg else 1):
					problems.append("step %d: mount added the wrong count" % step)
			elif build.parts() != parts_before:
				problems.append("step %d: a refused mount changed the build" % step)
		elif roll < 9:
			var was_leg := PartCatalog.socket_kind(build.part_at(socket)) == PartCatalog.KIND_LEG
			if inventory.unmount(build, socket):
				var gone := mounted_before - _mounted_total(build)
				if gone != (2 if was_leg and parts_before.has(Inventory.mirror_of(socket)) else 1):
					problems.append("step %d: unmount removed %d parts" % [step, gone])
			elif build.parts() != parts_before:
				problems.append("step %d: a refused unmount changed the build" % step)
		else:
			inventory.preview(build, socket, part if rng.randi_range(0, 1) == 0 else &"")
			if build.parts() != parts_before:
				problems.append("step %d: a preview changed the build" % step)
		_check_invariants(step, start_owned, bought, paid, problems)
	assert_eq(", ".join(problems), "", "invariants broken")


func _check_invariants(
	step: int, start_owned: Dictionary, bought: Dictionary, paid: int, problems: PackedStringArray
) -> void:
	for part_id: StringName in PartCatalog.part_ids():
		var want: int = start_owned.get(part_id, 0) + bought.get(part_id, 0)
		if inventory.owned(part_id) != want:
			problems.append(
				"step %d: owned %s is %d, wanted %d"
				% [step, part_id, inventory.owned(part_id), want]
			)
		var mounted := Inventory.mounted_count(build, part_id)
		var spare := inventory.spare(build, part_id)
		if mounted + spare != inventory.owned(part_id) or spare < 0:
			problems.append(
				"step %d: %s mounted %d + spare %d is not owned" % [step, part_id, mounted, spare]
			)
	if economy.banked_scrap + paid != 200 or economy.spent != paid or not economy.is_conserved():
		problems.append("step %d: scrap not conserved" % step)
	var left := 0
	var right := 0
	for leg in build.mounted_legs():
		if leg["side"] < 0:
			left += 1
		else:
			right += 1
	if left != right:
		problems.append("step %d: legs %d left, %d right" % [step, left, right])


# --- Stat formatting --------------------------------------------------------------------------------------------


func test_every_stat_shows_its_own_number_of_decimals() -> void:
	assert_eq(StatFormat.value_text("top_speed", 4.5), "4.50")
	assert_eq(StatFormat.value_text("turn_rate", 120.0), "120")
	assert_eq(StatFormat.value_text("turn_rate", 112.74), "113")
	assert_eq(StatFormat.value_text("max_slope", 30.0), "30")
	assert_eq(StatFormat.value_text("hp", 140.0), "140")
	assert_eq(StatFormat.value_text("dps", 60.0), "60")
	assert_eq(StatFormat.value_text("spread", 1.0), "1.00")
	assert_eq(StatFormat.value_text("step_up", 0.6), "0.60")
	assert_eq(StatFormat.value_text("climb", 0.9), "0.90")
	assert_eq(StatFormat.value_text("load", 0.5645), "0.56")


func test_deltas_carry_a_sign_and_the_decimals_of_their_stat() -> void:
	assert_eq(StatFormat.delta_text("top_speed", 0.584), "+0.58")
	assert_eq(StatFormat.delta_text("turn_rate", -7.2599), "-7")
	assert_eq(StatFormat.delta_text("max_slope", -5.0), "-5")
	assert_eq(StatFormat.delta_text("spread", 0.13), "+0.13")
	for entry in StatFormat.ROWS:
		var text := StatFormat.delta_text(entry["key"], 12.3456)
		var decimals := text.length() - text.find(".") - 1 if "." in text else 0
		assert_eq(decimals, int(entry["decimals"]), "decimals of %s" % entry["key"])


func test_a_change_that_rounds_to_nothing_is_not_shown() -> void:
	assert_eq(StatFormat.delta_text("top_speed", 0.003), "")
	assert_eq(StatFormat.delta_text("turn_rate", 0.4), "")
	assert_eq(StatFormat.delta_direction("turn_rate", 0.4), 0)
	assert_eq(StatFormat.delta_quality("turn_rate", 0.4), 0)
	assert_eq(StatFormat.delta_direction("top_speed", 0.58), 1)
	assert_eq(StatFormat.delta_direction("top_speed", -0.58), -1)


func _assert_polarity(key: String, higher_is_better: bool) -> void:
	assert_eq(StatFormat.is_better(key, 1.0), higher_is_better, "%s up" % key)
	assert_eq(StatFormat.is_better(key, -1.0), not higher_is_better, "%s down" % key)
	var up_quality := 1 if higher_is_better else -1
	assert_eq(StatFormat.delta_quality(key, 1.0), up_quality, "%s up quality" % key)
	assert_eq(StatFormat.delta_quality(key, -1.0), -up_quality, "%s down quality" % key)


func test_a_higher_speed_is_better() -> void:
	_assert_polarity("top_speed", true)


func test_a_higher_turn_rate_is_better() -> void:
	_assert_polarity("turn_rate", true)


func test_a_higher_step_up_is_better() -> void:
	_assert_polarity("step_up", true)


func test_a_higher_climb_is_better() -> void:
	_assert_polarity("climb", true)


func test_a_higher_slope_grip_is_better() -> void:
	_assert_polarity("max_slope", true)


func test_more_hp_is_better() -> void:
	_assert_polarity("hp", true)


func test_more_dps_is_better() -> void:
	_assert_polarity("dps", true)


func test_a_higher_spread_is_worse() -> void:
	_assert_polarity("spread", false)


func test_a_higher_load_is_worse() -> void:
	_assert_polarity("load", false)


func test_the_polarity_table_covers_exactly_the_panel_rows() -> void:
	var keys: Array = []
	for entry in StatFormat.ROWS:
		keys.append(entry["key"])
	var table_keys: Array = StatFormat.HIGHER_IS_BETTER.keys()
	keys.sort()
	table_keys.sort()
	assert_eq(table_keys, keys)


func test_the_better_and_worse_marks_are_25_percent_luma_apart_and_not_the_threat_hue() -> void:
	assert_gte(WorkshopTheme.mark_luma_gap(), 0.25)
	var threat := Color("E8345A")
	for color: Color in [WorkshopTheme.BETTER, WorkshopTheme.WORSE]:
		var hue_gap := absf(color.h - threat.h)
		hue_gap = minf(hue_gap, 1.0 - hue_gap) * 360.0
		var message := "%s is near the threat hue" % color.to_html()
		assert_true(color.s < 0.05 or hue_gap >= 30.0, message)
	assert_lt(WorkshopTheme.WORSE.s, 0.05, "the worse mark is neutral grey")


func test_the_load_line_is_mass_over_lift() -> void:
	assert_eq(StatFormat.load_detail(BuildStats.of(WalkerBuild.scout())), "315 / 450 kg")


func test_the_load_flag_starts_above_a_load_of_one() -> void:
	assert_false(StatFormat.is_overloaded({"load": 1.0}))
	assert_true(StatFormat.is_overloaded({"load": 1.001}))
	assert_false(StatFormat.is_overloaded(BuildStats.of(WalkerBuild.scout())))


func test_every_panel_row_is_a_stat_the_build_reports() -> void:
	var stats := BuildStats.of(WalkerBuild.scout())
	for entry in StatFormat.ROWS:
		assert_true(stats.has(entry["key"]), entry["key"])


# --- Camera -----------------------------------------------------------------------------------------------------


func _camera() -> WorkshopCamera:
	var rig := WorkshopCamera.new()
	add_child_autofree(rig)
	return rig


func test_the_wheel_zooms_between_4_and_9_metres() -> void:
	var rig := _camera()
	rig.zoom(-100)
	assert_almost_eq(rig.distance, 4.0, TOL)
	rig.zoom(100)
	assert_almost_eq(rig.distance, 9.0, TOL)


func test_the_camera_orbits_8_degrees_per_second_unless_paused() -> void:
	var rig := _camera()
	var start := rig.yaw_deg
	rig._process(0.5)
	assert_almost_eq(wrapf(rig.yaw_deg - start, -180.0, 180.0), 4.0, TOL)
	rig.orbit_paused = true
	var held := rig.yaw_deg
	rig._process(1.0)
	assert_almost_eq(rig.yaw_deg, held, TOL)


func test_a_drag_turns_0_15_degrees_per_pixel_and_pitch_stays_in_range() -> void:
	var rig := _camera()
	rig.set_view(0.0, 20.0, 6.0)
	rig.orbit_by_pixels(Vector2(100.0, 0.0))
	assert_almost_eq(rig.yaw_deg, -15.0, TOL)
	rig.orbit_by_pixels(Vector2(0.0, 10000.0))
	assert_almost_eq(rig.pitch_deg, rig.pitch_max_deg, TOL)
	rig.orbit_by_pixels(Vector2(0.0, -100000.0))
	assert_almost_eq(rig.pitch_deg, rig.pitch_min_deg, TOL)


# --- Theme and layout -------------------------------------------------------------------------------------------


func test_the_smallest_text_is_at_least_14_px_at_1080p() -> void:
	assert_gte(WorkshopTheme.smallest_text_px_1080p(), 14.0)
	var theme := WorkshopTheme.build()
	var types: Array[StringName] = [
		&"Label", &"Button", &"MutedLabel", &"HeadingLabel", &"ExitButton"
	]
	for type_name in types:
		var size := theme.get_font_size("font_size", type_name)
		assert_gte(float(size) * WorkshopTheme.SCALE_TO_1080P, 14.0, str(type_name))


func _ui() -> WorkshopUI:
	var ui := WorkshopUI.new()
	add_child_autofree(ui)
	ui.setup(inventory, economy)
	ui.refresh_parts(build, &"")
	ui.show_stats(BuildStats.of(build))
	return ui


func test_the_two_panels_fit_within_40_percent_of_a_1280_wide_screen() -> void:
	var ui := _ui()
	var left_width := ui.left_panel().get_combined_minimum_size().x
	var width := left_width + ui.right_panel().get_combined_minimum_size().x
	assert_lte(width / 1280.0, 0.40)
	assert_almost_eq(ui.left_panel().get_combined_minimum_size().x, 250.0, 0.5)
	assert_almost_eq(ui.right_panel().get_combined_minimum_size().x, 250.0, 0.5)


func test_the_part_list_names_every_part_you_can_hold() -> void:
	var listed: Array[StringName] = WorkshopUI.PART_ORDER
	for part_id in PartCatalog.part_ids():
		if PartCatalog.socket_kind(part_id) == PartCatalog.KIND_CHASSIS:
			continue
		assert_true(listed.has(part_id), str(part_id))


func test_buy_buttons_show_the_price_or_how_much_is_missing() -> void:
	var ui := _ui()
	var buy_long := ui.find_control("PartBuy_leg_long") as Button
	assert_eq(buy_long.text, "Buy pair")
	assert_eq(ui.shown_price(LONG), "70 per pair")
	assert_eq(ui.shown_price(ARMOR), "50")
	assert_false(buy_long.disabled)
	var poor_economy := _economy_with(60)
	ui.setup(inventory, poor_economy)
	ui.refresh_parts(build, &"")
	assert_eq(buy_long.text, "Need 10 more")
	assert_true(buy_long.disabled)
	assert_eq((ui.find_control("PartBuy_leg_short") as Button).text, "Buy pair")
	assert_eq(ui.shown_price(LONG), "70 per pair")
	assert_eq((ui.find_control("PartBuy_leg_medium") as Button).text, "Not for sale")
	assert_true((ui.find_control("PartBuy_leg_medium") as Button).disabled)
	assert_eq(ui.shown_price(MEDIUM), "")


func test_the_stat_panel_shows_values_and_signed_deltas_with_marks() -> void:
	var ui := _ui()
	assert_eq(ui.shown_value("top_speed"), "4.50")
	assert_eq(ui.shown_load_detail(), "315 / 450 kg")
	var preview := inventory.preview(build, &"leg_l0")
	ui.show_deltas(preview["delta"], "Take off", preview["invalid_reason_after"])
	assert_eq(ui.shown_delta("hp"), "")
	assert_ne(ui.shown_delta("top_speed"), "")
	var speed_change: float = preview["delta"]["top_speed"]
	assert_eq(ui.shown_delta_direction("top_speed"), 1 if speed_change > 0.0 else -1)
	assert_eq(ui.shown_delta("top_speed").left(1), "+" if speed_change > 0.0 else "-")
	ui.clear_deltas("hint")
	assert_eq(ui.shown_delta("top_speed"), "")
	assert_eq(ui.shown_delta_direction("top_speed"), 0)


func test_the_exit_button_follows_validity_and_shows_the_reason() -> void:
	var ui := _ui()
	ui.set_exit(false, "Needs 4, 6 or 8 legs")
	assert_true(ui.exit_button().disabled)
	assert_eq(ui.exit_reason_text(), "Needs 4, 6 or 8 legs")
	ui.set_exit(true, "")
	assert_false(ui.exit_button().disabled)
	assert_eq(ui.exit_reason_text(), "")
	assert_eq(ui.exit_button().text, "Exit [Tab]")


func test_the_armed_part_row_is_marked() -> void:
	var ui := _ui()
	ui.refresh_parts(build, LONG)
	var armed_row := ui.find_control("PartRow_leg_long") as PanelContainer
	var plain_row := ui.find_control("PartRow_leg_short") as PanelContainer
	assert_eq(armed_row.theme_type_variation, WorkshopTheme.ARMED_ROW)
	assert_eq(plain_row.theme_type_variation, WorkshopTheme.PART_ROW)


func test_the_spare_reason_says_what_is_missing_for_a_part_to_be_placed() -> void:
	assert_eq(inventory.spare_reason(build, LONG), "No spare long leg: buy one")
	assert_eq(inventory.spare_reason(build, ARMOR), "No spare armor plate: buy one")
	inventory.buy(LONG, economy)
	assert_eq(inventory.spare_reason(build, LONG), "")
	build.remove(&"leg_l2")
	build.remove(&"leg_r2")
	assert_eq(inventory.spare_reason(build, MEDIUM), "")


func _buy_long_pair_and_preview() -> Dictionary:
	inventory.buy(LONG, economy)
	return inventory.preview(build, &"leg_l3", LONG)


func test_the_long_pair_preview_marks_spread_and_turn_worse_and_load_better() -> void:
	var ui := _ui()
	var preview := _buy_long_pair_and_preview()
	ui.show_deltas(preview["delta"], "Place", preview["invalid_reason_after"])
	assert_eq(ui.shown_delta_quality("spread"), -1, "spread up is worse")
	assert_eq(ui.shown_delta_quality("turn_rate"), -1, "turn down is worse")
	assert_eq(ui.shown_delta_quality("max_slope"), -1, "slope down is worse")
	assert_eq(ui.shown_delta_quality("load"), 1, "load down is better")
	assert_eq(ui.shown_delta_quality("top_speed"), 1, "speed up is better")
	assert_eq(ui.shown_delta_quality("climb"), 0, "climb follows the shortest leg")
	assert_eq(ui.shown_delta_quality("hp"), 0, "hp is unchanged")
	ui.clear_deltas("hint")
	assert_eq(ui.shown_delta_quality("spread"), 0)


func test_a_better_row_is_tinted_in_the_accent_and_a_worse_row_in_grey() -> void:
	var ui := _ui()
	var preview := _buy_long_pair_and_preview()
	ui.show_deltas(preview["delta"], "Place", preview["invalid_reason_after"])
	var better_row := ui.find_control("StatRow_top_speed") as PanelContainer
	var worse_row := ui.find_control("StatRow_spread") as PanelContainer
	var plain_row := ui.find_control("StatRow_hp") as PanelContainer
	assert_eq(better_row.theme_type_variation, WorkshopTheme.STAT_ROW_BETTER)
	assert_eq(worse_row.theme_type_variation, WorkshopTheme.STAT_ROW_WORSE)
	assert_eq(plain_row.theme_type_variation, WorkshopTheme.STAT_ROW)


func test_the_load_row_shows_an_exclamation_mark_while_load_is_above_one() -> void:
	var ui := _ui()
	assert_false(ui.load_flag_visible())
	inventory.buy(ARMOR, economy)
	inventory.unmount(build, &"leg_l2")
	inventory.mount(build, &"top_1", ARMOR)
	ui.show_stats(BuildStats.of(build))
	assert_true(ui.load_flag_visible())
	assert_eq(ui.shown_value("load"), "1.05")
	inventory.unmount(build, &"top_1")
	ui.show_stats(BuildStats.of(build))
	assert_false(ui.load_flag_visible())


func test_a_blocked_exit_pulses_its_reason_for_0_3_seconds() -> void:
	var ui := _ui()
	ui.set_exit(false, "Needs 4, 6 or 8 legs")
	assert_almost_eq(ui.reason_pulse_left(), 0.0, TOL)
	ui.pulse_reason()
	assert_almost_eq(ui.reason_pulse_left(), WorkshopUI.PULSE_TIME, TOL)
	assert_almost_eq(WorkshopUI.PULSE_TIME, 0.3, TOL)
	assert_eq(ui.reason_pulse_count(), 1)
	ui._process(0.1)
	assert_almost_eq(ui.reason_pulse_left(), 0.2, TOL)
	ui._process(0.25)
	assert_almost_eq(ui.reason_pulse_left(), 0.0, TOL)
	assert_eq(ui.reason_pulse_count(), 1)


func test_a_valid_exit_does_not_pulse_and_a_valid_build_stops_a_pulse() -> void:
	var ui := _ui()
	ui.set_exit(true, "")
	ui.pulse_reason()
	assert_eq(ui.reason_pulse_count(), 0)
	ui.set_exit(false, "Needs 4, 6 or 8 legs")
	ui.pulse_reason()
	ui.set_exit(true, "")
	assert_almost_eq(ui.reason_pulse_left(), 0.0, TOL)


func test_a_click_on_the_disabled_exit_button_is_reported() -> void:
	var ui := _ui()
	watch_signals(ui)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui.set_exit(true, "")
	ui.exit_button().gui_input.emit(click)
	assert_signal_not_emitted(ui, "exit_blocked_pressed")
	ui.set_exit(false, "Needs 4, 6 or 8 legs")
	ui.exit_button().gui_input.emit(click)
	assert_signal_emit_count(ui, "exit_blocked_pressed", 1)


func test_a_new_inventory_changes_the_owned_labels() -> void:
	var ui := _ui()
	assert_eq(ui.shown_owned(SHORT), "Own 0")
	var richer := Inventory.new({MEDIUM: 6, CANNON: 1, SHORT: 4})
	ui.setup(richer, _economy_with(55))
	ui.refresh_parts(build, &"")
	assert_eq(ui.shown_owned(SHORT), "Own 4")
	assert_eq(ui.shown_scrap(), "55")


func test_turning_the_camera_input_off_ends_a_drag_in_progress() -> void:
	var rig := _camera()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_MIDDLE
	press.pressed = true
	rig._unhandled_input(press)
	assert_true(rig.is_dragging())
	rig.input_enabled = false
	assert_false(rig.is_dragging())
	rig.input_enabled = true
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(100.0, 0.0)
	var yaw := rig.yaw_deg
	rig._input(motion)
	assert_almost_eq(rig.yaw_deg, yaw, TOL)


func test_setup_before_the_workshop_is_in_the_tree_works_and_leaves_input_on() -> void:
	var scene: PackedScene = load("res://scenes/workshop/workshop.tscn")
	var workshop := scene.instantiate() as Workshop
	workshop.setup(build, inventory, economy)
	add_child_autofree(workshop)
	assert_false(workshop.has_exited())
	assert_true(workshop.camera_rig().input_enabled)
	assert_eq(workshop.ui().shown_scrap(), "200")
	assert_eq(workshop.current_build(), build)
	assert_true(workshop.is_exit_enabled())


func test_every_top_part_carries_the_body_layer_two_frames_after_setup() -> void:
	var scene: PackedScene = load("res://scenes/workshop/workshop.tscn")
	var workshop := scene.instantiate() as Workshop
	build.place(&"top_1", ARMOR)
	workshop.setup(build, inventory, economy)
	add_child_autofree(workshop)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().process_frame
	var tops: Dictionary = workshop.walker().top_mounts()
	assert_gt(tops.size(), 0, "the build has tops")
	for piece: Node in tops.values():
		assert_true(((piece as MeshInstance3D).layers & WorkshopCamera.BODY_LAYER_MASK) != 0, str(piece.name))

