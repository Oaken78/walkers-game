class_name DeltaMark
extends Control
## A small filled triangle: up for a stat that goes up, down for one that goes down. Drawn as a polygon so it does
## not depend on a font having the ▲/▼ glyphs.

## 1 draws ▲, -1 draws ▼, 0 draws nothing.
var direction: int = 0:
	set(value):
		direction = value
		queue_redraw()

var color: Color = Color("FF8A3D"):
	set(value):
		color = value
		queue_redraw()


func _init() -> void:
	custom_minimum_size = Vector2(14.0, 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	if direction == 0:
		return
	var w := size.x
	var h := size.y
	var points := PackedVector2Array()
	if direction > 0:
		points = PackedVector2Array([Vector2(w * 0.5, 0.0), Vector2(w, h), Vector2(0.0, h)])
	else:
		points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w * 0.5, h)])
	draw_colored_polygon(points, color)
