extends Control

const LEVEL_SCENE := "res://level/level.tscn"
const LEVEL_EDITOR_SCENE := "res://editor/level_editor.tscn"
const ProgressStoreScript = preload("res://level/progress_store.gd")
const SettingsStoreScript = preload("res://main/settings_store.gd")
const StageCatalogScript = preload("res://level/data/stage_catalog.gd")
const ScreenTransitionControllerScript = preload("res://main/screen_transition_controller.gd")
const LevelDataScript = preload("res://level/data/level_data.gd")
const AudioStreamLoaderScript = preload("res://level/audio/audio_stream_loader.gd")
const CYAN := Color("19e0db")
const MAGENTA := Color("ed1671")

@onready var menu: VBoxContainer = %Menu
@onready var main_content: Control = %Content
@onready var main_logo: Control = $Content/Logo
@onready var stage_screen: Control = %StageScreen
@onready var settings_screen: Control = %SettingsScreen
@onready var transition_logo: Control = %TransitionLogo
@onready var overlay: Control = %Overlay
@onready var overlay_title: Label = %OverlayTitle
@onready var overlay_body: Label = %OverlayBody
@onready var credits_content: HBoxContainer = %CreditsContent
@onready var exit_buttons: HBoxContainer = %ExitButtons
@onready var close_button: Button = %CloseButton
@onready var warning_badge: Control = %WarningBadge
@onready var background_music: AudioStreamPlayer = %BackgroundMusic
@onready var stage_preview_music: AudioStreamPlayer = %StagePreviewMusic
@onready var focus_sfx: AudioStreamPlayer = %FocusSfx
@onready var click_sfx: AudioStreamPlayer = %ClickSfx
@onready var timing_calibration: CanvasLayer = $TimingCalibrationOverlay
@onready var controller_prompt: Label = %ControllerPrompt

var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _motion_time := 0.0
var _bass := 0.0
var _mid := 0.0
var _treble := 0.0
var _last_slider_sfx_ms := 0
var _transition_controller: Node
var _stage_card_tweens: Dictionary = { }
var _stage_preview_tween: Tween
var _mouse_focus_enabled := true
var _focusable_controls: Array[Control] = []
var _original_mouse_filters: Dictionary = {}


func _ready() -> void:
	_transition_controller = ScreenTransitionControllerScript.new()
	add_child(_transition_controller)
	_transition_controller.setup(main_content, main_logo, transition_logo, %StartButton)
	get_viewport().size_changed.connect(queue_redraw)
	var input_manager := _input_manager()
	if input_manager != null:
		input_manager.connect("active_device_changed", _update_controller_prompt.unbind(1))
		input_manager.connect("controller_connection_changed", _update_controller_prompt.unbind(2))
	_update_controller_prompt()
	_connect_ui_sfx(self)
	%StartButton.pressed.connect(_show_stage_select)
	%BackButton.pressed.connect(_hide_stage_select)
	for stage_number in StageCatalogScript.stage_numbers():
		var card: Control = $StageScreen/StageLayout/CardsSlot/Cards.get_child(stage_number - 1)
		var button: BaseButton = card.get_child(card.get_child_count() - 1)
		button.pressed.connect(_start_game.bind(stage_number))
		var data = LevelDataScript.from_yaml(StageCatalogScript.data_path(stage_number))
		_setup_stage_card(button, card, card.get_node("Items/Record"), AudioStreamLoaderScript.load_stream(data.music_path))
	_refresh_stage_cards()
	%EditorButton.pressed.connect(_open_level_editor)
	%SettingsButton.pressed.connect(_show_settings)
	%SettingsBackButton.pressed.connect(_hide_settings)
	%FullscreenToggle.toggled.connect(_set_fullscreen)
	%ResolutionOption.item_selected.connect(SettingsStoreScript.save_resolution)
	%MasterSlider.value_changed.connect(_set_volume.bind("master_volume", %MasterValue))
	%MusicSlider.value_changed.connect(_set_volume.bind("music_volume", %MusicValue))
	%SfxSlider.value_changed.connect(_set_volume.bind("sfx_volume", %SfxValue))
	%VibrationSlider.value_changed.connect(_set_vibration_strength)
	%VibrationEnabled.toggled.connect(_set_vibration_enabled)
	%TimingSlider.value_changed.connect(_set_timing_offset)
	%CalibrationButton.pressed.connect(timing_calibration.open)
	timing_calibration.offset_selected.connect(_apply_calibrated_offset)
	timing_calibration.closed.connect(%CalibrationButton.grab_focus)
	%MasterEnabled.toggled.connect(_set_audio_enabled.bind("master_enabled", %MasterEnabled))
	%MusicEnabled.toggled.connect(_set_audio_enabled.bind("music_enabled", %MusicEnabled))
	%SfxEnabled.toggled.connect(_set_audio_enabled.bind("sfx_enabled", %SfxEnabled))
	%UnlockAllStagesButton.pressed.connect(_unlock_all_stages)
	%ExperienceModeToggle.toggled.connect(_set_audio_enabled.bind("experience_mode", %ExperienceModeToggle))
	%ResetRecordsButton.pressed.connect(%ResetRecordsDialog.popup_centered)
	%ResetRecordsDialog.confirmed.connect(_reset_all_records)
	%ResetRecordsDialog.canceled.connect(%ResetRecordsButton.grab_focus)
	%MasterSlider.value_changed.connect(_play_slider_sfx)
	%MusicSlider.value_changed.connect(_play_slider_sfx)
	%SfxSlider.value_changed.connect(_play_slider_sfx)
	%CreditsButton.pressed.connect(_show_credits)
	%ExitButton.pressed.connect(_show_exit)
	close_button.pressed.connect(_hide_overlay)
	%CancelExitButton.pressed.connect(_hide_overlay)
	%ConfirmExitButton.pressed.connect(get_tree().quit)
	background_music.finished.connect(background_music.play)
	_initialize_settings()
	transition_logo.reset_size()
	queue_redraw()
	%StartButton.grab_focus()
	if ProgressStoreScript.show_stage_select_on_load or ProgressStoreScript.pending_unlock_dialogue() > 0:
		ProgressStoreScript.show_stage_select_on_load = false
		_show_unlock_flow.call_deferred()


