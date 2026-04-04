@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const JSONSerializer := preload("res://addons/savekit/json_serializer.gd")
const JSONDeserializer := preload("res://addons/savekit/json_deserializer.gd")
const MockSaveableResource := preload("res://tests/fixtures/mock_saveable_resource.gd")


# =============================================================================
# save_to_dict
# =============================================================================

func test_save_captures_non_default_properties() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Sword"
	resource.quantity = 5
	var result := resource.save_to_dict(s)
	assert_has(result, "item_name")
	assert_has(result, "quantity")


func test_save_omits_default_values() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Sword"
	# quantity (1) and weight (0.0) left at defaults
	var result := resource.save_to_dict(s)
	assert_does_not_have(result, "quantity", "quantity at default should not be saved")
	assert_does_not_have(result, "weight", "weight at default should not be saved")


func test_save_encodes_values() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Bow"
	resource.weight = 1.5
	var result := resource.save_to_dict(s)
	assert_eq(result["item_name"], JSON.from_native("Bow"))
	assert_eq(result["weight"], JSON.from_native(1.5))


func test_save_emits_saved_signal() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	watch_signals(resource)
	resource.save_to_dict(s)
	assert_signal_emitted(resource, "saved")


# =============================================================================
# load_from_dict
# =============================================================================

func test_load_sets_properties() -> void:
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	d.scene_tree = get_tree()
	var resource := MockSaveableResource.new()
	resource.load_from_dict(d, {
		"item_name": JSON.from_native("Shield"),
		"quantity": JSON.from_native(3),
	})
	assert_eq(resource.item_name, "Shield")
	assert_eq(resource.quantity, 3)
	assert_eq(resource.weight, 0.0, "Untouched property should stay at default")


func test_load_emits_loaded_signal() -> void:
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	d.scene_tree = get_tree()
	var resource := MockSaveableResource.new()
	watch_signals(resource)
	resource.load_from_dict(d, {})
	assert_signal_emitted(resource, "loaded")


func test_load_emits_changed_signal() -> void:
	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	d.scene_tree = get_tree()
	var resource := MockSaveableResource.new()
	watch_signals(resource)
	resource.load_from_dict(d, {})
	assert_signal_emitted(resource, "changed")


# =============================================================================
# round-trip
# =============================================================================

func test_round_trip() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Potion"
	resource.quantity = 10
	resource.weight = 2.5
	var saved := resource.save_to_dict(s)

	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	d.scene_tree = get_tree()
	var loaded := MockSaveableResource.new()
	loaded.load_from_dict(d, saved)
	assert_eq(loaded.item_name, "Potion")
	assert_eq(loaded.quantity, 10)
	assert_almost_eq(loaded.weight, 2.5, 0.001)


func test_round_trip_preserves_defaults_for_unset_properties() -> void:
	var s := JSONSerializer.new()
	var resource := MockSaveableResource.new()
	resource.item_name = "Arrow"
	# quantity and weight left at defaults
	var saved := resource.save_to_dict(s)

	var d := JSONDeserializer.new()
	d.prepare_load_from_memory(JSON.stringify({"version": 1, "nodes": {}}).to_utf8_buffer())
	d.scene_tree = get_tree()
	var loaded := MockSaveableResource.new()
	loaded.load_from_dict(d, saved)
	assert_eq(loaded.item_name, "Arrow")
	assert_eq(loaded.quantity, 1, "Default should be preserved")
	assert_eq(loaded.weight, 0.0, "Default should be preserved")
