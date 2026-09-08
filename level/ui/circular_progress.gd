extends Control

var progress: float = 0.0:
	set(value):
		progress = clampf(value, 0.0, 1.0)
		queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var radius := maxf(minf(size.x, size.y) * 0.5 - 5.0, 0.0)
	var start := -PI * 0.5
	draw_arc(center, radius, start, start + TAU, 96, Color("203d48"), 5.0, true)
	if progress > 0.0:
		draw_arc(center, radius, start, start + TAU * progress, 96, Color("26fff2"), 5.0, true)
