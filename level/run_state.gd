class_name RunState
extends RefCounted

signal changed(snapshot: Dictionary)
signal failed

const START_GAUGE := 70.0
const JUDGMENTS := ["Perfect", "Fast", "Slow", "Too Slow"]

var total_notes: int = 0
var score: int = 0
var combo: int = 0
var max_combo: int = 0
var gauge: float = START_GAUGE
var resolved_notes: int = 0
var accuracy_points: float = 0.0
var judgments: Dictionary = {}
var timing_samples_ms: Array[float] = []
var early_inputs: int = 0
var _early_penalized: Dictionary = {}
var _failed: bool = false


func setup(note_count: int) -> void:
	total_notes = maxi(note_count, 0)
	score = 0
	combo = 0
	max_combo = 0
	gauge = START_GAUGE
	resolved_notes = 0
	accuracy_points = 0.0
	judgments.clear()
	timing_samples_ms.clear()
	early_inputs = 0
	for result in JUDGMENTS:
		judgments[result] = 0
	_early_penalized.clear()
	_failed = false
	changed.emit(snapshot())


func apply_judgment(result: String, polygon_index: int, timing_delta_ms: float = 0.0) -> void:
	if _failed:
		return
	if result == "Too Fast":
		if not _early_penalized.has(polygon_index):
			_early_penalized[polygon_index] = true
			early_inputs += 1
			gauge = maxf(0.0, gauge - 3.0)
			_emit_change()
		return
	if not judgments.has(result):
		return
	judgments[result] += 1
	timing_samples_ms.append(timing_delta_ms)
	resolved_notes += 1
	match result:
		"Perfect":
			score += 1000
			accuracy_points += 1.0
			combo += 1
			gauge = minf(100.0, gauge + 2.0)
		"Fast", "Slow":
			score += 700
			accuracy_points += 0.7
			combo += 1
			gauge = minf(100.0, gauge + 1.0)
		"Too Slow":
			combo = 0
			gauge = maxf(0.0, gauge - 12.0)
	max_combo = maxi(max_combo, combo)
	_emit_change()


func accuracy() -> float:
	if resolved_notes <= 0:
		return 0.0
	return accuracy_points / resolved_notes * 100.0


func rank(completed: bool = true) -> String:
	if not completed or _failed:
		return "F"
	var value := accuracy()
	if value >= 95.0:
		return "S"
	if value >= 85.0:
		return "A"
	if value >= 70.0:
		return "B"
	if value >= 55.0:
		return "C"
	return "D"


func average_offset_ms() -> float:
	if timing_samples_ms.is_empty():
		return 0.0
	var total := 0.0
	for sample in timing_samples_ms:
		total += sample
	return total / timing_samples_ms.size()


func mean_absolute_error_ms() -> float:
	if timing_samples_ms.is_empty():
		return 0.0
	var total := 0.0
	for sample in timing_samples_ms:
		total += absf(sample)
	return total / timing_samples_ms.size()


func snapshot() -> Dictionary:
	return {
		"score": score,
		"combo": combo,
		"max_combo": max_combo,
		"gauge": gauge,
		"resolved": resolved_notes,
		"total": total_notes,
		"accuracy": accuracy(),
		"judgments": judgments.duplicate(),
		"average_offset_ms": average_offset_ms(),
		"mean_absolute_error_ms": mean_absolute_error_ms(),
		"early_inputs": early_inputs,
	}


func _emit_change() -> void:
	changed.emit(snapshot())
	if gauge <= 0.0 and not _failed:
		_failed = true
		failed.emit()
