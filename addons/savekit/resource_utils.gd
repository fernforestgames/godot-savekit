const _RESOURCE_PATH_KEY := "path"
const _RESOURCE_UID_KEY := "uid"

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

static func serialize_resource_reference(resource: Resource) -> Dictionary:
	if not resource.resource_path:
		push_warning("Cannot serialize reference to resource ", resource, " as it does not have a resource path")
		return {}
	
	return {
		_RESOURCE_PATH_KEY: resource.resource_path,
		_RESOURCE_UID_KEY: ResourceUID.path_to_uid(resource.resource_path),
	}

static func deserialize_resource_reference(resource_dict: Dictionary, allowed_extensions: PackedStringArray) -> Resource:
	var resource_path: String = resource_dict.get(_RESOURCE_PATH_KEY, "")
	var resource_uid: String = resource_dict.get(_RESOURCE_UID_KEY, "")
	if resource_uid:
		var id := ResourceUID.text_to_id(resource_uid)
		if ResourceUID.has_id(id):
			resource_path = ResourceUID.get_id_path(id)

	return safe_load_resource(resource_path, allowed_extensions)
