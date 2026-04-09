extends "serializer.gd"
## Serializes save data into a binary format.

var _finalized: bool = false
var _saved_nodes_buffer: PackedByteArray
var _saved_resource_ids: PackedInt64Array
var _saved_resources_buffer: PackedByteArray

# File header layout
enum {
	_SERIALIZATION_VERSION_U32_OFFSET = 0,
	_SAVED_NODES_LENGTH_U64_OFFSET = 4,
	_SAVED_RESOURCES_LENGTH_U64_OFFSET = 12,
	_FILE_HEADER_SIZE = 20,
}

# u8 tags, used to differentiate types of Object
enum {
	_ENCODED_RESOURCE_REFERENCE_TAG = 1,
	_ENCODED_NODE_REFERENCE_TAG = 2,
	_SAVED_RESOURCE_REFERENCE_TAG = 3,
}

# Resource reference layout
enum {
	_ENCODED_RESOURCE_REFERENCE_PATH_LENGTH_U32_OFFSET = 1,
	_ENCODED_RESOURCE_REFERENCE_UID_LENGTH_U32_OFFSET = 5,
	_ENCODED_RESOURCE_REFERENCE_DATA_OFFSET = 9,
}

# Node reference layout
enum {
	_ENCODED_NODE_REFERENCE_PATH_LENGTH_U32_OFFSET = 1,
	_ENCODED_NODE_REFERENCE_DATA_OFFSET = 5,
}

# Saved resource reference layout
enum {
	_SAVED_RESOURCE_REFERENCE_ID_U64_OFFSET = 1,
	_SAVED_RESOURCE_REFERENCE_SIZE = 9,
}

enum {
	_ENCODED_TYPED_VALUE_TYPE_U8_OFFSET = 0,
	_ENCODED_TYPED_VALUE_CLASS_NAME_LENGTH_U16_OFFSET = 1,
	_ENCODED_TYPED_VALUE_DATA_OFFSET = 3,
}

const _NODE_SCENE_FILE_PATH_KEY := 0xF17E
const _SAVED_RESOURCE_SCRIPT_KEY := 0xC0DE

const _SERIALIZATION_VERSION: int = 1

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if not _finalized and (_saved_nodes_buffer or _saved_resources_buffer):
				push_warning("Binary serializer was not finalized before it was freed. Data is not actually being saved!")

func encode_var(value: Variant) -> Variant:
	match typeof(value):
		TYPE_CALLABLE:
			push_error("Cannot serialize callable value ", value)
			return null
		
		TYPE_OBJECT:
			if value is SaveableResource:
				return save_resource(value as SaveableResource)
			elif value is Resource:
				return encode_resource_reference(value as Resource)
			elif value is Node:
				return encode_node_reference(value as Node)
			else:
				push_warning("Cannot serialize non-Resource, non-Node object: ", value)
				return null
		
		TYPE_ARRAY:
			var array: Array = value
			return array.map(_encode_var_with_type_info)
		
		TYPE_DICTIONARY:
			var dictionary: Dictionary = value
			var encoded_dictionary: Dictionary
			for key: Variant in dictionary:
				var encoded_key: Variant = _encode_var_with_type_info(key)
				var encoded_value: Variant = _encode_var_with_type_info(dictionary[key])
				encoded_dictionary[encoded_key] = encoded_value
			
			return encoded_dictionary
		
		_:
			return value

func _encode_var_with_type_info(value: Variant) -> Variant:
	var buffer: PackedByteArray
	buffer.resize(_ENCODED_TYPED_VALUE_DATA_OFFSET)
	buffer.encode_u8(_ENCODED_TYPED_VALUE_TYPE_U8_OFFSET, typeof(value))

	if value is Object:
		var classname_buffer := (value as Object).get_class().to_utf8_buffer()
		buffer.encode_u16(_ENCODED_TYPED_VALUE_CLASS_NAME_LENGTH_U16_OFFSET, classname_buffer.size())
		buffer.append_array(classname_buffer)
	
	buffer.append_array(var_to_bytes(encode_var(value)))
	return buffer

func save_node(node: Node) -> void:
	var node_path := save_path_for_node(node)
	var save_dict := save_node_to_dict(node)

	if node.scene_file_path:
		save_dict[_NODE_SCENE_FILE_PATH_KEY] = node.scene_file_path
	# TODO: else, save script reference for programmatic instantiation?

	_saved_nodes_buffer.append_array(var_to_bytes(node_path))
	_saved_nodes_buffer.append_array(var_to_bytes(save_dict))

