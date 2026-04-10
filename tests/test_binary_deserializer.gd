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


# Builds a deserializer from the given (optional) populated serializer. When
# none is provided, the deserializer is loaded from a fresh, empty save.
func _make_deserializer(serializer: BinarySerializer = null) -> BinaryDeserializer:
	var s := serializer if serializer else BinarySerializer.new()
	var d := BinaryDeserializer.new()
	d.prepare_load_from_memory(s.finalize_save_in_memory())
	d.scene_tree = get_tree()
	d.saveable_node_group = &"saveable"
	return d


# =============================================================================
# prepare_load_from_memory
# =============================================================================

func test_prepare_with_valid_empty_data() -> void:
	var s := BinarySerializer.new()
	var d := BinaryDeserializer.new()
	var ok := d.prepare_load_from_memory(s.finalize_save_in_memory())
	assert_true(ok)
	assert_true(d.is_finished())


func test_prepare_with_too_small_data() -> void:
	var d := BinaryDeserializer.new()
	var bad_data: PackedByteArray
	bad_data.resize(2)
	var ok := d.prepare_load_from_memory(bad_data)
	assert_false(ok)
	assert_push_error("too small")


func test_prepare_with_invalid_version() -> void:
	# A buffer of all zeros decodes a version of 0, which doesn't match the
	# current serialization version. This avoids depending on the specific
	# byte offset of the version field.
	var d := BinaryDeserializer.new()
	var bad_data: PackedByteArray
	bad_data.resize(16)
	var ok := d.prepare_load_from_memory(bad_data)
	assert_false(ok)
	assert_push_error("Unsupported save data version")


func test_prepare_with_nodes() -> void:
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var s := BinarySerializer.new()
	s.save_node(node)
	var d := _make_deserializer(s)
	assert_false(d.is_finished())


# =============================================================================
# decode_var (round-trip via the serializer)
# =============================================================================

func test_decode_int() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var(42), TYPE_INT), 42)


func test_decode_float() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var(3.14), TYPE_FLOAT), 3.14)


func test_decode_string() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var("hello"), TYPE_STRING), "hello")


func test_decode_bool() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var(true), TYPE_BOOL), true)
	assert_eq(d.decode_var(s.encode_var(false), TYPE_BOOL), false)


func test_decode_vector2() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var(Vector2(1, 2)), TYPE_VECTOR2), Vector2(1, 2))


func test_decode_color() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	assert_eq(d.decode_var(s.encode_var(Color.RED), TYPE_COLOR), Color.RED)


# =============================================================================
# is_finished / get_remaining_node_count
# =============================================================================

func test_is_finished_with_empty_data() -> void:
	var d := _make_deserializer()
	assert_true(d.is_finished())
	assert_eq(d.get_remaining_node_count(), 0)


func test_remaining_count_matches_nodes() -> void:
	var node1 := Node.new()
	node1.name = "Node1"
	add_child_autofree(node1)
	node1.add_to_group("saveable")

	var node2 := Node.new()
	node2.name = "Node2"
	add_child_autofree(node2)
	node2.add_to_group("saveable")

	var s := BinarySerializer.new()
	s.save_node(node1)
	s.save_node(node2)
	var d := _make_deserializer(s)
	assert_eq(d.get_remaining_node_count(), 2)
	assert_false(d.is_finished())


func test_is_finished_after_loading_all() -> void:
	var node := MockSaveable.new()
	node.name = "TestNode"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var s := BinarySerializer.new()
	s.save_node(node)
	var d := _make_deserializer(s)
	d.load_node()
	assert_true(d.is_finished())
	assert_eq(d.get_remaining_node_count(), 0)


# =============================================================================
# load_node
# =============================================================================

func test_load_node_returns_node() -> void:
	var node := MockSaveable.new()
	node.name = "Target"
	add_child_autofree(node)
	node.add_to_group("saveable")
	node._save_data = {"key": "val"}

	var s := BinarySerializer.new()
	s.save_node(node)

	node._save_data = {}
	node.loaded_data = {}

	var d := _make_deserializer(s)
	var loaded := d.load_node()
	assert_eq(loaded, node)
	assert_eq(node.loaded_data["key"], "val")


