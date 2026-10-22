class_name ProgressStore
extends RefCounted

const SAVE_PATH := "user://progress.cfg"
const SECTION := "progress"
const UNLOCKED_KEY := "highest_unlocked_stage"
const PENDING_DIALOGUE_KEY := "pending_unlock_dialogue"
const LAST_PLAYED_STAGE_KEY := "last_played_stage"
const SEEN_DIALOGUE_SECTION := "seen_dialogue"
const LAST_STAGE := 9

static var selected_stage := 1
static var show_stage_select_on_load := false
static var custom_level_path := ""
static var editor_working_file_path := ""
static var editor_saved_signature := ""
# Tests can isolate persistence without touching the player's records.
static var save_path := SAVE_PATH


static func highest_unlocked_stage() -> int:
	var config := _load()
	return clampi(int(config.get_value(SECTION, UNLOCKED_KEY, 1)), 1, LAST_STAGE)


static func last_played_stage() -> int:
	var config := _load()
	var highest := highest_unlocked_stage()
	return clampi(int(config.get_value(SECTION, LAST_PLAYED_STAGE_KEY, 1)), 1, highest)


static func mark_stage_played(stage: int) -> void:
	var config := _load()
	config.set_value(SECTION, LAST_PLAYED_STAGE_KEY, clampi(stage, 1, highest_unlocked_stage()))
	_save(config)


static func has_seen_dialogue(dialogue_id: String) -> bool:
	if dialogue_id.is_empty():
		return false
	return bool(_load().get_value(SEEN_DIALOGUE_SECTION, dialogue_id, false))


static func mark_dialogue_seen(dialogue_id: String) -> void:
	if dialogue_id.is_empty():
		return
	var config := _load()
	config.set_value(SEEN_DIALOGUE_SECTION, dialogue_id, true)
	_save(config)


static func unlock_next_stage(cleared_stage: int) -> int:
	var highest := highest_unlocked_stage()
	var unlocked := next_unlocked_stage(cleared_stage, highest)
	if unlocked == highest:
		return highest
	var config := _load()
	config.set_value(SECTION, UNLOCKED_KEY, unlocked)
	config.set_value(SECTION, PENDING_DIALOGUE_KEY, unlocked)
	_save(config)
	return unlocked


static func unlock_all_stages() -> Error:
	var config := _load()
	config.set_value(SECTION, UNLOCKED_KEY, LAST_STAGE)
	config.set_value(SECTION, PENDING_DIALOGUE_KEY, 0)
	return _save(config)


static func reset_all_records() -> Error:
	var error := _save(ConfigFile.new())
	if error == OK:
		selected_stage = 1
		show_stage_select_on_load = false
	return error


static func next_unlocked_stage(cleared_stage: int, highest_unlocked: int) -> int:
	return clampi(maxi(highest_unlocked, cleared_stage + 1), 1, LAST_STAGE)


static func pending_unlock_dialogue() -> int:
	var config := _load()
	return clampi(int(config.get_value(SECTION, PENDING_DIALOGUE_KEY, 0)), 0, LAST_STAGE)


static func consume_unlock_dialogue() -> int:
	var config := _load()
	var stage := clampi(int(config.get_value(SECTION, PENDING_DIALOGUE_KEY, 0)), 0, LAST_STAGE)
	if stage == 0:
		return 0
	config.set_value(SECTION, PENDING_DIALOGUE_KEY, 0)
	_save(config)
	return stage


static func stage_record(stage: int) -> Dictionary:
	var config := _load()
	var section := "stage_%d" % clampi(stage, 1, LAST_STAGE)
	return {
		"score": int(config.get_value(section, "score", 0)),
		"rank": str(config.get_value(section, "rank", "-")),
		"accuracy": float(config.get_value(section, "accuracy", 0.0)),
		"max_combo": int(config.get_value(section, "max_combo", 0)),
		"average_offset_ms": float(config.get_value(section, "average_offset_ms", 0.0)),
		"mean_absolute_error_ms": float(config.get_value(section, "mean_absolute_error_ms", 0.0)),
		"early_inputs": int(config.get_value(section, "early_inputs", 0)),
		"cleared": bool(config.get_value(section, "cleared", false)),
	}


static func record_run(stage: int, stats: Dictionary, rank: String, completed: bool) -> void:
	var previous := stage_record(stage)
	if not is_better_record(int(stats["score"]), completed, previous["score"]):
		return
	var config := _load()
	var section := "stage_%d" % clampi(stage, 1, LAST_STAGE)
	for key in ["score", "accuracy", "max_combo", "average_offset_ms", "mean_absolute_error_ms", "early_inputs"]:
		config.set_value(section, key, stats[key])
	config.set_value(section, "rank", rank)
	config.set_value(section, "cleared", true)
	_save(config)


static func is_better_record(score: int, completed: bool, previous_score: int) -> bool:
	return completed and score > previous_score


static func star_rating(accuracy: float, completed: bool = true) -> Dictionary:
	if not completed:
		return {"tier": "none", "stars": 0}
	if is_equal_approx(accuracy, 100.0):
		return {"tier": "diamond", "stars": 3}
	if accuracy >= 90.0:
		return {"tier": "gold", "stars": 3}
	if accuracy >= 75.0:
		return {"tier": "silver", "stars": 2}
	return {"tier": "bronze", "stars": 1}


static func _load() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(save_path)
	return config


static func _save(config: ConfigFile) -> Error:
	var error := config.save(save_path)
	if error != OK:
		push_error("Failed to save progress: %s" % error_string(error))
	return error
