extends Control
## Circular reticle. Anything inside the circle can be grabbed; the nearest
## grabbable point in range is the one the hook snaps to.

const RADIUS := 48.0

var color := Color(1, 1, 1, 0.5)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var half := RADIUS + 4.0
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -half
	offset_right = half
	offset_top = -half
	offset_bottom = half


func set_color(c: Color) -> void:
	if c != color:
		color = c
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, RADIUS, 0, TAU, 64, color, 3.0, true)
	draw_circle(c, 2.5, color)
