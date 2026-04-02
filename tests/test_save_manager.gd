@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
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


func _make_load_data(nodes: Dictionary) -> Dictionary:
	return {"version": 1, "nodes": nodes}


# =============================================================================
# save_scene_tree
# =============================================================================

func test_save_with_no_saveable_nodes() -> void:
	var result := _manager.save_scene_tree()
	assert_eq(result["version"], 1)
	assert_has(result, "nodes")
	assert_eq(result["nodes"].size(), 0)


func test_save_captures_node_data() -> void:
	var data := {"health": 100, "name": "Player"}
	var node := _make_saveable(data, "Player")
	var result := _manager.save_scene_tree()
	var nodes: Dictionary = result["nodes"]
	var path := node.get_path()
	assert_has(nodes, path)
	assert_eq(nodes[path]["health"], 100)
	assert_eq(nodes[path]["name"], "Player")


func test_save_calls_before_save_on_nodes() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.save_scene_tree()
	assert_true(node.before_save_called)


func test_save_calls_after_save_on_nodes() -> void:
	var node := _make_saveable({}, "TestNode")
	_manager.save_scene_tree()
	assert_true(node.after_save_called)


func test_save_emits_before_save_signal() -> void:
	watch_signals(_manager)
	_manager.save_scene_tree()
	assert_signal_emitted(_manager, "before_save")


func test_save_emits_after_save_signal() -> void:
	watch_signals(_manager)
	_manager.save_scene_tree()
	assert_signal_emitted(_manager, "after_save")


func test_save_emits_node_saved_signal() -> void:
	_make_saveable({}, "TestNode")
	watch_signals(_manager)
	_manager.save_scene_tree()
	assert_signal_emitted(_manager, "node_saved")


func test_save_uses_node_path_as_key() -> void:
	var node := _make_saveable({"x": 1}, "MyNode")
	var result := _manager.save_scene_tree()
	assert_has(result["nodes"], node.get_path())


func test_save_uses_save_path_override() -> void:
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node._save_data = {"val": 42}
	node.save_path_override = NodePath("/custom/path")
	add_child_autofree(node)
	node.add_to_group("saveable")

	var result := _manager.save_scene_tree()
	var nodes: Dictionary = result["nodes"]
	assert_has(nodes, NodePath("/custom/path"))
	assert_eq(nodes[NodePath("/custom/path")]["val"], 42)


func test_save_multiple_nodes() -> void:
	_make_saveable({"id": 1}, "Node1")
	_make_saveable({"id": 2}, "Node2")
	var result := _manager.save_scene_tree()
	assert_eq(result["nodes"].size(), 2)


func test_save_includes_scene_file_path() -> void:
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {"key": "val"}
	add_child_autofree(node)
	node.add_to_group("saveable")

	var result := _manager.save_scene_tree()
	var path := node.get_path()
	assert_has(result["nodes"][path], "scene_file_path")
	assert_eq(result["nodes"][path]["scene_file_path"], "res://tests/fixtures/mock_saveable.tscn")


func test_save_skips_nodes_queued_for_deletion() -> void:
	var node := _make_saveable({"key": "val"}, "DyingNode")
	node.queue_free()
	var result := _manager.save_scene_tree()
	assert_eq(result["nodes"].size(), 0)


# =============================================================================
# load_into_scene_tree
# =============================================================================

func test_load_existing_node() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_into_scene_tree(_make_load_data({path: {"health": 50}}))
	assert_eq(node.loaded_data["health"], 50)


func test_load_calls_before_load_on_nodes() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_into_scene_tree(_make_load_data({path: {}}))
	assert_true(node.before_load_called)


func test_load_calls_after_load_on_nodes() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	_manager.load_into_scene_tree(_make_load_data({path: {}}))
	assert_true(node.after_load_called)


func test_load_emits_before_load_signal() -> void:
	watch_signals(_manager)
	_manager.load_into_scene_tree(_make_load_data({}))
	assert_signal_emitted(_manager, "before_load")


func test_load_emits_after_load_signal() -> void:
	watch_signals(_manager)
	_manager.load_into_scene_tree(_make_load_data({}))
	assert_signal_emitted(_manager, "after_load")


func test_load_emits_node_loaded_signal() -> void:
	var node := _make_saveable({}, "Target")
	var path := str(node.get_path())
	watch_signals(_manager)
	_manager.load_into_scene_tree(_make_load_data({path: {}}))
	assert_signal_emitted(_manager, "node_loaded")


func test_load_removes_unsaved_nodes() -> void:
	_make_saveable({}, "Removable")
	watch_signals(_manager)
	_manager.load_into_scene_tree(_make_load_data({}))
	assert_signal_emitted(_manager, "node_removed")


func test_load_skips_node_not_in_saveable_group() -> void:
	var outside_node := MockSaveable.new()
	outside_node.name = "OutsideNode"
	add_child_autofree(outside_node)
	# Deliberately NOT added to the saveable group
	var path := str(outside_node.get_path())
	_manager.load_into_scene_tree(_make_load_data({path: {"should_not": "load"}}))
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
	_manager.load_into_scene_tree(data)

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
	_manager.load_into_scene_tree(data)
	assert_signal_emitted(_manager, "node_created")


func test_load_fails_for_missing_node_without_scene_path() -> void:
	var path := "/root/NonExistent/Orphan"
	_manager.load_into_scene_tree(_make_load_data({path: {"val": 1}}))
	assert_push_error("Cannot instantiate node")


func test_load_with_invalid_version() -> void:
	_manager.load_into_scene_tree({"version": 999, "nodes": {}})
	assert_push_error("Unsupported save data version")


func test_load_with_missing_version() -> void:
	_manager.load_into_scene_tree({})
	assert_push_error("Unsupported save data version")


# =============================================================================
# round-trip
# =============================================================================

func test_round_trip_with_custom_save_load() -> void:
	var original_data := {"health": 100, "position_x": 5.5}
	var node := _make_saveable(original_data, "RoundTrip")
	var saved := _manager.save_scene_tree()
	_manager.load_into_scene_tree(saved)
	assert_eq(node.loaded_data["health"], 100)
	assert_eq(node.loaded_data["position_x"], 5.5)


func test_round_trip_with_scene_instantiated_node() -> void:
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {"coins": 42}
	add_child(node)
	node.add_to_group("saveable")

	var saved := _manager.save_scene_tree()
	var path := node.get_path()

	assert_has(saved["nodes"][path], "scene_file_path")
	assert_eq(saved["nodes"][path]["scene_file_path"], "res://tests/fixtures/mock_saveable.tscn")

	remove_child(node)
	node.free()

	watch_signals(_manager)
	_manager.load_into_scene_tree(saved)

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

	var saved := _manager.save_scene_tree()
	node.health = 100
	node.player_name = ""
	node.score = 0.0

	_manager.load_into_scene_tree(saved)
	assert_eq(node.health, 1)
	assert_eq(node.player_name, "Zara")
	assert_almost_eq(node.score, 77.7, 0.001)


func test_custom_and_default_nodes_coexist() -> void:
	var custom_node := _make_saveable({"key": "custom_val"}, "CustomNode")
	var default_node := _make_default_saveable("DefaultNode")
	default_node.health = 10

	var saved := _manager.save_scene_tree()
	var nodes: Dictionary = saved["nodes"]
	assert_has(nodes, custom_node.get_path())
	assert_has(nodes, default_node.get_path())
	assert_eq(nodes[custom_node.get_path()]["key"], "custom_val")
	assert_eq(nodes[default_node.get_path()]["health"], JSON.from_native(10))