func _show_unlock_flow() -> void:
	_show_stage_select()
	ProgressStoreScript.consume_unlock_dialogue()


func _update_controller_prompt() -> void:
	var input_manager := _input_manager()
	controller_prompt.visible = input_manager != null and input_manager.get("active_device_type") == "gamepad"
	if input_manager != null:
		controller_prompt.text = "%s 선택    %s 뒤로" % [input_manager.call("confirm_prompt"), input_manager.call("cancel_prompt")]


func _input_manager() -> Node:
	return get_node_or_null("/root/InputDeviceManager")


func _refresh_stage_cards() -> void:
	var highest := ProgressStoreScript.highest_unlocked_stage()
	var cards := $StageScreen/StageLayout/CardsSlot/Cards.get_children()
	var records: Array[Control] = []
	for card in cards:
		records.append(card.get_node("Items/Record"))
	var buttons := _stage_buttons()
	var active_style: StyleBox = cards[0].get_theme_stylebox("panel").duplicate()
	var locked_style: StyleBox = cards[1].get_theme_stylebox("panel").duplicate()
	for index in cards.size():
		var active := index + 1 <= highest
		records[index].set("active", active)
		buttons[index].disabled = not active
		buttons[index].focus_mode = Control.FOCUS_ALL if active else Control.FOCUS_NONE
		cards[index].add_theme_stylebox_override("panel", active_style.duplicate() if active else locked_style.duplicate())
		var items := cards[index].get_node("Items")
		var text_color := Color("14e6f2") if active else Color(0.52, 0.52, 0.52, 1.0)
		items.get_node("Stage").add_theme_color_override("font_color", text_color)
		items.get_node("Number").add_theme_color_override("font_color", text_color)
		items.get_node("Name").add_theme_color_override("font_color", Color(0.95, 0.96, 1, 1) if active else Color(0.57, 0.57, 0.57, 1))
		items.get_node("Name").text = StageCatalogScript.display_name(index + 1)
		var best: Label = items.get_node("Best")
		var rating_label: Label = items.get_node("Rating")
		var record := ProgressStoreScript.stage_record(index + 1)
		best.visible = active
		rating_label.visible = active
		best.text = "최고 점수 %07d" % record["score"] if record["score"] > 0 else "기록 없음"
		if record["score"] > 0:
			var rating := ProgressStoreScript.star_rating(record["accuracy"], record["cleared"])
			var earned_stars: int = clampi(int(rating["stars"]), 0, 3)
			rating_label.text = "★".repeat(earned_stars) + "☆".repeat(3 - earned_stars)
			rating_label.add_theme_color_override("font_color", _rating_color(rating["tier"]))
		else:
			rating_label.text = "☆☆☆"
			rating_label.add_theme_color_override("font_color", Color("52647a"))
	_configure_stage_focus(buttons, highest)


