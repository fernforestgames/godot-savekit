@warning_ignore_start("unsafe_call_argument")
extends GutTest

const SaveManager := preload("res://addons/savekit/save_manager.gd")
const MockSaveable := preload("res://tests/fixtures/mock_saveable.gd")
const MockSaveableScene := preload("res://tests/fixtures/mock_saveable.tscn")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")

class MockSaveableWithOverride extends MockSaveable:
	var save_path_override: Variant = null


var _manager: SaveManager


func before_each() -> void:
	_manager = SaveManager.new()
	add_child_autofree(_manager)


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


# =============================================================================
# deserialize_sorted_node_paths (static)
# =============================================================================

func test_sorted_paths_sorts_by_depth() -> void:
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: 1,
		"/root/A/B/C": {},
		"/root/A": {},
		"/root/A/B": {},
	}
	var paths: Array[NodePath] = SaveManager.deserialize_sorted_node_paths(data)
	assert_eq(paths.size(), 3)
	assert_eq(str(paths[0]), "/root/A")
	assert_eq(str(paths[1]), "/root/A/B")
	assert_eq(str(paths[2]), "/root/A/B/C")


func test_sorted_paths_with_only_version_key() -> void:
	var data := {SaveManager._SERIALIZATION_VERSION_KEY: 1}
	var paths: Array[NodePath] = SaveManager.deserialize_sorted_node_paths(data)
	assert_eq(paths.size(), 0)


# =============================================================================
# safe_load_resource (static)
# =============================================================================

func test_safe_load_rejects_relative_path() -> void:
	var result: Resource = SaveManager.safe_load_resource("some/relative/path.tscn", "tscn")
	assert_null(result)


func test_safe_load_rejects_non_res_path() -> void:
	var result: Resource = SaveManager.safe_load_resource("user://saves/file.tscn", "tscn")
	assert_null(result)


func test_safe_load_rejects_wrong_extension() -> void:
	var result: Resource = SaveManager.safe_load_resource("res://scenes/file.tres", "tscn")
	assert_null(result)


# =============================================================================
# serialize_tree
# =============================================================================

func test_serialize_with_no_saveable_nodes() -> void:
	var result: Dictionary = _manager.serialize_tree()
	assert_eq(result.size(), 1, "Should only contain the version key")


func test_serialize_captures_node_data() -> void:
	var data := {"health": 100, "name": "Player"}
	var node := _make_saveable(data, "Player")
	var result: Dictionary = _manager.serialize_tree()
	var node_path := str(node.get_path())
	assert_has(result, node_path)
	assert_eq(result[node_path]["health"], 100)
	assert_eq(result[node_path]["name"], "Player")


func test_serialize_calls_before_save() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.serialize_tree()
	assert_true(node.before_save_called)


func test_serialize_calls_after_save() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.serialize_tree()
	assert_true(node.after_save_called)


func test_serialize_emits_saved_node_signal() -> void:
	_make_saveable({}, "TestNode")
	watch_signals(_manager)
	_manager.serialize_tree()
	assert_signal_emitted(_manager, "saved_node")


func test_serialize_uses_node_path_as_key() -> void:
	var node := _make_saveable({"x": 1}, "MyNode")
	var result: Dictionary = _manager.serialize_tree()
	var node_path := str(node.get_path())
	assert_has(result, node_path)


func test_serialize_uses_save_path_override() -> void:
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node._save_data = {"val": 42}
	node.save_path_override = "/custom/path"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var result: Dictionary = _manager.serialize_tree()
	assert_has(result, "/custom/path")
	assert_eq(result["/custom/path"]["val"], 42)


func test_serialize_multiple_nodes() -> void:
	_make_saveable({"id": 1}, "Node1")
	_make_saveable({"id": 2}, "Node2")
	var result: Dictionary = _manager.serialize_tree()
	assert_eq(result.size(), 3, "version key + 2 nodes")


# =============================================================================
# deserialize_tree
# =============================================================================

func test_deserialize_rejects_wrong_version() -> void:
	var data := {SaveManager._SERIALIZATION_VERSION_KEY: 999}
	var err: Error = _manager.deserialize_tree(data)
	assert_eq(err, ERR_INVALID_DATA)
	assert_push_error("Unsupported serialization version")


