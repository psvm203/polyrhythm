class_name SequenceTimeline
extends Control

const ShapeFactoryScript = preload("res://level/geometry/shape_factory.gd")

signal selection_changed(index: int)
signal sequence_changed(sequence: Array[int])
signal tile_inserted(index: int)
signal tile_removed(index: int)
signal tile_moved(from_index: int, to_index: int)

const TILE_SIZE := 74.0
const TILE_GAP := 24.0
const CANVAS_PADDING := 54.0
const MAP_SIDE_LENGTH := 58.0

var sequence: Array[int] = []
var selected_index := -1
var _drag_from := -1
var _drag_position := Vector2.ZERO
var _map_mode := false
var _map_shapes: Array[PackedVector2Array] = []
var _map_centers := PackedVector2Array()
var _map_starter := PackedVector2Array()
var _map_offset := Vector2.ZERO
var _event_tiles: Dictionary = {}


func _ready() -> void:
	custom_minimum_size.y = 250.0
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	resized.connect(queue_redraw)
	if get_parent() is ScrollContainer:
		get_parent().get_h_scroll_bar().value_changed.connect(func(_value: float) -> void: queue_redraw())
		get_parent().get_v_scroll_bar().value_changed.connect(func(_value: float) -> void: queue_redraw())


func set_sequence(values: Array) -> void:
	sequence.clear()
	for value in values:
		sequence.append(int(value))
	selected_index = mini(selected_index, sequence.size() - 1)
	_refresh()


func set_map_mode(enabled: bool) -> void:
	_map_mode = enabled
	_refresh()


func set_events(events: Array) -> void:
	_event_tiles.clear()
	for event in events:
		if not event is Dictionary:
			continue
		for polygon_number in event.get("at", []):
			_event_tiles[int(polygon_number) - 1] = true
	queue_redraw()


func add_tile(sides: int) -> void:
	var insert_at := selected_index + 1 if selected_index >= 0 else sequence.size()
	sequence.insert(insert_at, sides)
	tile_inserted.emit(insert_at)
	select(insert_at)
	_changed()


func delete_selected() -> void:
	if selected_index < 0 or selected_index >= sequence.size():
		return
	sequence.remove_at(selected_index)
	tile_removed.emit(selected_index)
	select(mini(selected_index, sequence.size() - 1))
	_changed()


func duplicate_selected() -> void:
	if selected_index < 0 or selected_index >= sequence.size():
		return
	sequence.insert(selected_index + 1, sequence[selected_index])
	tile_inserted.emit(selected_index + 1)
	select(selected_index + 1)
	_changed()


func select(index: int) -> void:
	selected_index = clampi(index, -1, sequence.size() - 1)
	selection_changed.emit(selected_index)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _index_at(event.position)
		if event.pressed:
			_drag_from = index
			_drag_position = event.position
			select(index)
		elif _drag_from >= 0:
			var target := _drop_slot(event.position)
			if target >= 0:
				var value := sequence[_drag_from]
				sequence.remove_at(_drag_from)
				if target > _drag_from:
					target -= 1
				target = clampi(target, 0, sequence.size())
				sequence.insert(target, value)
				tile_moved.emit(_drag_from, target)
				select(target)
				_changed()
			_drag_from = -1
			queue_redraw()
	elif event is InputEventMouseMotion and _drag_from >= 0:
		_drag_position = event.position
		queue_redraw()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
			delete_selected()
		elif event.keycode == KEY_D and event.ctrl_pressed:
			duplicate_selected()
		elif event.keycode == KEY_LEFT:
			_select_relative(-1)
			accept_event()
		elif event.keycode == KEY_RIGHT:
			_select_relative(1)
			accept_event()


func _select_relative(direction: int) -> void:
	if sequence.is_empty():
		return
	if selected_index < 0:
		select(0 if direction > 0 else sequence.size() - 1)
	else:
		select(clampi(selected_index + direction, 0, sequence.size() - 1))
	_scroll_selected_into_view.call_deferred()