func _configure_stage_focus(buttons: Array[BaseButton], active_count: int) -> void:
	var count := clampi(active_count, 1, buttons.size())
	for index in buttons.size():
		if index >= count:
			continue
		var previous_index := wrapi(index - 1, 0, count)
		var next_index := wrapi(index + 1, 0, count)
		buttons[index].focus_neighbor_left = buttons[index].get_path_to(buttons[previous_index])
		buttons[index].focus_neighbor_right = buttons[index].get_path_to(buttons[next_index])
		var vertical_index := index + 4 if index < 4 else index - 4
		var vertical: Control = buttons[vertical_index] if vertical_index < count else %BackButton
		buttons[index].focus_neighbor_top = buttons[index].get_path_to(vertical)
		buttons[index].focus_neighbor_bottom = buttons[index].get_path_to(vertical)


func _rating_color(tier: String) -> Color:
	match tier:
		"diamond": return Color("76f7ff")
		"gold": return Color("ffd84d")
		"silver": return Color("c7d1dc")
		"bronze": return Color("c98252")
	return Color("52647a")


func _connect_ui_sfx(node: Node) -> void:
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE:
			_focusable_controls.append(control)
			_original_mouse_filters[control] = control.mouse_filter
			control.mouse_entered.connect(_focus_hovered_control.bind(control))
	if node is BaseButton:
		var button := node as BaseButton
		button.mouse_entered.connect(_play_focus_sfx)
		button.focus_entered.connect(_play_focus_sfx)
		button.pressed.connect(_play_click_sfx)
	for child in node.get_children():
		_connect_ui_sfx(child)


func _focus_hovered_control(control: Control) -> void:
	if not _mouse_focus_enabled or not control.is_visible_in_tree() or control.focus_mode == Control.FOCUS_NONE:
		return
	if control is BaseButton and (control as BaseButton).disabled:
		return
	control.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).relative.length_squared() > 0.0:
			_set_mouse_focus_enabled(true)
	elif event is InputEventMouseButton:
		_set_mouse_focus_enabled(true)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_set_mouse_focus_enabled(false)
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		_set_mouse_focus_enabled(false)
	elif event is InputEventJoypadMotion and absf((event as InputEventJoypadMotion).axis_value) > 0.35:
		_set_mouse_focus_enabled(false)


func _set_mouse_focus_enabled(enabled: bool) -> void:
	if _mouse_focus_enabled == enabled:
		return
	_mouse_focus_enabled = enabled
	for control in _focusable_controls:
		if not is_instance_valid(control):
			continue
		control.mouse_filter = (
			int(_original_mouse_filters.get(control, Control.MOUSE_FILTER_STOP))
			if enabled
			else Control.MOUSE_FILTER_IGNORE
		)


func _play_focus_sfx() -> void:
	focus_sfx.pitch_scale = 1.0
	focus_sfx.play()


func _play_click_sfx() -> void:
	if focus_sfx.playing:
		focus_sfx.stop()
	click_sfx.play()


func _play_slider_sfx(value: float) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_slider_sfx_ms < 45:
		return
	_last_slider_sfx_ms = now
	focus_sfx.pitch_scale = lerpf(0.82, 1.18, clampf(value / 100.0, 0.0, 1.0))
	focus_sfx.play()


func _setup_stage_card(button: BaseButton, card: Control, record: Control, preview_stream: AudioStream) -> void:
	var active: bool = record.get("active")
	button.disabled = not active
	button.focus_mode = Control.FOCUS_ALL if active else Control.FOCUS_NONE
	button.mouse_entered.connect(_on_stage_mouse_entered.bind(button, card, record, preview_stream))
	button.mouse_exited.connect(_on_stage_mouse_exited.bind(button, card, record))
	button.focus_entered.connect(_on_stage_focus_entered.bind(button, card, record, preview_stream))
	button.focus_exited.connect(_on_stage_focus_exited.bind(button, card, record))


func _on_stage_mouse_entered(
	button: BaseButton,
	card: Control,
	record: Control,
	_preview_stream: AudioStream,
) -> void:
	_update_stage_card(button, card, record)


