extends Node

var _save_data: Dictionary = {}
var before_save_called: bool = false
var after_save_called: bool = false
var before_load_called: bool = false
var after_load_called: bool = false
var loaded_data: Dictionary = {}


func before_save() -> void:
	before_save_called = true


func after_save() -> void:
	after_save_called = true


func save_to_dict(_serializer) -> Dictionary:
	return _save_data.duplicate()


func before_load() -> void:
	before_load_called = true


func after_load() -> void:
	after_load_called = true


func load_from_dict(_deserializer, data: Dictionary) -> void:
	loaded_data = data
