@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const JSONSerializer := preload("res://addons/savekit/json_serializer.gd")
const JSONDeserializer := preload("res://addons/savekit/json_deserializer.gd")
const MockSaveable := preload("res://tests/fixtures/mock_saveable.gd")
const MockSaveableScene := preload("res://tests/fixtures/mock_saveable.tscn")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")
const MockSaveableResource := preload("res://tests/fixtures/mock_saveable_resource.gd")


func _make_deserializer(nodes: Dictionary = {}, resources: Dictionary = {}) -> JSONDeserializer:
	var data := {"version": 1, "nodes": nodes}
	if resources:
		data["resources"] = resources
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify(data).to_utf8_buffer())
	d.scene_tree = get_tree()
	d.saveable_node_group = &"saveable"
	return d


# =============================================================================
# prepare_load_from_memory
# =============================================================================

func test_prepare_with_valid_data() -> void:
	var d := _make_deserializer()
	assert_true(d.is_finished())


func test_prepare_with_nodes() -> void:
	var node := Node.new()
	node.name = "TestNode"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var path := str(node.get_path())
	var d := _make_deserializer({path: {}})
	assert_false(d.is_finished())


func test_prepare_with_invalid_version() -> void:
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 999}).to_utf8_buffer())
	assert_push_error("Unsupported save data version")


func test_prepare_with_missing_version() -> void:
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"nodes": {}}).to_utf8_buffer())
	assert_push_error("Unsupported save data version")


# =============================================================================
# decode_var
# =============================================================================

func test_decode_int() -> void:
	var d := _make_deserializer()
	assert_eq(d.decode_var(JSON.from_native(42), TYPE_INT), 42)


func test_decode_float() -> void:
	var d := _make_deserializer()
	assert_eq(d.decode_var(JSON.from_native(3.14), TYPE_FLOAT), 3.14)


func test_decode_string() -> void:
	var d := _make_deserializer()
	assert_eq(d.decode_var(JSON.from_native("hello"), TYPE_STRING), "hello")


func test_decode_bool() -> void:
	var d := _make_deserializer()
	assert_eq(d.decode_var(JSON.from_native(true), TYPE_BOOL), true)
	assert_eq(d.decode_var(JSON.from_native(false), TYPE_BOOL), false)


func test_decode_vector2() -> void:
	var d := _make_deserializer()
	var encoded: Variant = JSON.from_native(Vector2(1, 2))
	var decoded: Variant = d.decode_var(encoded, TYPE_VECTOR2)
	assert_eq(decoded, Vector2(1, 2))


func test_decode_color() -> void:
	var d := _make_deserializer()
	var encoded: Variant = JSON.from_native(Color.RED)
	var decoded: Variant = d.decode_var(encoded, TYPE_COLOR)
	assert_eq(decoded, Color.RED)


func test_decode_rid_returns_null() -> void:
	var d := _make_deserializer()
	assert_null(d.decode_var(null, TYPE_RID))


func test_decode_resource_reference() -> void:
	var d := _make_deserializer()
	var decoded: Variant = d.decode_var(
		{"path": "res://tests/fixtures/mock_saveable.gd"},
		TYPE_OBJECT,
		&"Script",
	)
	assert_not_null(decoded)


# =============================================================================
# decode_resource_reference
# =============================================================================

func test_decode_resource_reference_by_path() -> void:
	var d := _make_deserializer()
	var decoded := d.decode_resource_reference("res://tests/fixtures/mock_saveable.gd", "", &"Script")
	assert_not_null(decoded)


func test_decode_resource_reference_invalid_path() -> void:
	var d := _make_deserializer()
	var decoded := d.decode_resource_reference("user://bad/path.gd")
	assert_null(decoded)


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

	var d := _make_deserializer({
		str(node1.get_path()): {},
		str(node2.get_path()): {},
	})
	assert_eq(d.get_remaining_node_count(), 2)
	assert_false(d.is_finished())