func _on_stage_mouse_exited(button: BaseButton, card: Control, record: Control) -> void:
	_update_stage_card(button, card, record)
	if not button.has_focus():
		_stop_stage_preview()


func _on_stage_focus_entered(
	button: BaseButton,
	card: Control,
	record: Control,
	preview_stream: AudioStream,
) -> void:
	_update_stage_card(button, card, record)
	_play_stage_preview(preview_stream)


func _on_stage_focus_exited(button: BaseButton, card: Control, record: Control) -> void:
	_update_stage_card(button, card, record)
	if not button.is_hovered():
		_stop_stage_preview()


func _play_stage_preview(preview_stream: AudioStream) -> void:
	if preview_stream == null:
		_stop_stage_preview()
		return
	if _stage_preview_tween != null and _stage_preview_tween.is_valid():
		_stage_preview_tween.kill()
	stage_preview_music.stream = preview_stream
	stage_preview_music.volume_db = -24.0
	stage_preview_music.play()
	_stage_preview_tween = create_tween().set_parallel(true)
	_stage_preview_tween.tween_property(background_music, "volume_db", -24.0, 0.22)
	_stage_preview_tween.tween_property(stage_preview_music, "volume_db", -2.0, 0.22)


func _stop_stage_preview() -> void:
	if not stage_preview_music.playing:
		background_music.volume_db = -2.0
		return
	if _stage_preview_tween != null and _stage_preview_tween.is_valid():
		_stage_preview_tween.kill()
	_stage_preview_tween = create_tween().set_parallel(true)
	_stage_preview_tween.tween_property(background_music, "volume_db", -2.0, 0.22)
	_stage_preview_tween.tween_property(stage_preview_music, "volume_db", -24.0, 0.22)
	_stage_preview_tween.chain().tween_callback(stage_preview_music.stop)


func _update_stage_card(button: BaseButton, card: Control, record: Control) -> void:
	var highlighted := button.is_hovered() or button.has_focus()
	var active: bool = record.get("active")
	card.pivot_offset = card.size * 0.5
	card.z_index = 2 if highlighted else 0
	record.call("set_highlighted", highlighted)
	var panel_style := card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if highlighted:
		panel_style.border_color = Color(0.08, 0.92, 0.94, 1.0) if active else Color(0.8, 0.8, 0.8, 0.82)
		panel_style.shadow_color = Color(0.04, 0.86, 0.92, 0.28) if active else Color(0.76, 0.76, 0.76, 0.16)
		panel_style.shadow_size = 14
	else:
		panel_style.border_color = Color(0.86, 0.89, 0.96, 0.76) if active else Color(0.74, 0.74, 0.74, 0.52)
		panel_style.shadow_color = Color.TRANSPARENT
		panel_style.shadow_size = 0
	card.add_theme_stylebox_override("panel", panel_style)
	if _stage_card_tweens.has(card):
		var previous := _stage_card_tweens[card] as Tween
		if previous != null and previous.is_valid():
			previous.kill()
	var tween := create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(card, "scale", Vector2.ONE * (1.04 if highlighted else 1.0), 0.18)
	tween.tween_property(card, "modulate", Color(1.05, 1.05, 1.05, 1.0) if highlighted else Color.WHITE, 0.18)
	_stage_card_tweens[card] = tween


func _process(delta: float) -> void:
	_motion_time += delta
	if background_music.playing:
		_motion_time = background_music.get_playback_position()
	_update_audio_response(delta)
	queue_redraw()


func _update_audio_response(delta: float) -> void:
	if _analyzer == null:
		var bus_index := AudioServer.get_bus_index(&"MenuMusic")
		if bus_index < 0:
			return
		_analyzer = AudioServer.get_bus_effect_instance(
			bus_index,
			0,
		) as AudioEffectSpectrumAnalyzerInstance
	if _analyzer == null:
		return
	var raw_bass := _frequency_energy(35.0, 180.0)
	var raw_mid := _frequency_energy(180.0, 2200.0)
	var raw_treble := _frequency_energy(2200.0, 9000.0)
	_bass = _smoothed_energy(_bass, raw_bass, delta, 9.0)
	_mid = _smoothed_energy(_mid, raw_mid, delta, 7.0)
	_treble = _smoothed_energy(_treble, raw_treble, delta, 11.0)


