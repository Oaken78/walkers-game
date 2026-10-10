extends GutTest
## GameFlow: who may do what when, the timers and the ledger calls of a trip home (T12).

const DT: float = 1.0 / 60.0

var economy: Economy
var flow: GameFlow
var arrivals: Array = []


func before_each() -> void:
	economy = Economy.new()
	flow = GameFlow.new(economy)
	arrivals = []
	flow.arrived_home.connect(func(kind: int, amount: int, _at: Vector3) -> void: arrivals.append([kind, amount]))


func _run(seconds: float) -> void:
	for i in int(round(seconds * 60.0)):
		flow.tick(DT)


func _to_field() -> void:
	assert_true(flow.request_exit(true))


func test_boots_in_the_workshop() -> void:
	assert_eq(flow.state, GameFlow.State.WORKSHOP)
	assert_eq(flow.fade_alpha(), 0.0)


func test_exit_needs_a_valid_build() -> void:
	assert_false(flow.request_exit(false))
	assert_eq(flow.state, GameFlow.State.WORKSHOP)
	assert_true(flow.request_exit(true))
	assert_eq(flow.state, GameFlow.State.FIELD)


func test_exit_is_refused_outside_the_workshop() -> void:
	_to_field()
	assert_false(flow.request_exit(true))


func test_enter_only_within_4_m_of_the_bench() -> void:
	_to_field()
	assert_false(flow.request_enter(4.01))
	assert_eq(flow.state, GameFlow.State.FIELD)
	assert_true(flow.request_enter(4.0))
	assert_eq(flow.state, GameFlow.State.FADING_OUT)


func test_enter_banks_after_a_half_second_fade() -> void:
	_to_field()
	economy.pick_up("a", 12)
	flow.request_enter(2.0)
	_run(0.4)
	assert_eq(economy.carried_scrap, 12, "not banked yet")
	_run(0.2)
	assert_eq(economy.banked_scrap, 12)
	assert_eq(flow.state, GameFlow.State.WORKSHOP)
	assert_eq(arrivals, [[GameFlow.Kind.ENTER, 0]])


func test_bank_signal_fires_for_zero_carried() -> void:
	var banked: Array = []
	economy.banked.connect(func(amount: int) -> void: banked.append(amount))
	_to_field()
	flow.request_enter(1.0)
	_run(0.6)
	assert_eq(banked, [0])


func test_death_collapses_one_second_fades_then_drops_the_cache() -> void:
	_to_field()
	economy.pick_up("a", 20)
	var started: Array = [0]
	flow.collapse_started.connect(func() -> void: started[0] += 1)
	assert_true(flow.request_death(Vector3(5, 0, 9)))
	assert_eq(started[0], 1)
	assert_eq(flow.state, GameFlow.State.COLLAPSING)
	_run(0.9)
	assert_eq(flow.state, GameFlow.State.COLLAPSING)
	_run(0.2)
	assert_eq(flow.state, GameFlow.State.FADING_OUT)
	assert_eq(economy.cache_amount, 0, "the ledger waits for the black")
	_run(0.5)
	assert_eq(flow.state, GameFlow.State.WORKSHOP)
	assert_eq(economy.cache_amount, 20)
	assert_eq(economy.cache_position, Vector3(5, 0, 9))
	assert_eq(economy.carried_scrap, 0)
	assert_eq(arrivals, [[GameFlow.Kind.DEATH, 20]])
	assert_true(economy.is_conserved())


func test_recall_has_no_collapse() -> void:
	_to_field()
	economy.pick_up("a", 10)
	assert_true(flow.request_recall(Vector3(1, 0, 2)))
	assert_eq(flow.state, GameFlow.State.FADING_OUT)
	_run(0.6)
	assert_eq(economy.cache_amount, 10)
	assert_eq(arrivals, [[GameFlow.Kind.RECALL, 10]])


func test_second_death_before_reclaiming_destroys_the_cache() -> void:
	_to_field()
	economy.pick_up("a", 20)
	flow.request_death(Vector3.ZERO)
	_run(2.0)
	_to_field()
	economy.pick_up("b", 7)
	flow.request_death(Vector3(3, 0, 3))
	_run(2.0)
	assert_eq(economy.cache_amount, 7)
	assert_eq(economy.lost, 20)
	assert_true(economy.is_conserved())


func test_no_transition_while_busy() -> void:
	_to_field()
	flow.request_death(Vector3.ZERO)
	assert_false(flow.request_death(Vector3.ONE), "a dying walker dies once")
	assert_false(flow.request_recall(Vector3.ZERO))
	assert_false(flow.request_enter(0.0))
	assert_false(flow.request_exit(true))
	_run(1.1)
	assert_eq(flow.state, GameFlow.State.FADING_OUT)
	assert_false(flow.request_death(Vector3.ONE))
	assert_false(flow.request_recall(Vector3.ZERO))
	assert_false(flow.request_enter(0.0))


func test_fade_goes_up_then_down() -> void:
	_to_field()
	flow.request_recall(Vector3.ZERO)
	_run(0.25)
	assert_almost_eq(flow.fade_alpha(), 0.5, 0.05)
	_run(0.26)
	assert_eq(flow.state, GameFlow.State.WORKSHOP)
	assert_almost_eq(flow.fade_alpha(), 1.0, 0.05, "black on arrival")
	_run(0.5)
	assert_eq(flow.fade_alpha(), 0.0)
