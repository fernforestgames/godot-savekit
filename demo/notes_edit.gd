extends TextEdit

const PROPERTIES_TO_SAVE: PackedStringArray = ["text"]

func save_to_dict() -> Dictionary:
	return SaveManager.default_save_to_dict(self , PROPERTIES_TO_SAVE)

func load_from_dict(data: Dictionary) -> void:
	SaveManager.default_load_from_dict(self , data, PROPERTIES_TO_SAVE)
