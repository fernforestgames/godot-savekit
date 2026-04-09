@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const JSONSerializer := preload("res://addons/savekit/json_serializer.gd")
const MockSaveable := preload("res://tests/fixtures/mock_saveable.gd")
const MockSaveableScene := preload("res://tests/fixtures/mock_saveable.tscn")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")
const MockSaveableResource := preload("res://tests/fixtures/mock_saveable_resource.gd")


class MockSaveableWithOverride extends MockSaveable:
	var save_path_override: Variant = null


func _parse_finalized(s: JSONSerializer) -> Dictionary:
	return JSON.parse_string(s.finalize_save_in_memory().get_string_from_utf8())



# =============================================================================
# encode_var
# =============================================================================

func test_encode_int() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(42), JSON.from_native(42))


func test_encode_float() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(3.14), JSON.from_native(3.14))


func test_encode_string() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var("hello"), JSON.from_native("hello"))


func test_encode_bool() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(true), JSON.from_native(true))
	assert_eq(s.encode_var(false), JSON.from_native(false))


func test_encode_vector2() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(Vector2(1, 2)), JSON.from_native(Vector2(1, 2)))


func test_encode_color() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(Color.RED), JSON.from_native(Color.RED))


func test_encode_array() -> void:
	var s := JSONSerializer.new()
	var encoded: Variant = s.encode_var([1, "two", 3.0])
	assert_true(encoded is Array, "Encoded array should be an Array")
	assert_eq((encoded as Array).size(), 3, "Encoded array should have 3 elements")


func test_encode_dictionary() -> void:
	var s := JSONSerializer.new()
	var encoded: Variant = s.encode_var({"key": "value"})
	assert_true(encoded is Dictionary, "Encoded dictionary should be a Dictionary")


func test_encode_null() -> void:
	var s := JSONSerializer.new()
	assert_eq(s.encode_var(null), JSON.from_native(null))


func test_encode_rid_returns_null() -> void:
	var s := JSONSerializer.new()
	assert_null(s.encode_var(RID()))


func test_encode_node_returns_reference_dict() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	var result: Dictionary = s.encode_var(node)
	assert_has(result, "node")
	assert_eq(result["node"], str(node.get_path()))


func test_encode_resource_returns_reference_dict() -> void:
	var s := JSONSerializer.new()
	var script: Script = MockSaveable
	var result: Dictionary = s.encode_var(script)
	assert_has(result, "path")


func test_encode_saveable_resource_returns_id_reference() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Sword"
	var result: Dictionary = s.encode_var(resource)
	assert_has(result, "res")


# =============================================================================
# encode_resource_reference
# =============================================================================

func test_encode_resource_reference_includes_path() -> void:
	var s := JSONSerializer.new()
	var script: Script = MockSaveable
	var result := s.encode_resource_reference(script) as Dictionary
	assert_has(result, "path")
	assert_eq(result["path"], "res://tests/fixtures/mock_saveable.gd")


func test_encode_resource_reference_without_path_returns_null() -> void:
	var s := JSONSerializer.new()
	var resource := Resource.new()
	assert_null(s.encode_resource_reference(resource))


# =============================================================================
# encode_node_reference
# =============================================================================

func test_encode_node_reference_uses_node_path() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "RefNode"
	add_child_autofree(node)
	var result := s.encode_node_reference(node) as Dictionary
	assert_eq(result["node"], str(node.get_path()))


func test_encode_node_reference_uses_save_path_override() -> void:
	var s := JSONSerializer.new()
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node.save_path_override = NodePath("/override/path")
	add_child_autofree(node)
	var result := s.encode_node_reference(node) as Dictionary
	assert_eq(result["node"], "/override/path")


# =============================================================================
# save_node_to_dict
# =============================================================================

func test_save_node_to_dict_with_custom_method() -> void:
	var s := JSONSerializer.new()
	var node := MockSaveable.new()
	node.name = "Custom"
	node._save_data = {"key": "value"}
	add_child_autofree(node)
	var result := s.save_node_to_dict(node)
	assert_eq(result["key"], "value")


func test_save_node_to_dict_with_default_method() -> void:
	var s := JSONSerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Default"
	node.health = 50
	add_child_autofree(node)
	var result := s.save_node_to_dict(node)
	assert_has(result, "health")
	assert_eq(result["health"], JSON.from_native(50))


# =============================================================================
# default_save_to_dict
# =============================================================================

func test_default_save_captures_changed_properties() -> void:
	var s := JSONSerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	node.health = 50
	node.player_name = "Bob"
	add_child_autofree(node)
	var result := s.default_save_to_dict(node)
	assert_has(result, "health")
	assert_has(result, "player_name")
	assert_eq(result["health"], JSON.from_native(50))
	assert_eq(result["player_name"], JSON.from_native("Bob"))


func test_default_save_omits_properties_at_defaults() -> void:
	var s := JSONSerializer.new()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	var result := s.default_save_to_dict(node)
	assert_does_not_have(result, "health")
	assert_does_not_have(result, "score")
	assert_does_not_have(result, "player_name")


func test_default_save_with_only_properties_filter() -> void:
	var s := JSONSerializer.new()
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
# save_node
# =============================================================================

func test_save_node_stores_data() -> void:
	var s := JSONSerializer.new()
	var node := MockSaveable.new()
	node.name = "TestNode"
	node._save_data = {"key": "val"}
	add_child_autofree(node)
	s.save_node(node)
	var result := _parse_finalized(s)
	var path := str(node.get_path())
	assert_has(result["nodes"], path)
	assert_eq(result["nodes"][path]["key"], "val")


