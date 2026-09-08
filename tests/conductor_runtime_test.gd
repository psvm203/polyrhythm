extends SceneTree

const ConductorScript = preload("res://level/actors/conductor.gd")
const RotatorScript = preload("res://level/actors/rotator.gd")

var failures := 0
var assertions := 0

class AudioReference extends Node:
	var playing := true
	var stream_paused := false
	var position := 0.0

	func get_playback_position() -> float:
		return position


func _init() -> void:
	call_deferred("_run")


func fixture(offset: float = 0.0) -> Dictionary:
	var parent := Node2D.new()
	var r = RotatorScript.new()
	r.name = "Rotator"
	var c = ConductorScript.new()
	c.name = "Conductor"
	parent.add_child(r)
	parent.add_child(c)
	root.add_child(parent)
	r.set_process(false)
	c.set_process(false)
	c.set_process_unhandled_input(false)
	var poly := PackedVector2Array([Vector2(-50, 0), Vector2(0, 86.6), Vector2(50, 0)])
	var polys: Array[PackedVector2Array] = [poly, poly, poly]
	var edge := PackedVector2Array([Vector2(50, 0), Vector2(-50, 0)])
	var edges: Array[PackedVector2Array] = [edge, edge, edge]
	r.setup(polys, PackedVector2Array([Vector2(0,28.867), Vector2(0,28.867), Vector2(0,28.867)]), PackedInt32Array([3,3,3]), edges, PackedFloat32Array([0,0,0]), PackedVector2Array([Vector2(0,-260),Vector2(0,-260),Vector2(0,-260)]), 1.0)
	var now := [1000000]
	c.time_source_usec = func() -> int: return now[0]
	c.detailed_timing_logs = false
	c.judgment_offset_sec = offset
	c.setup(PackedFloat32Array([1.0,2.0,3.0]))
	c.start()
	r.paused = false
	var results: Array = []
	c.judged.connect(func(result, index, delta): results.append([result,index,delta]))
	return {"parent":parent,"r":r,"c":c,"now":now,"results":results}


func press(f: Dictionary, at: float) -> void:
	f.now[0] = 1000000 + roundi(at * 1000000)
	var event := InputEventKey.new()
	event.physical_keycode = KEY_SPACE
	event.pressed = true
	f.c._unhandled_input(event)


func tick(f: Dictionary, at: float) -> void:
	f.now[0] = 1000000 + roundi(at * 1000000)
	f.c._process(0.0)


