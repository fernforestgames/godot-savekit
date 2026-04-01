extends TextEdit

func save_to_dict() -> Dictionary:
	return {
		"text": text,
	}

func load_from_dict(data: Dictionary) -> void:
	text = data.get("text", text)
