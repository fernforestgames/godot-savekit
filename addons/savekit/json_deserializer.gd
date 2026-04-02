extends "deserializer.gd"

const JSONSerializer := preload("json_serializer.gd")

var _node_deserialization_stack: Array[NodePath] = []
var _saved_nodes: Dictionary[NodePath, Dictionary]
var _saved_resources_by_id: Dictionary[String, Dictionary]
var _loaded_resources_by_id: Dictionary[String, SaveableResource]

func _init(save_dict: Dictionary) -> void:
	var version: int = save_dict.get(JSONSerializer._SERIALIZATION_VERSION_KEY, 0)
	if version != JSONSerializer._SERIALIZATION_VERSION:
		push_error("Unsupported save data version: ", version)
		return
	
	_saved_nodes.assign(save_dict.get(JSONSerializer._NODES_KEY, {}) as Dictionary)
	_saved_resources_by_id.assign(save_dict.get(JSONSerializer._RESOURCES_KEY, {}) as Dictionary)
	_node_deserialization_stack = _stack_sort_node_paths()

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if _node_deserialization_stack:
				push_warning("JSON deserializer freed before all nodes were loaded. Remaining nodes that were not loaded: ", _saved_nodes.keys())
			elif _saved_resources_by_id:
				push_warning("Unexpected dangling saved resources that were never loaded: ", _saved_resources_by_id)

func decode_var(value: Variant, expected_type: Variant.Type, expected_class_name: StringName = &"") -> Variant:
	match expected_type:
		TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			push_warning("Cannot deserialize value of type ", type_string(expected_type), ": ", value)
			return null
		
		TYPE_OBJECT:
			var value_dict := value as Dictionary
			if not value_dict:
				push_warning("Expected a dictionary when deserializing an object, got: ", value)
				return null
			
			var saved_resource_id: String = value_dict.get(JSONSerializer._SAVED_RESOURCE_ID_KEY, "")
			if saved_resource_id:
				return load_resource(saved_resource_id)
			
			var encoded_resource_reference_path: String = value_dict.get(JSONSerializer._ENCODED_RESOURCE_REFERENCE_PATH_KEY, "")
			if encoded_resource_reference_path:
				var encoded_resource_reference_uid: String = value_dict.get(JSONSerializer._ENCODED_RESOURCE_REFERENCE_UID_KEY, "")
				return decode_resource_reference(encoded_resource_reference_path, encoded_resource_reference_uid, expected_class_name)
			
			var encoded_node_reference: String = value_dict.get(JSONSerializer._ENCODED_NODE_REFERENCE_KEY, "")
			if encoded_node_reference:
				return decode_node_reference(NodePath(encoded_node_reference))
			
			push_warning("Cannot deserialize object from dictionary: ", value_dict)
			return null
		
		_:
			return JSON.to_native(value)

func decode_node_reference(node_path: NodePath) -> Node:
	# To ensure we can convert this node path into a valid node reference, we need to effectively "preload" the target node and all of its ancestors.
	# This process is similar to load_node(), but circumventing the normal order and without actually loading data into the nodes yet.
	if node_path.get_name_count() > 1:
		var parent_node := decode_node_reference(node_path.slice(0, -1))
		if not parent_node:
			return null
	
	var save_dict: Dictionary = _saved_nodes.get(node_path, {})
	var scene_file_path: String = save_dict.get(JSONSerializer._NODE_SCENE_FILE_PATH_KEY, "")
	return find_or_instantiate_node(node_path, scene_file_path)

func decode_resource_reference(resource_path: String, resource_uid: String = "", expected_class_name: StringName = &"") -> Resource:
	if resource_uid:
		var id := ResourceUID.text_to_id(resource_uid)
		if ResourceUID.has_id(id):
			resource_path = ResourceUID.get_id_path(id)
	
	var allowed_extensions := ResourceLoader.get_recognized_extensions_for_type(expected_class_name if expected_class_name else &"Resource")
	return ResourceUtils.safe_load_resource(resource_path, allowed_extensions)

func get_remaining_node_count() -> int:
	return _node_deserialization_stack.size()

func is_finished() -> bool:
	return not _node_deserialization_stack

func load_node() -> Node:
	var node_path: NodePath = _node_deserialization_stack.pop_back()
	if not node_path:
		return null
	
	var save_dict: Dictionary = _saved_nodes[node_path]
	_saved_nodes.erase(node_path)

	var scene_file_path: String = save_dict.get(JSONSerializer._NODE_SCENE_FILE_PATH_KEY, "")
	save_dict.erase(JSONSerializer._NODE_SCENE_FILE_PATH_KEY)

	var node := find_or_instantiate_node(node_path, scene_file_path)
	if node:
		load_node_from_dict(node, save_dict)

	return node

func _stack_sort_node_paths() -> Array[NodePath]:
	var node_paths: Array[NodePath]
	node_paths.assign(_saved_nodes.keys())

	# Load nodes in order of depth, to ensure parents are loaded before children.
	# We'll use this to instantiate any missing nodes along the way.
	node_paths.sort_custom(func(a: NodePath, b: NodePath) -> bool:
		# We're creating a stack, so sort nodes to load FIRST at the end
		return a.get_name_count() > b.get_name_count())
	
	return node_paths

func load_resource(id: String) -> SaveableResource:
	var resource: SaveableResource = _loaded_resources_by_id.get(id)
	if not resource:
		var save_dict: Dictionary = _saved_resources_by_id.get(id, {})
		if not save_dict:
			push_error("No saved resource found with ID ", id)
			return null
		
		_saved_resources_by_id.erase(id)
	
		var script: Script = decode_var(save_dict.get(JSONSerializer._SAVED_RESOURCE_SCRIPT_KEY, {}), TYPE_OBJECT, "Script")
		if not script:
			push_error("Failed to decode script for resource with ID ", id, ", cannot load resource")
			return null
		
		save_dict.erase(JSONSerializer._SAVED_RESOURCE_SCRIPT_KEY)
		
		@warning_ignore("unsafe_method_access")
		resource = script.new()
		resource.load_from_dict(self , save_dict)
		_loaded_resources_by_id[id] = resource

	return resource
