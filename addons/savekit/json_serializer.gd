extends "serializer.gd"

var _finalized: bool = false
var _saved_nodes: Dictionary[NodePath, Dictionary]
var _saved_resources_by_id: Dictionary[String, Dictionary]

const _NODE_SCENE_FILE_PATH_KEY: String = "scene_file_path"

const _NODES_KEY := "nodes"
const _RESOURCES_KEY := "resources"

const _ENCODED_NODE_REFERENCE_KEY := "node"
const _ENCODED_RESOURCE_REFERENCE_PATH_KEY := "path"
const _ENCODED_RESOURCE_REFERENCE_UID_KEY := "uid"

const _SAVED_RESOURCE_ID_KEY := "res"
const _SAVED_RESOURCE_SCRIPT_KEY := "script"

const _SERIALIZATION_VERSION_KEY: String = "version"
const _SERIALIZATION_VERSION: int = 1

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if not _finalized and (_saved_nodes or _saved_resources_by_id):
				push_warning("finalize_save() was not called on JSON serializer before it was freed. Data is not actually being saved!")

func finalize_save() -> Dictionary:
	var save_dict := {
		_SERIALIZATION_VERSION_KEY: _SERIALIZATION_VERSION,
		_NODES_KEY: _saved_nodes,
	}

	if _saved_resources_by_id:
		save_dict[_RESOURCES_KEY] = _saved_resources_by_id
	
	_finalized = true
	return save_dict

func encode_var(value: Variant) -> Variant:
	match typeof(value):
		TYPE_RID, TYPE_CALLABLE, TYPE_SIGNAL:
			push_warning("Cannot serialize value of type ", type_string(typeof(value)), ": ", value)
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
		
		_:
			return JSON.from_native(value)

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

func encode_node_reference(node: Node) -> Variant:
	return {
		_ENCODED_NODE_REFERENCE_KEY: str(save_path_for_node(node)),
	}

func save_node(node: Node) -> void:
	var node_path := save_path_for_node(node)
	var save_dict := save_node_to_dict(node)

	if node.scene_file_path:
		save_dict[_NODE_SCENE_FILE_PATH_KEY] = node.scene_file_path
	# TODO: else, save script reference for programmatic instantiation?

	_saved_nodes[node_path] = save_dict

func save_resource(resource: SaveableResource) -> Variant:
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