func test_load_node_loads_parents_before_children() -> void:
	var parent := MockSaveable.new()
	parent.name = "Parent"
	add_child_autofree(parent)
	parent.add_to_group("saveable")

	var child := MockSaveable.new()
	child.name = "Child"
	parent.add_child(child)
	child.add_to_group("saveable")

	var s := BinarySerializer.new()
	# Save in opposite order to verify the deserializer sorts them.
	s.save_node(child)
	s.save_node(parent)

	var d := _make_deserializer(s)
	var first := d.load_node()
	var second := d.load_node()
	assert_eq(first, parent, "Parent should be loaded before child")
	assert_eq(second, child, "Child should be loaded after parent")


func test_load_node_strips_scene_file_path() -> void:
	# When the saved node has a scene_file_path, it should be consumed by the
	# deserializer (used for instantiation) and not leak into load_from_dict.
	var node: MockSaveable = MockSaveableScene.instantiate()
	node.name = "Target"
	add_child_autofree(node)
	node.add_to_group("saveable")
	node._save_data = {"health": 10}

	var s := BinarySerializer.new()
	s.save_node(node)

	node.loaded_data = {}
	var d := _make_deserializer(s)
	d.load_node()
	assert_false(node.loaded_data.has("scene_file_path"),
		"scene_file_path should be stripped before passing to load_from_dict")
	assert_eq(node.loaded_data["health"], 10)


func test_load_node_with_default_load() -> void:
	var node := MockDefaultSaveable.new()
	node.name = "DefaultNode"
	add_child_autofree(node)
	node.add_to_group("saveable")
	node.health = 25
	node.player_name = "Carol"
	# Leave score at its default so it isn't included in the save.

	var s := BinarySerializer.new()
	s.save_node(node)

	# Modify score to verify load_from_dict doesn't touch absent properties.
	node.score = 7.0

	var d := _make_deserializer(s)
	d.load_node()
	assert_eq(node.health, 25)
	assert_eq(node.player_name, "Carol")
	assert_eq(node.score, 7.0, "Untouched property should be left alone")


func test_load_node_returns_null_for_missing_node_without_scene() -> void:
	# Use save_path_override to record an entry pointing at a non-existent
	# location with no scene_file_path, so loading should fail.
	var node := MockSaveableWithOverride.new()
	node.name = "Source"
	add_child_autofree(node)
	node.add_to_group("saveable")
	node.save_path_override = NodePath("/root/NonExistent/Node")

	var s := BinarySerializer.new()
	s.save_node(node)

	var d := _make_deserializer(s)
	var result := d.load_node()
	assert_null(result)
	assert_push_error("Cannot instantiate node")


# =============================================================================
# default_load_from_dict
# =============================================================================

func test_default_load_sets_properties() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	d.default_load_from_dict(node, {
		"health": s.encode_var(5),
		"player_name": s.encode_var("Test"),
	})
	assert_eq(node.health, 5)
	assert_eq(node.player_name, "Test")
	assert_eq(node.score, 0.0, "Untouched property should stay at default")


func test_default_load_with_only_properties_filter() -> void:
	var s := BinarySerializer.new()
	var d := _make_deserializer()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	d.default_load_from_dict(node, {
		"health": s.encode_var(5),
		"player_name": s.encode_var("Nope"),
		"score": s.encode_var(42.0),
	}, PackedStringArray(["health", "score"]))
	assert_eq(node.health, 5)
	assert_eq(node.score, 42.0)
	assert_eq(node.player_name, "", "player_name not in allowlist, should stay at default")


# =============================================================================
# find_or_instantiate_node
# =============================================================================

