extends GutTest
## Unit tests for the input map in project.godot: every action from GDD section 6 exists with its default binding.

# Action name -> default binding from GDD section 6. Keys are physical keycodes, mice are button indexes.
const KEY_BINDINGS: Dictionary = {
	"move_forward": KEY_W,
	"move_back": KEY_S,
	"turn_left": KEY_A,
	"turn_right": KEY_D,
	"strafe_left": KEY_Q,
	"strafe_right": KEY_E,
	"interact": KEY_F,
	"build_exit": KEY_TAB,
	"pause": KEY_ESCAPE,
}
const MOUSE_BINDINGS: Dictionary = {
	"fire": MOUSE_BUTTON_LEFT,
	"aim": MOUSE_BUTTON_RIGHT,
	"zoom_in": MOUSE_BUTTON_WHEEL_UP,
	"zoom_out": MOUSE_BUTTON_WHEEL_DOWN,
	"build_place": MOUSE_BUTTON_LEFT,
	"build_remove": MOUSE_BUTTON_RIGHT,
}


func test_every_key_action_is_bound_to_its_gdd_key() -> void:
	for action: String in KEY_BINDINGS:
		var key_event := _first_event(action) as InputEventKey
		assert_not_null(key_event, "no key event on " + action)
		if key_event:
			assert_eq(key_event.physical_keycode, KEY_BINDINGS[action], "wrong key on " + action)


func test_every_mouse_action_is_bound_to_its_gdd_button() -> void:
	for action: String in MOUSE_BINDINGS:
		var mouse_event := _first_event(action) as InputEventMouseButton
		assert_not_null(mouse_event, "no mouse event on " + action)
		if mouse_event:
			assert_eq(mouse_event.button_index, MOUSE_BINDINGS[action], "wrong button on " + action)


func _first_event(action: String) -> InputEvent:
	if not InputMap.has_action(action) or InputMap.action_get_events(action).is_empty():
		return null
	return InputMap.action_get_events(action)[0]
