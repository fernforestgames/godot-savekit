@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const BinarySerializer := preload("res://addons/savekit/binary_serializer.gd")
const BinaryDeserializer := preload("res://addons/savekit/binary_deserializer.gd")
const MockSaveable := preload("res://tests/fixtures/mock_saveable.gd")
const MockSaveableScene := preload("res://tests/fixtures/mock_saveable.tscn")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")
const MockSaveKitResource := preload("res://tests/fixtures/mock_resource.gd")


class MockSaveableWithOverride extends MockSaveable:
	var save_path_override: Variant = null


# Round-trips a serializer's output through a deserializer, so we can verify
# behavior end-to-end without depending on the binary format's internal layout.
func _round_trip_deserializer(serializer: BinarySerializer) -> BinaryDeserializer:
	var save_data := serializer.finalize_save_in_memory()
	var d := BinaryDeserializer.new()
	d.prepare_load_from_memory(save_data)
	d.scene_tree = get_tree()
	d.saveable_node_group = &"saveable"
	return d


# =============================================================================
# encode_var
# =============================================================================

func test_encode_int() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(42), 42)


func test_encode_float() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(3.14), 3.14)


func test_encode_string() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var("hello"), "hello")


func test_encode_bool() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(true), true)
	assert_eq(s.encode_var(false), false)


func test_encode_vector2() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(Vector2(1, 2)), Vector2(1, 2))


func test_encode_color() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(Color.RED), Color.RED)


func test_encode_array() -> void:
	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([1, "two", 3.0])
	assert_true(encoded is Array, "Encoded array should be an Array")
	assert_eq((encoded as Array).size(), 3, "Encoded array should have 3 elements")


func test_encode_dictionary() -> void:
	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var({"key": "value"})
	assert_true(encoded is Dictionary, "Encoded dictionary should be a Dictionary")


func test_encode_null() -> void:
	var s := BinarySerializer.new()
	assert_eq(s.encode_var(null), null)


func test_encode_callable_returns_null() -> void:
	var s := BinarySerializer.new()
	assert_null(s.encode_var(Callable()))
	assert_push_error("Cannot serialize callable")


func test_encode_node_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	assert_not_null(s.encode_var(node))


func test_encode_resource_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var script: Script = MockSaveable
	assert_not_null(s.encode_var(script))


func test_encode_save_kit_resource_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var resource := MockSaveKitResource.new()
	resource.item_name = "Sword"
	assert_not_null(s.encode_var(resource))


# =============================================================================
# encode_resource_reference
# =============================================================================

func test_encode_resource_reference_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var script: Script = MockSaveable
	assert_not_null(s.encode_resource_reference(script))


func test_encode_resource_reference_without_path_returns_null() -> void:
	var s := BinarySerializer.new()
	var resource := Resource.new()
	assert_null(s.encode_resource_reference(resource))


# =============================================================================
# encode_node_reference
# =============================================================================

func test_encode_node_reference_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "RefNode"
	add_child_autofree(node)
	assert_not_null(s.encode_node_reference(node))


func test_encode_node_reference_uses_save_path_override() -> void:
	# Two nodes with the same name but different override paths should produce
	# distinct encoded references — verifying the override flows through
	# without inspecting the buffer's internal layout.
	var s := BinarySerializer.new()
	var node_a := MockSaveableWithOverride.new()
	node_a.name = "Same"
	node_a.save_path_override = NodePath("/override/a")
	add_child_autofree(node_a)
	var node_b := MockSaveableWithOverride.new()
	node_b.name = "Same"
	node_b.save_path_override = NodePath("/override/b")
	add_child_autofree(node_b)
	assert_ne(s.encode_node_reference(node_a), s.encode_node_reference(node_b))


# =============================================================================
# save_node_to_dict
# =============================================================================

func test_save_node_to_dict_with_custom_method() -> void:
	var s := BinarySerializer.new()
	var node := MockSaveable.new()
	node.name = "Custom"
	node._save_data = {"key": "value"}
	add_child_autofree(node)
	var result := s.save_node_to_dict(node)
	assert_eq(result["key"], "value")


func test_save_node_to_dict_with_default_method() -> void:
	var s := BinarySerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Default"
	node.health = 50
	add_child_autofree(node)
	var result := s.save_node_to_dict(node)
	assert_has(result, "health")
	assert_eq(result["health"], 50)


# =============================================================================
# default_save_to_dict
# =============================================================================

func test_default_save_captures_changed_properties() -> void:
	var s := BinarySerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	node.health = 50
	node.player_name = "Bob"
	add_child_autofree(node)
	var result := s.default_save_to_dict(node)
	assert_has(result, "health")
	assert_has(result, "player_name")
	assert_eq(result["health"], 50)
	assert_eq(result["player_name"], "Bob")


func test_default_save_omits_properties_at_defaults() -> void:
	var s := BinarySerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	var result := s.default_save_to_dict(node)
	assert_does_not_have(result, "health")
	assert_does_not_have(result, "score")
	assert_does_not_have(result, "player_name")


