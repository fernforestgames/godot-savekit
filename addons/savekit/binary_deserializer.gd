extends "deserializer.gd"
## Deserializes save data from binary format.

const BinarySerializer := preload("binary_serializer.gd")

var _node_deserialization_stack: Array[NodePath] = []
var _saved_nodes: Dictionary[NodePath, Dictionary]
var _saved_resources_by_id: Dictionary[int, Dictionary]
var _loaded_resources_by_id: Dictionary[int, SaveKitResource]

func prepare_load_from_memory(data: PackedByteArray) -> bool:
	if data.size() < BinarySerializer._FILE_HEADER_SIZE:
		push_error("Save data is too small to contain required header information")
		return false

	var version := data.decode_u32(BinarySerializer._SERIALIZATION_VERSION_U32_OFFSET)
	if version != BinarySerializer._SERIALIZATION_VERSION:
		push_error("Unsupported save data version: ", version)
		return false
	
	var saved_nodes_length := data.decode_var_size(BinarySerializer._FILE_HEADER_SIZE)
	_saved_nodes.assign(data.decode_var(BinarySerializer._FILE_HEADER_SIZE) as Dictionary)
	_saved_resources_by_id.assign(data.decode_var(BinarySerializer._FILE_HEADER_SIZE + saved_nodes_length) as Dictionary)

	_node_deserialization_stack.assign(_saved_nodes.keys())
	sort_node_paths_in_load_order(_node_deserialization_stack)
	return true

func decode_var(value: Variant, expected_type: Variant.Type, expected_class_name: StringName = &"") -> Variant:
	match expected_type:
		TYPE_CALLABLE:
			push_error("Cannot deserialize callable value ", value)
			return null
		
		TYPE_OBJECT:
			var buffer := value as PackedByteArray
			if not buffer:
				push_warning("Expected a PackedByteArray when deserializing an object, got: ", value)
				return null
			
			var type_tag := buffer.get(0)
			match type_tag:
				BinarySerializer._ENCODED_RESOURCE_REFERENCE_TAG:
					return _decode_resource_reference(buffer, expected_class_name)
				
				BinarySerializer._ENCODED_NODE_REFERENCE_TAG:
					var path_length := buffer.decode_u32(BinarySerializer._ENCODED_NODE_REFERENCE_PATH_LENGTH_U32_OFFSET)
					if path_length <= 0:
						push_warning("Invalid path length ", path_length, " found when deserializing a node reference")
						return null
					
					var path_buffer := buffer.slice(BinarySerializer._ENCODED_NODE_REFERENCE_DATA_OFFSET, BinarySerializer._ENCODED_NODE_REFERENCE_DATA_OFFSET + path_length)
					var node_path := NodePath(path_buffer.get_string_from_utf8())
					return _decode_node_reference(node_path)
				
				BinarySerializer._SAVED_RESOURCE_REFERENCE_TAG:
					return _load_resource(buffer)
				
				_:
					push_warning("Unknown type tag ", type_tag, " found when deserializing an object")
					return null
		
		TYPE_ARRAY:
			var array := value as Array
			if not array:
				push_warning("Expected an array when deserializing an array, got: ", value)
				return null
			
			return array.map(_decode_var_with_type_info)
		
		TYPE_DICTIONARY:
			var dictionary := value as Dictionary
			if not dictionary:
				push_warning("Expected a dictionary when deserializing a dictionary, got: ", value)
				return null
			
			var decoded_dictionary: Dictionary
			for key: Variant in dictionary:
				var decoded_key: Variant = _decode_var_with_type_info(key)
				var decoded_value: Variant = _decode_var_with_type_info(dictionary[key])
				decoded_dictionary[decoded_key] = decoded_value
			
			return decoded_dictionary
		
		_:
			return value

func _decode_var_with_type_info(value: Variant) -> Variant:
	var buffer := value as PackedByteArray
	if not buffer:
		push_warning("Expected a PackedByteArray when decoding a typed value, got: ", value)
		return null
	
	var type := buffer.decode_u8(BinarySerializer._ENCODED_TYPED_VALUE_TYPE_U8_OFFSET) as Variant.Type
	var classname_length := buffer.decode_u16(BinarySerializer._ENCODED_TYPED_VALUE_CLASS_NAME_LENGTH_U16_OFFSET)

	var classname: StringName = ""
	if classname_length:
		var classname_buffer := buffer.slice(BinarySerializer._ENCODED_TYPED_VALUE_DATA_OFFSET, BinarySerializer._ENCODED_TYPED_VALUE_DATA_OFFSET + classname_length)
		classname = StringName(classname_buffer.get_string_from_utf8())

	var encoded_value := buffer.slice(BinarySerializer._ENCODED_TYPED_VALUE_DATA_OFFSET + classname_length)
	return decode_var(bytes_to_var(encoded_value), type, classname)

