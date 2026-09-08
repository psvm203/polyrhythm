class_name RhythmClock
extends RefCounted

var time_source_usec: Callable
var start_usec: int = 0
var paused_at_usec: int = -1
var paused_total_usec: int = 0
var running: bool = false


func reset() -> void:
	start_usec = 0
	paused_at_usec = -1
	paused_total_usec = 0
	running = false


func start(at_usec: int = -1) -> void:
	start_usec = now_usec() if at_usec < 0 else at_usec
	paused_at_usec = -1
	paused_total_usec = 0
	running = true


func pause(at_usec: int = -1) -> void:
	if not running or paused_at_usec >= 0:
		return
	paused_at_usec = now_usec() if at_usec < 0 else at_usec


func resume(at_usec: int = -1) -> void:
	if not running or paused_at_usec < 0:
		return
	var resume_usec := now_usec() if at_usec < 0 else at_usec
	paused_total_usec += maxi(resume_usec - paused_at_usec, 0)
	paused_at_usec = -1


func elapsed_usec(at_usec: int = -1) -> int:
	if not running:
		return 0
	var sample_usec := paused_at_usec if paused_at_usec >= 0 else (now_usec() if at_usec < 0 else at_usec)
	return maxi(sample_usec - start_usec - paused_total_usec, 0)


func elapsed_sec(at_usec: int = -1) -> float:
	return float(elapsed_usec(at_usec)) / 1_000_000.0


func is_paused() -> bool:
	return running and paused_at_usec >= 0


func now_usec() -> int:
	if time_source_usec.is_valid():
		return int(time_source_usec.call())
	return Time.get_ticks_usec()