func test_is_finished_after_loading_all() -> void:
	var node := MockSaveable.new()
	node.name = "TestNode"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var path := str(node.get_path())
	var d := _make_deserializer({path: {}})
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

	var path := str(node.get_path())
	var d := _make_deserializer({path: {"key": "val"}})
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

	var parent_path := str(parent.get_path())
	var child_path := str(child.get_path())

	# Intentionally pass child before parent to verify sorting
	var d := _make_deserializer({
		child_path: {},
		parent_path: {},
	})

	var first := d.load_node()
	var second := d.load_node()
	assert_eq(first, parent, "Parent should be loaded before child")
	assert_eq(second, child, "Child should be loaded after parent")


func test_load_node_strips_scene_file_path() -> void:
	var node := MockSaveable.new()
	node.name = "Target"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var path := str(node.get_path())
	var d := _make_deserializer({path: {
		"health": 10,
		"scene_file_path": "res://tests/fixtures/mock_saveable.tscn",
	}})
	d.load_node()
	assert_false(node.loaded_data.has("scene_file_path"),
		"scene_file_path should be stripped before passing to load_from_dict")
	assert_eq(node.loaded_data["health"], 10)


func test_load_node_with_custom_load() -> void:
	var node := MockSaveable.new()
	node.name = "Target"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var path := str(node.get_path())
	var d := _make_deserializer({path: {"custom_key": "custom_val"}})
	d.load_node()
	assert_eq(node.loaded_data["custom_key"], "custom_val")


func test_load_node_with_default_load() -> void:
	var node := MockDefaultSaveable.new()
	node.name = "DefaultNode"
	add_child_autofree(node)
	node.add_to_group("saveable")

	var path := str(node.get_path())
	var d := _make_deserializer({path: {
		"health": JSON.from_native(25),
		"player_name": JSON.from_native("Carol"),
	}})
	d.load_node()
	assert_eq(node.health, 25)
	assert_eq(node.player_name, "Carol")
	assert_eq(node.score, 0.0, "Untouched property should stay at default")


func test_load_node_returns_null_for_missing_node_without_scene() -> void:
	var path := "/root/NonExistent/Node"
	var d := _make_deserializer({path: {"val": 1}})
	var result := d.load_node()
	assert_null(result)
	assert_push_error("Cannot instantiate node")


# =============================================================================
# default_load_from_dict
# =============================================================================

func test_default_load_sets_properties() -> void:
	var d := _make_deserializer()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	d.default_load_from_dict(node, {
		"health": JSON.from_native(5),
		"player_name": JSON.from_native("Test"),
	})
	assert_eq(node.health, 5)
	assert_eq(node.player_name, "Test")
	assert_eq(node.score, 0.0, "Untouched property should stay at default")


func test_default_load_with_only_properties_filter() -> void:
	var d := _make_deserializer()
	var node := MockDefaultSaveable.new()
	node.name = "Node"
	add_child_autofree(node)
	d.default_load_from_dict(node, {
		"health": JSON.from_native(5),
		"player_name": JSON.from_native("Nope"),
		"score": JSON.from_native(42.0),
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
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	# scene_tree intentionally NOT set
	var node := d.find_or_instantiate_node(NodePath("/root/Test"), "")
	assert_null(node)
	assert_push_error("scene_tree must be set")


# =============================================================================
# load_resource
# =============================================================================

func test_load_resource_round_trip() -> void:
	var serializer := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Potion"
	resource.quantity = 5
	var ref: Dictionary = serializer.save_resource(resource)
	var save_data := serializer.finalize_save_in_memory()

	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(save_data)
	d.scene_tree = get_tree()
	var loaded: SaveableResource = d.load_resource(ref["res"])
	assert_not_null(loaded)
	assert_eq(loaded.get("item_name"), "Potion")
	assert_eq(loaded.get("quantity"), 5)


func test_load_resource_deduplicates() -> void:
	var serializer := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Shield"
	var ref: Dictionary = serializer.save_resource(resource)
	var save_data := serializer.finalize_save_in_memory()

	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(save_data)
	d.scene_tree = get_tree()
	var loaded1 := d.load_resource(ref["res"])
	var loaded2 := d.load_resource(ref["res"])
	assert_eq(loaded1, loaded2, "Same resource instance should be returned")


func test_load_resource_missing_id() -> void:
	var d := _make_deserializer()
	var loaded := d.load_resource("nonexistent_id")
	assert_null(loaded)
	assert_push_error("No saved resource found with ID")
