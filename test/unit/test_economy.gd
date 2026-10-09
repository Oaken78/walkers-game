extends GutTest
## Unit tests for scripts/economy/economy.gd and recall_hold.gd: one behaviour per test.

var eco: Economy


func before_each() -> void:
	eco = Economy.new()
	eco.register_site("R0", 0, false)
	eco.register_site("R1", 1, true)
	eco.register_site("R2", 2, true)


func test_pick_up_adds_to_carried() -> void:
	assert_true(eco.pick_up("R1", 10))
	assert_eq(eco.carried_scrap, 10)
	assert_eq(eco.banked_scrap, 0)


func test_a_node_counts_once_until_banked() -> void:
	eco.pick_up("R1", 10)
	assert_false(eco.pick_up("R1", 10))
	assert_eq(eco.carried_scrap, 10)


func test_bank_moves_carried_to_banked_and_emits() -> void:
	eco.pick_up("R2", 20)
	watch_signals(eco)
	assert_eq(eco.bank(), 20)
	assert_eq(eco.carried_scrap, 0)
	assert_eq(eco.banked_scrap, 20)
	assert_signal_emitted_with_parameters(eco, "banked", [20])


func test_bank_with_nothing_carried_still_emits() -> void:
	watch_signals(eco)
	eco.bank()
	assert_signal_emitted_with_parameters(eco, "banked", [0])


func test_ring_0_never_refills_rings_1_and_2_do() -> void:
	eco.pick_up("R0", 5)
	eco.pick_up("R1", 10)
	eco.pick_up("R2", 20)
	eco.bank()
	assert_true(eco.is_depleted("R0"))
	assert_false(eco.is_depleted("R1"))
	assert_false(eco.is_depleted("R2"))
	assert_false(eco.pick_up("R0", 5))
	assert_true(eco.pick_up("R1", 10))


func test_site_with_respawns_off_never_refills() -> void:
	eco.register_site("Odd", 2, false)
	eco.pick_up("Odd", 20)
	eco.bank()
	assert_true(eco.is_depleted("Odd"))


func test_death_turns_carried_into_the_cache() -> void:
	eco.pick_up("R1", 10)
	watch_signals(eco)
	eco.die(Vector3(1, 2, 3))
	assert_eq(eco.carried_scrap, 0)
	assert_eq(eco.cache_amount, 10)
	assert_eq(eco.cache_position, Vector3(1, 2, 3))
	assert_signal_emitted(eco, "cache_changed")


func test_death_with_nothing_carried_makes_no_cache() -> void:
	eco.die(Vector3.ZERO)
	assert_false(eco.has_cache())


func test_reclaim_returns_the_exact_amount_once() -> void:
	eco.pick_up("R2", 20)
	eco.die(Vector3.ZERO)
	assert_eq(eco.reclaim(), 20)
	assert_eq(eco.carried_scrap, 20)
	assert_eq(eco.reclaim(), 0)
	assert_eq(eco.carried_scrap, 20)


func test_a_second_death_destroys_the_old_cache() -> void:
	eco.pick_up("R2", 20)
	eco.die(Vector3.ZERO)
	eco.pick_up("R1", 10)
	eco.die(Vector3(5, 0, 0))
	assert_eq(eco.cache_amount, 10)
	assert_eq(eco.cache_position, Vector3(5, 0, 0))
	assert_eq(eco.lost, 20)
	assert_true(eco.is_conserved())


func test_a_second_death_with_nothing_carried_still_destroys_the_old_cache() -> void:
	eco.pick_up("R2", 20)
	eco.die(Vector3.ZERO)
	eco.die(Vector3(5, 0, 0))
	assert_false(eco.has_cache())
	assert_eq(eco.lost, 20)


func test_recall_drops_a_cache_like_death() -> void:
	eco.pick_up("R2", 20)
	eco.recall(Vector3(7, 0, 7))
	assert_eq(eco.cache_amount, 20)
	assert_eq(eco.cache_position, Vector3(7, 0, 7))
	assert_eq(eco.carried_scrap, 0)


func test_spend_refuses_when_short_and_takes_from_the_bank() -> void:
	eco.pick_up("R2", 20)
	eco.bank()
	assert_false(eco.can_afford(40))
	assert_false(eco.spend(40))
	assert_eq(eco.banked_scrap, 20)
	assert_true(eco.spend(15))
	assert_eq(eco.banked_scrap, 5)
	assert_eq(eco.spent, 15)
	assert_true(eco.is_conserved())