func test_default_save_with_only_properties_filter() -> void:
	var s := BinarySerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	node.health = 50
	node.player_name = "Eve"
	node.score = 3.14
	add_child_autofree(node)
	var result := s.default_save_to_dict(node, PackedStringArray(["health", "score"]))
	assert_has(result, "health")
	assert_has(result, "score")
	assert_does_not_have(result, "player_name", "player_name not in allowlist")


# =============================================================================
# save_path_for_node
# =============================================================================

func test_save_path_uses_node_path_by_default() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	assert_eq(s.save_path_for_node(node), node.get_path())


func test_save_path_uses_override() -> void:
	var s := BinarySerializer.new()
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node.save_path_override = NodePath("/custom/path")
	add_child_autofree(node)
	assert_eq(s.save_path_for_node(node), NodePath("/custom/path"))


# =============================================================================
# save_resource
# =============================================================================

func test_save_resource_returns_non_null() -> void:
	var s := BinarySerializer.new()
	var resource := MockSaveKitResource.new()
	assert_not_null(s.save_resource(resource))


func test_save_resource_deduplicates() -> void:
	var s := BinarySerializer.new()
	var resource := MockSaveKitResource.new()
	var ref1: Variant = s.save_resource(resource)
	var ref2: Variant = s.save_resource(resource)
	assert_eq(ref1, ref2, "Same resource should produce the same reference")


# =============================================================================
# finalize_save_in_memory
# =============================================================================

func test_finalize_returns_non_empty_buffer() -> void:
	var s := BinarySerializer.new()
	var buffer := s.finalize_save_in_memory()
	assert_true(buffer is PackedByteArray, "Finalized save should be a PackedByteArray")
	assert_true(buffer.size() > 0, "Finalized save should not be empty")


# =============================================================================
# save_node — verified via round-trip rather than format inspection
# =============================================================================

func test_save_node_persists_data_through_round_trip() -> void:
	var s := BinarySerializer.new()
	var node := MockSaveable.new()
	node.name = "RoundTripNode"
	node._save_data = {"key": "val"}
	add_child_autofree(node)
	node.add_to_group("saveable")
	s.save_node(node)

	# Reset state so we can verify load actually replaced it
	node.loaded_data = {}
	var d := _round_trip_deserializer(s)
	d.load_node()
	assert_eq(node.loaded_data["key"], "val")


func test_save_node_with_scene_file_path_round_trips() -> void:
	var s := BinarySerializer.new()
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {}
	add_child_autofree(node)
	node.add_to_group("saveable")
	var saved_path := node.get_path()
	s.save_node(node)

	# Remove the node so the deserializer must re-instantiate it from the
	# saved scene_file_path.
	var parent := node.get_parent()
	parent.remove_child(node)
	node.queue_free()

	var d := _round_trip_deserializer(s)
	var loaded := d.load_node()
	assert_not_null(loaded)
	assert_eq(loaded.scene_file_path, "res://tests/fixtures/mock_saveable.tscn")
	assert_eq(loaded.get_path(), saved_path)


# =============================================================================
# encode_var — nested objects in containers
# =============================================================================

func test_encode_node_in_array() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	var result: Array = s.encode_var([node])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "Node inside array should not be encoded as null")


func test_encode_node_in_dictionary() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	var result: Dictionary = s.encode_var({"my_node": node})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "Node inside dict should not be encoded as null")


func test_encode_save_kit_resource_in_array() -> void:
	var s := BinarySerializer.new()
	var resource := MockSaveKitResource.new()
	resource.item_name = "Gem"
	var result: Array = s.encode_var([resource])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "SaveKitResource inside array should not be encoded as null")


func test_encode_save_kit_resource_in_dictionary() -> void:
	var s := BinarySerializer.new()
	var resource := MockSaveKitResource.new()
	resource.item_name = "Gem"
	var result: Dictionary = s.encode_var({"item": resource})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "SaveKitResource inside dict should not be encoded as null")


func test_encode_resource_reference_in_array() -> void:
	var s := BinarySerializer.new()
	var script: Script = MockSaveable
	var result: Array = s.encode_var([script])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "Resource inside array should not be encoded as null")


func test_encode_resource_reference_in_dictionary() -> void:
	var s := BinarySerializer.new()
	var script: Script = MockSaveable
	var result: Dictionary = s.encode_var({"script": script})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "Resource inside dict should not be encoded as null")


func test_encode_mixed_objects_in_array() -> void:
	var s := BinarySerializer.new()
	var node := Node.new()
	node.name = "MixNode"
	add_child_autofree(node)
	var resource := MockSaveKitResource.new()
	resource.item_name = "Bow"
	var script: Script = MockSaveable
	var result: Array = s.encode_var([node, resource, script, 42, "plain"])
	assert_eq(result.size(), 5, "Mixed array should preserve all elements")
	assert_not_null(result[0], "Node in mixed array should not be encoded as null")
	assert_not_null(result[1], "SaveKitResource in mixed array should not be encoded as null")
	assert_not_null(result[2], "Resource in mixed array should not be encoded as null")
