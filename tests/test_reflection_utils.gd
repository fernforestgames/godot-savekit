extends GutTest

const ReflectionUtils := preload("res://addons/savekit/reflection_utils.gd")
const MockDefaultSaveable := preload("res://tests/fixtures/mock_default_saveable.gd")


# =============================================================================
# get_storable_non_default_properties
# =============================================================================

func test_returns_empty_for_script_properties_at_defaults() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	var props := ReflectionUtils.get_storable_non_default_properties(node)
	var names := _prop_names(props)
	assert_does_not_have(names, "health")
	assert_does_not_have(names, "player_name")
	assert_does_not_have(names, "score")


func test_returns_changed_script_properties() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	node.health = 50
	node.player_name = "Alice"

	var props := ReflectionUtils.get_storable_non_default_properties(node)
	var names := _prop_names(props)
	assert_has(names, "health")
	assert_has(names, "player_name")
	assert_does_not_have(names, "score", "score is still at its default")


func test_returned_property_includes_value() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	node.score = 99.5

	var props := ReflectionUtils.get_storable_non_default_properties(node)
	for prop in props:
		if prop["name"] == "score":
			assert_eq(prop["value"], 99.5)
			return
	fail_test("score property not found in results")


func test_excludes_script_property() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	var props := ReflectionUtils.get_storable_non_default_properties(node)
	var names := _prop_names(props)
	assert_does_not_have(names, "script")


func test_filters_builtin_properties_at_defaults() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	var props := ReflectionUtils.get_storable_non_default_properties(node)
	var names := _prop_names(props)
	assert_does_not_have(names, "process_mode")


func test_returns_changed_builtin_property() -> void:
	var node := MockDefaultSaveable.new()
	add_child_autofree(node)
	node.process_mode = Node.PROCESS_MODE_DISABLED

	var props := ReflectionUtils.get_storable_non_default_properties(node)
	var names := _prop_names(props)
	assert_has(names, "process_mode")


# =============================================================================
# get_script_default_property_values
# =============================================================================

func test_script_defaults_returns_known_defaults() -> void:
	var defaults: Dictionary[String, Variant] = {}
	ReflectionUtils.get_script_default_property_values(MockDefaultSaveable, defaults)
	assert_eq(defaults.get("health"), 100)
	assert_eq(defaults.get("player_name"), "")
	assert_eq(defaults.get("score"), 0.0)


func test_script_defaults_with_null_script_is_noop() -> void:
	var defaults: Dictionary[String, Variant] = {}
	ReflectionUtils.get_script_default_property_values(null, defaults)
	assert_eq(defaults.size(), 0)


# =============================================================================
# get_builtin_class_default_property_values
# =============================================================================

func test_builtin_defaults_for_node() -> void:
	var defaults := ReflectionUtils.get_builtin_class_default_property_values("Node")
	assert_has(defaults, "name")
	assert_has(defaults, "process_mode")


func test_builtin_defaults_without_ancestors() -> void:
	var with_ancestors := ReflectionUtils.get_builtin_class_default_property_values("Node2D", true)
	var without_ancestors := ReflectionUtils.get_builtin_class_default_property_values("Node2D", false)
	assert_true(with_ancestors.size() >= without_ancestors.size(),
		"Including ancestors should return at least as many properties")


# =============================================================================
# Helpers
# =============================================================================

func _prop_names(props: Array[Dictionary]) -> Array[String]:
	var names: Array[String]
	for p in props:
		names.append(p["name"])
	return names
