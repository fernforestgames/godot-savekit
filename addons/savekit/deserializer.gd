@abstract
class_name SaveKitDeserializer
extends RefCounted
## Base class for deserializers that load saved data into nodes.
##
## Subclasses can implement custom save data formats by providing implementations for the abstract methods.

## The scene tree for finding and adding nodes during loading. This must be set before loading any nodes.
var scene_tree: SceneTree

## The name for a method that Nodes can implement to customize how they are loaded from a dictionary. The method should have the following signature:
##
## [codeblock]
## func load_from_dict(deserializer: Deserializer, data: Dictionary) -> void
## [/codeblock]
##
## Within this method, nodes can use the deserializer's [method decode_var] method to decode values from the provided dictionary.
var load_from_dict_method: StringName = &"load_from_dict"

## A scene tree group for finding and adding nodes during loading.
##
## Nodes to be loaded must be in this group to be found, and nodes added to the tree during loading will be added to this group.
var saveable_node_group: StringName = &"saveable"

## Emitted when a new node is added to the scene tree during loading.
signal node_created(node: Node)

const ResourceUtils := preload("resource_utils.gd")

## Prepares the deserializer with the given save data. Returns false if the save data is invalid.
@abstract
func prepare_load_from_memory(data: PackedByteArray) -> bool

## Prepares the deserializer by loading save data from the given file path. Returns an error if loading failed.
func prepare_load_from_file(path: String) -> Error:
	var bytes := FileAccess.get_file_as_bytes(path)
	if not bytes:
		return FileAccess.get_open_error()
	
	if not prepare_load_from_memory(bytes):
		return ERR_INVALID_DATA

	return OK

## Decodes a saved value into a runtime value that can be set on a Node or Resource.
##
## Callers must provide [param expected_type] (and [param expected_class_name], if applicable) to guide the deserializer in how to decode the value. See [method default_load_from_dict] for an example.
##
## Note: [param expected_class_name] should refer to a class that exists within [ClassDB] (i.e., built-in or GDExtension classes). It should [i]not[/i] contain the name of a script-defined [code]class_name[/code].
@abstract
func decode_var(value: Variant, expected_type: Variant.Type, expected_class_name: StringName = &"") -> Variant

## Returns whether deserialization has finished (i.e., all nodes have been loaded).
@abstract
func is_finished() -> bool

## Loads the next node from the save data, returning the loaded node or null if an error occurred. The node will be added to the scene tree automatically, if not already present.
##
## Internally, this will call [method find_or_instantiate_node] and [method load_node_from_dict].
##
## Note that a null return value does not necessarily mean that deserialization has finished. Call [method is_finished] to check.
@abstract
func load_node() -> Node

## Loads data into [param node] from the given dictionary.
func load_node_from_dict(node: Node, dict: Dictionary) -> void:
	if not node.has_method(load_from_dict_method):
		return default_load_from_dict(node, dict)

	node.call(load_from_dict_method, self , dict)

## Implements the default behavior for [method load_node_from_dict], for the case where the node does not implement a custom [member load_from_dict_method]. This will set the node's properties to the decoded values of [param data].
##
## This method can also be called from a custom [member load_from_dict_method] implementation, to load some properties automatically and implement custom behavior for others. [param only_properties] can be used to specify a subset of properties to load from [param data].
func default_load_from_dict(node: Node, data: Dictionary, only_properties: PackedStringArray = PackedStringArray()) -> void:
	var properties_by_name: Dictionary[String, Dictionary]
	for property in node.get_property_list():
		var name: String = property["name"]
		properties_by_name[name] = property

	for name: String in data:
		if only_properties and name not in only_properties:
			continue

		var property: Dictionary = properties_by_name.get(name, {})
		if not property:
			push_warning("Cannot load saved property ", name, " not currently found on node ", node.get_path())
			continue

		var usage_flags: PropertyUsageFlags = property["usage"]
		if usage_flags & PROPERTY_USAGE_STORAGE == 0:
			push_warning("Not loading property ", name, " with storage disabled")
			continue
		
		var encoded_value: Variant = data[name]
		var type: Variant.Type = property["type"]
		var classname: StringName = property.get("class_name", &"")

		var decoded_value: Variant = decode_var(encoded_value, type, classname)
		node.set(name, decoded_value)

## Finds a node at [param node_path] in the scene tree, or instantiates it from [param scene_file_path] and adds it to the scene tree if it did not already exist. Returns null if the node could not be found or instantiated.
##
## The node must be a member of [member saveable_node_group] to be found successfully.
func find_or_instantiate_node(node_path: NodePath, scene_file_path: String, fail_on_missing_group: bool = true) -> Node:
	if not scene_tree:
		push_error("scene_tree must be set on deserializer to find or instantiate nodes")
		return null
	
	var node := scene_tree.root.get_node_or_null(node_path)
	if not node:
		var parent_path := node_path.slice(0, -1)
		var parent_node := scene_tree.root.get_node_or_null(parent_path)
		if not parent_node:
			push_warning("Could not find parent ", parent_path, " for node ", node_path, " while loading, adding to root")
			parent_node = scene_tree.root
		
		if not scene_file_path:
			# TODO: Instantiate via script reference instead
			push_error("Cannot instantiate node ", node_path, " that is missing from the scene tree, as it has no scene file path")
			return null
		
		var scene_extensions := ResourceLoader.get_recognized_extensions_for_type("PackedScene")
		var scene: PackedScene = ResourceUtils.safe_load_resource(scene_file_path, scene_extensions)
		if not scene:
			push_error("Failed to load scene for node ", node_path, " from path ", scene_file_path)
			return null

		node = scene.instantiate()
		node.name = node_path.get_name(node_path.get_name_count() - 1)
		node.add_to_group(saveable_node_group)
		parent_node.add_child(node)
		node_created.emit(node)
	elif fail_on_missing_group and not node.is_in_group(saveable_node_group):
		push_warning("Node ", node_path, " is not in group \"", saveable_node_group, "\", refusing to load it")
		return null

	return node

func sort_node_paths_in_load_order(r_node_paths: Array[NodePath]) -> void:
	# Load nodes in order of depth, to ensure parents are loaded before children.
	# We'll use this to instantiate any missing nodes along the way.
	r_node_paths.sort_custom(func(a: NodePath, b: NodePath) -> bool:
		# We're creating a stack, so sort nodes to load FIRST at the end
		return a.get_name_count() > b.get_name_count())
