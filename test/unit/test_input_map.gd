extends GutTest
## Unit tests for the input map in project.godot: every action name from GDD section 6 exists and is bound.

const GDD_ACTIONS: Array[String] = [
	"move_forward",
	"move_back",
	"turn_left",
	"turn_right",
	"strafe_left",
	"strafe_right",
	"fire",
	"aim",
	"interact",
	"zoom_in",
	"zoom_out",
	"build_place",
	"build_remove",
	"build_exit",
	"pause",
]


func test_every_gdd_action_exists_with_at_least_one_event() -> void:
	for action in GDD_ACTIONS:
		assert_true(InputMap.has_action(action), "missing action " + action)
		if InputMap.has_action(action):
			assert_gt(InputMap.action_get_events(action).size(), 0, "unbound action " + action)
