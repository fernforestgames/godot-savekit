@abstract
class_name SaveKitSerializer
extends RefCounted
## Base class for serializers that persist nodes into save data.
##
## Subclasses can implement custom save data formats by providing implementations for the abstract methods.

const ReflectionUtils := preload("reflection_utils.gd")

## The name for a method that Nodes can implement to customize how they are saved to a dictionary. The method should have the following signature:
##
## [codeblock]
## func save_to_dict(serializer: Serializer) -> Dictionary
## [/codeblock]
##
## Within this method, nodes can use the serializer's [method encode_var] method to encode values into the returned dictionary.
var save_to_dict_method: StringName = &"save_to_dict"

## Nodes are normally serialized in save data according to their path in the scene tree. However, in some cases it may be desirable to override this path (e.g., to deduplicate the saved node with its original instantiation in a packed scene).
##
## This is the name for a property (of type [NodePath]) that Nodes can implement to provide a custom node path when saving.
var save_path_override_key: StringName = &"save_path_override"

## Encodes a runtime value for saving, returning a value that can be persisted.
@abstract
func encode_var(value: Variant) -> Variant

## Adds [param node] to the save data, serializing its properties according to [method save_node_to_dict].
@abstract
func save_node(node: Node) -> void

## After all nodes have been saved using [method save_node], this method can be called to get the finalized save data.
@abstract
func finalize_save_in_memory() -> PackedByteArray

## After all nodes have been saved using [method save_node], this method can be called to write the finalized save data to a file. Returns whether the file writing was successful.
func finalize_save_to_disk(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		return FileAccess.get_open_error()
	
	var bytes := finalize_save_in_memory()
	if not file.store_buffer(bytes):
		return file.get_error()
	
	return OK

## Saves data for [param node] into a dictionary, suitable for persisting.
func save_node_to_dict(node: Node) -> Dictionary:
	if not node.has_method(save_to_dict_method):
		return default_save_to_dict(node)

	var save_dict: Variant = node.call(save_to_dict_method, self )
	if save_dict is not Dictionary:
		push_error("Node ", node.get_path(), " did not return a dictionary from ", save_to_dict_method, "()")
		return {}
	
	return save_dict

## Implements the default behavior for [method save_node_to_dict], for the case where the node does not implement a custom [member save_to_dict_method]. This will serialize all of the node's exported properties that have a non-default value.
##
## This method can also be called from a custom [member save_to_dict_method] implementation, to save some properties automatically and implement custom behavior for others. [param only_properties] can be used to specify a subset of properties to save from the node.
func default_save_to_dict(node: Node, only_properties: PackedStringArray = PackedStringArray()) -> Dictionary:
	var save_dict := {}
	for property_dict in ReflectionUtils.get_storable_non_default_properties(node):
		var name: String = property_dict["name"]
		if only_properties and name not in only_properties:
			continue

		var value: Variant = property_dict["value"]
		save_dict[name] = encode_var(value)

	return save_dict

## Returns the [NodePath] to associate with [param node] in save data, honoring any value set for [member save_path_override_key].
func save_path_for_node(node: Node) -> NodePath:
	var path_override: Variant = node.get(save_path_override_key)
	if path_override:
		return path_override
	
	return node.get_path()
