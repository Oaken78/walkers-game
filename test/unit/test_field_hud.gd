extends GutTest
## FieldHud (T20): bars and labels follow the data signals, compass placement, toast queue, unbind, layout budget.

const HUD_SCENE: String = "res://ui/hud/field_hud.tscn"
const VIEWS: Array[Vector2] = [Vector2(1280, 720), Vector2(1920, 1080)]

var _hud: FieldHud
var _health: Health
var _economy: Economy
var _walker: Node3D
var _camera: Camera3D


func before_each() -> void:
	_hud = (load(HUD_SCENE) as PackedScene).instantiate() as FieldHud
	add_child_autofree(_hud)
	_health = Health.new(100.0)
	_economy = Economy.new()
	_walker = Node3D.new()
	add_child_autofree(_walker)
	_camera = Camera3D.new()
	add_child_autofree(_camera)
	_hud.bind(_health, _economy, _walker, _camera, Vector3(0, 0, -50), null)


func test_hp_bar_fraction_follows_health_changed() -> void:
	assert_almost_eq(_hud.hp_fraction, 1.0, 0.001)
	_health.damage(40.0)
	assert_almost_eq(_hud.hp_fraction, 0.6, 0.001)
	assert_eq(_hud.hp_text, "60 / 100")
	_health.set_max_hp(200.0)
	assert_almost_eq(_hud.hp_fraction, 0.6, 0.001)
	assert_eq(_hud.hp_text, "120 / 200")


func test_low_hp_turns_urgent_below_a_quarter() -> void:
	_health.damage(70.0)
	assert_false(_hud.is_low())
	_health.damage(10.0)
	assert_true(_hud.is_low())
	_health.repair_full()
	assert_false(_hud.is_low())


func test_scrap_labels_follow_economy_changed() -> void:
	_economy.collect_loose(35)
	assert_eq(_hud.carried_text, "35")
	assert_eq(_hud.banked_text, "0")
	_economy.bank()
	assert_eq(_hud.carried_text, "0")
	assert_eq(_hud.banked_text, "35")


func test_cache_mark_appears_with_a_cache_and_hides_without() -> void:
	assert_false(_hud.cache_mark_visible())
	_economy.collect_loose(20)
	_economy.die(Vector3(10, 0, 0))
	assert_true(_hud.cache_mark_visible())
	_economy.reclaim()
	assert_false(_hud.cache_mark_visible())


func test_mark_90_degrees_right_sits_at_the_strip_end() -> void:
	_economy.collect_loose(20)
	_economy.die(Vector3(30, 0, 0))
	_hud.apply_layout(VIEWS[1])
	_hud._process(0.016)
	var end_x: float = _hud.compass_x(90.0)
	assert_almost_eq(_hud.mark_x("cache"), end_x, 0.5)
	assert_almost_eq(end_x, _hud.compass_size.x - _hud.compass_pad_px(), 0.01)
	assert_almost_eq(_hud.compass_x(-200.0), _hud.compass_pad_px(), 0.01, "beyond the span pins to the left end")
	assert_almost_eq(_hud.compass_x(0.0), _hud.compass_size.x * 0.5, 0.01)


func test_bearing_is_signed_and_wraps_behind_the_camera() -> void:
	var b := Basis.IDENTITY
	assert_almost_eq(FieldHud.bearing_deg(b, Vector3.ZERO, Vector3(10, 0, 0)), 90.0, 0.01)
	assert_almost_eq(FieldHud.bearing_deg(b, Vector3.ZERO, Vector3(-10, 0, 0)), -90.0, 0.01)
	assert_almost_eq(FieldHud.bearing_deg(b, Vector3.ZERO, Vector3(0, 0, -10)), 0.0, 0.01)
	assert_almost_eq(absf(FieldHud.bearing_deg(b, Vector3.ZERO, Vector3(0, 0, 10))), 180.0, 0.01)


func test_toast_queue_shows_one_at_a_time() -> void:
	_hud.show_toast("first", 1.0)
	_hud.show_toast("second", 1.0)
	assert_eq(_hud.toast_text, "first")
	assert_eq(_hud.toast_queue_size(), 1)
	for i in 40:
		_hud._process(0.1)
		if _hud.toast_text == "second":
			break
	assert_eq(_hud.toast_text, "second")
	assert_eq(_hud.toast_queue_size(), 0)
	for i in 40:
		_hud._process(0.1)
	assert_almost_eq(_hud.toast_alpha(), 0.0, 0.001)


func test_toast_fades_in_and_out() -> void:
	_hud.show_toast("hello", 1.0)
	_hud._process(0.1)
	assert_between(_hud.toast_alpha(), 0.1, 0.9)
	_hud._process(0.5)
	assert_almost_eq(_hud.toast_alpha(), 1.0, 0.001)


func test_unbind_disconnects_every_signal() -> void:
	_hud.unbind()
	assert_eq(_health.changed.get_connections().size(), 0)
	assert_eq(_economy.changed.get_connections().size(), 0)
	assert_eq(_economy.cache_changed.get_connections().size(), 0)
	_health.damage(10.0)
	_economy.collect_loose(5)
	_hud._process(0.016)
	assert_true(true, "a null bind and later data changes raise nothing")


func test_rebind_does_not_double_connect() -> void:
	_hud.bind(_health, _economy, _walker, _camera, Vector3.ZERO, null)
	assert_eq(_health.changed.get_connections().size(), 1)
	assert_eq(_economy.cache_changed.get_connections().size(), 1)


func test_total_area_is_within_8_percent_at_both_resolutions() -> void:
	_economy.collect_loose(20)
	_economy.die(Vector3(5, 0, 0))
	_hud.set_enter_prompt(true)
	_hud.show_toast("Wreck cache: 20 scrap at 5 m", 4.0)
	_hud._process(0.016)
	_hud.recall_fraction = 0.5
	_hud._recall_plate.visible = true
	for view: Vector2 in VIEWS:
		var fraction: float = _hud.area_fraction(view)
		assert_lt(fraction, 0.08, "all elements up at %s" % view)
		gut.p("HUD area at %s: %.2f %%" % [view, fraction * 100.0])


func test_elements_keep_clear_of_aim_marks_chevron_and_the_readout() -> void:
	_hud.set_enter_prompt(true)
	_hud.show_toast("x", 4.0)
	_hud._process(0.016)
	_hud._recall_plate.visible = true
	for view: Vector2 in VIEWS:
		var s: float = view.y / 1080.0
		var centre_box := Rect2(view * 0.5, Vector2.ZERO).grow((14.0 + 40.0) * s)
		var chevron_box := Rect2(view - Vector2.ONE * (24.0 + 32.0 + 40.0) * s, Vector2.ONE * (24.0 + 32.0 + 40.0) * s)
		var readout_box := Rect2(Vector2.ZERO, Vector2(420, 160) * s)
		for r: Rect2 in _hud.element_rects(view):
			assert_false(r.intersects(centre_box), "%s hits the aim marks at %s" % [r, view])
			assert_false(r.intersects(chevron_box), "%s hits the chevron corner at %s" % [r, view])
			assert_false(r.intersects(readout_box), "%s hits the F9 readout at %s" % [r, view])


func test_every_control_ignores_the_mouse() -> void:
	for c: Control in _hud.all_controls():
		assert_eq(c.mouse_filter, Control.MOUSE_FILTER_IGNORE, "%s" % c.name)
