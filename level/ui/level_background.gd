extends Control

# Base, primary glow, secondary glow, in campaign order.
const PALETTES := [
	[Color("071126"), Color("438cff"), Color("a45dff")], # Rhythm Start
	[Color("0c191a"), Color("9bbd94"), Color("eadbab")], # Circle Of Life
	[Color("041b22"), Color("19e0db"), Color("c1ed68")], # Electric Elegance
	[Color("210912"), Color("f05275"), Color("ffc1a0")], # Shape Samurai
	[Color("150c29"), Color("ac78ff"), Color("e9c876")], # Time Rift
	[Color("071d16"), Color("52e69a"), Color("67dbe8")], # Music Is Life
	[Color("091827"), Color("609fe8"), Color("b7dceb")], # Keep Me Down
	[Color("200b25"), Color("f660c5"), Color("9277ff")], # Freak Tonight
]

var _stage: int = 1
var _base: Color = PALETTES[0][0]
var _primary: Color = PALETTES[0][1]
var _secondary: Color = PALETTES[0][2]
var _motion_time: float = 0.0
var _analyzer: AudioEffectSpectrumAnalyzerInstance
var _bass: float = 0.0
var _mid: float = 0.0
var _treble: float = 0.0
var restoration: Control


func setup(stage_number: int) -> void:
	_stage = stage_number if stage_number >= 1 and stage_number <= PALETTES.size() else 1
	_base = PALETTES[_stage - 1][0]
	_primary = PALETTES[_stage - 1][1]
	_secondary = PALETTES[_stage - 1][2]
	if restoration != null:
		remove_child(restoration)
		restoration.queue_free()
		restoration = null
	if _stage == 2:
		restoration = preload("res://level/ui/city_restoration.gd").new()
		add_child(restoration)
		restoration.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	queue_redraw()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()


func _process(delta: float) -> void:
	_motion_time += delta
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
	_bass = _smoothed_energy(_bass, _frequency_energy(35.0, 180.0), delta, 10.0)
	_mid = _smoothed_energy(_mid, _frequency_energy(180.0, 2200.0), delta, 8.0)
	_treble = _smoothed_energy(_treble, _frequency_energy(2200.0, 9000.0), delta, 12.0)


func _frequency_energy(from_hz: float, to_hz: float) -> float:
	var magnitude := _analyzer.get_magnitude_for_frequency_range(from_hz, to_hz)
	var amplitude := maxf(magnitude.x, magnitude.y)
	if amplitude <= 0.000001:
		return 0.0
	return clampf((linear_to_db(amplitude) + 55.0) / 45.0, 0.0, 1.0)


func _smoothed_energy(current: float, target: float, delta: float, speed: float) -> float:
	return lerpf(current, target, 1.0 - exp(-speed * delta))


func _draw() -> void:
	var view := size
	draw_rect(Rect2(Vector2.ZERO, view), _base)
	if _stage == 2:
		return
	_draw_glow(view)
	match _stage:
		1: _draw_orbits(view)
		3: _draw_grid(view)
		4: _draw_slashes(view)
		5: _draw_clock(view)
		6: _draw_waves(view)
		7: _draw_rain(view)
		8: _draw_tunnel(view)
	_draw_particles(view)


func _draw_glow(view: Vector2) -> void:
	var upper_center := Vector2(view.x * 0.52, view.y * 0.34)
	upper_center += Vector2(sin(_motion_time * 0.7) * _mid * 12.0, cos(_motion_time * 0.55) * _bass * 8.0)
	for ring in range(40, 0, -1):
		var ratio := float(ring) / 40.0
		draw_circle(upper_center, view.length() * (0.62 + _bass * 0.012) * ratio, Color(_primary, 0.006 + _bass * 0.002))
	var lower_center := Vector2(view.x * 0.46, view.y * 0.88)
	for ring in range(18, 0, -1):
		var ratio := float(ring) / 18.0
		draw_circle(lower_center, view.x * 0.28 * ratio, Color(_secondary, 0.006))


func _draw_grid(view: Vector2) -> void:
	var spacing := maxf(80.0, view.x / 16.0)
	var color := Color(_primary, 0.08 + _mid * 0.035)
	var flow_boost := 1.0 + _mid * 0.8
	var x := fmod(_motion_time * 7.0 * flow_boost, spacing) - spacing
	while x <= view.x:
		draw_line(Vector2(x, 0.0), Vector2(x, view.y), color, 1.0)
		x += spacing
	var y := fmod(_motion_time * 4.0 * flow_boost, spacing) - spacing
	while y <= view.y:
		draw_line(Vector2(0.0, y), Vector2(view.x, y), color, 1.0)
		y += spacing
	for index in range(6):
		var point := Vector2(
			fposmod(_motion_time * 7.0 * flow_boost + index * spacing * 3.0, view.x + spacing),
			fposmod(_motion_time * 4.0 * flow_boost + index * spacing * 2.0, view.y + spacing),
		)
		draw_circle(point, 4.0 + _treble * 2.0, Color(_secondary, 0.35))


func _draw_orbits(view: Vector2) -> void:
	var drift_scale := 1.0 + _mid * 0.55
	var drift := Vector2(sin(_motion_time * 0.13) * view.x * 0.01, cos(_motion_time * 0.1) * view.y * 0.008) * drift_scale
	var center := Vector2(view.x * 0.42, view.y * 0.92) + drift
	var turn := _motion_time * 0.012
	var bass_scale := 1.0 + _bass * 0.025
	var mid_scale := 1.0 + _mid * 0.018
	draw_arc(center, view.x * 0.54 * bass_scale, turn, turn + TAU, 160, Color(_secondary, 0.22 + _bass * 0.16), 2.2 + _bass * 1.4, true)
	draw_arc(center, view.x * 0.72 * mid_scale, -turn * 0.7, -turn * 0.7 + TAU, 192, Color(_primary, 0.18 + _mid * 0.12), 2.0 + _mid * 0.8, true)
	draw_arc(center, view.x * 0.34 * bass_scale, turn * 1.3, turn * 1.3 + TAU, 128, Color(_primary, 0.11 + _treble * 0.10), 1.5 + _treble * 0.7, true)


