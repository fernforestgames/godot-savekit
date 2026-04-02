extends TextEdit

const Deserializer := preload("res://addons/savekit/deserializer.gd")
const Serializer := preload("res://addons/savekit/serializer.gd")

const PROPERTIES_TO_SAVE: PackedStringArray = ["text"]

func save_to_dict(s: Serializer) -> Dictionary:
	return s.default_save_to_dict(self , PROPERTIES_TO_SAVE)

func load_from_dict(s: Deserializer, data: Dictionary) -> void:
	s.default_load_from_dict(self , data, PROPERTIES_TO_SAVE)