func test_save_node_includes_scene_file_path() -> void:
	var s := JSONSerializer.new()
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "SceneNode"
	node._save_data = {}
	add_child_autofree(node)
	s.save_node(node)
	var result := _parse_finalized(s)
	var path := str(node.get_path())
	assert_has(result["nodes"][path], "scene_file_path")
	assert_eq(result["nodes"][path]["scene_file_path"], "res://tests/fixtures/mock_saveable.tscn")


func test_save_node_without_scene_file_path() -> void:
	var s := JSONSerializer.new()
	var node := MockSaveable.new()
	node.name = "NoScene"
	node._save_data = {"x": 1}
	add_child_autofree(node)
	s.save_node(node)
	var result := _parse_finalized(s)
	var path := str(node.get_path())
	assert_does_not_have(result["nodes"][path], "scene_file_path")


# =============================================================================
# save_path_for_node
# =============================================================================

func test_save_path_uses_node_path_by_default() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	assert_eq(s.save_path_for_node(node), node.get_path())


func test_save_path_uses_override() -> void:
	var s := JSONSerializer.new()
	var node := MockSaveableWithOverride.new()
	node.name = "OverrideNode"
	node.save_path_override = NodePath("/custom/path")
	add_child_autofree(node)
	assert_eq(s.save_path_for_node(node), NodePath("/custom/path"))


# =============================================================================
# finalize_save_in_memory
# =============================================================================

func test_finalize_returns_version_and_nodes() -> void:
	var s := JSONSerializer.new()
	var result := _parse_finalized(s)
	assert_has(result, "version")
	assert_eq(result["version"], 1)
	assert_has(result, "nodes")


func test_finalize_omits_resources_when_none_saved() -> void:
	var s := JSONSerializer.new()
	var result := _parse_finalized(s)
	assert_does_not_have(result, "resources")


func test_finalize_includes_resources_when_present() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Sword"
	s.save_resource(resource)
	var result := _parse_finalized(s)
	assert_has(result, "resources")
	assert_true((result["resources"] as Dictionary).size() > 0)


# =============================================================================
# save_resource
# =============================================================================

func test_save_resource_returns_reference_with_id() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	var ref: Dictionary = s.save_resource(resource)
	assert_has(ref, "res")


func test_save_resource_deduplicates() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	var ref1: Dictionary = s.save_resource(resource)
	var ref2: Dictionary = s.save_resource(resource)
	assert_eq(ref1["res"], ref2["res"], "Same resource should produce the same ID")


# =============================================================================
# encode_var — nested objects in containers
# =============================================================================

func test_encode_node_in_array() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	var result: Array = s.encode_var([node])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "Node inside array should not be encoded as null")


func test_encode_node_in_dictionary() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	var result: Dictionary = s.encode_var({"my_node": node})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "Node inside dict should not be encoded as null")


func test_encode_saveable_resource_in_array() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Gem"
	var result: Array = s.encode_var([resource])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "SaveableResource inside array should not be encoded as null")


func test_encode_saveable_resource_in_dictionary() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Gem"
	var result: Dictionary = s.encode_var({"item": resource})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "SaveableResource inside dict should not be encoded as null")


func test_encode_resource_reference_in_array() -> void:
	var s := JSONSerializer.new()
	var script: Script = MockSaveable
	var result: Array = s.encode_var([script])
	assert_eq(result.size(), 1)
	assert_not_null(result[0], "Resource inside array should not be encoded as null")


func test_encode_resource_reference_in_dictionary() -> void:
	var s := JSONSerializer.new()
	var script: Script = MockSaveable
	var result: Dictionary = s.encode_var({"script": script})
	assert_eq(result.size(), 1, "Encoded dict should have one entry")
	for value: Variant in result.values():
		assert_not_null(value, "Resource inside dict should not be encoded as null")


func test_encode_node_in_nested_containers() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "DeepNested"
	add_child_autofree(node)
	var result: Variant = s.encode_var({"list": [{"target": node}]})
	assert_not_null(result, "Nested containers with a node should not encode as null")
	var json_string := JSON.stringify(result, "", false)
	assert_true(json_string.length() > 0, "Nested containers with a node should produce valid JSON")


func test_encode_saveable_resource_in_nested_containers() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Ring"
	var result: Variant = s.encode_var([[{"item": resource}]])
	assert_not_null(result, "Nested containers with a resource should not encode as null")
	var json_string := JSON.stringify(result, "", false)
	assert_true(json_string.length() > 0, "Nested containers with a resource should produce valid JSON")


func test_encode_mixed_objects_in_array() -> void:
	var s := JSONSerializer.new()
	var node := Node.new()
	node.name = "MixNode"
	add_child_autofree(node)
	var resource := MockSaveableResource.new()
	resource.item_name = "Bow"
	var script: Script = MockSaveable
	var result: Array = s.encode_var([node, resource, script, 42, "plain"])
	assert_eq(result.size(), 5, "Mixed array should preserve all elements")
	assert_not_null(result[0], "Node in mixed array should not be encoded as null")
	assert_not_null(result[1], "SaveableResource in mixed array should not be encoded as null")
	assert_not_null(result[2], "Resource in mixed array should not be encoded as null")
