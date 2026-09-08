extends Node2D

const ContactSolverScript = preload("res://level/timing/contact_solver.gd")

signal polygon_advanced(from_index: int, to_index: int)

var polygons: Array[PackedVector2Array] = []
var polygon_centers: PackedVector2Array = PackedVector2Array()
var sides_counts: PackedInt32Array = PackedInt32Array()
var entrance_edges_world: Array[PackedVector2Array] = []
var exit_angle_offsets: PackedFloat32Array = PackedFloat32Array()
var start_offsets: PackedVector2Array = PackedVector2Array()

var transition_duration: float = 0.32
var current_index: int = 0
var angle: float = 0.0
var angular_speed: float = 0.0
var completed: bool = false
var last_index: int = -1
var paused: bool = true
var clock_driven: bool = false
var _transition_time: float = 0.0
var current_offset: Vector2 = Vector2.ZERO
var _start_offset: Vector2 = Vector2.ZERO

var rotated_current: PackedVector2Array = PackedVector2Array()


func setup(
		polygons_arg: Array[PackedVector2Array],
		polygon_centers_arg: PackedVector2Array,
		sides_counts_arg: PackedInt32Array,
		entrance_edges_world_arg: Array[PackedVector2Array],
		exit_angle_offsets_arg: PackedFloat32Array,
		start_offsets_arg: PackedVector2Array,
		transition_duration_arg: float,
) -> void:
	polygons = polygons_arg
	polygon_centers = polygon_centers_arg
	sides_counts = sides_counts_arg
	entrance_edges_world = entrance_edges_world_arg
	exit_angle_offsets = exit_angle_offsets_arg
	start_offsets = start_offsets_arg
	transition_duration = maxf(transition_duration_arg, 0.0)
	current_index = 0
	last_index = polygons.size() - 1
	completed = false
	_enter_polygon(0)


func _enter_polygon(index: int) -> void:
	var previous_index := current_index
	current_index = clampi(index, 0, last_index) if last_index >= 0 else 0
	_transition_time = 0.0
	_start_offset = _start_offset_for(current_index)
	current_offset = _start_offset
	if sides_counts.size() > current_index:
		var sides: int = sides_counts[current_index]
		if sides > 0:
			# Use the externally-set transition_duration (may be adjusted by conductor
			# to align with the scheduled judgment time).
			angular_speed = TAU / maxf(transition_duration, 0.0001)
			angle = 0.0
		else:
			angular_speed = 0.0
			angle = 0.0
	else:
		angular_speed = 0.0
		angle = 0.0
	_compute_rotated_current()
	if previous_index != current_index:
		polygon_advanced.emit(previous_index, current_index)
	queue_redraw()


func set_transition_duration(value: float) -> void:
	transition_duration = maxf(value, 0.05)
	if current_index >= 0 and current_index < sides_counts.size():
		var sides: int = sides_counts[current_index]
		if sides > 0:
			angular_speed = TAU / transition_duration


func snap_to_target() -> void:
	current_offset = Vector2.ZERO
	angle = 0.0
	_transition_time = transition_duration
	_compute_rotated_current()


func restart_current_transition() -> void:
	if polygons.is_empty() or current_index < 0 or current_index > last_index:
		return
	_enter_polygon(current_index)


func _start_offset_for(index: int) -> Vector2:
	if index < 0 or index >= start_offsets.size():
		return Vector2.ZERO
	return start_offsets[index]


func advance_to_next() -> int:
	if polygons.is_empty():
		return -1
	if current_index >= last_index:
		completed = true
		return -1
	var next_index := current_index + 1
	_enter_polygon(next_index)
	return next_index


func is_completed() -> bool:
	return completed


func is_fly_in_complete() -> bool:
	if transition_duration <= 0.0:
		return true
	return _transition_time >= transition_duration


func get_rotated_polygon() -> PackedVector2Array:
	return rotated_current


func get_rotated_exit_edge_world() -> PackedVector2Array:
	if polygons.is_empty() or current_index < 0 or current_index >= polygons.size():
		return PackedVector2Array()
	var poly := polygons[current_index]
	var sides: int = sides_counts[current_index]
	var exit_a_index: int = 0 if current_index % 2 == 0 else sides - 2
	if exit_a_index < 0 or exit_a_index + 1 >= poly.size():
		return PackedVector2Array()
	var exit_a := poly[exit_a_index]
	var exit_b := poly[exit_a_index + 1]
	var center: Vector2 = polygon_centers[current_index]
	var rotated_a := center + (exit_a - center).rotated(angle)
	var rotated_b := center + (exit_b - center).rotated(angle)
	return PackedVector2Array([rotated_a, rotated_b])