func _frequency_energy(from_hz: float, to_hz: float) -> float:
	var magnitude := _analyzer.get_magnitude_for_frequency_range(from_hz, to_hz)
	var amplitude := maxf(magnitude.x, magnitude.y)
	if amplitude <= 0.000001:
		return 0.0
	var decibels := linear_to_db(amplitude)
	return clampf((decibels + 55.0) / 45.0, 0.0, 1.0)


func _smoothed_energy(current: float, target: float, delta: float, speed: float) -> float:
	return lerpf(current, target, 1.0 - exp(-speed * delta))


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), Color("071126"))
	_draw_background_gradient(view)
	_draw_grid(view)
	_draw_orbits(view)
	_draw_particles(view)
	_draw_music_notes(view)


func _draw_background_gradient(view: Vector2) -> void:
	var center := Vector2(view.x * 0.46, view.y * 0.36)
	var max_radius := view.length() * 0.68
	for ring in range(48, 0, -1):
		var ratio := float(ring) / 48.0
		var color := Color(0.08, 0.14, 0.38, 0.012)
		draw_circle(center, max_radius * ratio, color)
	# A restrained lower glow anchors the menu without competing with it.
	for ring in range(20, 0, -1):
		var ratio := float(ring) / 20.0
		draw_circle(Vector2(view.x * 0.5, view.y * 0.78), view.x * 0.24 * ratio, Color(0.15, 0.04, 0.28, 0.008))


func _draw_grid(view: Vector2) -> void:
	var spacing := maxf(80.0, view.x / 16.0)
	var grid_color := Color(0.24, 0.38, 0.66, 0.055)
	var x_offset := fmod(_motion_time * 12.0, spacing)
	var y_offset := fmod(_motion_time * 7.0, spacing)
	var x := x_offset - spacing
	while x <= view.x:
		draw_line(Vector2(x, 0), Vector2(x, view.y), grid_color, 1.0)
		x += spacing
	var y := y_offset - spacing
	while y <= view.y:
		draw_line(Vector2(0, y), Vector2(view.x, y), grid_color, 1.0)
		y += spacing
func _draw_orbits(view: Vector2) -> void:
	var drift := Vector2(sin(_motion_time * 0.16) * view.x * 0.009, cos(_motion_time * 0.12) * view.y * 0.006)
	var center := Vector2(view.x * 0.39, view.y * 0.92) + drift
	var bass_pulse := 1.0 + _bass * 0.018
	var mid_pulse := 1.0 + _mid * 0.012
	var orbit_turn := _motion_time * 0.018
	_draw_arc_segments(center, view.x * 0.53 * bass_pulse, orbit_turn, orbit_turn + TAU, 160, Color(0.38, 0.22, 0.92, 0.32 + _bass * 0.16), 2.5 + _bass * 1.2)
	_draw_arc_segments(center, view.x * 0.71 * mid_pulse, -orbit_turn * 0.65, -orbit_turn * 0.65 + TAU, 192, Color(0.92, 0.20, 0.75, 0.27 + _mid * 0.12), 2.2)
	_draw_arc_segments(center, view.x * 0.33 * mid_pulse, orbit_turn * 1.2, orbit_turn * 1.2 + TAU, 128, Color(0.18, 0.38, 0.85, 0.10 + _bass * 0.08), 1.5 + _mid * 0.6)


func _draw_arc_segments(
		center: Vector2,
		radius: float,
		start_angle: float,
		end_angle: float,
		segments: int,
		color: Color,
		width: float,
) -> void:
	var previous := center + Vector2.from_angle(start_angle) * radius
	for index in range(1, segments + 1):
		var angle := lerpf(start_angle, end_angle, float(index) / segments)
		var point := center + Vector2.from_angle(angle) * radius
		draw_line(previous, point, color, width, true)
		previous = point


