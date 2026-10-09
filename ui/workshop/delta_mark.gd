class_name DeltaMark
extends Control
## A small triangle: up for a stat that goes up, down for one that goes down. Better is a FILLED triangle in the
## accent, worse is a HOLLOW triangle in light grey, so a change reads without colour (shape and fill carry it).
## Drawn as polygons so it does not depend on a font having the up/down glyphs.

## Stroke width of the hollow mark (px at the 1280 base).
const HOLLOW_WIDTH: float = 2.0

## 1 draws an up triangle, -1 a down triangle, 0 nothing.
var direction: int = 0:
	set(value):
		direction = value
		queue_redraw()

## True: filled, in better_color. False: hollow, in worse_color.
var better: bool = true:
	set(value):
		better = value
		queue_redraw()

var better_color: Color = WorkshopTheme.BETTER
var worse_color: Color = WorkshopTheme.WORSE


func _init() -> void:
	custom_minimum_size = Vector2(14.0, 12.0)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_vertical = Control.SIZE_SHRINK_CENTER


func _draw() -> void:
	if direction == 0:
		return
	var inset := 0.0 if better else HOLLOW_WIDTH * 0.5
	var w := size.x - 2.0 * inset
	var h := size.y - 2.0 * inset
	var origin := Vector2(inset, inset)
	var points := PackedVector2Array()
	if direction > 0:
		points = PackedVector2Array([Vector2(w * 0.5, 0.0), Vector2(w, h), Vector2(0.0, h)])
	else:
		points = PackedVector2Array([Vector2(0.0, 0.0), Vector2(w, 0.0), Vector2(w * 0.5, h)])
	for i in points.size():
		points[i] += origin
	if better:
		draw_colored_polygon(points, better_color)
	else:
		points.append(points[0])
		draw_polyline(points, worse_color, HOLLOW_WIDTH, true)
