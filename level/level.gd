extends Node2D

const PolygonChain = preload("res://level/geometry/polygon_chain.gd")
const RunStateScript = preload("res://level/run_state.gd")
const ProgressStoreScript = preload("res://level/progress_store.gd")
const SettingsStoreScript = preload("res://main/settings_store.gd")
const LevelDataScript = preload("res://level/data/level_data.gd")
const StageCatalogScript = preload("res://level/data/stage_catalog.gd")
const AudioStreamLoaderScript = preload("res://level/audio/audio_stream_loader.gd")
const LevelEventSystemScript = preload("res://level/events/level_event_system.gd")
const EventHandlerRegistryScript = preload("res://level/events/event_handler_registry.gd")
const NoteTimelineScript = preload("res://level/timing/note_timeline.gd")
const LevelResultServiceScript = preload("res://level/level_result_service.gd")
const EVENT_GUARD := "boss_guard"
const EVENT_SAMURAI := "samurai_split"
const EVENT_TIME_STOP := "time_stop"
const MAIN_SCENE := "res://main/main_screen.tscn"
const EDITOR_SCENE := "res://editor/level_editor.tscn"
const NEON_PALETTE := [
	Color("20e3df"),
	Color("348cff"),
	Color("7657ff"),
	Color("c14cff"),
	Color("f044a7"),
	Color("35d6a0"),
]

signal level_finished(stats: Dictionary, completed: bool, rank: String)

@export var side_length: float = 100.0
@export var base_midpoint := Vector2(500, 600)
@export var outline_width: float = 2.0
@export_range(1, 20, 1) var fully_visible_past_polygons: int = 10
@export_range(2, 30, 1) var past_polygon_trail_length: int = 14
@export_range(0.0, 1.0) var starter_triangle_alpha: float = 0.32
@export_range(0.0, 1.0) var current_fill_alpha: float = 0.86
@export_range(0.0, 1.0) var inner_highlight_alpha: float = 0.24
@export var polygon_glow_width: float = 11.0
@export_range(0.0, 0.2) var landing_pulse_scale: float = 0.06
@export var fly_in_distance: float = 260.0
@export var transition_duration: float = 0.32
@export var spawn_fade_duration: float = 0.35
@export var shared_edge_color := Color(0.15, 1.0, 0.95, 1.0)
@export var shared_edge_width: float = 5.0
@export var shared_edge_glow_width: float = 15.0
@export var timing_trace_path: String = "user://timing/latest_run.json"

@onready var rotator: Node2D = $Rotator
@onready var conductor: Node = $Conductor
@onready var camera: Camera2D = $Camera
@onready var countdown: CanvasLayer = $CountdownOverlay
@onready var judgement: CanvasLayer = $JudgementOverlay
@onready var music: AudioStreamPlayer2D = $AudioStreamPlayer2D
@onready var pause_overlay: CanvasLayer = $PauseOverlay
@onready var dialogue_overlay: CanvasLayer = $DialogueOverlay
@onready var gameplay_hud: CanvasLayer = $GameplayHUD
@onready var result_overlay: CanvasLayer = $ResultOverlay
@onready var timing_debug_overlay: CanvasLayer = $TimingDebugOverlay

var _shapes: Array[PackedVector2Array] = []
var _starter_triangle: PackedVector2Array = PackedVector2Array()
var _polygon_centers: PackedVector2Array = PackedVector2Array()
var _sides_counts: PackedInt32Array = PackedInt32Array()
var _current_index: int = 0
var _tutorial_preview_active: bool = false
var _run_state: RunState = RunStateScript.new()
var _level_ended: bool = false
var _level_sequence: Array[int] = []
var _boss_health: int = 0
var _time_stopped := false
var _note_timeline
var _event_system: LevelEventSystem = LevelEventSystemScript.new()
var level_data: LevelData
var _is_custom_level := false
var _active_dialogue_id := ""
var _previous_judgment_result := ""


