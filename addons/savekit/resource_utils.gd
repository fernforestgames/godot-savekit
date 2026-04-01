static func safe_load_resource(path: String, extension: String) -> Resource:
	path = path.simplify_path()
	if not path.is_absolute_path() or not path.begins_with("res://") or not path.ends_with(".%s" % extension):
		push_warning("Invalid resource path ", path, ", ignoring")
		return null
	
	return load(path)
