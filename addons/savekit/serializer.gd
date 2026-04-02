@abstract
extends RefCounted

const ReflectionUtils := preload("reflection_utils.gd")

var save_to_dict_method: StringName = &"save_to_dict"
var save_path_override_key: StringName = &"save_path_override"

@abstract
func encode_var(value: Variant) -> Variant

@abstract
func save_node(node: Node) -> void

func save_node_to_dict(node: Node) -> Dictionary:
	if not node.has_method(save_to_dict_method):
		return default_save_to_dict(node)

	var save_dict: Variant = node.call(save_to_dict_method, self )
	if save_dict is not Dictionary:
		push_error("Node ", node.get_path(), " did not return a dictionary from ", save_to_dict_method, "()")
		return {}
	
	return save_dict

func default_save_to_dict(node: Node, only_properties: PackedStringArray = PackedStringArray()) -> Dictionary:
	var save_dict := {}
	for property_dict in ReflectionUtils.get_storable_non_default_properties(node):
		var property_name: String = property_dict["name"]
		if only_properties and property_name not in only_properties:
			continue

		save_dict[property_name] = encode_var(node.get(property_name))

	return save_dict

func save_path_for_node(node: Node) -> NodePath:
	var path_override: Variant = node.get(save_path_override_key)
	if path_override != null:
		return path_override
	
	return node.get_path()