func finalize_save_in_memory() -> PackedByteArray:
	var buffer: PackedByteArray
	buffer.resize(_FILE_HEADER_SIZE)
	buffer.encode_u32(_SERIALIZATION_VERSION_U32_OFFSET, _SERIALIZATION_VERSION)
	buffer.encode_u64(_SAVED_NODES_LENGTH_U64_OFFSET, _saved_nodes_buffer.size())
	buffer.encode_u64(_SAVED_RESOURCES_LENGTH_U64_OFFSET, _saved_resources_buffer.size())
	buffer.append_array(_saved_nodes_buffer)
	buffer.append_array(_saved_resources_buffer)
	_finalized = true
	return buffer

## Encodes a reference to a resource that can be loaded from the [code]res://[/code] filesystem later.
##
## This does not serialize any properties or other data from the resource, only enough information to load it later. This is appropriate for resources that are expected to be shared across saves and exist independently of the save data (e.g., sprites, sound effects, static game data).
func encode_resource_reference(resource: Resource) -> Variant:
	if not resource.resource_path:
		push_warning("Cannot encode reference to resource ", resource, " as it does not have a resource_path")
		return null
	
	var buffer: PackedByteArray
	buffer.resize(_ENCODED_RESOURCE_REFERENCE_DATA_OFFSET)
	buffer.set(0, _ENCODED_RESOURCE_REFERENCE_TAG)

	var path_buffer := resource.resource_path.to_utf8_buffer()
	buffer.encode_u32(_ENCODED_RESOURCE_REFERENCE_PATH_LENGTH_U32_OFFSET, path_buffer.size())
	buffer.append_array(path_buffer)

	var uid := ResourceUID.path_to_uid(resource.resource_path)

	if uid == resource.resource_path:
		buffer.encode_u32(_ENCODED_RESOURCE_REFERENCE_UID_LENGTH_U32_OFFSET, 0)
	else:
		var uid_buffer := uid.to_utf8_buffer()
		buffer.encode_u32(_ENCODED_RESOURCE_REFERENCE_UID_LENGTH_U32_OFFSET, uid_buffer.size())
		buffer.append_array(uid_buffer)
	
	return buffer

## Encodes a reference to a node in the scene tree.
##
## This does not serialize any properties or other data from the node, only enough information to find it in the scene tree later. This is appropriate for cross-references [i]between[/i] nodes, or references [i]from[/i] resources [i]to[/i] nodes. Node data itself will be serialized separately using [method save_node].
func encode_node_reference(node: Node) -> Variant:
	var buffer: PackedByteArray
	buffer.resize(_ENCODED_NODE_REFERENCE_DATA_OFFSET)
	buffer.set(0, _ENCODED_NODE_REFERENCE_TAG)

	var path_buffer := str(save_path_for_node(node)).to_utf8_buffer()
	buffer.encode_u32(_ENCODED_NODE_REFERENCE_PATH_LENGTH_U32_OFFSET, path_buffer.size())
	buffer.append_array(path_buffer)

	return buffer

## Adds [param resource] to the save data, serializing its properties according to [method SaveableResource.save_to_dict]. Returns a reference that can be used to link to this resource from other saved data.
##
## If [param resource] has already been saved, it will not be saved again; instead, a reference to the previously saved data will be returned.
func save_resource(resource: SaveableResource) -> Variant:
	var instance_id := resource.get_instance_id()
	if instance_id not in _saved_resource_ids:
		# Register before encoding, to avoid infinite recursion in case of circular references
		_saved_resource_ids.append(instance_id)

		var save_dict := resource.save_to_dict(self )
		var script: Script = resource.get_script()
		save_dict[_SAVED_RESOURCE_SCRIPT_KEY] = encode_resource_reference(script)

		_saved_resources_buffer.append_array(var_to_bytes(instance_id))
		_saved_resources_buffer.append_array(var_to_bytes(save_dict))
	
	var buffer: PackedByteArray
	buffer.resize(_SAVED_RESOURCE_REFERENCE_SIZE)
	buffer.set(0, _SAVED_RESOURCE_REFERENCE_TAG)
	buffer.encode_u64(_SAVED_RESOURCE_REFERENCE_ID_U64_OFFSET, instance_id)

	return buffer
