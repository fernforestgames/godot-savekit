extends "serializer.gd"
## Serializes save data into JSON format.

## Passed to [method JSON.stringify], this controls if and how something is indented in the serialized JSON. This string will be used where there should be an indent in the output.
##
## For example, [code]"  "[/code] will indent with two spaces, and [code]"\t"[/code] will indent with tabs. Set to [code]""[/code] to not prettify at all.
##
## Enabling this is helpful for creating human-readable JSON.
var indent: String = "\t"

## Passed to [method JSON.stringify], this controls whether keys in serialized JSON dictionaries are sorted alphabetically. Enabling this can be helpful for creating human-readable JSON, but may have a performance cost.
var sort_keys: bool = false

## Passed to [method JSON.stringify], this controls whether floating-point numbers are stringified including all unreliable digits. Enabling this guarantees exact decoding of floats, but may increase the size of the JSON output.
var full_precision: bool = false

var _finalized: bool = false
var _saved_nodes: Dictionary[NodePath, Dictionary]
var _saved_resources_by_id: Dictionary[String, Dictionary]

const _NODE_SCENE_FILE_PATH_KEY: String = "scene_file_path"

const _NODES_KEY := "nodes"
const _RESOURCES_KEY := "resources"

const _ENCODED_NODE_REFERENCE_KEY := "node"
const _ENCODED_RESOURCE_REFERENCE_PATH_KEY := "path"
const _ENCODED_RESOURCE_REFERENCE_UID_KEY := "uid"
const _ENCODED_TYPED_VALUE_KEY := "v"
const _ENCODED_TYPED_VALUE_TYPE_KEY := "t"
const _ENCODED_TYPED_VALUE_CLASS_NAME_KEY := "c"

const _SAVED_RESOURCE_ID_KEY := "res"
const _SAVED_RESOURCE_SCRIPT_KEY := "script"

const _SERIALIZATION_VERSION_KEY: String = "version"
const _SERIALIZATION_VERSION: int = 1

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if not _finalized and (_saved_nodes or _saved_resources_by_id):
				push_warning("JSON serializer was not finalized before it was freed. Data is not actually being saved!")

func finalize_save_in_memory() -> PackedByteArray:
	var save_dict := {
		_SERIALIZATION_VERSION_KEY: _SERIALIZATION_VERSION,
		_NODES_KEY: _saved_nodes,
	}

	if _saved_resources_by_id:
		save_dict[_RESOURCES_KEY] = _saved_resources_by_id
	
	var json_string := JSON.stringify(save_dict, indent, sort_keys, full_precision)
	_finalized = true
	return json_string.to_utf8_buffer()

func encode_var(value: Variant) -> Variant:
	match typeof(value):
		TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			push_warning("Cannot serialize value of type ", type_string(typeof(value)), ": ", value)
			return null

		TYPE_OBJECT:
			if value is SaveKitResource:
				return save_resource(value as SaveKitResource)
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
			var encoded_dictionary: Dictionary[String, Variant]
			for key: Variant in dictionary:
				var encoded_key: Variant = _encode_var_with_type_info(key)
				var encoded_value: Variant = _encode_var_with_type_info(dictionary[key])

				# JSON keys must be strings, so (wastefully) recursively encode them.
				# The alternative would be to encode all object types into strings all of the time, which is wasteful in a different way.
				var stringified_key := JSON.stringify(encoded_key, "", false)
				encoded_dictionary[stringified_key] = encoded_value
			
			return encoded_dictionary
		
		_:
			return JSON.from_native(value)

func _encode_var_with_type_info(value: Variant) -> Variant:
	var encoded := {
		_ENCODED_TYPED_VALUE_KEY: encode_var(value),
		_ENCODED_TYPED_VALUE_TYPE_KEY: typeof(value),
	}

	if value is Object:
		encoded[_ENCODED_TYPED_VALUE_CLASS_NAME_KEY] = (value as Object).get_class()
	
	return encoded

## Encodes a reference to a resource that can be loaded from the [code]res://[/code] filesystem later.
##
## This does not serialize any properties or other data from the resource, only enough information to load it later. This is appropriate for resources that are expected to be shared across saves and exist independently of the save data (e.g., sprites, sound effects, static game data).
func encode_resource_reference(resource: Resource) -> Variant:
	if not resource.resource_path:
		push_warning("Cannot encode reference to resource ", resource, " as it does not have a resource_path")
		return null

	var uid := ResourceUID.path_to_uid(resource.resource_path)
	if uid == resource.resource_path:
		return {
			_ENCODED_RESOURCE_REFERENCE_PATH_KEY: resource.resource_path,
		}
	else:
		return {
			_ENCODED_RESOURCE_REFERENCE_UID_KEY: uid,
			_ENCODED_RESOURCE_REFERENCE_PATH_KEY: resource.resource_path,
		}

## Encodes a reference to a node in the scene tree.
##
## This does not serialize any properties or other data from the node, only enough information to find it in the scene tree later. This is appropriate for cross-references [i]between[/i] nodes, or references [i]from[/i] resources [i]to[/i] nodes. Node data itself will be serialized separately using [method save_node].
func encode_node_reference(node: Node) -> Variant:
	return {
		_ENCODED_NODE_REFERENCE_KEY: str(save_path_for_node(node)),
	}

func save_node(node: Node) -> void:
	var node_path := save_path_for_node(node)
	if node_path in _saved_nodes:
		push_warning("Node ", node_path, " has already been saved, overwriting")

	var save_dict := save_node_to_dict(node)

	if node.scene_file_path:
		save_dict[_NODE_SCENE_FILE_PATH_KEY] = node.scene_file_path
	# TODO: else, save script reference for programmatic instantiation?

	_saved_nodes[node_path] = save_dict

## Adds [param resource] to the save data, serializing its properties according to [method SaveKitResource.save_to_dict]. Returns a reference that can be used to link to this resource from other saved data.
##
## If [param resource] has already been saved, it will not be saved again; instead, a reference to the previously saved data will be returned.
func save_resource(resource: SaveKitResource) -> Variant:
	var instance_id := str(resource.get_instance_id())
	if instance_id not in _saved_resources_by_id:
		# Register a placeholder before encoding, to avoid infinite recursion in case of circular references
		_saved_resources_by_id[instance_id] = {}

		var save_dict := resource.save_to_dict(self )
		var script: Script = resource.get_script()
		save_dict[_SAVED_RESOURCE_SCRIPT_KEY] = encode_resource_reference(script)

		_saved_resources_by_id[instance_id] = save_dict
	
	return {
		_SAVED_RESOURCE_ID_KEY: instance_id,
	}
