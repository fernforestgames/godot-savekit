extends Window

@onready var code_edit: CodeEdit = %CodeEdit
@onready var load_button: Button = %LoadButton
@onready var error_label: Label = %ErrorLabel

func _ready() -> void:
	visible = true

func _on_close_requested() -> void:
	get_tree().quit()

func _on_load_button_pressed() -> void:
	if not SaveManager.load_scene_tree_from_memory(code_edit.text.to_utf8_buffer()):
		error_label.text = "Error loading save data"
		error_label.visible = true
		return

	error_label.visible = false

func _on_save_button_pressed() -> void:
	var save_data := SaveManager.save_scene_tree_in_memory()
	code_edit.text = save_data.get_string_from_utf8()
	error_label.visible = false

func _on_code_edit_text_changed() -> void:
	load_button.disabled = not code_edit.text
