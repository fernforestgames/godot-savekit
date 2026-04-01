@abstract
class_name SaveableResource
extends Resource

var all_saveable_resources_by_uuid: Dictionary[String, Dictionary]

const ReflectionUtils := preload("reflection_utils.gd")
const ResourceUtils := preload("resource_utils.gd")
const UUID := preload("uuid.gd")

const _SCRIPT_RESOURCE_KEY := "script"

var _uuid_for_saving: String

func _save_into_dict(saved_resources: Dictionary[String, Dictionary]) -> String:
	if not _uuid_for_saving:
		_uuid_for_saving = UUID.generate_uuid_v4()

	if _uuid_for_saving not in saved_resources:
		all_saveable_resources_by_uuid = saved_resources

		# Register a placeholder empty dictionary before saving, to avoid infinite recursion in case of circular references
		saved_resources[_uuid_for_saving] = {}

		var save_dict := save_to_dict()
		var script: Script = get_script()
		save_dict[_SCRIPT_RESOURCE_KEY] = ResourceUtils.serialize_resource_reference(script)
		saved_resources[_uuid_for_saving] = save_dict

		all_saveable_resources_by_uuid = {}
	
	return _uuid_for_saving

func save_to_dict() -> Dictionary:
	var script: Script = get_script()
	var script_property_default_values: Dictionary[String, Variant]
	ReflectionUtils.get_script_default_property_values(script, script_property_default_values)
	
	var save_dict := {}
	for property in script.get_script_property_list():
		var name: String = property["name"]
		var usage: PropertyUsageFlags = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		var value: Variant = get(name)
		var type: Variant.Type = property["type"]

		# Don't save default values
		if name in script_property_default_values and value == script_property_default_values[name]:
			continue
		
		match type:
			TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
				push_warning("Cannot save property ", name, " of resource ", self , " with type ", type_string(type))
			
			TYPE_OBJECT:
				if value == null:
					save_dict[name] = null
					continue
				
				if value is SaveableResource:
					# Save a reference to avoid encoding the same resource multiple times
					var saveable_resource: SaveableResource = value
					save_dict[name] = saveable_resource._save_into_dict(all_saveable_resources_by_uuid)
				elif value is Resource:
					save_dict[name] = ResourceUtils.serialize_resource_reference(value as Resource)
				# TODO: Serialize Node references
				else:
					push_warning("Cannot save property ", name, " of resource ", self , " with value: ", value)

			_:
				save_dict[name] = JSON.from_native(value)
	
	return save_dict

static func _load_from_dict(uuid: String, saved_resources: Dictionary[String, Dictionary]) -> SaveableResource:
	var save_value: Variant = saved_resources.get(uuid)
	if save_value == null:
		push_error("No saved resource exists with UUID ", uuid)
		return null

	var save_dict := save_value as Dictionary
	if not save_dict:
		push_error("Resource with UUID ", uuid, " is not saved as a valid dictionary")
		return null
	
	var script_dict: Dictionary = save_dict.get(_SCRIPT_RESOURCE_KEY, {})
	save_dict.erase(_SCRIPT_RESOURCE_KEY)

	var script_resource: Script = ResourceUtils.deserialize_resource_reference(script_dict, ["gd", "cs"])

	@warning_ignore("unsafe_method_access")
	var load_resource: SaveableResource = script_resource.new()
	
	load_resource.all_saveable_resources_by_uuid = saved_resources
	load_resource.load_from_dict(save_dict)
	load_resource.all_saveable_resources_by_uuid = {}

	return load_resource

func load_from_dict(dict: Dictionary) -> void:
	var properties_by_name: Dictionary[String, Dictionary]
	for property: Dictionary in self.get_property_list():
		properties_by_name[property.name] = property

	for property_name: String in dict:
		if property_name not in properties_by_name:
			push_warning("Cannot load saved property ", property_name, " not currently found on object")
			continue

		var property := properties_by_name[property_name]
		var usage_flags: PropertyUsageFlags = property["usage"]
		if usage_flags & PROPERTY_USAGE_STORAGE == 0:
			push_warning("Not loading property ", property_name, " with storage disabled")
			continue
		
		var value: Variant = dict[property_name]
		var type: Variant.Type = property["type"]
		match type:
			TYPE_OBJECT:
				var resource_dict := value as Dictionary
				var resource: Resource
				if resource_dict:
					var classname: StringName = property["class_name"]
					var recognized_extensions := ResourceLoader.get_recognized_extensions_for_type(classname)
					resource = ResourceUtils.deserialize_resource_reference(resource_dict, recognized_extensions)
				else:
					var uuid: String = value
					resource = SaveableResource._load_from_dict(uuid, all_saveable_resources_by_uuid)

				set(property_name, resource)

			_:
				set(property_name, value)

	emit_changed()