func _draw_particles(view: Vector2) -> void:
	var particles := [
		[Vector2(0.055, 0.36), Color("b56dff"), 2.3],
		[Vector2(0.105, 0.55), Color("e8ff74"), 2.8],
		[Vector2(0.225, 0.58), CYAN, 4.5],
		[Vector2(0.61, 0.045), Color("29aaff"), 2.8],
		[Vector2(0.67, 0.105), Color("15efff"), 2.1],
		[Vector2(0.75, 0.085), MAGENTA, 2.8],
		[Vector2(0.80, 0.24), CYAN, 4.0],
		[Vector2(0.86, 0.34), Color("8957ff"), 2.8],
		[Vector2(0.94, 0.21), MAGENTA, 2.2],
		[Vector2(0.84, 0.58), MAGENTA, 4.5],
		[Vector2(0.74, 0.82), Color("ff38c7"), 2.2],
		[Vector2(0.85, 0.87), Color("397dff"), 4.0],
		[Vector2(0.10, 0.89), Color("fff36a"), 2.2],
	]
	for index in particles.size():
		var item: Array = particles[index]
		var phase := float(index) * 1.73
		var orbit_speed := 0.20 + float(index % 4) * 0.035
		var orbit_radius := 6.0 + float(index % 3) * 3.0 + _mid * 10.0
		var drift := Vector2(
			cos(_motion_time * orbit_speed + phase) * orbit_radius,
			sin(_motion_time * orbit_speed * 0.78 + phase) * orbit_radius * 0.72,
		)
		drift += Vector2(sin(_motion_time * 0.09 + phase), cos(_motion_time * 0.07 + phase)) * 4.0
		var point: Vector2 = item[0] * view + drift
		var color: Color = item[1]
		var idle_pulse := (sin(_motion_time * 1.15 + phase) + 1.0) * 0.06
		var radius: float = item[2] * (1.0 + idle_pulse + _treble * 0.32)
		var glow := color
		glow.a = 0.08 + _treble * 0.08
		draw_circle(point, radius * 3.6, glow)
		draw_circle(point, radius, color)
		if index % 4 == 0:
			var ring_color := color
			ring_color.a = 0.12 + _treble * 0.12
			draw_arc(point, radius * (2.2 + _bass * 0.8), 0.0, TAU, 24, ring_color, 1.0, true)
	var turn := _motion_time * 0.035
	_draw_polygon_outline(Vector2(0.18, 0.35) * view + Vector2(sin(_motion_time * 0.25), cos(_motion_time * 0.21)) * 5.0, 25.0 + _treble * 2.0, 4, 0.18 + turn, Color(0.05, 0.65, 0.95, 0.45 + _treble * 0.2))
	_draw_polygon_outline(Vector2(0.88, 0.08) * view + Vector2(cos(_motion_time * 0.19), sin(_motion_time * 0.23)) * 6.0, 29.0 + _mid * 2.0, 4, 0.62 - turn * 0.7, Color(0.55, 0.17, 0.95, 0.44 + _treble * 0.18))
	_draw_polygon_outline(Vector2(0.95, 0.89) * view + Vector2(sin(_motion_time * 0.17), cos(_motion_time * 0.20)) * 5.0, 24.0, 5, 0.20 + turn * 0.6, Color(0.55, 0.17, 0.95, 0.38 + _treble * 0.16))


func _draw_polygon_outline(center: Vector2, radius: float, sides: int, rotation_angle: float, color: Color) -> void:
	var points := PackedVector2Array()
	for index in range(sides + 1):
		var angle := rotation_angle + TAU * float(index) / sides
		points.append(center + Vector2.from_angle(angle) * radius)
	draw_polyline(points, color, 2.0, true)


func _draw_music_notes(view: Vector2) -> void:
	var notes := [
		[Vector2(0.105, 0.22), MAGENTA, 1.0],
		[Vector2(0.10, 0.71), Color("16d7f0"), 1.25],
		[Vector2(0.91, 0.32), CYAN, 1.3],
		[Vector2(0.92, 0.68), Color("b568ff"), 1.0],
	]
	for index in notes.size():
		var item: Array = notes[index]
		var phase := float(index) * 1.9
		var float_offset := Vector2(
			sin(_motion_time * (0.24 + index * 0.025) + phase) * (9.0 + _mid * 5.0),
			cos(_motion_time * (0.30 + index * 0.02) + phase) * (8.0 + _mid * 7.0),
		)
		var origin: Vector2 = item[0] * view + float_offset
		var color: Color = item[1]
		var scale_value: float = item[2] * (1.0 + _treble * 0.10)
		var sway := sin(_motion_time * 0.65 + phase) * 0.10
		var glow := color
		glow.a = 0.10
		draw_circle(origin, 15.0 * scale_value, glow)
		draw_circle(origin, 7.5 * scale_value, color)
		var stem_bottom := origin + (Vector2(6.5, 0) * scale_value).rotated(sway)
		var stem_top := origin + (Vector2(6.5, -31) * scale_value).rotated(sway)
		draw_line(stem_bottom, stem_top, color, 4.0 * scale_value, true)
		var flag := PackedVector2Array(
			[
				origin + (Vector2(6.5, -31) * scale_value).rotated(sway),
				origin + (Vector2(22, -25) * scale_value).rotated(sway),
				origin + (Vector2(7, -19) * scale_value).rotated(sway),
			],
		)
		draw_colored_polygon(flag, color)