func get_rotated_entrance_edge_world() -> PackedVector2Array:
	if polygons.is_empty() or current_index < 0 or current_index >= polygons.size():
		return PackedVector2Array()
	var poly := polygons[current_index]
	if poly.size() < 2:
		return PackedVector2Array()
	var center: Vector2 = polygon_centers[current_index]
	var world_center := center + current_offset
	# ShapeFactory builds the shared base as the closing edge: last vertex -> first vertex.
	var rotated_a := world_center + (poly[poly.size() - 1] - center).rotated(angle)
	var rotated_b := world_center + (poly[0] - center).rotated(angle)
	return PackedVector2Array([rotated_a, rotated_b])


func get_current_offset() -> Vector2:
	return current_offset


func get_transition_elapsed() -> float:
	return _transition_time


func get_transition_progress() -> float:
	if transition_duration <= 0.0:
		return 1.0
	return clampf(_transition_time / transition_duration, 0.0, 1.0)


func get_entrance_edge_gap() -> float:
	if current_index < 0 or current_index >= entrance_edges_world.size():
		return INF
	var moving_edge := get_rotated_entrance_edge_world()
	var target_edge: PackedVector2Array = entrance_edges_world[current_index]
	if moving_edge.size() < 2 or target_edge.size() < 2:
		return INF
	return ContactSolverScript.segment_gap(moving_edge, target_edge)


func get_target_world_position() -> Vector2:
	if polygons.is_empty():
		return Vector2.ZERO
	var target_index := current_index + 1
	if target_index >= entrance_edges_world.size():
		target_index = current_index
	if target_index < 0 or target_index >= entrance_edges_world.size():
		return polygon_centers[current_index]
	var entrance: PackedVector2Array = entrance_edges_world[target_index]
	if entrance.size() < 2:
		return polygon_centers[current_index]
	return (entrance[0] + entrance[1]) * 0.5


func get_alignment_delta() -> float:
	if polygons.is_empty():
		return 0.0
	var local_exit_angle: float = exit_angle_offsets[current_index]
	var current_exit_world_angle := local_exit_angle + angle
	var target_pos := get_target_world_position()
	var direction := target_pos - polygon_centers[current_index]
	if direction.length() < 0.0001:
		return 0.0
	var target_world_angle := direction.angle()
	return wrapf(target_world_angle - current_exit_world_angle, -PI, PI)


func get_alignment_time_delta() -> float:
	if polygons.is_empty():
		return 0.0
	var delta := get_alignment_delta()
	if angular_speed <= 0.0:
		return INF if delta > 0 else -INF
	return delta / angular_speed


func get_current_polygon_center() -> Vector2:
	if polygons.is_empty():
		return Vector2.ZERO
	return polygon_centers[current_index] + current_offset


func get_target_polygon_center() -> Vector2:
	return polygon_centers[current_index]


func get_next_polygon_center() -> Vector2:
	if polygons.is_empty():
		return Vector2.ZERO
	var next_index := current_index + 1
	if next_index >= polygons.size():
		return polygon_centers[current_index]
	return polygon_centers[next_index]


func get_polygon_center(index: int) -> Vector2:
	if index < 0 or index >= polygon_centers.size():
		return Vector2.ZERO
	return polygon_centers[index]


func get_entrance_edge(index: int) -> PackedVector2Array:
	if index < 0 or index >= entrance_edges_world.size():
		return PackedVector2Array()
	return entrance_edges_world[index]


func get_color_for_index(index: int, total: int) -> Color:
	if total <= 0:
		return Color.WHITE
	return Color.from_hsv(float(index) / total, 0.6, 1.0)


func _compute_rotated_current() -> void:
	rotated_current.clear()
	if polygons.is_empty() or current_index < 0 or current_index >= polygons.size():
		return
	var poly := polygons[current_index]
	var base_center: Vector2 = polygon_centers[current_index]
	var world_center: Vector2 = base_center + current_offset
	for i in poly.size():
		var local := poly[i] - base_center
		rotated_current.append(world_center + local.rotated(angle))


# Gameplay supplies absolute time. Standalone previews can still use frame deltas.
func sample_timeline(game_time: float, start_time: float, contact_time: float) -> void:
	transition_duration = maxf(contact_time - start_time, 0.000001)
	angular_speed = TAU / transition_duration
	_sample_elapsed(maxf(game_time - start_time, 0.0))


func _sample_elapsed(elapsed: float) -> void:
	_transition_time = elapsed
	var progress := get_transition_progress()
	current_offset = _start_offset.lerp(Vector2.ZERO, progress)
	angle = progress * TAU if progress < 1.0 else 0.0
	_compute_rotated_current()
	queue_redraw()


func _process(delta: float) -> void:
	if completed or polygons.is_empty() or paused or clock_driven:
		return
	_sample_elapsed(_transition_time + delta)