func test_deserialize_rejects_missing_version() -> void:
	var data := {}
	var err: Error = _manager.deserialize_tree(data)
	assert_eq(err, ERR_INVALID_DATA)
	assert_push_error("Unsupported serialization version")


func test_deserialize_loads_existing_node() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {"health": 50},
	}
	var err: Error = _manager.deserialize_tree(data)
	assert_eq(err, OK)
	assert_eq(node.loaded_data["health"], 50)


func test_deserialize_calls_before_load() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {},
	}
	_manager.deserialize_tree(data)
	assert_true(node.before_load_called)


func test_deserialize_calls_after_load() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {},
	}
	_manager.deserialize_tree(data)
	assert_true(node.after_load_called)


func test_deserialize_emits_loaded_node_signal() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {},
	}
	watch_signals(_manager)
	_manager.deserialize_tree(data)
	assert_signal_emitted(_manager, "loaded_node")


func test_deserialize_removes_unsaved_nodes() -> void:
	_make_saveable({}, "Removable")
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
	}
	watch_signals(_manager)
	_manager.deserialize_tree(data)
	assert_signal_emitted(_manager, "removed_unsaved_node")


func test_deserialize_returns_ok_on_success() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {"key": "value"},
	}
	assert_eq(_manager.deserialize_tree(data), OK)


func test_deserialize_skips_node_not_in_saveable_group() -> void:
	var outside_node := MockSaveable.new()
	outside_node.name = "OutsideNode"
	add_child_autofree(outside_node)
	# Deliberately NOT added to the saveable group
	var node_path := str(outside_node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {"should_not": "load"},
	}
	_manager.deserialize_tree(data)
	assert_eq(outside_node.loaded_data.size(), 0, "Node outside group should not be loaded")


func test_deserialize_strips_scene_file_path_from_node_data() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {
			"health": 10,
			SaveManager._SCENE_FILE_PATH_KEY: "res://scenes/test.tscn",
		},
	}
	_manager.deserialize_tree(data)
	assert_false(
		node.loaded_data.has(SaveManager._SCENE_FILE_PATH_KEY),
		"Scene file path key should be stripped before passing to load_from_dict"
	)
	assert_eq(node.loaded_data["health"], 10)


func test_deserialize_does_not_mutate_input_dict() -> void:
	var node := _make_saveable({}, "Target")
	var node_path := str(node.get_path())
	var node_dict := {
		"health": 10,
		SaveManager._SCENE_FILE_PATH_KEY: "res://scenes/test.tscn",
	}
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: node_dict,
	}
	_manager.deserialize_tree(data)
	assert_has(node_dict, SaveManager._SCENE_FILE_PATH_KEY,
		"Original dict should not be mutated")


# =============================================================================
# deserialize_tree: PackedScene instantiation
# =============================================================================

func test_deserialize_instantiates_missing_node_from_scene() -> void:
	# The node does NOT exist in the tree — deserialize should instantiate it
	# from the scene file path embedded in the save data.
	var parent := Node.new()
	parent.name = "SceneParent"
	add_child_autofree(parent)

	var node_path := str(parent.get_path()) + "/MockSaveable"
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {
			"score": 99,
			SaveManager._SCENE_FILE_PATH_KEY: "res://tests/fixtures/mock_saveable.tscn",
		},
	}

	watch_signals(_manager)
	var err: Error = _manager.deserialize_tree(data)
	assert_eq(err, OK)

	var created_node: MockSaveable = parent.get_node_or_null("MockSaveable")
	assert_not_null(created_node, "Node should have been instantiated from PackedScene")
	assert_true(created_node.is_in_group("saveable"), "Instantiated node should be added to saveable group")
	assert_eq(created_node.loaded_data["score"], 99)
	assert_signal_emitted(_manager, "loaded_node")


func test_deserialize_fails_for_missing_node_without_scene_path() -> void:
	var node_path := "/root/NonExistent/Orphan"
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {"val": 1},
	}
	_manager.deserialize_tree(data)
	assert_push_error("Cannot instantiate node")


# =============================================================================
# round-trip
# =============================================================================