func expect(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		push_error(message)


func _run() -> void:
	for fps in [30, 60, 120, 144]:
		for phase in [0.0, 0.25, 0.75, 1.0]:
			var f := fixture()
			var before: float = 1.0 - phase / fps
			tick(f, before)
			# Deliberately provide a stale visual frame at the exact note timestamp.
			press(f, 1.0)
			expect(f.results.size() == 1 and f.results[0][0] == "Perfect", "%d FPS phase %.2f preserves exact input" % [fps, phase])
			expect(is_zero_approx(f.c.timing_trace.latest()["timing_delta_ms"]), "exact input keeps zero delta")
			f.parent.free()
	for lag in [0.060, 0.120, 0.500]:
		var f := fixture()
		tick(f, 1.0 - lag)
		press(f, 1.0)
		expect(f.results[0][0] == "Perfect", "stale render never shifts input center")
		f.parent.free()
	for offset in [-0.150, -0.100, 0.0, 0.150]:
		var f := fixture(offset)
		press(f, 1.0 + offset)
		if offset < 0.0:
			expect(f.r.current_index == 0 and not f.r.is_fly_in_complete(), "negative offset does not snap early")
			expect(f.results.is_empty(), "early accepted hit waits for contact")
			tick(f, 1.0)
		expect(f.results.size() == 1 and f.results[0][0] == "Perfect", "offset center is Perfect exactly once")
		expect(f.r.current_index == 1, "resolved contact advances presentation")
		tick(f, 1.25)
		expect(f.results.size() == 1, "accepted hit is never emitted twice")
		f.parent.free()
	var stalled := fixture()
	tick(stalled, 2.5)
	expect(stalled.results.size() == 2, "long stall expires all elapsed notes")
	expect(stalled.r.current_index == 2, "long stall catches up presentation")
	expect(is_equal_approx(stalled.r.get_transition_progress(), 0.5), "next polygon uses absolute progress")
	press(stalled, 3.0)
	expect(stalled.results.size() == 3 and stalled.results[2][0] == "Perfect", "stall does not shift following note")
	expect(stalled.r.is_completed(), "final resolved note completes presentation")
	stalled.parent.free()
	var expired := fixture()
	press(expired, 2.0)
	expect(expired.results.size() == 2, "input between frames expires older note first")
	expect(expired.results[0][0] == "Too Slow" and expired.results[1][0] == "Perfect", "input targets first unexpired note")
	expect(expired.c.timing_trace.latest()["polygon_index"] == 1, "trace follows input ownership")
	expired.parent.free()
	for delta in [-0.051, -0.050, -0.025, 0.025, 0.100]:
		var f := fixture()
		press(f, 1.0 + delta)
		expect(f.c.timing_trace.latest()["result"] == f.c.classify_timing_delta(delta), "runtime respects boundary %.3f" % delta)
		if delta == -0.051:
			press(f, 1.0)
			expect(f.results.size() == 2 and f.results[1][0] == "Perfect", "Too Fast does not consume note")
		f.parent.free()
	var dense := fixture(-0.150)
	dense.c.setup(PackedFloat32Array([1.0, 1.0625, 1.125]))
	dense.c.start()
	press(dense, 0.85)
	press(dense, 0.9125)
	expect(dense.results.is_empty(), "multiple early notes can queue before first contact")
	tick(dense, 1.0)
	expect(dense.results.size() == 1, "only arrived note is displayed")
	tick(dense, 1.0625)
	expect(dense.results.size() == 2 and dense.results[1][0] == "Perfect", "second early input survives pending presentation")
	dense.parent.free()
	var paused := fixture(-0.100)
	press(paused, 0.9)
	paused.c.pause_clock(&"boss")
	paused.c.pause_clock(&"manual")
	paused.now[0] += 5000000
	paused.c.resume_clock(&"manual")
	expect(paused.c.paused and paused.r.paused, "menu resume preserves boss pause")
	expect(is_equal_approx(paused.c._get_game_time(), 0.9), "nested pause freezes game time")
	paused.c.resume_clock(&"boss")
	paused.now[0] += 100000
	paused.c._process(0.0)
	expect(paused.results.size() == 1 and paused.results[0][0] == "Perfect", "pending input survives pause without delta change")
	paused.parent.free()
	var stopped := fixture()
	stopped.c.judged.connect(func(_r, _i, _d): stopped.c.pause_clock())
	tick(stopped, 3.5)
	expect(stopped.results.size() == 1, "synchronous result pause stops catch-up immediately")
	stopped.c.resume_clock()
	stopped.c._process(0.0)
	expect(stopped.results.size() == 2, "resume advances without repeating emitted note")
	stopped.parent.free()
	var visual := fixture()
	tick(visual, 0.5)
	visual.r._process(0.5)
	expect(is_equal_approx(visual.r.get_transition_progress(), 0.5), "rotator cannot integrate an extra render delta")
	visual.parent.free()
	var changed_offset := fixture(-0.100)
	press(changed_offset, 0.9)
	changed_offset.c.judgment_offset_sec = 0.150
	tick(changed_offset, 1.0)
	expect(changed_offset.results.size() == 1 and is_zero_approx(changed_offset.results[0][2]), "offset edit preserves already accepted delta")
	changed_offset.parent.free()
	var early_miss := fixture(-0.150)
	tick(early_miss, 0.96)
	expect(early_miss.results.is_empty() and not early_miss.r.is_fly_in_complete(), "negative-offset miss also waits for visual contact")
	tick(early_miss, 1.0)
	expect(early_miss.results.size() == 1 and early_miss.results[0][0] == "Too Slow", "expired early window emits one miss on contact")
	early_miss.parent.free()
	var audio := fixture()
	var reference := AudioReference.new()
	audio.parent.add_child(reference)
	audio.c.set_audio_reference(reference)
	for index in 100:
		reference.position = 0.0 if index % 2 == 0 else 5.0
		tick(audio, 0.5)
	expect(is_equal_approx(audio.c._get_game_time(), 0.5), "repeated audio samples cannot alter the clock")
	press(audio, 1.0)
	expect(audio.results[0][0] == "Perfect", "audio jumps cannot shift judgment")
	audio.parent.free()
	print("Conductor runtime tests: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
