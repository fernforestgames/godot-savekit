@abstract
extends RefCounted

var scene_tree: SceneTree

var load_from_dict_method: StringName = &"load_from_dict"

var saveable_node_group: StringName = &"saveable"

signal node_created(node: Node)

const ResourceUtils := preload("resource_utils.gd")

@abstract
func decode_var(value: Variant, expected_type: Variant.Type, expected_class_name: StringName = &"") -> Variant

@abstract
func is_finished() -> bool

@abstract
func load_node() -> Node

func load_node_from_dict(node: Node, dict: Dictionary) -> void:
	if not node.has_method(load_from_dict_method):
		return default_load_from_dict(node, dict)

	node.call(load_from_dict_method, self , dict)

func default_load_from_dict(node: Node, data: Dictionary, only_properties: PackedStringArray = PackedStringArray()) -> void:
	var properties_by_name: Dictionary[String, Dictionary]
	for property in node.get_property_list():
		var name: String = property["name"]
		properties_by_name[name] = property

	for property_name: String in data:
		if only_properties and property_name not in only_properties:
			continue

		var property: Dictionary = properties_by_name.get(property_name, {})
		if not property:
			push_warning("Cannot load saved property ", property_name, " not currently found on node ", node.get_path())
			continue
		
		var type: Variant.Type = property["type"]
		var classname: StringName = property.get("class_name", &"")
		node.set(property_name, decode_var(data[property_name], type, classname))

func find_or_instantiate_node(node_path: NodePath, scene_file_path: String) -> Node:
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
	elif not node.is_in_group(saveable_node_group):
		push_warning("Node ", node_path, " is not in group \"", saveable_node_group, "\", refusing to load it")
		return null

	return node