func test_find_existing_node_in_group() -> void:
	var node := Node.new()
	node.name = "Existing"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var d := _make_deserializer()
	var found := d.find_or_instantiate_node(node.get_path(), "")
	assert_eq(found, node)


func test_find_rejects_node_not_in_group() -> void:
	var node := Node.new()
	node.name = "NotInGroup"
	add_child_autofree(node)
	# NOT added to saveable group

	var d := _make_deserializer()
	var found := d.find_or_instantiate_node(node.get_path(), "")
	assert_null(found, "Should reject nodes not in the saveable group")


func test_instantiate_from_scene() -> void:
	var parent := Node.new()
	parent.name = "Parent"
	add_child_autofree(parent)

	var child_path := NodePath(str(parent.get_path()) + "/MockSaveable")
	var d := _make_deserializer()
	watch_signals(d)
	var node := d.find_or_instantiate_node(child_path, "res://tests/fixtures/mock_saveable.tscn")
	assert_not_null(node)
	assert_true(node.is_in_group("saveable"), "Instantiated node should be added to saveable group")
	assert_signal_emitted(d, "node_created")


func test_instantiate_adds_correct_name() -> void:
	var parent := Node.new()
	parent.name = "Parent"
	add_child_autofree(parent)

	var child_path := NodePath(str(parent.get_path()) + "/MyNode")
	var d := _make_deserializer()
	var node := d.find_or_instantiate_node(child_path, "res://tests/fixtures/mock_saveable.tscn")
	assert_not_null(node)
	assert_eq(node.name, &"MyNode")


func test_instantiate_fails_without_scene_path() -> void:
	var path := NodePath("/root/NonExistent/Orphan")
	var d := _make_deserializer()
	var node := d.find_or_instantiate_node(path, "")
	assert_null(node)
	assert_push_error("Cannot instantiate node")


func test_instantiate_requires_scene_tree() -> void:
	var s := BinarySerializer.new()
	var d := BinaryDeserializer.new()
	d.prepare_load_from_memory(s.finalize_save_in_memory())
	# scene_tree intentionally NOT set
	var node := d.find_or_instantiate_node(NodePath("/root/Test"), "")
	assert_null(node)
	assert_push_error("scene_tree must be set")


# =============================================================================
# SaveKitResource round trips
# =============================================================================

func test_save_kit_resource_round_trip() -> void:
	var resource := MockSaveKitResource.new()
	resource.item_name = "Potion"
	resource.quantity = 5

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var(resource)
	var d := _make_deserializer(s)
	var loaded: Variant = d.decode_var(encoded, TYPE_OBJECT, &"SaveKitResource")
	assert_not_null(loaded)
	assert_eq(loaded.get("item_name"), "Potion")
	assert_eq(loaded.get("quantity"), 5)


func test_save_kit_resource_round_trip_deduplicates() -> void:
	var resource := MockSaveKitResource.new()
	resource.item_name = "Shield"

	var s := BinarySerializer.new()
	var encoded1: Variant = s.encode_var(resource)
	var encoded2: Variant = s.encode_var(resource)
	var d := _make_deserializer(s)
	var loaded1: Variant = d.decode_var(encoded1, TYPE_OBJECT, &"SaveKitResource")
	var loaded2: Variant = d.decode_var(encoded2, TYPE_OBJECT, &"SaveKitResource")
	assert_eq(loaded1, loaded2, "Same resource should yield the same instance")


# =============================================================================
# decode_var — nested objects in containers (round-tripped)
# =============================================================================

func test_decode_node_reference_in_array() -> void:
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([node])
	var d := _make_deserializer(s)
	var decoded: Array = d.decode_var(encoded, TYPE_ARRAY)
	assert_eq(decoded.size(), 1)
	assert_eq(decoded[0], node, "Node reference inside array should be decoded back to the node")


func test_decode_node_reference_in_dictionary() -> void:
	var node := Node.new()
	node.name = "Nested"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var({"my_node": node})
	var d := _make_deserializer(s)
	var decoded: Dictionary = d.decode_var(encoded, TYPE_DICTIONARY)
	assert_has(decoded, "my_node")
	assert_eq(decoded["my_node"], node, "Node reference inside dict should be decoded back to the node")