func _scroll_selected_into_view() -> void:
	if selected_index < 0 or not get_parent() is ScrollContainer:
		return
	var scroll := get_parent() as ScrollContainer
	var center := _map_centers[selected_index] + _map_offset if _map_mode else _tile_rect(selected_index).get_center()
	scroll.scroll_horizontal = roundi(center.x - scroll.size.x * 0.5)
	if _map_mode:
		scroll.scroll_vertical = roundi(center.y - scroll.size.y * 0.5)


func _index_at(position: Vector2) -> int:
	if _map_mode:
		for index in _map_shapes.size():
			if Geometry2D.is_point_in_polygon(position - _map_offset, _map_shapes[index]):
				return index
		return -1
	for index in sequence.size():
		if _tile_rect(index).grow(8.0).has_point(position):
			return index
	return -1


func _drop_slot(position: Vector2) -> int:
	if sequence.is_empty() or position.y < 45.0 or position.y > 195.0:
		if _map_mode:
			return _index_at(position)
		return -1
	if _map_mode:
		return _index_at(position)
	var first_center := _tile_rect(0).get_center().x
	var step := TILE_SIZE + TILE_GAP
	return clampi(floori((position.x - first_center + step * 0.5) / step), 0, sequence.size())


func _tile_rect(index: int) -> Rect2:
	var center := Vector2(CANVAS_PADDING + TILE_SIZE * 0.5 + index * (TILE_SIZE + TILE_GAP), 118.0)
	return Rect2(center - Vector2.ONE * TILE_SIZE * 0.5, Vector2.ONE * TILE_SIZE)


func _draw() -> void:
	_draw_grid()
	if sequence.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(54, 126), "아래 팔레트에서 도형을 추가하세요", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color("7992ad"))
		return
	if _map_mode:
		_draw_map()
		if _drag_from >= 0:
			_draw_drag_preview()
		return
	for index in sequence.size() - 1:
		var from := _tile_rect(index).get_center()
		var to := _tile_rect(index + 1).get_center()
		draw_line(from, to, Color("24566f"), 5.0, true)
	for index in sequence.size():
		_draw_tile(index)
	if _drag_from >= 0:
		_draw_drop_indicator()
		_draw_drag_preview()


func _draw_grid() -> void:
	# Restrict the grid to the visible region even for very long levels.
	var scroll := get_parent() as ScrollContainer
	var origin := Vector2(scroll.scroll_horizontal, scroll.scroll_vertical) if scroll else Vector2.ZERO
	var visible_size := scroll.size if scroll else size
	for x in range(int(origin.x / 28) * 28, int(origin.x + visible_size.x) + 28, 28):
		for y in range(int(origin.y / 28) * 28, int(origin.y + visible_size.y) + 28, 28):
			draw_circle(Vector2(x, y), 0.8, Color("223043"))
	if not _map_mode:
		draw_line(Vector2(origin.x, 32), Vector2(origin.x + visible_size.x, 32), Color("29384b"), 1)
		for index in sequence.size():
			var x := _tile_rect(index).get_center().x
			draw_line(Vector2(x, 26), Vector2(x, 38), Color("526a80"), 1)


