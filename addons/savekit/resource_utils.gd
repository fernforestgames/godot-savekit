## Loads a resource from [param path], only if it points into the [code]res://[/code] filesystem and has an allowed extension. This ensures that only intended resources within the game's PCK can be loaded, and prevents loading of arbitrary files from the user's filesystem.
static func safe_load_resource(path: String, allowed_extensions: PackedStringArray) -> Resource:
	path = path.simplify_path()
	if not path.is_absolute_path() or not path.begins_with("res://"):
		push_warning("Invalid resource path ", path)
		return null

	for extension in allowed_extensions:
		if path.ends_with(".%s" % extension):
			return load(path)
	
	push_warning("Resource path ", path, " does not have an allowed extension (", allowed_extensions, ")")
	return null
