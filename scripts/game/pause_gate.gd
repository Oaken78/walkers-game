class_name PauseGate
extends Node
## Esc (the `pause` action) pauses the tree and Esc again resumes it. This node keeps running while the tree is paused
## (PROCESS_MODE_ALWAYS), so it is the one place that can see the second Esc. A plain "Paused" label shows meanwhile.

signal pause_changed(paused: bool)

## Nothing pauses while this is false (during a death or a fade the screen is not the player's to stop).
var allowed: bool = true

@onready var _panel: Control = get_node_or_null("%PausePanel") as Control


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	if _panel != null:
		_panel.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"pause"):
		if get_tree().paused:
			set_paused(false)
			get_viewport().set_input_as_handled()
		elif allowed:
			set_paused(true)
			get_viewport().set_input_as_handled()


func set_paused(value: bool) -> void:
	if get_tree().paused == value:
		return
	get_tree().paused = value
	if _panel != null:
		_panel.visible = value
	pause_changed.emit(value)
