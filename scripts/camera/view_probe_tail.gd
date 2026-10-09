extends Node
## T17: runs after every other _process (priority 1000) and tells the ViewProbe where the frame's script work ended.

func _ready() -> void:
	process_priority = 1000


func _process(_delta: float) -> void:
	get_parent().get_node("ViewProbe").mark_process_end()