func _decode_node_reference(node_path: NodePath) -> Node:
	# To ensure we can convert this node path into a valid node reference, we need to effectively "preload" the target node and all of its ancestors.
	# This process is similar to load_node(), but circumventing the normal order and without actually loading data into the nodes yet.
	if node_path.get_name_count() > 1:
		var parent_node := _decode_node_reference(node_path.slice(0, -1))
		if not parent_node:
			return null

	var save_dict: Dictionary = _saved_nodes.get(node_path, {})
	var scene_file_path: String = save_dict.get(BinarySerializer._NODE_SCENE_FILE_PATH_KEY, "")
	return find_or_instantiate_node(node_path, scene_file_path, false)

## Decodes a reference to a resource, loading it by UID or path as appropriate.
##
## Note: [param expected_class_name] should refer to a class that exists within [ClassDB] (i.e., built-in or GDExtension classes). It should [i]not[/i] contain the name of a script-defined [code]class_name[/code].
func _decode_resource_reference(buffer: PackedByteArray, expected_class_name: StringName) -> Resource:
	var path_length := buffer.decode_u32(BinarySerializer._ENCODED_RESOURCE_REFERENCE_PATH_LENGTH_U32_OFFSET)
	var uid_length := buffer.decode_u32(BinarySerializer._ENCODED_RESOURCE_REFERENCE_UID_LENGTH_U32_OFFSET)

	var path_buffer := buffer.slice(BinarySerializer._ENCODED_RESOURCE_REFERENCE_DATA_OFFSET, BinarySerializer._ENCODED_RESOURCE_REFERENCE_DATA_OFFSET + path_length)

	var uid_buffer: PackedByteArray
	if uid_length:
		uid_buffer = buffer.slice(BinarySerializer._ENCODED_RESOURCE_REFERENCE_DATA_OFFSET + path_length, BinarySerializer._ENCODED_RESOURCE_REFERENCE_DATA_OFFSET + path_length + uid_length)

	var resource_path := path_buffer.get_string_from_utf8()
	if uid_buffer:
		var id := ResourceUID.text_to_id(uid_buffer.get_string_from_utf8())
		if ResourceUID.has_id(id):
			resource_path = ResourceUID.get_id_path(id)
	
	var allowed_extensions := ResourceLoader.get_recognized_extensions_for_type(expected_class_name if expected_class_name else &"Resource")
	return ResourceUtils.safe_load_resource(resource_path, allowed_extensions)

## Returns how many nodes remain to be loaded from the save data. This can be used to determine loading progress.
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

	var scene_file_path: String = save_dict.get(BinarySerializer._NODE_SCENE_FILE_PATH_KEY, "")
	save_dict.erase(BinarySerializer._NODE_SCENE_FILE_PATH_KEY)

	var node := find_or_instantiate_node(node_path, scene_file_path, true)
	if node:
		load_node_from_dict(node, save_dict)

	return node

## Loads a [SaveKitResource] from the save data. If the resource has already been loaded, the existing instance will be returned.
func _load_resource(buffer: PackedByteArray) -> SaveKitResource:
	var resource_id := buffer.decode_u64(BinarySerializer._SAVED_RESOURCE_REFERENCE_ID_U64_OFFSET)

	var resource: SaveKitResource = _loaded_resources_by_id.get(resource_id)
	if not resource:
		var save_dict: Dictionary = _saved_resources_by_id.get(resource_id, {})
		if not save_dict:
			push_error("No saved resource found with ID ", resource_id)
			return null
		
		_saved_resources_by_id.erase(resource_id)
	
		var script: Script = _decode_resource_reference(save_dict.get(BinarySerializer._SAVED_RESOURCE_SCRIPT_KEY) as PackedByteArray, "Script")
		if not script:
			push_error("Failed to decode script for resource with ID ", resource_id, ", cannot load resource")
			return null
		
		save_dict.erase(BinarySerializer._SAVED_RESOURCE_SCRIPT_KEY)
		
		@warning_ignore("unsafe_method_access")
		resource = script.new()
		resource.load_from_dict(self , save_dict)
		_loaded_resources_by_id[resource_id] = resource

	return resource