func _draw_tile(index: int) -> void:
	var sides := sequence[index]
	var center := _tile_rect(index).get_center()
	var radius := TILE_SIZE * 0.42
	var points := PackedVector2Array()
	for point_index in sides:
		var angle := -PI * 0.5 + TAU * point_index / sides
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	var selected := index == selected_index
	if selected:
		draw_style_box(_selection_style(), _tile_rect(index).grow(10))
	var fill := Color("24685f") if selected else Color("1c3448")
	var outline := Color("c9fff7") if selected else Color("48a9b8")
	draw_colored_polygon(points, fill)
	for point_index in sides:
		draw_line(points[point_index], points[(point_index + 1) % sides], outline, 2.0, true)
	var label := str(sides)
	var font := ThemeDB.fallback_font
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	draw_string(font, center + Vector2(-width * 0.5, 7), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, center + Vector2(-8, 61), str(index + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("7799ad"))
	_draw_event_marker(index, center + Vector2(25, -28))


func _draw_drag_preview() -> void:
	var sides := sequence[_drag_from]
	var radius := TILE_SIZE * 0.46
	var points := PackedVector2Array()
	for point_index in sides:
		var angle := -PI * 0.5 + TAU * point_index / sides
		points.append(_drag_position + Vector2(cos(angle), sin(angle)) * radius)
	draw_colored_polygon(points, Color(0.18, 0.95, 0.84, 0.58))
	for point_index in sides:
		draw_line(points[point_index], points[(point_index + 1) % sides], Color(0.82, 1, 0.97, 0.9), 3.0, true)


func _draw_drop_indicator() -> void:
	var slot := _drop_slot(_drag_position)
	if slot < 0:
		return
	var step := TILE_SIZE + TILE_GAP
	var x := _tile_rect(0).get_center().x - step * 0.5 + slot * step
	draw_line(Vector2(x, 58), Vector2(x, 178), Color("fff27a"), 4.0, true)


func _draw_map() -> void:
	if not _map_starter.is_empty():
		var starter := _translated(_map_starter)
		draw_colored_polygon(starter, Color(0.08, 0.18, 0.25, 0.7))
		_draw_polygon_outline(starter, Color("315c70"), 2.0)
	for index in _map_shapes.size():
		var points := _translated(_map_shapes[index])
		var selected := index == selected_index
		draw_colored_polygon(points, Color("2de2c5") if selected else Color("173d59"))
		_draw_polygon_outline(points, Color("c9fff7") if selected else Color("48a9b8"), 4.0 if selected else 2.5)
		var center := _map_centers[index] + _map_offset
		var label := str(sequence[index])
		var width := ThemeDB.fallback_font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
		draw_string(ThemeDB.fallback_font, center + Vector2(-width * 0.5, 6), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		_draw_event_marker(index, center + Vector2(22, -22))


func _draw_event_marker(index: int, position: Vector2) -> void:
	if not _event_tiles.has(index):
		return
	draw_circle(position, 8.0, Color("ffb84d"))
	draw_string(ThemeDB.fallback_font, position + Vector2(-4, 4), "E", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("151020"))


func _draw_polygon_outline(points: PackedVector2Array, color: Color, width: float) -> void:
	for index in points.size():
		draw_line(points[index], points[(index + 1) % points.size()], color, width, true)


func _translated(points: PackedVector2Array) -> PackedVector2Array:
	var translated := PackedVector2Array()
	for point in points:
		translated.append(point + _map_offset)
	return translated


func _changed() -> void:
	sequence_changed.emit(sequence.duplicate())
	_refresh()


func _refresh() -> void:
	if _map_mode:
		_rebuild_map()
	else:
		custom_minimum_size = Vector2(maxf(900.0, CANVAS_PADDING * 2.0 + sequence.size() * (TILE_SIZE + TILE_GAP)), 250.0)
	queue_redraw()


func _rebuild_map() -> void:
	_map_shapes.clear()
	_map_centers.clear()
	_map_starter.clear()
	if sequence.is_empty():
		custom_minimum_size = Vector2(900, 250)
		return
	var factory := ShapeFactoryScript.new()
	var result: Dictionary = factory.build(sequence, MAP_SIDE_LENGTH, Vector2.ZERO)
	_map_shapes.assign(result["shapes"])
	_map_centers = result["polygon_centers"]
	var half_edge := Vector2(MAP_SIDE_LENGTH * 0.5, 0)
	_map_starter = factory.build_polygon_on_edge(3, half_edge, -half_edge)
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for shape in _map_shapes:
		for point in shape:
			minimum = minimum.min(point)
			maximum = maximum.max(point)
	for point in _map_starter:
		minimum = minimum.min(point)
		maximum = maximum.max(point)
	_map_offset = Vector2.ONE * CANVAS_PADDING - minimum
	var map_size := maximum - minimum + Vector2.ONE * CANVAS_PADDING * 2.0
	custom_minimum_size = Vector2(maxf(900.0, map_size.x), maxf(250.0, map_size.y))


func _selection_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.39, 0.89, 0.80, 0.07)
	style.border_color = Color(0.39, 0.89, 0.80, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	return style
