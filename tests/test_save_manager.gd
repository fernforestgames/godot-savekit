@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const SaveManager := preload("res://addons/savekit/save_manager.gd")
const SaveGameFile := preload("res://addons/savekit/save_game_file.gd")
const MockSaveable := preload("res://tests/fixtures/mock_saveable.gd")
const MockSaveableScene := preload("res://tests/fixtures/mock_saveable.tscn")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")


class MockSaveableWithOverride extends MockSaveable:
	var save_path_override: Variant = null


var _manager: SaveManager
var _temp_diraccess: DirAccess
var _test_dir: String


func before_each() -> void:
	print("before_each")
	_manager = SaveManager.new()
	# Use a unique temporary directory for each test so file system state
	# from one test never leaks into another.
	_temp_diraccess = DirAccess.create_temp("savekit_test")
	_test_dir = _temp_diraccess.get_current_dir()
	_manager.save_games_directory = _test_dir
	add_child_autofree(_manager)


func after_each() -> void:
	_temp_diraccess = null


func _make_saveable(save_data: Dictionary = {}, node_name: String = "Saveable") -> MockSaveable:
	var node := MockSaveable.new()
	node.name = node_name
	node._save_data = save_data
	add_child_autofree(node)
	node.add_to_group("saveable")
	return node


func _make_default_saveable(node_name: String = "DefaultSaveable") -> MockDefaultSaveable:
	var node := MockDefaultSaveable.new()
	node.name = node_name
	add_child_autofree(node)
	node.add_to_group("saveable")
	return node


func _make_load_data(nodes: Dictionary) -> PackedByteArray:
	return JSON.stringify({"version": 1, "nodes": nodes}).to_utf8_buffer()


func _parse_save_data(data: PackedByteArray) -> Dictionary:
	return JSON.parse_string(data.get_string_from_utf8())


# =============================================================================
# save_scene_tree_in_memory
# =============================================================================

func test_save_with_no_saveable_nodes() -> void:
	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	assert_eq(result["version"], 1)
	assert_has(result, "nodes")
	assert_eq(result["nodes"].size(), 0)


func test_save_captures_node_data() -> void:
	var data := {"health": 100, "name": "Player"}
	var node := _make_saveable(data, "Player")
	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	var nodes: Dictionary = result["nodes"]
	var path := str(node.get_path())
	assert_has(nodes, path)
	assert_eq(nodes[path]["health"], 100)
	assert_eq(nodes[path]["name"], "Player")


func test_save_calls_before_save_on_nodes() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.save_scene_tree_in_memory()
	assert_true(node.before_save_called)


func test_save_calls_after_save_on_nodes() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.save_scene_tree_in_memory()
	assert_true(node.after_save_called)


func test_save_emits_before_save_signal() -> void:
	watch_signals(_manager)
	_manager.save_scene_tree_in_memory()
	assert_signal_emitted(_manager, "before_save")


func test_save_emits_after_save_signal() -> void:
	watch_signals(_manager)
	_manager.save_scene_tree_in_memory()
	assert_signal_emitted(_manager, "after_save")


func test_save_emits_node_saved_signal() -> void:
	_make_saveable({}, "TestNode")
	watch_signals(_manager)
	_manager.save_scene_tree_in_memory()
	assert_signal_emitted(_manager, "node_saved")


func test_save_uses_node_path_as_key() -> void:
	var node := _make_saveable({"x": 1}, "MyNode")
	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	assert_has(result["nodes"], str(node.get_path()))


func test_save_uses_save_path_override() -> void:
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node._save_data = {"val": 42}
	node.save_path_override = NodePath("/custom/path")
	add_child_autofree(node)
	node.add_to_group("saveable")

	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	var nodes: Dictionary = result["nodes"]
	assert_has(nodes, "/custom/path")
	assert_eq(nodes["/custom/path"]["val"], 42)


func test_save_multiple_nodes() -> void:
	_make_saveable({"id": 1}, "Node1")
	_make_saveable({"id": 2}, "Node2")
	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	assert_eq(result["nodes"].size(), 2)


func test_save_includes_scene_file_path() -> void:
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {"key": "val"}
	add_child_autofree(node)
	node.add_to_group("saveable")

	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	var path := str(node.get_path())
	assert_has(result["nodes"][path], "scene_file_path")
	assert_eq(result["nodes"][path]["scene_file_path"], "res://tests/fixtures/mock_saveable.tscn")