func _ready() -> void:
	var data_path: String = ProgressStoreScript.custom_level_path
	_is_custom_level = not data_path.is_empty()
	if data_path.is_empty():
		data_path = StageCatalogScript.data_path(ProgressStoreScript.selected_stage)
	level_data = LevelDataScript.from_yaml(data_path)
	$BackgroundLayer/Background.setup(StageCatalogScript.DEFAULT_STAGE if _is_custom_level else ProgressStoreScript.selected_stage)
	for unknown_event in EventHandlerRegistryScript.unknown_event_names(level_data.events):
		push_warning("Unknown level event ignored at runtime: %s" % unknown_event)
	_event_system.setup(level_data.events)
	_level_sequence = _event_system.transform_sequence(level_data.expanded_sequence())
	music.stream = AudioStreamLoaderScript.load_stream(level_data.music_path)
	if music.stream == null:
		push_error("Level music not found: %s" % level_data.music_path)
	var factory := ShapeFactory.new()
	var factory_result := factory.build(_level_sequence, side_length, base_midpoint)
	_shapes = factory_result["shapes"]
	var base_half_offset := Vector2(side_length / 2.0, 0.0)
	# Reverse the first polygon's base edge so the fixed triangle sits on the opposite side.
	_starter_triangle = factory.build_polygon_on_edge(
		3,
		base_midpoint + base_half_offset,
		base_midpoint - base_half_offset,
	)
	_polygon_centers = factory_result["polygon_centers"]
	_sides_counts = factory_result["sides_counts"]
	var chain_result := PolygonChain.new().build(
		_shapes,
		_polygon_centers,
		factory_result["exit_edges"],
		factory_result["exit_edge_local_indices"],
	)
	var start_offsets := _compute_start_offsets()
	rotator.setup(
		_shapes,
		_polygon_centers,
		_sides_counts,
		chain_result["entrance_edges_world"],
		chain_result["exit_angle_offsets"],
		start_offsets,
		transition_duration,
	)
	var game_settings := SettingsStoreScript.load_settings()
	conductor.judgment_offset_sec = float(game_settings["timing_offset_ms"]) / 1000.0
	_note_timeline = NoteTimelineScript.build(
		_level_sequence,
		level_data.bpm,
		conductor.perfect_window_sec,
		conductor.early_window_sec,
		conductor.late_window_sec,
		conductor.judgment_offset_sec,
		level_data.note_times_sec,
	)
	conductor.setup(_note_timeline.contact_times())
	conductor.set_audio_reference(music, level_data.music_start_offset_sec)
	timing_debug_overlay.set_sources(conductor, rotator, music, _note_timeline)
	camera.setup(rotator, _polygon_centers)
	rotator.polygon_advanced.connect(_on_polygon_advanced)
	if conductor != null:
		conductor.judged.connect(_on_judged)
	_run_state.changed.connect(_on_stats_changed)
	_run_state.failed.connect(_on_run_failed)
	_run_state.experience_mode = bool(game_settings["experience_mode"])
	_run_state.setup(_level_sequence.size())
	_boss_health = level_data.boss_health
	gameplay_hud.setup_boss(level_data.boss_name, _boss_health, _event_system.has_event(EVENT_SAMURAI), _event_system.has_event(EVENT_TIME_STOP))
	if countdown != null:
		countdown.countdown_finished.connect(_on_countdown_finished)
	if pause_overlay != null:
		pause_overlay.resume_requested.connect(_set_game_paused.bind(false))
		pause_overlay.restart_requested.connect(_restart_level_from_pause)
		pause_overlay.exit_requested.connect(_return_to_main_from_pause)
		pause_overlay.timing_offset_changed.connect(_set_judgment_offset)
		pause_overlay.set_exit_visible(true)
	if dialogue_overlay != null:
		dialogue_overlay.dialogue_finished.connect(_on_dialogue_finished)
	if result_overlay != null:
		result_overlay.retry_requested.connect(_retry_level)
		result_overlay.stage_select_requested.connect(_return_to_stage_select)
	var skip_seen_dialogue := bool(game_settings["skip_seen_dialogue"])
	_active_dialogue_id = "stage_%d_tutorial" % ProgressStoreScript.selected_stage if not _is_custom_level else ""
	var dialogue_was_seen := ProgressStoreScript.has_seen_dialogue(_active_dialogue_id)
	if not level_data.tutorial_lines.is_empty() and not (skip_seen_dialogue and dialogue_was_seen):
		_tutorial_preview_active = true
		rotator.snap_to_target()
		dialogue_overlay.play(level_data.tutorial_lines, level_data.tutorial_speaker)
	else:
		_start_countdown()
	queue_redraw()
	set_process(false)


