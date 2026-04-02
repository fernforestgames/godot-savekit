@abstract
class_name SaveableResource
extends Resource
## Base class for user-defined resources that can be saved and loaded.
##
## [code]SaveableResource[/code]s are used instead of the base [Resource] class to clearly identify data that is meant for persistence in save files, versus resource data that is part of the game's PCK.

## Emitted whenever this resource is saved.
signal saved

## Emitted whenever this resource is loaded.
signal loaded

const ReflectionUtils := preload("reflection_utils.gd")
const Serializer := preload("serializer.gd")
const Deserializer := preload("deserializer.gd")

## Saves data for this resource into a dictionary, suitable for persisting. This will serialize all of the resource's exported properties that have a non-default value.
##
## This method can be overridden to implement custom saving behavior.
func save_to_dict(s: Serializer) -> Dictionary:
	var script: Script = get_script()
	var script_property_default_values: Dictionary[String, Variant]
	ReflectionUtils.get_script_default_property_values(script, script_property_default_values)
	
	var save_dict := {}
	for property in get_property_list():
		var name: String = property["name"]
		var usage: PropertyUsageFlags = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		var value: Variant = get(name)

		# Don't save default values
		if name in script_property_default_values and value == script_property_default_values[name]:
			continue
		
		save_dict[name] = s.encode_var(value)
	
	saved.emit()
	return save_dict

## Loads data into this resource from the given dictionary. This will set the resource's properties to the decoded values of [param data].
##
## This method can be overridden to implement custom loading behavior.
func load_from_dict(s: Deserializer, data: Dictionary) -> void:
	var properties_by_name: Dictionary[String, Dictionary]
	for property: Dictionary in self.get_property_list():
		properties_by_name[property.name] = property

	for name: String in data:
		if name not in properties_by_name:
			push_warning("Cannot load saved property ", name, " not currently found on resource ", self )
			continue

		var property := properties_by_name[name]
		var usage_flags: PropertyUsageFlags = property["usage"]
		if usage_flags & PROPERTY_USAGE_STORAGE == 0:
			push_warning("Not loading property ", name, " with storage disabled")
			continue
		
		var encoded_value: Variant = data[name]
		var type: Variant.Type = property["type"]
		var classname: StringName = property.get("class_name", &"")

		var decoded_value: Variant = s.decode_var(encoded_value, type, classname)
		set(name, decoded_value)

	loaded.emit()
	emit_changed()
