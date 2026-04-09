extends "deserializer.gd"
## Deserializes save data from binary format.

const BinarySerializer := preload("binary_serializer.gd")

var _saved_nodes_buffer: PackedByteArray
var _saved_resources: Dictionary[int, Dictionary]

func prepare_load_from_memory(data: PackedByteArray) -> bool:
	if data.size() < BinarySerializer._FILE_HEADER_SIZE:
		push_error("Save data is too small to contain required header information")
		return false

	var version := data.decode_u32(BinarySerializer._SERIALIZATION_VERSION_U32_OFFSET)
	if version != BinarySerializer._SERIALIZATION_VERSION:
		push_error("Unsupported save data version: ", version)
		return false
	
	var saved_nodes_length := data.decode_u64(BinarySerializer._SAVED_NODES_LENGTH_U64_OFFSET)
	_saved_nodes_buffer = data.slice(BinarySerializer._FILE_HEADER_SIZE, BinarySerializer._FILE_HEADER_SIZE + saved_nodes_length)

	var saved_resources_length := data.decode_u64(BinarySerializer._SAVED_RESOURCES_LENGTH_U64_OFFSET)
	var saved_resources_buffer := data.slice(BinarySerializer._FILE_HEADER_SIZE + saved_nodes_length, BinarySerializer._FILE_HEADER_SIZE + saved_nodes_length + saved_resources_length)
	_decode_saved_resources(saved_resources_buffer)
	
	return true

func _decode_saved_resources(buffer: PackedByteArray) -> void:
	var offset: int = 0
	while offset < buffer.size():
		var resource_id_size := buffer.decode_var_size(offset)
		if resource_id_size <= 0:
			push_error("Failed to decode saved resource ID at offset ", offset)
			return

		var resource_id: int = buffer.decode_var(offset)
		offset += resource_id_size

		var save_dict_size := buffer.decode_var_size(offset)
		if save_dict_size <= 0:
			push_error("Failed to decode saved data size for resource ID ", resource_id, " at offset ", offset)
			return
		
		var save_dict: Dictionary = buffer.decode_var(offset)
		offset += save_dict_size

		_saved_resources[resource_id] = save_dict

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
					pass
				
				BinarySerializer._SAVED_RESOURCE_TAG:
					pass
				
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
			push_warning("Deserialization of type ", type_string(expected_type), " is not yet implemented")
			return null

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

func decode_node_reference(node_path: NodePath) -> Node:
	# To ensure we can convert this node path into a valid node reference, we need to effectively "preload" the target node and all of its ancestors.
	# This process is similar to load_node(), but circumventing the normal order and without actually loading data into the nodes yet.
	if node_path.get_name_count() > 1:
		var parent_node := decode_node_reference(node_path.slice(0, -1))
		if not parent_node:
			return null
	
	# TODO: Iterate _saved_nodes_buffer
	return null

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

func is_finished() -> bool:
	return not _saved_nodes_buffer

func load_node() -> Node:
	return null