func _start_countdown() -> void:
	if _tutorial_preview_active:
		_tutorial_preview_active = false
		rotator.restart_current_transition()
	if countdown != null:
		countdown.play()


func _on_dialogue_finished() -> void:
	ProgressStoreScript.mark_dialogue_seen(_active_dialogue_id)
	_start_countdown()


func _on_judged(result: String, polygon_index: int, timing_delta_ms: float) -> void:
	var resolution := EventHandlerRegistryScript.resolve_judgment(_event_system, polygon_index, result)
	var resolved_result: String = resolution["result"]
	var display_result: String = resolution["display_result"]
	var omit_display := display_result == "Too Slow" and _previous_judgment_result == "Too Fast"
	# Even hidden judgments become the previous result for the next judgment.
	_previous_judgment_result = resolved_result
	if judgement != null:
		if not omit_display:
			judgement.show_judgement(display_result)
		_input_manager_call("play_rumble", [display_result])
	if _boss_health > 0:
		_boss_health = maxi(0, _boss_health - level_data.boss_damage(resolved_result, resolution["guarded"]))
		if _event_system.has_event(EVENT_SAMURAI):
			gameplay_hud.update_samurai_attack(_boss_health, _event_system.occurs(EVENT_SAMURAI, polygon_index + 1))
		elif _event_system.has_event(EVENT_TIME_STOP):
			gameplay_hud.update_time_spell(_boss_health, _event_system.occurs(EVENT_TIME_STOP, polygon_index + 1), false)
		else:
			gameplay_hud.update_boss(_boss_health, _event_system.occurs(EVENT_GUARD, polygon_index + 1))
	_run_state.apply_judgment(resolved_result, polygon_index, timing_delta_ms)
	var restoration = $BackgroundLayer/Background.restoration
	if restoration != null:
		restoration.update_reconstruction(_run_state.resolved_notes, _run_state.total_notes)
	if not _level_ended and level_data.duration_sec <= 0.0 and _run_state.resolved_notes >= _run_state.total_notes:
		_finish_level(_boss_health <= 0)


func _on_stats_changed(stats: Dictionary) -> void:
	if gameplay_hud != null:
		gameplay_hud.update_stats(stats)


func _on_run_failed() -> void:
	_finish_level(false)


func _finish_level(completed: bool) -> void:
	if _level_ended:
		return
	_level_ended = true
	set_process(false)
	if completed and not _is_custom_level:
		ProgressStoreScript.unlock_next_stage(ProgressStoreScript.selected_stage)
	conductor.pause_clock()
	rotator.paused = true
	if music != null:
		music.stop()
	var result := LevelResultServiceScript.build(
		_run_state,
		completed,
		ProgressStoreScript.selected_stage,
		_is_custom_level,
		level_data.bpm,
		_level_sequence.size(),
	)
	var stats: Dictionary = result["stats"]
	var final_rank: String = result["rank"]
	conductor.save_timing_trace(timing_trace_path, result["trace_metadata"])
	if not _is_custom_level:
		ProgressStoreScript.record_run(ProgressStoreScript.selected_stage, stats, final_rank, completed)
	else:
		level_finished.emit(stats, completed, final_rank)
		call_deferred("_return_to_editor")
		return
	if result_overlay != null:
		result_overlay.show_result(stats, completed)
	level_finished.emit(stats, completed, final_rank)