func test_save_skips_nodes_queued_for_deletion() -> void:
	var node := _make_saveable({"key": "val"}, "DyingNode")
	node.queue_free()
	var result := _parse_save_data(_manager.save_scene_tree_in_memory())
	assert_eq(result["nodes"].size(), 0)


# =============================================================================
# load_scene_tree_from_memory
# =============================================================================

func test_load_existing_node() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_scene_tree_from_memory(_make_load_data({path: {"health": 50}}))
	assert_eq(node.loaded_data["health"], 50)


func test_load_calls_before_load_on_nodes() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_scene_tree_from_memory(_make_load_data({path: {}}))
	assert_true(node.before_load_called)


func test_load_calls_after_load_on_nodes() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_scene_tree_from_memory(_make_load_data({path: {}}))
	assert_true(node.after_load_called)


func test_load_emits_before_load_signal() -> void:
	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(_make_load_data({}))
	assert_signal_emitted(_manager, "before_load")


func test_load_emits_after_load_signal() -> void:
	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(_make_load_data({}))
	assert_signal_emitted(_manager, "after_load")


func test_load_emits_node_loaded_signal() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(_make_load_data({path: {}}))
	assert_signal_emitted(_manager, "node_loaded")


func test_load_removes_unsaved_nodes() -> void:
	_make_saveable({}, "Removable")
	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(_make_load_data({}))
	assert_signal_emitted(_manager, "node_removed")


func test_load_skips_node_not_in_saveable_group() -> void:
	var outside_node := MockSaveable.new()
	outside_node.name = "OutsideNode"
	add_child_autofree(outside_node)
	# Deliberately NOT added to the saveable group
	var path := str(outside_node.get_path())
	_manager.load_scene_tree_from_memory(_make_load_data({path: {"should_not": "load"}}))
	assert_eq(outside_node.loaded_data.size(), 0, "Node outside group should not be loaded")


func test_load_instantiates_missing_node_from_scene() -> void:
	var parent := Node.new()
	parent.name = "SceneParent"
	add_child_autofree(parent)

	var path := str(parent.get_path()) + "/MockSaveable"
	var data := _make_load_data({
		path: {
			"score": 99,
			"scene_file_path": "res://tests/fixtures/mock_saveable.tscn",
		},
	})

	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(data)

	var created_node: MockSaveable = parent.get_node_or_null("MockSaveable")
	assert_not_null(created_node, "Node should have been instantiated from PackedScene")
	assert_true(created_node.is_in_group("saveable"), "Instantiated node should be added to saveable group")
	assert_eq(created_node.loaded_data["score"], 99)
	assert_signal_emitted(_manager, "node_loaded")


func test_load_emits_node_created_for_instantiated_nodes() -> void:
	var parent := Node.new()
	parent.name = "SceneParent"
	add_child_autofree(parent)

	var path := str(parent.get_path()) + "/MockSaveable"
	var data := _make_load_data({
		path: {
			"scene_file_path": "res://tests/fixtures/mock_saveable.tscn",
		},
	})

	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(data)
	assert_signal_emitted(_manager, "node_created")


func test_load_fails_for_missing_node_without_scene_path() -> void:
	var path := "/root/NonExistent/Orphan"
	_manager.load_scene_tree_from_memory(_make_load_data({path: {"val": 1}}))
	assert_push_error("Cannot instantiate node")


func test_load_with_invalid_version() -> void:
	var data := JSON.stringify({"version": 999, "nodes": {}}).to_utf8_buffer()
	_manager.load_scene_tree_from_memory(data)
	assert_push_error("Unsupported save data version")


func test_load_with_missing_version() -> void:
	var data := JSON.stringify({"nodes": {}}).to_utf8_buffer()
	_manager.load_scene_tree_from_memory(data)
	assert_push_error("Unsupported save data version")


# =============================================================================
# round-trip
# =============================================================================

func test_round_trip_with_custom_save_load() -> void:
	var original_data := {"health": 100, "position_x": 5.5}
	var node := _make_saveable(original_data, "RoundTrip")
	var saved := _manager.save_scene_tree_in_memory()
	_manager.load_scene_tree_from_memory(saved)
	assert_eq(node.loaded_data["health"], 100)
	assert_eq(node.loaded_data["position_x"], 5.5)


