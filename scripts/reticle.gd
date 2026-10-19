extends Control
## Circular reticle. Anything inside the circle can be grabbed; the nearest
## grabbable point in range is the one the hook snaps to.

const RADIUS := 48.0

var color := Color(1, 1, 1, 0.5)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_CENTER)
	size = Vector2.ONE * (RADIUS * 2 + 8)
	position = -size * 0.5


func set_color(c: Color) -> void:
	if c != color:
		color = c
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_arc(c, RADIUS, 0, TAU, 64, color, 3.0, true)
	draw_circle(c, 2.5, color)
