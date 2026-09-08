extends Node

const PlayInputScript = preload("res://main/play_input.gd")
const RhythmClockScript = preload("res://level/timing/rhythm_clock.gd")
const TimingTraceScript = preload("res://level/timing/timing_trace.gd")
const JudgmentPipelineScript = preload("res://level/timing/judgment_pipeline.gd")

signal judged(result: String, polygon_index: int, timing_delta_ms: float)

# The judgment center matches the visual moment when the polygon edges meet.
@export var perfect_window_sec: float = 0.025
@export var early_window_sec: float = 0.050
@export var late_window_sec: float = 0.100
@export var judgment_offset_sec: float = 0.0
@export var detailed_timing_logs: bool = true

@onready var rotator: Node = $"../Rotator"

var paused: bool = true
var scheduled_judgment_times: PackedFloat32Array = PackedFloat32Array()
var game_time: float = 0.0
# Judgment ownership is independent of the polygon waiting to be displayed.
var _next_note_index := 0
var _resolved_notes: Dictionary = {}
var _presentation_finished := false
var _pause_reasons: Dictionary = {}
var _clock = RhythmClockScript.new()
var timing_trace = TimingTraceScript.new()
var _judgment_pipeline = JudgmentPipelineScript.new()
var _observed_contact_times: Dictionary = {}
var audio_player: Node
var audio_start_offset_sec := 0.0
var audio_drift_sec := 0.0
# Tests can provide a deterministic microsecond clock; gameplay uses the engine clock.
var time_source_usec: Callable


func setup(scheduled_times: PackedFloat32Array) -> void:
	scheduled_judgment_times = scheduled_times
	game_time = 0.0
	paused = true
	_next_note_index = 0
	_resolved_notes.clear()
	_presentation_finished = false
	_pause_reasons.clear()
	_sync_clock_source()
	_clock.reset()
	timing_trace.clear()
	_sync_judgment_pipeline()
	_observed_contact_times.clear()
	audio_drift_sec = 0.0
	if rotator != null:
		rotator.clock_driven = true
		rotator.paused = true
		_sync_visual()
	if detailed_timing_logs:
		print(
			"[TIMING_SETUP] notes=%d perfect_ms=%.1f early_ms=%.1f late_ms=%.1f judgment_offset_ms=%.1f"
			% [scheduled_judgment_times.size(), perfect_window_sec * 1000.0, early_window_sec * 1000.0, late_window_sec * 1000.0, judgment_offset_sec * 1000.0],
		)


func start() -> void:
	game_time = 0.0
	_sync_clock_source()
	_clock.start()
	_pause_reasons.clear()
	paused = false
	if rotator != null:
		rotator.paused = false
	_sync_visual()
	if detailed_timing_logs:
		print("[TIMING_START] clock_usec=%d" % _clock.start_usec)


func pause_clock(reason: StringName = &"manual") -> void:
	_pause_reasons[reason] = true
	if paused:
		return
	_clock.pause()
	game_time = _get_game_time()
	_sync_visual()
	paused = true
	if rotator != null:
		rotator.paused = true


func resume_clock(reason: StringName = &"manual") -> void:
	_pause_reasons.erase(reason)
	if not _clock.running or not _pause_reasons.is_empty():
		return
	_clock.resume()
	paused = false
	if rotator != null:
		rotator.paused = false


func _process(_delta: float) -> void:
	if paused or rotator == null or rotator.is_completed():
		return
	game_time = _get_game_time()
	_sample_audio_drift()
	_update_timing()