func test_decode_save_kit_resource_in_array() -> void:
	var resource := MockSaveKitResource.new()
	resource.item_name = "Gem"
	resource.quantity = 3

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([resource])
	var d := _make_deserializer(s)
	var decoded: Array = d.decode_var(encoded, TYPE_ARRAY)
	assert_eq(decoded.size(), 1)
	assert_not_null(decoded[0], "SaveKitResource inside array should be decoded")
	assert_eq(decoded[0].get("item_name"), "Gem")
	assert_eq(decoded[0].get("quantity"), 3)


func test_decode_save_kit_resource_in_dictionary() -> void:
	var resource := MockSaveKitResource.new()
	resource.item_name = "Gem"
	resource.quantity = 3

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var({"item": resource})
	var d := _make_deserializer(s)
	var decoded: Dictionary = d.decode_var(encoded, TYPE_DICTIONARY)
	assert_has(decoded, "item")
	assert_not_null(decoded["item"], "SaveKitResource inside dict should be decoded")
	assert_eq(decoded["item"].get("item_name"), "Gem")


func test_decode_resource_reference_in_array() -> void:
	var script: Script = MockSaveable
	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([script])
	var d := _make_deserializer(s)
	var decoded: Array = d.decode_var(encoded, TYPE_ARRAY)
	assert_eq(decoded.size(), 1)
	assert_not_null(decoded[0], "Resource reference inside array should be decoded to a resource")


func test_decode_resource_reference_in_dictionary() -> void:
	var script: Script = MockSaveable
	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var({"script": script})
	var d := _make_deserializer(s)
	var decoded: Dictionary = d.decode_var(encoded, TYPE_DICTIONARY)
	assert_has(decoded, "script")
	assert_not_null(decoded["script"], "Resource reference inside dict should be decoded to a resource")


func test_decode_node_in_nested_containers() -> void:
	var node := Node.new()
	node.name = "DeepNested"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var({"list": [{"target": node}]})
	var d := _make_deserializer(s)
	var decoded: Dictionary = d.decode_var(encoded, TYPE_DICTIONARY)
	var inner_list: Array = decoded["list"]
	var inner_dict: Dictionary = inner_list[0]
	assert_eq(inner_dict["target"], node, "Node deeply nested in dict>array>dict should be decoded")


func test_decode_save_kit_resource_in_nested_containers() -> void:
	var resource := MockSaveKitResource.new()
	resource.item_name = "Ring"

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([[{"item": resource}]])
	var d := _make_deserializer(s)
	var decoded: Array = d.decode_var(encoded, TYPE_ARRAY)
	var inner_array: Array = decoded[0]
	var inner_dict: Dictionary = inner_array[0]
	assert_not_null(inner_dict["item"], "SaveKitResource deeply nested should be decoded")
	assert_eq(inner_dict["item"].get("item_name"), "Ring")


func test_decode_mixed_objects_in_array() -> void:
	var node := Node.new()
	node.name = "MixNode"
	add_child_autofree(node)
	node.add_to_group("saveable")
	var resource := MockSaveKitResource.new()
	resource.item_name = "Bow"
	var script: Script = MockSaveable

	var s := BinarySerializer.new()
	var encoded: Variant = s.encode_var([node, resource, script, 42, "plain"])
	var d := _make_deserializer(s)
	var decoded: Array = d.decode_var(encoded, TYPE_ARRAY)
	assert_eq(decoded[0], node, "Node in mixed array should be decoded")
	assert_not_null(decoded[1], "SaveKitResource in mixed array should be decoded")
	assert_eq(decoded[1].get("item_name"), "Bow")
	assert_not_null(decoded[2], "Resource reference in mixed array should be decoded")
	assert_eq(decoded[3], 42)
	assert_eq(decoded[4], "plain")