func _start_game(stage_number: int = 1) -> void:
	ProgressStoreScript.selected_stage = stage_number
	ProgressStoreScript.mark_stage_played(stage_number)
	ProgressStoreScript.custom_level_path = ""
	get_tree().change_scene_to_file(LEVEL_SCENE)


func _open_level_editor() -> void:
	ProgressStoreScript.custom_level_path = ""
	ProgressStoreScript.editor_working_file_path = ""
	ProgressStoreScript.editor_saved_signature = ""
	get_tree().change_scene_to_file(LEVEL_EDITOR_SCENE)


func _show_settings() -> void:
	_transition_to(settings_screen, $SettingsScreen/SettingsLayout/SmallLogo, %SettingsTitle, %SettingsPanel, %SettingsBackButton, null, false)


func _hide_settings() -> void:
	_transition_to_main(settings_screen, $SettingsScreen/SettingsLayout/SmallLogo, %SettingsTitle, %SettingsPanel, %SettingsBackButton, false)


func _initialize_settings() -> void:
	var settings := SettingsStoreScript.load_settings()
	SettingsStoreScript.apply(settings)
	%FullscreenToggle.set_pressed_no_signal(settings["fullscreen"])
	_update_unlock_button()
	_sync_audio_toggle(%ExperienceModeToggle, settings["experience_mode"])
	%TimingSlider.set_value_no_signal(settings["timing_offset_ms"])
	_update_timing_offset_label(settings["timing_offset_ms"])
	_setup_resolution(%ResolutionOption, settings)
	for row in [[%MasterSlider, %MasterValue, %MasterEnabled, "master"], [%MusicSlider, %MusicValue, %MusicEnabled, "music"], [%SfxSlider, %SfxValue, %SfxEnabled, "sfx"]]:
		row[0].set_value_no_signal(settings["%s_volume" % row[3]])
		_update_volume_label(row[1], row[0].value)
		_sync_audio_toggle(row[2], settings["%s_enabled" % row[3]])
	%VibrationSlider.set_value_no_signal(settings["controller_vibration_strength"])
	%VibrationValue.text = "%d%%" % roundi(settings["controller_vibration_strength"])
	_sync_audio_toggle(%VibrationEnabled, settings["controller_vibration_enabled"])
	_update_fullscreen_toggle(settings["fullscreen"])


func _set_fullscreen(enabled: bool) -> void:
	_update_fullscreen_toggle(enabled)
	SettingsStoreScript.save_setting("fullscreen", enabled)


func _update_fullscreen_toggle(enabled: bool) -> void:
	%FullscreenToggle.text = "On" if enabled else "Off"
	%ResolutionOption.disabled = enabled
	var color := Color(0.08, 1.0, 0.92, 1.0) if enabled else Color(0.58, 0.63, 0.74, 1.0)
	%FullscreenToggle.add_theme_color_override("font_color", color)
	%FullscreenToggle.add_theme_color_override("font_pressed_color", color)


func _set_audio_enabled(enabled: bool, key: String, toggle: Button) -> void:
	_sync_audio_toggle(toggle, enabled)
	SettingsStoreScript.save_setting(key, enabled)


func _unlock_all_stages() -> void:
	if ProgressStoreScript.unlock_all_stages() != OK:
		%UnlockAllStagesButton.text = "다시 시도"
		return
	_refresh_stage_cards()
	_update_unlock_button()


func _reset_all_records() -> void:
	if ProgressStoreScript.reset_all_records() != OK:
		%ResetRecordsButton.text = "초기화 실패 · 다시 시도"
	else:
		_refresh_stage_cards()
		_update_unlock_button()
		%ResetRecordsButton.text = "초기화 완료"
	%ResetRecordsButton.grab_focus()


func _update_unlock_button() -> void:
	var unlocked := ProgressStoreScript.highest_unlocked_stage() == ProgressStoreScript.LAST_STAGE
	%UnlockAllStagesButton.disabled = unlocked
	%UnlockAllStagesButton.text = "해금 완료" if unlocked else "해금"