func _unhandled_input(event: InputEvent) -> void:
	if paused or rotator == null or rotator.is_completed():
		return
	var input_manager := get_node_or_null("/root/InputDeviceManager")
	var gamepad_input := bool(input_manager.call("is_play_input", event)) if input_manager != null else false
	if not (PlayInputScript.is_pressed(event) or gamepad_input):
		return
	# Expire older notes before assigning this input, even between render frames.
	game_time = _get_game_time()
	_update_timing()
	if paused or _next_note_index >= scheduled_judgment_times.size():
		return
	var index := _next_note_index
	var contact: float = scheduled_judgment_times[index]
	var center := get_judgment_time(contact)
	_sync_judgment_pipeline()
	var evaluation: Dictionary = _judgment_pipeline.evaluate(game_time, center, contact)
	var timing_delta: float = evaluation["delta_sec"]
	var result: String = evaluation["result"]
	_record_input_trace(event, index, contact, center, timing_delta, result)
	_log_input_timing(index, contact, center, timing_delta, result)
	if result == "Too Fast":
		_emit_result(result, index, timing_delta)
	else:
		_queue_result(result, timing_delta)
		_flush_resolved_notes()


func _update_timing() -> void:
	_sync_visual()
	_flush_resolved_notes()
	while not paused and _next_note_index < scheduled_judgment_times.size():
		var center := _current_judgment_center()
		if not is_miss_due(game_time, center):
			break
		_queue_result("Too Slow", game_time - center)
		_flush_resolved_notes()


func _queue_result(result: String, timing_delta: float) -> void:
	_resolved_notes[_next_note_index] = {"result": result, "delta": timing_delta}
	_next_note_index += 1


func _flush_resolved_notes() -> void:
	while not paused and not rotator.is_completed():
		if _presentation_finished:
			_presentation_finished = false
			rotator.advance_to_next()
			_sync_visual()
			continue
		var index: int = rotator.current_index
		if not _resolved_notes.has(index) or game_time < scheduled_judgment_times[index]:
			break
		var resolved: Dictionary = _resolved_notes[index]
		_resolved_notes.erase(index)
		rotator.snap_to_target()
		_presentation_finished = true
		_emit_result(resolved["result"], index, resolved["delta"])
		# A judgment signal can synchronously end or pause the run.
		if paused:
			return


func _sync_visual() -> void:
	if rotator == null or rotator.is_completed():
		return
	var index: int = rotator.current_index
	if index >= scheduled_judgment_times.size():
		return
	var start_time: float = scheduled_judgment_times[index - 1] if index > 0 else 0.0
	var contact: float = scheduled_judgment_times[index]
	rotator.sample_timeline(game_time, start_time, contact)
	if game_time >= contact and not _observed_contact_times.has(index):
		# This is a diagnostic observation, never a replacement judgment center.
		_observed_contact_times[index] = game_time


func classify_timing_delta(timing_delta: float) -> String:
	_sync_judgment_pipeline()
	return _judgment_pipeline.classify_delta(timing_delta)


func is_miss_due(current_time: float, scheduled_time: float) -> bool:
	_sync_judgment_pipeline()
	return _judgment_pipeline.is_miss_due(current_time, scheduled_time)


func get_judgment_time(visual_landing_time: float) -> float:
	return visual_landing_time + judgment_offset_sec


func should_defer_judgment(timing_delta: float, result: String) -> bool:
	_sync_judgment_pipeline()
	return _judgment_pipeline.should_defer(timing_delta, result)


func _sync_judgment_pipeline() -> void:
	_judgment_pipeline.configure(perfect_window_sec, early_window_sec, late_window_sec)


func _get_game_time() -> float:
	_sync_clock_source()
	return _clock.elapsed_sec()


func _now_usec() -> int:
	_sync_clock_source()
	return _clock.now_usec()


func _sync_clock_source() -> void:
	_clock.time_source_usec = time_source_usec


func set_audio_reference(player: Node, start_offset_sec: float = 0.0) -> void:
	audio_player = player
	audio_start_offset_sec = maxf(start_offset_sec, 0.0)


func save_timing_trace(path: String, metadata: Dictionary = {}) -> Error:
	return timing_trace.save_json(path, metadata)


func _sample_audio_drift() -> void:
	if audio_player == null or not audio_player.has_method(&"get_playback_position"):
		return
	if not bool(audio_player.get("playing")) or bool(audio_player.get("stream_paused")):
		return
	# Raw playback position is telemetry; mixer updates must not move note clocks.
	var relative_audio_sec := float(audio_player.call("get_playback_position")) - audio_start_offset_sec
	audio_drift_sec = relative_audio_sec - game_time


