class_name JudgmentPipeline
extends RefCounted

const BOUNDARY_EPSILON_SEC := 0.0000005

var perfect_window_sec := 0.025
var early_window_sec := 0.050
var late_window_sec := 0.100


func configure(perfect: float, early: float, late: float) -> void:
	perfect_window_sec = maxf(perfect, 0.0)
	early_window_sec = maxf(early, perfect_window_sec)
	late_window_sec = maxf(late, perfect_window_sec)


func evaluate(input_time_sec: float, center_time_sec: float, visual_contact_sec: float = NAN) -> Dictionary:
	var delta := input_time_sec - center_time_sec
	var result := classify_delta(delta)
	var contact := center_time_sec if is_nan(visual_contact_sec) else visual_contact_sec
	return {
		"input_time_sec": input_time_sec,
		"center_time_sec": center_time_sec,
		"delta_sec": delta,
		"delta_ms": delta * 1000.0,
		"result": result,
		"defer_until_contact": should_defer(input_time_sec - contact, result),
		"advance_note": result != "Too Fast",
	}


func classify_delta(delta_sec: float) -> String:
	if delta_sec < -early_window_sec - BOUNDARY_EPSILON_SEC:
		return "Too Fast"
	if delta_sec < -perfect_window_sec - BOUNDARY_EPSILON_SEC:
		return "Fast"
	if delta_sec <= perfect_window_sec + BOUNDARY_EPSILON_SEC:
		return "Perfect"
	if delta_sec <= late_window_sec + BOUNDARY_EPSILON_SEC:
		return "Slow"
	return "Too Slow"


func is_miss_due(current_time_sec: float, center_time_sec: float) -> bool:
	return current_time_sec > center_time_sec + late_window_sec + BOUNDARY_EPSILON_SEC


func should_defer(delta_sec: float, result: String) -> bool:
	return delta_sec < 0.0 and result != "Too Fast" and result != "Too Slow"


func overdue_count(centers: PackedFloat32Array, start_index: int, current_time_sec: float) -> int:
	var count := 0
	for index in range(maxi(start_index, 0), centers.size()):
		if not is_miss_due(current_time_sec, centers[index]):
			break
		count += 1
	return count
