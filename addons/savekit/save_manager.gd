extends Node
## Coordinates saving and loading, using a configurable serializer and deserializer. This is the main entry point for saving and loading the scene tree.
##
## By default, this is installed as an autoload singleton named [code]SaveManager[/code] when the plugin is enabled, but it can also be used as a regular node if desired (e.g., to have multiple independent save managers with different configurations).

## A scene tree group containing all nodes that should be saved and loaded.
##
## [member Deserializer.saveable_node_group] will also be set to this value when the deserializer is created.
@export var saveable_node_group: StringName = &"saveable"

## The name for a method that Nodes can implement to perform actions before the SaveManager starts saving the scene tree.
##
## Will only be called on nodes that are members of [member saveable_node_group].
@export var before_save_method: StringName = &"before_save"

## The name for a method that Nodes can implement to perform actions after the SaveManager has saved the scene tree.
##
## Will only be called on nodes that are members of [member saveable_node_group].
@export var after_save_method: StringName = &"after_save"

## The name for a method that Nodes can implement to perform actions before the SaveManager starts loading the scene tree.
##
## Will only be called on nodes that are members of [member saveable_node_group] and [b]already in the scene tree[/b] before loading begins.
@export var before_load_method: StringName = &"before_load"

## The name for a method that Nodes can implement to perform actions after the SaveManager has loaded the scene tree.
##
## Will only be called on nodes that are members of [member saveable_node_group], including nodes added to the scene tree during loading. Nodes which were removed from the scene tree during loading will [b]not[/b] have this method called.
@export var after_load_method: StringName = &"after_load"

## The implementation of the [Serializer] interface to use for saving the scene tree.
@export var serializer_script: Script = preload("json_serializer.gd")

## The implementation of the [Deserializer] interface to use for loading the scene tree.
@export var deserializer_script: Script = preload("json_deserializer.gd")

## Emitted before the SaveManager starts saving the scene tree.
signal before_save

## Emitted after the SaveManager has saved the scene tree.
signal after_save

## Emitted before the SaveManager starts loading the scene tree.
signal before_load

## Emitted after the SaveManager has loaded the scene tree.
signal after_load

## Emitted after [param node] has been saved.
signal node_saved(node: Node)

## Emitted after [param node] has been loaded.
signal node_loaded(node: Node)

## Emitted when [param node] has been created and added to the scene tree, as part of the loading process.
signal node_created(node: Node)

## Emitted when [param node] has been removed from the scene tree, as part of the loading process.
signal node_removed(node: Node)

const Deserializer := preload("deserializer.gd")
const Serializer := preload("serializer.gd")

func _save_scene_tree(finalizer: Callable) -> Variant:
	before_save.emit()

	var scene_tree := get_tree()
	scene_tree.call_group(saveable_node_group, before_save_method)

	@warning_ignore("unsafe_method_access")
	var serializer: Serializer = serializer_script.new()

	var saveable_nodes := scene_tree.get_nodes_in_group(saveable_node_group)
	for node in saveable_nodes:
		if node.is_queued_for_deletion():
			push_warning("Node ", node.get_path(), " is queued for deletion, skipping it during save")
			continue
		
		serializer.save_node(node)
		node_saved.emit(node)
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_node_group, after_save_method)

	var result: Variant = finalizer.call(serializer)
	after_save.emit()
	return result

func save_scene_tree_in_memory() -> PackedByteArray:
	return _save_scene_tree(func(serializer: Serializer) -> Variant:
		return serializer.finalize_save_in_memory()
	)

func save_scene_tree_to_disk(path: String) -> Error:
	return _save_scene_tree(func(serializer: Serializer) -> Variant:
		return serializer.finalize_save_to_disk(path)
	)

func _before_load() -> Deserializer:
	before_load.emit()

	var scene_tree := get_tree()
	scene_tree.call_group(saveable_node_group, before_load_method)

	@warning_ignore("unsafe_method_access")
	var deserializer: Deserializer = deserializer_script.new()
	deserializer.scene_tree = scene_tree
	deserializer.saveable_node_group = saveable_node_group
	deserializer.node_created.connect(_on_node_created)
	return deserializer

func _load_scene_tree(deserializer: Deserializer) -> void:
	var loaded_nodes: Array[Node]
	while not deserializer.is_finished():
		var node := deserializer.load_node()
		if not node:
			continue

		loaded_nodes.append(node)
		node_loaded.emit(node)
	
	# TODO: Does this need to be deferred?
	var scene_tree := get_tree()
	for node in scene_tree.get_nodes_in_group(saveable_node_group):
		if node not in loaded_nodes:
			node.queue_free()
			node_removed.emit(node)
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_node_group, after_load_method)
	after_load.emit()

func load_scene_tree_from_memory(data: PackedByteArray) -> bool:
	var deserializer := _before_load()
	if not deserializer.prepare_load_from_memory(data):
		return false
	
	_load_scene_tree(deserializer)
	return true

func load_scene_tree_from_file(path: String) -> Error:
	var deserializer := _before_load()
	var error := deserializer.prepare_load_from_file(path)
	if error != OK:
		return error
	
	_load_scene_tree(deserializer)
	return OK

func _on_node_created(node: Node) -> void:
	node_created.emit(node)
