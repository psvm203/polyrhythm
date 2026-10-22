class_name StageCatalog
extends RefCounted

const DEFAULT_STAGE := 1

const _STAGES := {
	1: {
		"name": "Rhythm Start",
		"data_path": "res://level/data/level_1.yaml",
	},
	2: {
		"name": "Electric Elegance",
		"data_path": "res://level/data/level_2.yaml",
	},
	3: {
		"name": "Shape Samurai",
		"data_path": "res://level/data/level_3.yaml",
	},
	4: {
		"name": "Time Rift",
		"data_path": "res://level/data/level_4.yaml",
	},
	5: {
		"name": "Take Me Over",
		"data_path": "res://level/data/level_5.yaml",
	},
	6: {
		"name": "Music Is Life",
		"data_path": "res://level/data/level_6.yaml",
	},
	7: {
		"name": "Keep Me Down",
		"data_path": "res://level/data/level_7.yaml",
	},
	8: {
		"name": "Freak Tonight",
		"data_path": "res://level/data/level_8.yaml",
	},
	9: {
		"name": "Matadora",
		"data_path": "res://level/data/level_9.yaml",
	},
}


static func stage_numbers() -> Array[int]:
	var numbers: Array[int] = []
	for stage_number in _STAGES:
		numbers.append(stage_number)
	numbers.sort()
	return numbers


static func data_path(stage_number: int) -> String:
	return String(_stage(stage_number)["data_path"])


static func display_name(stage_number: int) -> String:
	return String(_stage(stage_number)["name"])


static func _stage(stage_number: int) -> Dictionary:
	return _STAGES.get(stage_number, _STAGES[DEFAULT_STAGE])
