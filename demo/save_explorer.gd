extends Window

@onready var code_edit: CodeEdit = %CodeEdit
@onready var load_button: Button = %LoadButton
@onready var error_label: Label = %ErrorLabel

func _ready() -> void:
	visible = true

func _on_close_requested() -> void:
	get_tree().quit()

func _on_load_button_pressed() -> void:
	var json_text := code_edit.text
	var save_data: Variant = JSON.parse_string(json_text)
	if save_data == null:
		error_label.text = "Error parsing JSON"
		error_label.visible = true
		return
	
	var err := SaveManager.deserialize_tree(save_data as Dictionary)
	if err != OK:
		error_label.text = "Error deserializing save data: " + str(err)
		error_label.visible = true
		return
	
	error_label.visible = false

func _on_save_button_pressed() -> void:
	var save_data := SaveManager.serialize_tree()
	code_edit.text = JSON.stringify(save_data, "\t")
	error_label.visible = false

func _on_code_edit_text_changed() -> void:
	load_button.disabled = not code_edit.text