func _emit_result(result: String, polygon_index: int, timing_delta: float = 0.0) -> void:
	if detailed_timing_logs:
		var visual_time := scheduled_judgment_times[polygon_index] if polygon_index < scheduled_judgment_times.size() else 0.0
		print(
			"[JUDGMENT] polygon=%d result=%s game_ms=%.3f visual_delta_ms=%+.3f judgment_delta_ms=%+.3f"
			% [polygon_index + 1, result, game_time * 1000.0, (game_time - visual_time) * 1000.0, timing_delta * 1000.0],
		)
	judged.emit(result, polygon_index, timing_delta * 1000.0)


func _log_input_timing(index: int, visual_time: float, judgment_time: float, timing_delta: float, result: String) -> void:
	if not detailed_timing_logs:
		return
	var gap := _rotator_float(&"get_entrance_edge_gap", INF)
	var transition_elapsed := _rotator_float(&"get_transition_elapsed", 0.0)
	var transition_progress := _rotator_float(&"get_transition_progress", 0.0)
	var offset: Vector2 = rotator.get_current_offset() if rotator.has_method(&"get_current_offset") else Vector2.ZERO
	var alignment_deg := rad_to_deg(rotator.get_alignment_delta()) if rotator.has_method(&"get_alignment_delta") else 0.0
	print(
		"[TIMING_INPUT] polygon=%d result=%s game_ms=%.3f visual_ms=%.3f judgment_ms=%.3f visual_delta_ms=%+.3f judgment_delta_ms=%+.3f edge_gap_px=%.3f offset_px=(%.3f,%.3f) offset_length_px=%.3f angle_deg=%.3f alignment_deg=%+.3f transition_ms=%.3f progress=%.4f"
		% [index + 1, result, game_time * 1000.0, visual_time * 1000.0, judgment_time * 1000.0, (game_time - visual_time) * 1000.0, timing_delta * 1000.0, gap, offset.x, offset.y, offset.length(), rad_to_deg(rotator.angle), alignment_deg, transition_elapsed * 1000.0, transition_progress],
	)


func _rotator_float(method: StringName, fallback: float) -> float:
	if rotator != null and rotator.has_method(method):
		return float(rotator.call(method))
	return fallback


func _record_input_trace(
	event: InputEvent,
	index: int,
	visual_time: float,
	judgment_time: float,
	timing_delta: float,
	result: String,
) -> void:
	var observed_contact := float(_observed_contact_times[index]) if _observed_contact_times.has(index) else visual_time
	timing_trace.record_input({
		"event_received_usec": _now_usec(),
		"device": _input_device_name(event),
		"polygon_index": index,
		"game_time_sec": game_time,
		"visual_contact_sec": visual_time,
		"observed_contact_sec": observed_contact,
		"contact_observed": _observed_contact_times.has(index),
		"visual_polygon_index": rotator.current_index,
		"judgment_center_sec": judgment_time,
		"judgment_offset_ms": judgment_offset_sec * 1000.0,
		"timing_delta_ms": timing_delta * 1000.0,
		"result": result,
		"perfect_window_ms": perfect_window_sec * 1000.0,
		"early_window_ms": early_window_sec * 1000.0,
		"late_window_ms": late_window_sec * 1000.0,
		"fps": Engine.get_frames_per_second(),
		"frame_time_ms": get_process_delta_time() * 1000.0,
	})


func _input_device_name(event: InputEvent) -> String:
	if event is InputEventJoypadButton or event is InputEventJoypadMotion:
		return "gamepad"
	if event is InputEventMouseButton:
		return "mouse"
	if event is InputEventKey:
		return "keyboard"
	return "unknown"


func _current_judgment_center() -> float:
	if _next_note_index >= scheduled_judgment_times.size():
		return INF
	return get_judgment_time(scheduled_judgment_times[_next_note_index])
