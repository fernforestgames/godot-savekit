extends Node

@export var saveable_group: StringName = &"saveable"

@export var before_save_method: StringName = &"before_save"
@export var after_save_method: StringName = &"after_save"
@export var save_to_dict_method: StringName = &"save_to_dict"
@export var save_path_override_key: StringName = &"save_path_override"

@export var before_load_method: StringName = &"before_load"
@export var after_load_method: StringName = &"after_load"
@export var load_from_dict_method: StringName = &"load_from_dict"

@export var save_game_directory: String = "user://save_games/"

const _SERIALIZATION_VERSION: int = 1
const _SERIALIZATION_VERSION_KEY: String = "__savekit_version"
const _SCENE_FILE_PATH_KEY: String = "__scene_file_path"

func serialize_tree() -> Dictionary:
	var scene_tree := get_tree()
	scene_tree.call_group(saveable_group, before_save_method)

	var saveable_nodes := scene_tree.get_nodes_in_group(saveable_group)
	var save_dict := {}
	for node in saveable_nodes:
		var node_path: Variant = node.get(save_path_override_key)
		if not node_path:
			node_path = node.get_path()
		
		# TODO: Replace with configurable logging
		# TODO: Fire signal or callback?
		print("Saving node: ", node_path)

		var node_dict: Variant = node.call(save_to_dict_method)
		if node_dict is not Dictionary:
			push_error("Node ", node_path, " did not return a dictionary from ", save_to_dict_method, "()")
			continue
		
		if node.scene_file_path:
			node_dict[_SCENE_FILE_PATH_KEY] = node.scene_file_path
		
		save_dict[node_path] = node_dict
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_group, after_save_method)
	
	save_dict[_SERIALIZATION_VERSION_KEY] = _SERIALIZATION_VERSION
	return save_dict

func deserialize_tree(data: Dictionary) -> Error:
	var serialization_version: int = data.get(_SERIALIZATION_VERSION_KEY, 0)
	if serialization_version != _SERIALIZATION_VERSION:
		push_error("Unsupported serialization version: ", serialization_version)
		return ERR_INVALID_DATA

	var scene_tree := get_tree()
	scene_tree.call_group(saveable_group, before_load_method)

	var node_paths := deserialize_sorted_node_paths(data)
	
	var loaded_nodes: Array[Node]
	for node_path: NodePath in node_paths:
		# TODO: Replace with configurable logging
		# TODO: Fire signal or callback?
		print("Loading node: ", node_path)

		var node_dict: Dictionary = data[str(node_path)]
		node_dict = node_dict.duplicate()

		@warning_ignore("shadowed_variable_base_class")
		var scene_file_path: String = node_dict.get(_SCENE_FILE_PATH_KEY, "")
		node_dict.erase(_SCENE_FILE_PATH_KEY)

		var node := scene_tree.root.get_node_or_null(node_path)
		if not node:
			var parent_path := node_path.slice(0, -1)
			var parent_node := scene_tree.root.get_node_or_null(parent_path)
			if not parent_node:
				push_warning("Could not find parent ", parent_path, " for node ", node_path, " while loading, adding to root")
				parent_node = scene_tree.root
			
			if not scene_file_path:
				push_error("Cannot instantiate node ", node_path, " that is missing from the scene tree, as it has no scene file path")
				continue
			
			var scene: PackedScene = safe_load_resource(scene_file_path, "tscn")
			if not scene:
				push_error("Failed to load scene for node ", node_path, " from path ", scene_file_path)
				continue
			
			# TODO: Replace with configurable logging
			# TODO: Fire signal or callback?
			print("Instantiating node ", node_path, " from scene ", scene_file_path)

			node = scene.instantiate()
			node.name = node_path.get_name(node_path.get_name_count() - 1)
			parent_node.add_child(node)
			node.add_to_group(saveable_group)
		elif not node.is_in_group(saveable_group):
			push_warning("Node ", node_path, " is not in the \"", saveable_group, "\" group, refusing to load it")
			continue
		
		node.call(load_from_dict_method, node_dict)
		loaded_nodes.append(node)
	
	for node in scene_tree.get_nodes_in_group(saveable_group):
		if node not in loaded_nodes:
			# TODO: Replace with configurable logging
			# TODO: Fire signal or callback?
			print("Removing node from tree which wasn't saved: ", node.get_path())
			node.queue_free()
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_group, after_load_method)
	return OK

static func deserialize_sorted_node_paths(data: Dictionary) -> Array[NodePath]:
	var node_paths: Array[NodePath]
	node_paths.resize(data.size() - 1)

	var index: int = 0
	for path: String in data:
		if path == _SERIALIZATION_VERSION_KEY:
			continue
		
		node_paths[index] = NodePath(path)
		index += 1

	# Load nodes in order of depth, to ensure parents are loaded before children.
	# We'll use this to instantiate any missing nodes along the way.
	node_paths.sort_custom(func(a: NodePath, b: NodePath) -> bool:
		return a.get_name_count() < b.get_name_count())
	
	return node_paths

static func safe_load_resource(path: String, extension: String) -> Resource:
	path = path.simplify_path()
	if not path.is_absolute_path() or not path.begins_with("res://") or not path.ends_with(".%s" % extension):
		push_warning("Invalid resource path ", path, ", ignoring")
		return null
	
	return load(path)
