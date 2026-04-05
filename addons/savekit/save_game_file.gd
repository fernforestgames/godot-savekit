extends RefCounted
## A description of a save game file on disk. Objects of this type are validated and returned by the save manager, and should not be created manually.

## The components of the save name. On disk, these are used to create separate save game directories. In game, this could be used, for example, to differentiate individual games [i]as well as[/i] different save slots within those games (e.g., [code]"My Cool Game", "Autosave 1"[/code]).
##
## Since these names may come from user input, the components are sanitized and validated before being assigned to this property. The resulting text may not exactly match what the user entered.
var save_name_components: PackedStringArray

## The absolute path to the save game file on disk.
var absolute_path: String

## The last modified time of the save game file, represented as a Unix timestamp.
var modified_at_unix_time: int

## The last modified time of the save game file, as an ISO 8601 date and time string ([code]YYYY-MM-DDTHH:MM:SS[/code]).
var modified_at_datetime: String:
	get:
		return Time.get_datetime_string_from_unix_time(modified_at_unix_time)
	set(value):
		modified_at_unix_time = Time.get_unix_time_from_datetime_string(value)

## Sanitizes user-provided save name components; for example, by disallowing invalid characters and directory traversal with [code]..[/code].
##
## Returns the sanitized path, which is guaranteed to be relative, or an empty string if the sanitized result is invalid.
static func sanitize_save_name_components(components: PackedStringArray) -> String:
	if not components:
		return ""

	var validated_components: PackedStringArray
	validated_components.resize(components.size())
	for i in components.size():
		validated_components[i] = components[i].validate_filename()

	var save_path := "/".join(validated_components).simplify_path().replace(".", "_")
	if save_path.is_absolute_path():
		push_error("Save name must not be an absolute path: ", save_path)
		return ""
	
	return save_path

func _to_string() -> String:
	return "SaveGameFile(save_name_components=%s, absolute_path=\"%s\", modified_at=%s)" % [save_name_components, absolute_path, modified_at_datetime]