func _retry_level() -> void:
	_input_manager_call("stop_rumble")
	get_tree().reload_current_scene()


func _return_to_stage_select() -> void:
	_input_manager_call("stop_rumble")
	if _is_custom_level:
		_return_to_editor()
		return
	ProgressStoreScript.show_stage_select_on_load = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _return_to_main_from_pause() -> void:
	_input_manager_call("stop_rumble")
	get_tree().paused = false
	get_tree().change_scene_to_file(EDITOR_SCENE if _is_custom_level else MAIN_SCENE)


func _restart_level_from_pause() -> void:
	_input_manager_call("stop_rumble")
	get_tree().paused = false
	get_tree().reload_current_scene()


func _return_to_editor() -> void:
	_input_manager_call("stop_rumble")
	get_tree().paused = false
	get_tree().change_scene_to_file(EDITOR_SCENE)


func _on_countdown_finished() -> void:
	rotator.paused = false
	set_process(true)
	conductor.start()
	if music != null:
		var stream_length := music.stream.get_length() if music.stream != null else 0.0
		var start_offset := level_data.clamped_music_start_offset(stream_length)
		conductor.set_audio_reference(music, start_offset)
		music.play(start_offset)


func _process(_delta: float) -> void:
	if not _level_ended and level_data.duration_sec > 0.0 and conductor._get_game_time() >= level_data.duration_sec:
		# Resolve deadlines before deciding success, including a stalled final frame.
		conductor._process(0.0)
		if not _level_ended and not conductor.paused:
			_finish_level(_boss_health <= 0 and _run_state.resolved_notes >= _run_state.total_notes)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		timing_debug_overlay.toggle()
		get_viewport().set_input_as_handled()
		return
	var keyboard_cancel := event.is_action_pressed("ui_cancel") and not event is InputEventJoypadButton
	var input_manager := get_node_or_null("/root/InputDeviceManager")
	var pause_input := bool(input_manager.call("is_pause_input", event)) if input_manager != null else false
	if (keyboard_cancel or pause_input) and not _level_ended and not get_tree().paused:
		_set_game_paused(true)
		get_viewport().set_input_as_handled()


func _set_game_paused(value: bool) -> void:
	if value:
		_input_manager_call("stop_rumble")
		set_process(false)
		conductor.pause_clock()
		music.stream_paused = true
		pause_overlay.open()
		get_tree().paused = true
	else:
		get_tree().paused = false
		pause_overlay.close()
		conductor.resume_clock()
		music.stream_paused = conductor.paused
		set_process(true)


func _input_manager_call(method: StringName, arguments: Array = []) -> void:
	var input_manager := get_node_or_null("/root/InputDeviceManager")
	if input_manager != null:
		input_manager.callv(method, arguments)


func _set_judgment_offset(offset_sec: float) -> void:
	conductor.judgment_offset_sec = offset_sec
	if conductor.detailed_timing_logs:
		print("[TIMING_OFFSET_CHANGED] judgment_offset_ms=%.1f" % (offset_sec * 1000.0))


func _on_polygon_advanced(_from_index: int, to_index: int) -> void:
	_current_index = to_index
	queue_redraw()
	if _event_system.has_event(EVENT_SAMURAI):
		gameplay_hud.update_samurai_attack(_boss_health, _event_system.occurs(EVENT_SAMURAI, to_index))
		var cue := EventHandlerRegistryScript.cue(_event_system, to_index)
		if not cue.is_empty():
			judgement.show_judgement(cue)
	elif _event_system.has_event(EVENT_TIME_STOP):
		gameplay_hud.update_time_spell(_boss_health, _event_system.occurs(EVENT_TIME_STOP, to_index), false)
		if _event_system.occurs(EVENT_TIME_STOP, to_index):
			_trigger_time_stop()


