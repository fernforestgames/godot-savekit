## Lists all exported properties on [param obj] (from its built-in class and/or script) that have a non-default value.
##
## Returns an array of dictionaries matching the format of [method Object.get_property_list], with an additional [code]value[/code] key containing the current value of the property.
static func get_storable_non_default_properties(obj: Object) -> Array[Dictionary]:
	var script: Script = obj.get_script()
	var script_property_default_values: Dictionary[String, Variant]
	get_script_default_property_values(script, script_property_default_values)
	
	var builtin_class := obj.get_class()
	var builtin_class_property_default_values := get_builtin_class_default_property_values(builtin_class)

	var property_list := obj.get_property_list()
	var non_default_properties: Array[Dictionary]
	for property in property_list:
		var name: String = property["name"]
		if name == "script":
			# Don't try to save script references here
			continue

		var usage: PropertyUsageFlags = property["usage"]
		if usage & PROPERTY_USAGE_STORAGE == 0:
			continue
		
		var value: Variant = obj.get(name)

		# Don't save default values
		if name in script_property_default_values and value == script_property_default_values[name]:
			continue
		if name in builtin_class_property_default_values and value == builtin_class_property_default_values[name]:
			continue
		
		property["value"] = value
		non_default_properties.append(property)

	return non_default_properties

## Populates [param r_default_property_values] with the default values for all properties defined in [param script], including properties inherited from base scripts if [param include_ancestors] is true.
static func get_script_default_property_values(script: Script, r_default_property_values: Dictionary[String, Variant], include_ancestors: bool = true) -> void:
	if not script:
		return

	if include_ancestors:
		get_script_default_property_values(script.get_base_script(), r_default_property_values, include_ancestors)

	for property in script.get_script_property_list():
		var name: String = property["name"]
		r_default_property_values[name] = script.get_property_default_value(name)

## Returns a dictionary of default property values for a built-in (or GDExtension) class, including properties inherited from base classes if [param include_ancestors] is true.
static func get_builtin_class_default_property_values(builtin_class: String, include_ancestors: bool = true) -> Dictionary[String, Variant]:
	var default_property_values: Dictionary[String, Variant] = {}

	for property in ClassDB.class_get_property_list(builtin_class, not include_ancestors):
		var name: String = property["name"]
		default_property_values[name] = ClassDB.class_get_property_default_value(builtin_class, name)
	
	return default_property_values