func test_round_trip_with_scene_instantiated_node() -> void:
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {"coins": 42}
	add_child(node)
	node.add_to_group("saveable")

	var saved := _manager.save_scene_tree_in_memory()
	var parsed := _parse_save_data(saved)
	var path := str(node.get_path())

	assert_has(parsed["nodes"][path], "scene_file_path")
	assert_eq(parsed["nodes"][path]["scene_file_path"], "res://tests/fixtures/mock_saveable.tscn")

	remove_child(node)
	node.free()

	watch_signals(_manager)
	_manager.load_scene_tree_from_memory(saved)

	var restored: MockSaveable = get_node_or_null("SceneNode")
	assert_not_null(restored, "Node should have been re-instantiated from its scene")
	autoqfree(restored)
	assert_eq(restored.loaded_data["coins"], 42)
	assert_true(restored.is_in_group("saveable"))
	assert_signal_emitted(_manager, "node_loaded")


func test_round_trip_with_default_save_load() -> void:
	var node := _make_default_saveable("RoundTripper")
	node.health = 1
	node.player_name = "Zara"
	node.score = 77.7

	var saved := _manager.save_scene_tree_in_memory()
	node.health = 100
	node.player_name = ""
	node.score = 0.0

	_manager.load_scene_tree_from_memory(saved)
	assert_eq(node.health, 1)
	assert_eq(node.player_name, "Zara")
	assert_almost_eq(node.score, 77.7, 0.001)


func test_custom_and_default_nodes_coexist() -> void:
	var custom_node := _make_saveable({"key": "custom_val"}, "CustomNode")
	var default_node := _make_default_saveable("DefaultNode")
	default_node.health = 10

	var saved := _parse_save_data(_manager.save_scene_tree_in_memory())
	var nodes: Dictionary = saved["nodes"]
	assert_has(nodes, str(custom_node.get_path()))
	assert_has(nodes, str(default_node.get_path()))
	assert_eq(nodes[str(custom_node.get_path())]["key"], "custom_val")
	assert_eq(nodes[str(default_node.get_path())]["health"], JSON.from_native(10))


# =============================================================================
# save_game
# =============================================================================

func test_save_game_writes_file_to_expected_path() -> void:
	_make_saveable({"health": 42}, "Player")
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(save_file, "save_game should return a SaveGameFile")
	assert_eq(save_file.absolute_path, _test_dir.path_join("Slot1.json"))
	assert_true(FileAccess.file_exists(save_file.absolute_path), "Save file should exist on disk")


func test_save_game_populates_save_name_components() -> void:
	var save_file := _manager.save_game(PackedStringArray(["MySave"]))
	assert_not_null(save_file)
	assert_eq(Array(save_file.save_name_components), ["MySave"])


func test_save_game_populates_modified_time() -> void:
	var before_unix := Time.get_unix_time_from_system()
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(save_file)
	# Allow for some clock skew/rounding - modified time should be within a few seconds of now.
	assert_almost_eq(float(save_file.modified_at_unix_time), float(before_unix), 5.0)


func test_save_game_creates_nested_directories_for_multi_component_name() -> void:
	var save_file := _manager.save_game(PackedStringArray(["Game", "Slot1"]))
	assert_not_null(save_file)
	assert_true(FileAccess.file_exists(save_file.absolute_path))
	assert_eq(save_file.absolute_path, _test_dir.path_join("Game/Slot1.json"))
	assert_eq(Array(save_file.save_name_components), ["Game", "Slot1"])
	assert_true(DirAccess.dir_exists_absolute(_test_dir.path_join("Game")),
		"Intermediate directory should be created on disk")


func test_save_game_sanitizes_invalid_characters_without_collapsing_hierarchy() -> void:
	# A slash inside a single component should be replaced rather than turning
	# that component into a pair of subdirectories.
	var save_file := _manager.save_game(PackedStringArray(["Campaign/Alt", "Save1"]))
	assert_not_null(save_file)
	assert_eq(Array(save_file.save_name_components), ["Campaign_Alt", "Save1"])
	assert_true(FileAccess.file_exists(save_file.absolute_path))