func _trigger_time_stop() -> void:
	if _time_stopped or _level_ended:
		return
	_time_stopped = true
	conductor.pause_clock(&"boss_time_stop")
	music.stream_paused = true
	gameplay_hud.update_time_spell(_boss_health, true, true)
	var configured_duration: Variant = _event_system.value(EVENT_TIME_STOP, "duration_sec", 0.65)
	var duration := 0.65
	if configured_duration is int or configured_duration is float:
		duration = float(configured_duration)
	elif configured_duration is String and (configured_duration as String).is_valid_float():
		duration = (configured_duration as String).to_float()
	if not is_finite(duration):
		duration = 0.65
	await get_tree().create_timer(maxf(duration, 0.0)).timeout
	if _level_ended:
		return
	gameplay_hud.update_time_spell(_boss_health, true, false)
	conductor.resume_clock(&"boss_time_stop")
	music.stream_paused = conductor.paused
	_time_stopped = false


func _compute_start_offsets() -> PackedVector2Array:
	var offsets := PackedVector2Array()
	for index in _polygon_centers.size():
		var prev_center: Vector2
		if index == 0:
			prev_center = base_midpoint
		else:
			prev_center = _polygon_centers[index - 1]
		var current_center: Vector2 = _polygon_centers[index]
		var direction := current_center - prev_center
		if direction.length() < 0.0001:
			direction = Vector2(0.0, -1.0)
		else:
			direction = direction.normalized()
		offsets.append(direction * fly_in_distance)
	return offsets


func _compute_scheduled_judgment_times() -> PackedFloat32Array:
	if _note_timeline != null:
		return _note_timeline.contact_times()
	return NoteTimelineScript.build(_level_sequence, level_data.bpm, 0.0, 0.0, 0.0).contact_times()


func _draw() -> void:
	if _shapes.is_empty():
		return
	# Use musical progress so fading freezes with the polygons when paused.
	var path_progress: float = float(_current_index) + rotator.get_transition_progress()
	var starter_alpha := starter_triangle_alpha * _past_polygon_visibility(-1, path_progress)
	if starter_alpha > 0.0:
		_draw_glass_polygon(_starter_triangle, 5, starter_alpha, false, 0.0)
	for index in range(maxi(0, _current_index - past_polygon_trail_length), _current_index):
		_draw_passive_polygon(index, path_progress)
	_draw_current_polygon(_current_index)
	_draw_shared_entrance_edge(_current_index)


func _draw_shared_entrance_edge(index: int) -> void:
	# The fixed starter triangle acts as the previous polygon for index zero.
	if index < 0:
		return
	var edge: PackedVector2Array = rotator.get_rotated_entrance_edge_world()
	if edge.size() < 2:
		return
	var elapsed: float = rotator.get_transition_elapsed()
	var spawn_t := clampf(elapsed / maxf(spawn_fade_duration, 0.0001), 0.0, 1.0)
	var spawn_alpha := 1.0 - pow(1.0 - spawn_t, 3.0)
	var pulse_strength := _landing_pulse_strength(elapsed, rotator.transition_duration)
	if pulse_strength > 0.0:
		var center: Vector2 = _polygon_centers[index] + rotator.get_current_offset()
		edge = _scaled_polygon(edge, center, 1.0 + pulse_strength * landing_pulse_scale)
	var pulse := 0.82 + sin(elapsed * 7.0) * 0.18
	var glow_color := shared_edge_color
	glow_color.a = 0.28 * spawn_alpha * pulse
	var core_color := shared_edge_color
	core_color.a *= spawn_alpha
	draw_line(edge[0], edge[1], glow_color, shared_edge_glow_width, true)
	draw_line(edge[0], edge[1], core_color, shared_edge_width, true)


func _draw_current_polygon(index: int) -> void:
	var rotated: PackedVector2Array = rotator.get_rotated_polygon()
	if rotated.is_empty():
		return
	var elapsed: float = rotator.get_transition_elapsed()
	var spawn_t: float = clampf(elapsed / maxf(spawn_fade_duration, 0.0001), 0.0, 1.0)
	var spawn_alpha: float = 1.0 - pow(1.0 - spawn_t, 3.0)
	# A restrained sheen marks visual landing without obscuring the polygon shape.
	var pulse_strength := _landing_pulse_strength(elapsed, rotator.transition_duration)
	var pulse_scale: float = 1.0 + pulse_strength * landing_pulse_scale
	var displayed := rotated
	if pulse_scale != 1.0:
		var center: Vector2 = _polygon_centers[index] + rotator.get_current_offset()
		displayed = _scaled_polygon(rotated, center, pulse_scale)
	_draw_glass_polygon(displayed, index, spawn_alpha * current_fill_alpha, true, pulse_strength)


