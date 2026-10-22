extends SceneTree

const ProgressStoreScript = preload("res://level/progress_store.gd")

var _failures := 0


func _init() -> void:
	_expect(ProgressStoreScript.next_unlocked_stage(1, 1) == 2, "stage one unlocks stage two")
	_expect(ProgressStoreScript.next_unlocked_stage(2, 2) == 3, "stage two unlocks stage three")
	_expect(ProgressStoreScript.next_unlocked_stage(3, 3) == 4, "stage three unlocks stage four")
	_expect(ProgressStoreScript.next_unlocked_stage(1, 4) == 4, "replay does not reduce progress")
	_expect(ProgressStoreScript.next_unlocked_stage(8, 8) == 9, "stage eight unlocks Matadora")
	_expect(ProgressStoreScript.next_unlocked_stage(9, 9) == 9, "last stage stays capped")
	var empty_record := ProgressStoreScript.stage_record(ProgressStoreScript.LAST_STAGE)
	_expect(empty_record.has_all(["score", "rank", "accuracy", "max_combo", "average_offset_ms", "mean_absolute_error_ms", "early_inputs", "cleared"]), "stage record has a stable shape")
	_expect(ProgressStoreScript.is_better_record(1000, true, 900), "higher completed score updates record")
	_expect(not ProgressStoreScript.is_better_record(800, true, 900), "lower score keeps record")
	_expect(not ProgressStoreScript.is_better_record(1200, false, 900), "failed run cannot replace record")
	_expect(ProgressStoreScript.star_rating(100.0)["tier"] == "diamond", "all Perfect awards diamond stars")
	_expect(ProgressStoreScript.star_rating(95.0) == {"tier": "gold", "stars": 3}, "high accuracy awards three gold stars")
	_expect(ProgressStoreScript.star_rating(80.0) == {"tier": "silver", "stars": 2}, "mid accuracy awards two silver stars")
	_expect(ProgressStoreScript.star_rating(60.0) == {"tier": "bronze", "stars": 1}, "a clear awards one bronze star")
	if _failures == 0:
		print("Progress store tests passed: 14 assertions")
		quit(0)
	else:
		push_error("Progress store tests failed: %d assertion(s)" % _failures)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