func test_save_game_uses_custom_file_extension() -> void:
	_manager.save_file_extension = ".dat"
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(save_file)
	assert_true(save_file.absolute_path.ends_with(".dat"))
	assert_true(FileAccess.file_exists(save_file.absolute_path))


func test_save_game_refuses_overwrite_by_default() -> void:
	var first := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(first)

	var second := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_null(second, "save_game should refuse to overwrite an existing file by default")


func test_save_game_overwrites_when_allowed() -> void:
	var first := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(first)

	var second := _manager.save_game(PackedStringArray(["Slot1"]), true)
	assert_not_null(second, "save_game should overwrite when allow_overwrite is true")
	assert_eq(second.absolute_path, first.absolute_path)


func test_save_game_returns_null_for_empty_components() -> void:
	var save_file := _manager.save_game(PackedStringArray())
	assert_null(save_file)
	assert_push_error("sanitization")


func test_save_game_returns_null_for_components_that_sanitize_to_empty() -> void:
	var save_file := _manager.save_game(PackedStringArray([""]))
	assert_null(save_file)
	assert_push_error("sanitization")


func test_save_game_returns_null_for_non_absolute_directory() -> void:
	_manager.save_games_directory = "relative/dir/"
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_null(save_file)
	assert_push_error("save_games_directory must be an absolute path")


func test_save_game_captures_scene_tree_data() -> void:
	_make_saveable({"health": 99, "name": "Hero"}, "Player")
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(save_file)

	var data := FileAccess.get_file_as_bytes(save_file.absolute_path)
	var parsed := _parse_save_data(data)
	assert_eq(parsed["version"], 1)
	assert_has(parsed, "nodes")
	assert_eq(parsed["nodes"].size(), 1)


# =============================================================================
# load_game
# =============================================================================

func test_load_game_round_trip() -> void:
	var node := _make_saveable({"health": 75}, "Player")
	var save_file := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(save_file)

	# Clear the node's state and reload.
	node.loaded_data = {}
	var error := _manager.load_game(PackedStringArray(["Slot1"]))
	assert_eq(error, OK)
	assert_eq(node.loaded_data["health"], 75)


func test_load_game_round_trip_with_multi_component_name() -> void:
	var node := _make_saveable({"health": 88}, "Hero")
	var save_file := _manager.save_game(PackedStringArray(["Campaign", "Chapter1"]))
	assert_not_null(save_file)

	node.loaded_data = {}
	var error := _manager.load_game(PackedStringArray(["Campaign", "Chapter1"]))
	assert_eq(error, OK)
	assert_eq(node.loaded_data["health"], 88)


func test_load_game_returns_error_for_missing_file() -> void:
	var error := _manager.load_game(PackedStringArray(["DoesNotExist"]))
	assert_ne(error, OK, "Loading a non-existent save should return an error")


func test_load_game_returns_invalid_parameter_for_empty_components() -> void:
	var error := _manager.load_game(PackedStringArray())
	assert_eq(error, ERR_INVALID_PARAMETER)
	assert_push_error("sanitization")


func test_load_game_returns_invalid_parameter_for_non_absolute_directory() -> void:
	_manager.save_games_directory = "relative/dir/"
	var error := _manager.load_game(PackedStringArray(["Slot1"]))
	assert_eq(error, ERR_INVALID_PARAMETER)
	assert_push_error("save_games_directory must be an absolute path")


# =============================================================================
# get_save_file_at_path
# =============================================================================

func test_get_save_file_at_path_returns_file_for_valid_path() -> void:
	var saved := _manager.save_game(PackedStringArray(["Slot1"]))
	assert_not_null(saved)

	var result := _manager.get_save_file_at_path(saved.absolute_path)
	assert_not_null(result)
	assert_eq(result.absolute_path, saved.absolute_path)
	assert_eq(Array(result.save_name_components), ["Slot1"])


func test_get_save_file_at_path_reconstructs_multi_component_save_name() -> void:
	var saved := _manager.save_game(PackedStringArray(["Game", "Slot1"]))
	assert_not_null(saved)

	var result := _manager.get_save_file_at_path(saved.absolute_path)
	assert_not_null(result)
	assert_eq(Array(result.save_name_components), ["Game", "Slot1"])


func test_get_save_file_at_path_returns_null_for_missing_file() -> void:
	var missing := _test_dir.path_join("NotThere.json")
	var result := _manager.get_save_file_at_path(missing)
	assert_null(result)