func _past_polygon_visibility(index: int, path_progress: float) -> float:
	# Keep the latest ten intact, fade ranks 11–14, and hide rank 15 onward.
	var age := path_progress - float(index + 1)
	var fade_start := float(fully_visible_past_polygons)
	var fade_end := float(maxi(past_polygon_trail_length, fully_visible_past_polygons + 1))
	return 1.0 - smoothstep(fade_start, fade_end, age)


func _draw_passive_polygon(index: int, path_progress: float) -> void:
	var alpha := current_fill_alpha * _past_polygon_visibility(index, path_progress)
	if alpha > 0.0:
		_draw_glass_polygon(_shapes[index], index, alpha, false, 0.0)


func _draw_glass_polygon(
		points: PackedVector2Array,
		index: int,
		alpha: float,
		is_current: bool,
		pulse_strength: float,
) -> void:
	if points.size() < 3:
		return
	var center := _polygon_center(points)
	var base := _color_for_index(index)
	var center_color := base.lightened(0.22 + pulse_strength * 0.16)
	center_color.a = alpha
	var edge_color := base.lerp(Color("071126"), 0.48)
	edge_color.a = alpha * 0.78
	for vertex in points.size():
		var next := (vertex + 1) % points.size()
		draw_polygon(
			PackedVector2Array([center, points[vertex], points[next]]),
			PackedColorArray([center_color, edge_color, edge_color]),
		)

	var outline := points.duplicate()
	outline.append(points[0])
	if is_current:
		var glow := base.lightened(0.30)
		glow.a = alpha * (0.16 + pulse_strength * 0.14)
		draw_polyline(outline, glow, polygon_glow_width + pulse_strength * 4.0, true)
	var rim := base.lightened(0.48 if is_current else 0.12)
	rim.a = alpha * (0.95 if is_current else 0.48)
	draw_polyline(outline, rim, maxf(outline_width, 1.0), true)

	var inset := PackedVector2Array()
	for point in points:
		inset.append(center.lerp(point, 0.72))
	inset.append(inset[0])
	var inner_color := Color.WHITE
	inner_color.a = inner_highlight_alpha * alpha * (1.0 if is_current else 0.22)
	draw_polyline(inset, inner_color, 1.0, true)


func _polygon_center(points: PackedVector2Array) -> Vector2:
	var center := Vector2.ZERO
	for point in points:
		center += point
	return center / points.size()


func _scaled_polygon(points: PackedVector2Array, center: Vector2, scale_value: float) -> PackedVector2Array:
	var scaled := PackedVector2Array()
	scaled.resize(points.size())
	for index in points.size():
		scaled[index] = center + (points[index] - center) * scale_value
	return scaled


func _landing_pulse_strength(elapsed: float, landing_time: float) -> float:
	var cue_start: float = maxf(0.0, landing_time - 0.050)
	var cue_end: float = landing_time + 0.050
	if elapsed < cue_start or elapsed >= cue_end:
		return 0.0
	var cue_t := clampf((elapsed - cue_start) / (cue_end - cue_start), 0.0, 1.0)
	return sin(cue_t * PI)


func _color_for_index(index: int) -> Color:
	if _event_system.occurs(EVENT_GUARD, index) or _event_system.occurs(EVENT_SAMURAI, index):
		return Color("ff294f")
	if _event_system.occurs(EVENT_TIME_STOP, index):
		return Color("a45cff")
	if NEON_PALETTE.is_empty():
		return Color.WHITE
	return NEON_PALETTE[index % NEON_PALETTE.size()]