func _stage_buttons() -> Array[BaseButton]:
	var buttons: Array[BaseButton] = []
	for card in $StageScreen/StageLayout/CardsSlot/Cards.get_children():
		buttons.append(card.get_child(card.get_child_count() - 1))
	return buttons


func _sync_audio_toggle(toggle: Button, enabled: bool) -> void:
	toggle.set_pressed_no_signal(enabled)
	toggle.text = "On" if enabled else "Off"


func _setup_resolution(option: OptionButton, settings: Dictionary) -> void:
	option.clear()
	for size in SettingsStoreScript.RESOLUTIONS:
		option.add_item("%d × %d" % [size.x, size.y])
	option.select(SettingsStoreScript.resolution_index(settings))


func _set_volume(value: float, key: String, label: Label) -> void:
	_update_volume_label(label, value)
	SettingsStoreScript.save_setting(key, value)


func _set_vibration_strength(value: float) -> void:
	%VibrationValue.text = "%d%%" % roundi(value)
	SettingsStoreScript.save_setting("controller_vibration_strength", value)


func _set_vibration_enabled(enabled: bool) -> void:
	_sync_audio_toggle(%VibrationEnabled, enabled)
	SettingsStoreScript.save_setting("controller_vibration_enabled", enabled)


func _update_volume_label(label: Label, value: float) -> void:
	label.text = "%d%%" % roundi(value)


func _set_timing_offset(value: float) -> void:
	_update_timing_offset_label(value)
	SettingsStoreScript.save_setting("timing_offset_ms", value)


func _update_timing_offset_label(value: float) -> void:
	%TimingValue.text = "%+d ms" % roundi(value)


func _apply_calibrated_offset(value: float) -> void:
	%TimingSlider.set_value_no_signal(value)
	_set_timing_offset(value)


func _show_credits() -> void:
	_show_overlay("", "")
	overlay_title.hide()
	overlay_body.hide()
	credits_content.show()


func _show_exit() -> void:
	_show_overlay("", "게임을 종료하시겠습니까?")
	credits_content.hide()
	warning_badge.show()
	overlay_title.hide()
	exit_buttons.show()
	close_button.hide()
	_clear_focus()
	%ConfirmExitButton.grab_focus()


func _show_overlay(title: String, body: String) -> void:
	warning_badge.hide()
	credits_content.hide()
	overlay_body.show()
	overlay_title.show()
	overlay_title.text = title
	overlay_body.text = body
	exit_buttons.hide()
	close_button.show()
	overlay.show()
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_focus()
	close_button.grab_focus()


func _hide_overlay() -> void:
	_clear_focus()
	overlay.hide()
	menu.mouse_filter = Control.MOUSE_FILTER_PASS
	%StartButton.grab_focus()


func _show_stage_select() -> void:
	_refresh_stage_cards()
	var stage_buttons := _stage_buttons()
	var selected_index := ProgressStoreScript.last_played_stage() - 1
	_transition_to(stage_screen, $StageScreen/StageLayout/SmallLogo, %StageTitle, $StageScreen/StageLayout/CardsSlot/Cards, %BackButton, stage_buttons[selected_index])


func _hide_stage_select() -> void:
	_stop_stage_preview()
	_transition_to_main(stage_screen, $StageScreen/StageLayout/SmallLogo, %StageTitle, $StageScreen/StageLayout/CardsSlot/Cards, %BackButton)


func _transition_to(
		target_screen: Control,
		target_logo: Control,
		target_title: Control,
	target_body: Control,
	back_button: Control,
	focus_target: Control = null,
	animate_logo: bool = true,
) -> void:
	await _transition_controller.transition_to(target_screen, target_logo, target_title, target_body, back_button, focus_target, animate_logo)


func _transition_to_main(
		current_screen: Control,
		current_logo: Control,
		current_title: Control,
	current_body: Control,
	back_button: Control,
	animate_logo: bool = true,
) -> void:
	await _transition_controller.transition_to_main(current_screen, current_logo, current_title, current_body, back_button, animate_logo)


func _clear_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or _transition_controller.is_transitioning():
		return
	if overlay.visible:
		_hide_overlay()
	elif stage_screen.visible:
		_hide_stage_select()
	elif settings_screen.visible:
		_hide_settings()
	elif main_content.visible:
		_show_exit()
	else:
		return
	get_viewport().set_input_as_handled()
