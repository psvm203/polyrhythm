extends SceneTree

const Progress = preload("res://level/progress_store.gd")
const Catalog = preload("res://level/data/stage_catalog.gd")
var failures := 0

func _init() -> void:
	var original_path: String = Progress.save_path
	Progress.save_path = "/tmp/polyrhythm_reorder_%d.cfg" % OS.get_process_id()
	var old := ConfigFile.new()
	old.set_value("progress", "highest_unlocked_stage", 9)
	old.set_value("progress", "last_played_stage", 9)
	old.set_value("progress", "pending_unlock_dialogue", 4)
	for stage in range(1, 10):
		old.set_value("stage_%d" % stage, "score", stage * 1000)
		old.set_value("stage_%d" % stage, "cleared", true)
		old.set_value("seen_dialogue", "stage_%d_tutorial" % stage, true)
	old.save(Progress.save_path)
	var order := [1, 9, 2, 3, 4, 6, 7, 8]
	var names := ["Rhythm Start", "Circle Of Life", "Electric Elegance", "Shape Samurai", "Time Rift", "Music Is Life", "Keep Me Down", "Freak Tonight"]
	for index in order.size():
		expect(Catalog.display_name(index + 1) == names[index], "stage order matches requested campaign")
		expect(Progress.stage_record(index + 1)["score"] == order[index] * 1000, "record follows its original stage")
	expect(Progress.highest_unlocked_stage() == 8, "all unlocked stages remain accessible")
	expect(Progress.last_played_stage() == 2, "last played reconstruction moves to stage two")
	expect(Progress.pending_unlock_dialogue() == 5, "pending unlock follows Time Rift")
	expect(Progress.has_seen_dialogue("stage_5_tutorial"), "dialogue history follows the moved stage")
	var migrated := ConfigFile.new()
	migrated.load(Progress.save_path)
	expect(not migrated.has_section("stage_9"), "obsolete stage nine section is removed")
	expect(int(migrated.get_value("progress", "stage_order_version")) == 2, "migration is persisted once")
	var backup := ConfigFile.new()
	backup.load(Progress.save_path + ".before_stage_reorder")
	expect(backup.get_value("stage_5", "score") == 5000, "removed stage record remains in original backup")
	expect(Progress.stage_record(2)["score"] == 9000, "repeated loads do not remap again")
	# Earlier players retain access to their original stages after inserting the new second stage.
	for previous in range(1, 10):
		var partial := ConfigFile.new()
		partial.set_value("progress", "highest_unlocked_stage", previous)
		partial.set_value("progress", "last_played_stage", 5)
		Progress._migrate_stage_order(partial)
		for index in order.size():
			if order[index] <= previous:
				expect(int(partial.get_value("progress", "highest_unlocked_stage")) >= index + 1, "migration never relocks previously accessible content")
		expect(partial.get_value("progress", "last_played_stage") == 1, "removed last-played stage uses a valid fallback")
	DirAccess.remove_absolute(Progress.save_path)
	DirAccess.remove_absolute(Progress.save_path + ".before_stage_reorder")
	Progress.save_path = original_path
	print("Stage reorder tests: %d failures" % failures)
	quit(1 if failures else 0)

func expect(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)