func test_serialize_then_deserialize_round_trip() -> void:
	var original_data := {"health": 100, "position_x": 5.5}
	var node := _make_saveable(original_data, "RoundTrip")
	var saved: Dictionary = _manager.serialize_tree()
	var err: Error = _manager.deserialize_tree(saved)
	assert_eq(err, OK)
	assert_eq(node.loaded_data["health"], 100)
	assert_eq(node.loaded_data["position_x"], 5.5)


func test_scene_instantiated_node_round_trip() -> void:
	# Instantiate a node from a PackedScene (gives it a scene_file_path),
	# serialize it, remove it, then deserialize — it should be re-instantiated.
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {"coins": 42}
	add_child(node)
	node.add_to_group("saveable")

	var saved: Dictionary = _manager.serialize_tree()
	var node_path := str(node.get_path())

	# Verify the scene file path was captured in the serialized data
	assert_has(saved[node_path], SaveManager._SCENE_FILE_PATH_KEY)
	assert_eq(saved[node_path][SaveManager._SCENE_FILE_PATH_KEY], "res://tests/fixtures/mock_saveable.tscn")

	# Remove the node so deserialize must re-instantiate it from the scene
	remove_child(node)
	node.free()

	watch_signals(_manager)
	var err: Error = _manager.deserialize_tree(saved)
	assert_eq(err, OK)

	var restored: MockSaveable = get_node_or_null("SceneNode")
	assert_not_null(restored, "Node should have been re-instantiated from its scene")
	autoqfree(restored)
	assert_eq(restored.loaded_data["coins"], 42)
	assert_true(restored.is_in_group("saveable"))
	assert_signal_emitted(_manager, "loaded_node")


# =============================================================================
# default_save_to_dict / default_load_from_dict (reflection-based fallback)
# =============================================================================

func test_default_save_captures_changed_properties() -> void:
	var node := _make_default_saveable("DefaultNode")
	node.health = 50
	node.player_name = "Bob"

	var result: Dictionary = _manager.serialize_tree()
	var node_path := str(node.get_path())
	assert_has(result, node_path)
	assert_eq(result[node_path]["health"], JSON.from_native(50))
	assert_eq(result[node_path]["player_name"], JSON.from_native("Bob"))


func test_default_save_omits_properties_at_defaults() -> void:
	var node := _make_default_saveable("AllDefaults")
	# Leave all properties at their defaults

	var result: Dictionary = _manager.serialize_tree()
	var node_path := str(node.get_path())
	assert_has(result, node_path)
	assert_does_not_have(result[node_path], "health", "default value should not be serialized")
	assert_does_not_have(result[node_path], "score", "default value should not be serialized")


func test_default_load_sets_properties_on_node() -> void:
	var node := _make_default_saveable("LoadTarget")
	var node_path := str(node.get_path())
	var data := {
		SaveManager._SERIALIZATION_VERSION_KEY: SaveManager._SERIALIZATION_VERSION,
		node_path: {
			"health": JSON.from_native(25),
			"player_name": JSON.from_native("Carol"),
		},
	}
	var err: Error = _manager.deserialize_tree(data)
	assert_eq(err, OK)
	assert_eq(node.health, 25)
	assert_eq(node.player_name, "Carol")
	assert_eq(node.score, 0.0, "Untouched property stays at default")


func test_default_round_trip() -> void:
	var node := _make_default_saveable("RoundTripper")
	node.health = 1
	node.player_name = "Zara"
	node.score = 77.7

	var saved: Dictionary = _manager.serialize_tree()
	# Reset properties before loading
	node.health = 100
	node.player_name = ""
	node.score = 0.0

	var err: Error = _manager.deserialize_tree(saved)
	assert_eq(err, OK)
	assert_eq(node.health, 1)
	assert_eq(node.player_name, "Zara")
	assert_almost_eq(node.score, 77.7, 0.001)


func test_default_and_custom_nodes_coexist() -> void:
	var custom_node := _make_saveable({"key": "custom_val"}, "CustomNode")
	var default_node := _make_default_saveable("DefaultNode")
	default_node.health = 10

	var saved: Dictionary = _manager.serialize_tree()
	assert_has(saved, str(custom_node.get_path()))
	assert_has(saved, str(default_node.get_path()))
	assert_eq(saved[str(custom_node.get_path())]["key"], "custom_val")
	assert_eq(saved[str(default_node.get_path())]["health"], JSON.from_native(10))