func _draw_slashes(view: Vector2) -> void:
	var moon := Vector2(view.x * 0.78, view.y * 0.28)
	draw_circle(moon, view.y * (0.15 + _bass * 0.005), Color(_primary, 0.10))
	draw_arc(moon, view.y * 0.18, PI * 0.15, PI * 1.8, 96, Color(_secondary, 0.18), 1.5, true)
	for index in range(9):
		var x := view.x * (float(index) / 6.0 - 0.2) + sin(_motion_time * 0.2 + index) * 14.0
		var start := Vector2(x, view.y * 1.1)
		var end := Vector2(x + view.x * 0.38, -view.y * 0.1)
		draw_line(start, end, Color(_primary, 0.06 + _mid * 0.025), 8.0, true)
		draw_line(start, end, Color(_secondary, 0.12), 1.0, true)


func _draw_clock(view: Vector2) -> void:
	var center := Vector2(view.x * 0.76, view.y * 0.46)
	var radius := view.y * (0.38 + _bass * 0.008)
	for ring in [0.72, 1.0, 1.12]:
		draw_arc(center, radius * ring, 0.0, TAU, 128, Color(_primary, 0.18), 1.5, true)
	for tick in range(60):
		var angle := TAU * tick / 60.0 + _motion_time * 0.025
		var direction := Vector2.from_angle(angle)
		var major := tick % 5 == 0
		draw_line(center + direction * radius * (0.88 if major else 0.95), center + direction * radius, Color(_secondary, 0.28 if major else 0.12), 2.0 if major else 1.0, true)
	for hand in range(2):
		var angle := _motion_time * (0.08 if hand == 0 else -0.16) - PI * 0.5
		draw_line(center, center + Vector2.from_angle(angle) * radius * (0.55 if hand == 0 else 0.82), Color(_secondary, 0.22), 2.0, true)


func _draw_waves(view: Vector2) -> void:
	for band in range(6):
		var points := PackedVector2Array()
		for step in range(81):
			var x := float(step) / 80.0
			var wave := sin(x * TAU * 1.4 + _motion_time * 0.3 + band * 0.6)
			var y := 0.55 + band * 0.065 + wave * (0.08 + _mid * 0.015)
			points.append(Vector2(x * view.x, y * view.y))
		draw_polyline(points, Color(_primary.lerp(_secondary, float(band) / 5.0), 0.14 + _bass * 0.06), 1.5, true)


func _draw_rain(view: Vector2) -> void:
	for index in range(36):
		var depth := 0.4 + float(index % 5) * 0.15
		var x := fposmod(index * 0.618, 1.0) * view.x
		var y := fposmod(index * 97.0 + _motion_time * 32.0 * depth, view.y + 120.0) - 60.0
		var start := Vector2(x, y)
		var end := start + Vector2(-18.0, 65.0) * depth
		draw_line(start, end, Color(_primary, 0.08 + depth * 0.10 + _treble * 0.04), 1.0, true)
		draw_circle(end, 1.5 * depth, Color(_secondary, 0.25))


func _draw_tunnel(view: Vector2) -> void:
	var center := Vector2(view.x * 0.68, view.y * 0.44)
	for ring in range(9):
		var depth := fposmod(float(ring) / 9.0 + _motion_time * 0.015, 1.0)
		var radius := (0.08 + depth * depth) * view.length() * 0.7
		var points := PackedVector2Array()
		for corner in range(7):
			var angle := TAU * corner / 6.0 + _motion_time * 0.025 + depth * 0.3
			points.append(center + Vector2.from_angle(angle) * radius)
		var color := _primary.lerp(_secondary, depth)
		draw_polyline(points, Color(color, sin(depth * PI) * (0.18 + _bass * 0.06)), 1.5, true)


func _draw_particles(view: Vector2) -> void:
	var particles := [
		[Vector2(0.06, 0.25), _secondary, 2.2],
		[Vector2(0.12, 0.72), _secondary, 2.0],
		[Vector2(0.23, 0.52), _primary, 3.0],
		[Vector2(0.64, 0.08), _primary, 2.4],
		[Vector2(0.77, 0.18), _secondary, 2.5],
		[Vector2(0.91, 0.34), _primary, 3.0],
		[Vector2(0.86, 0.68), _primary, 2.4],
		[Vector2(0.72, 0.88), _secondary, 2.3],
		[Vector2(0.10, 0.91), _secondary, 2.0],
	]
	for index in particles.size():
		var item: Array = particles[index]
		var phase := float(index) * 1.73
		var response_radius := 1.0 + _mid * 0.65
		var drift := Vector2(
			cos(_motion_time * (0.18 + _treble * 0.05) + phase) * (7.0 + index % 3 * 2.0),
			sin(_motion_time * (0.14 + _treble * 0.04) + phase) * (5.0 + index % 2 * 2.0),
		) * response_radius
		var point: Vector2 = item[0] * view + drift
		var color: Color = item[1]
		var radius: float = item[2] * (1.0 + sin(_motion_time + phase) * 0.08 + _treble * 0.38)
		var glow := color
		glow.a = 0.07 + _treble * 0.10
		draw_circle(point, radius * 3.8, glow)
		draw_circle(point, radius, color)
