extends SceneTree

const StageCatalogScript = preload("res://level/data/stage_catalog.gd")

var _failures := 0


func _init() -> void:
	_expect(StageCatalogScript.stage_numbers() == [1, 2, 3, 4, 5, 6, 7, 8], "stages remain in display order")
	_expect(StageCatalogScript.display_name(4) == "Shape Samurai", "stage names come from the catalog")
	_expect(StageCatalogScript.data_path(4) == "res://level/data/level_4.yaml", "stage data paths come from the catalog")
	_expect(StageCatalogScript.data_path(999) == StageCatalogScript.data_path(1), "unknown stages use the safe default")
	for stage_number in StageCatalogScript.stage_numbers():
		_expect(FileAccess.file_exists(StageCatalogScript.data_path(stage_number)), "stage %d points to existing data" % stage_number)
	if _failures == 0:
		print("Stage catalog tests passed: 12 assertions")
		quit(0)
	else:
		push_error("Stage catalog tests failed: %d assertion(s)" % _failures)
		quit(1)


func _expect(condition: bool, label: String) -> void:
	if condition:
		return
	_failures += 1
	push_error(label)