func test_carried_scrap_cannot_be_spent() -> void:
	eco.pick_up("R2", 20)
	assert_false(eco.spend(10))


func test_loose_scrap_has_no_node_and_counts_every_time() -> void:
	assert_true(eco.collect_loose(4))
	assert_true(eco.collect_loose(4))
	assert_eq(eco.carried_scrap, 8)


func test_random_sequence_of_1000_operations_conserves_scrap() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261009
	var names: Array[String] = ["R0", "R1", "R2", "R1b", "R2b"]
	eco.register_site("R1b", 1, true)
	eco.register_site("R2b", 2, true)
	for i in range(1000):
		match rng.randi_range(0, 7):
			0, 1, 2:
				eco.pick_up(names[rng.randi_range(0, names.size() - 1)], rng.randi_range(-2, 20))
			3:
				eco.bank()
			4:
				eco.die(Vector3(rng.randf(), 0.0, rng.randf()))
			5:
				eco.recall(Vector3.ZERO)
			6:
				eco.reclaim()
			7:
				eco.spend(rng.randi_range(0, 30))
		assert_true(eco.is_conserved(), "conservation broke at operation %d" % i)
		assert_true(eco.carried_scrap >= 0 and eco.banked_scrap >= 0 and eco.cache_amount >= 0)
	assert_gt(eco.total_picked_up, 0)


# --- RecallHold ------------------------------------------------------------------------------------------------


func _hold() -> RecallHold:
	var hold := RecallHold.new()
	hold.read_input = false
	add_child_autofree(hold)
	return hold


func _run(hold: RecallHold, pressed: bool, seconds: float) -> void:
	for i in range(int(round(seconds * 60.0))):
		hold.step(pressed, 1.0 / 60.0)


func test_holding_three_seconds_fires_recall() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 3.0)
	assert_signal_emit_count(hold, "recall_requested", 1)


func test_holding_less_than_three_seconds_does_not_fire() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 2.9)
	_run(hold, false, 0.1)
	assert_signal_not_emitted(hold, "recall_requested")
	assert_signal_emitted(hold, "cancelled")


func test_a_tap_under_0_3_s_is_a_tap_not_a_hold() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 0.2)
	assert_eq(hold.progress, 0.0)
	_run(hold, false, 0.1)
	assert_signal_emitted(hold, "tapped")
	assert_signal_not_emitted(hold, "cancelled")


func test_progress_rises_to_one_and_resets_on_release() -> void:
	var hold := _hold()
	_run(hold, true, 1.5)
	assert_almost_eq(hold.progress, 0.5, 0.02)
	_run(hold, false, 0.1)
	assert_eq(hold.progress, 0.0)


func test_one_hold_fires_once_and_needs_a_release_to_fire_again() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 7.0)
	assert_signal_emit_count(hold, "recall_requested", 1)
	_run(hold, false, 0.1)
	_run(hold, true, 3.0)
	assert_signal_emit_count(hold, "recall_requested", 2)


func test_holding_exactly_0_3_s_is_a_cancelled_hold_not_a_tap() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 0.3)
	_run(hold, false, 0.1)
	assert_signal_emitted(hold, "cancelled")
	assert_signal_not_emitted(hold, "tapped")


func test_a_pause_drops_the_hold_without_a_signal() -> void:
	var hold := _hold()
	watch_signals(hold)
	_run(hold, true, 1.5)
	hold.notification(Node.NOTIFICATION_PAUSED)
	assert_eq(hold.progress, 0.0)
	_run(hold, false, 0.1)
	assert_signal_not_emitted(hold, "cancelled")
	assert_signal_not_emitted(hold, "tapped")


func test_a_freed_target_does_not_break_the_recall() -> void:
	var hold := _hold()
	var body := Node3D.new()
	hold.target = body
	body.free()
	watch_signals(hold)
	_run(hold, true, 3.0)
	assert_signal_emit_count(hold, "recall_requested", 1)


func test_a_hold_a_hair_under_0_3_s_plus_epsilon_is_still_a_cancelled_hold() -> void:
	var hold := _hold()
	watch_signals(hold)
	hold.step(true, 0.3 - 0.000001)
	hold.step(false, 0.0)
	assert_signal_emitted(hold, "cancelled")
	assert_signal_not_emitted(hold, "tapped")
