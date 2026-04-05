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

## The directory to save and load games to/from.
@export_dir var save_games_directory: String = "user://save_games/"

## The extension to use with save game files, or an empty string to have no extension. Should include the dot if specified (e.g., [code].json[/code]).
@export var save_file_extension: String = ".json"

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
const SaveGameFile := preload("save_game_file.gd")
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

## Saves all [member saveable_node_group] nodes in the scene tree, returning a buffer containing the saved data.
func save_scene_tree_in_memory() -> PackedByteArray:
	return _save_scene_tree(func(serializer: Serializer) -> Variant:
		return serializer.finalize_save_in_memory()
	)

## Saves all [member saveable_node_group] nodes in the scene tree, writing the saved data to the given file path. Returns an error if saving failed.
func save_scene_tree_to_disk(absolute_path: String) -> Error:
	return _save_scene_tree(func(serializer: Serializer) -> Variant:
		return serializer.finalize_save_to_disk(absolute_path)
	)

## Creates a save game file, naming it according to [param save_name_components], and optionally overwriting any existing file.
##
## On disk, [param save_name_components] is used to create separate save game directories inside [member save_games_directory]. In game, this could be used, for example, to differentiate individual games [i]as well as[/i] different save slots within those games (e.g., [code]"My Cool Game", "Autosave 1"[/code]).
##
## Since these names may come from user input, the components are sanitized and validated before being assigned to this property. The resulting text may not exactly match what the user entered.
##
## Returns information about the created save game file, or null if saving failed.
func save_game(save_name_components: PackedStringArray, allow_overwrite: bool = false) -> SaveGameFile:
	if not save_games_directory.is_absolute_path():
		push_error("save_games_directory must be an absolute path: ", save_games_directory)
		return null

	var save_path := SaveGameFile.sanitize_save_name_components(save_name_components)
	if not save_path:
		push_error("After sanitization, save name components resulted in an empty filename: ", save_name_components)
		return null
	
	var sanitized_save_name_components := save_path.split("/")
	var absolute_path := save_games_directory.path_join(save_path + save_file_extension)
	if not allow_overwrite and FileAccess.file_exists(absolute_path):
		push_warning("Disallowing overwriting save file: ", absolute_path)
		return null
	
	var error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if error != OK:
		push_error("Failed to create directory for save file: ", absolute_path, " (", error_string(error), ")")
		return null
	
	error = save_scene_tree_to_disk(absolute_path)
	if error != OK:
		push_error("Failed to save scene tree to disk: ", absolute_path, " (", error_string(error), ")")
		return null
	
	var save_game_file := SaveGameFile.new()
	save_game_file.save_name_components = sanitized_save_name_components
	save_game_file.absolute_path = absolute_path
	save_game_file.modified_at_unix_time = FileAccess.get_modified_time(absolute_path)
	return save_game_file

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

## Loads [member saveable_node_group] nodes into the scene tree from the given buffer of save data. Returns false if loading failed.
##
## Nodes will be added, removed, and updated as needed to match the provided save data.
func load_scene_tree_from_memory(data: PackedByteArray) -> bool:
	var deserializer := _before_load()
	if not deserializer.prepare_load_from_memory(data):
		return false
	
	_load_scene_tree(deserializer)
	return true

## Loads [member saveable_node_group] nodes into the scene tree from file at the given path. Returns an error if loading failed.
##
## Nodes will be added, removed, and updated as needed to match the provided save data.
func load_scene_tree_from_file(absolute_path: String) -> Error:
	var deserializer := _before_load()
	var error := deserializer.prepare_load_from_file(absolute_path)
	if error != OK:
		return error
	
	_load_scene_tree(deserializer)
	return OK

## Opens a save game file that matches [param save_name_components] within [member save_games_directory], and loads it into the scene tree. Returns an error if loading failed.
func load_game(save_name_components: PackedStringArray) -> Error:
	if not save_games_directory.is_absolute_path():
		push_error("save_games_directory must be an absolute path: ", save_games_directory)
		return ERR_INVALID_PARAMETER

	var save_path := SaveGameFile.sanitize_save_name_components(save_name_components)
	if not save_path:
		push_error("After sanitization, save name components resulted in an empty filename: ", save_name_components)
		return ERR_INVALID_PARAMETER
	
	var absolute_path := save_games_directory.path_join(save_path + save_file_extension)
	return load_scene_tree_from_file(absolute_path)

## Looks up a save game file by its absolute path, or returns null if the path doesn't point to a valid save game file. The path must be within [member save_games_directory].
func get_save_file_at_path(path: String) -> SaveGameFile:
	path = path.simplify_path()
	if not path.begins_with(save_games_directory):
		push_warning("Save file path must be within save_games_directory: ", path)
		return null

	if not FileAccess.file_exists(path):
		return null
	
	var relative_path := path.substr(save_games_directory.length())
	if not relative_path:
		push_warning("Given save file path is the same as save_games_directory, expected a file within that directory: ", path)
		return null
	
	var save_game_file := SaveGameFile.new()
	save_game_file.save_name_components = relative_path.get_basename().split("/")
	save_game_file.absolute_path = path
	save_game_file.modified_at_unix_time = FileAccess.get_modified_time(path)
	return save_game_file

## Lists save game files that exist on disk.
##
## An optional [param directory_path] (which must be an absolute path) can be provided to limit the results to a specific subdirectory within [member save_games_directory]. By default, all save game files within [member save_games_directory] and its subdirectories will be listed.
##
## If [param recursive] is true, save game files within all subdirectories of [param directory_path] will be included.
##
## If [param sort_by_modified_time] is true, the resulting list will be sorted by modified time, with the most recently modified save games first. Otherwise, the order is not guaranteed.
func list_save_files(directory_path: String = "", recursive: bool = true, sort_by_modified_time: bool = true) -> Array[SaveGameFile]:
	if directory_path:
		directory_path = directory_path.simplify_path()
		if not directory_path.begins_with(save_games_directory):
			push_warning("Directory path must be within save_games_directory: ", directory_path)
			return []
	else:
		directory_path = save_games_directory
	
	var dir := DirAccess.open(directory_path)
	if not dir:
		push_warning("Could not list save games directory: ", directory_path, " (", error_string(DirAccess.get_open_error()), ")")
		return []
	
	dir.include_hidden = false
	dir.include_navigational = false
	dir.list_dir_begin()

	var file_name := dir.get_next()
	var save_files: Array[SaveGameFile]

	while file_name:
		if dir.current_is_dir():
			if recursive:
				save_files.append_array(list_save_files(directory_path.path_join(file_name), true, false))
		elif file_name.ends_with(save_file_extension):
			var save_file := get_save_file_at_path(directory_path.path_join(file_name))
			if save_file:
				save_files.append(save_file)

		file_name = dir.get_next()
	
	dir.list_dir_end()

	if sort_by_modified_time:
		save_files.sort_custom(func(a: SaveGameFile, b: SaveGameFile) -> bool:
			# Sort most recent saves first
			return a.modified_at_unix_time > b.modified_at_unix_time
		)

	return save_files

func _on_node_created(node: Node) -> void:
	node_created.emit(node)