func test_get_save_file_at_path_returns_null_for_path_outside_directory() -> void:
	var result := _manager.get_save_file_at_path("user://something_else/foo.json")
	assert_null(result)
	assert_push_warning("Save file path must be within save_games_directory")


func test_get_save_file_at_path_returns_null_when_path_equals_directory() -> void:
	# Make sure the directory exists.
	DirAccess.make_dir_recursive_absolute(_test_dir)
	# A trailing-slash mismatch means passing the directory itself falls through
	# the begins_with guard; but FileAccess.file_exists returns false for a dir.
	var result := _manager.get_save_file_at_path(_test_dir)
	assert_null(result)


# =============================================================================
# list_save_files
# =============================================================================

func test_list_save_files_returns_empty_when_directory_missing() -> void:
	# Ensure the configured save directory doesn't exist on disk.
	DirAccess.remove_absolute(_test_dir)
	var files := _manager.list_save_files()
	assert_eq(files.size(), 0)
	assert_push_warning("Could not list save games directory")


func test_list_save_files_lists_all_saves() -> void:
	_manager.save_game(PackedStringArray(["Slot1"]))
	_manager.save_game(PackedStringArray(["Slot2"]))
	_manager.save_game(PackedStringArray(["Slot3"]))

	var files := _manager.list_save_files()
	assert_eq(files.size(), 3)

	var names: Array[String] = []
	for file in files:
		names.append(String(file.save_name_components[0]))
	names.sort()
	assert_eq(names, ["Slot1", "Slot2", "Slot3"])


func test_list_save_files_ignores_files_with_other_extensions() -> void:
	_manager.save_game(PackedStringArray(["Slot1"]))

	# Drop a non-matching file into the save directory.
	var other := FileAccess.open(_test_dir.path_join("notes.txt"), FileAccess.WRITE)
	assert_not_null(other)
	other.store_string("not a save")
	other.close()

	var files := _manager.list_save_files()
	assert_eq(files.size(), 1)
	assert_eq(String(files[0].save_name_components[0]), "Slot1")


func test_list_save_files_recursive_finds_saves_in_subdirectories() -> void:
	_manager.save_game(PackedStringArray(["TopLevel"]))
	_manager.save_game(PackedStringArray(["nested", "Inner"]))

	var recursive_files := _manager.list_save_files("", true)
	assert_eq(recursive_files.size(), 2)

	var non_recursive_files := _manager.list_save_files("", false)
	assert_eq(non_recursive_files.size(), 1)
	assert_eq(String(non_recursive_files[0].save_name_components[0]), "TopLevel")


func test_list_save_files_sorted_respects_non_increasing_order() -> void:
	_manager.save_game(PackedStringArray(["A"]))
	_manager.save_game(PackedStringArray(["B"]))
	_manager.save_game(PackedStringArray(["C"]))

	var files := _manager.list_save_files("", true, true)
	assert_eq(files.size(), 3)
	# Verify the list satisfies the sort invariant (newest first). Using
	# a weaker non-increasing check rather than strict ordering since we
	# can't reliably give save files different modified times without
	# deliberate delays between writes.
	for i in range(1, files.size()):
		assert_true(
			files[i - 1].modified_at_unix_time >= files[i].modified_at_unix_time,
			"Files should be in non-increasing modified time order"
		)


func test_list_save_files_unsorted_still_returns_all_files() -> void:
	_manager.save_game(PackedStringArray(["A"]))
	_manager.save_game(PackedStringArray(["B"]))
	_manager.save_game(PackedStringArray(["C"]))

	var files := _manager.list_save_files("", true, false)
	assert_eq(files.size(), 3)


func test_list_save_files_directory_outside_save_dir_returns_empty() -> void:
	var files := _manager.list_save_files("user://some_other_dir/")
	assert_eq(files.size(), 0)
	assert_push_warning("Directory path must be within save_games_directory")


func test_list_save_files_with_explicit_subdirectory() -> void:
	_manager.save_game(PackedStringArray(["TopLevel"]))
	_manager.save_game(PackedStringArray(["nested", "Inner"]))

	var files := _manager.list_save_files(_test_dir.path_join("nested"))
	assert_eq(files.size(), 1)
	assert_eq(Array(files[0].save_name_components), ["nested", "Inner"])
