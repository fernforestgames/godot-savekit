@tool
extends EditorPlugin

const SAVE_MANAGER_AUTOLOAD_NAME := "SaveManager"
const SAVE_MANAGER_PATH := "save_manager.gd"

func _enable_plugin() -> void:
	add_autoload_singleton(SAVE_MANAGER_AUTOLOAD_NAME, SAVE_MANAGER_PATH)

func _disable_plugin() -> void:
	remove_autoload_singleton(SAVE_MANAGER_AUTOLOAD_NAME)

func _enter_tree() -> void:
	# Initialization of the plugin goes here.
	pass

func _exit_tree() -> void:
	# Clean-up of the plugin goes here.
	pass
