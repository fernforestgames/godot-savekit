extends Node

@export var saveable_group: StringName = &"saveable"

@export var before_save_method: StringName = &"before_save"
@export var after_save_method: StringName = &"after_save"

@export var before_load_method: StringName = &"before_load"
@export var after_load_method: StringName = &"after_load"

# TODO: Looser coupling
const JSONSerializer := preload("json_serializer.gd")
const JSONDeserializer := preload("json_deserializer.gd")

signal finished_saving
signal finished_loading

signal node_saved(node: Node)
signal node_loaded(node: Node)

signal node_created(node: Node)
signal node_removed(node: Node)

func save_scene_tree() -> Dictionary:
	var scene_tree := get_tree()
	scene_tree.call_group(saveable_group, before_save_method)

	var serializer := JSONSerializer.new()

	var saveable_nodes := scene_tree.get_nodes_in_group(saveable_group)
	for node in saveable_nodes:
		if node.is_queued_for_deletion():
			push_warning("Node ", node.get_path(), " is queued for deletion, skipping it during save")
			continue
		
		serializer.save_node(node)
		node_saved.emit(node)
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_group, after_save_method)

	var save_dict := serializer.finalize_save()
	finished_saving.emit()
	return save_dict

func load_into_scene_tree(data: Dictionary) -> void:
	var scene_tree := get_tree()
	scene_tree.call_group(saveable_group, before_load_method)

	var deserializer := JSONDeserializer.new(data)
	deserializer.scene_tree = scene_tree
	deserializer.saveable_node_group = saveable_group
	deserializer.node_created.connect(_on_node_created)

	var loaded_nodes: Array[Node]
	while not deserializer.is_finished():
		var node := deserializer.load_node()
		if not node:
			continue

		loaded_nodes.append(node)
		node_loaded.emit(node)
	
	# TODO: Does this need to be deferred?
	for node in scene_tree.get_nodes_in_group(saveable_group):
		if node not in loaded_nodes:
			node.queue_free()
			node_removed.emit(node)
	
	scene_tree.call_group_flags(SceneTree.GROUP_CALL_REVERSE, saveable_group, after_load_method)
	finished_loading.emit()

func _on_node_created(node: Node) -> void:
	if node.has_method(before_load_method):
		node.call(before_load_method)
	
	node_created.emit(node)
