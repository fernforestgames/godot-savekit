extends GutTest

const ResourceUtils := preload("res://addons/savekit/resource_utils.gd")


# =============================================================================
# safe_load_resource
# =============================================================================

func test_rejects_relative_path() -> void:
	var result := ResourceUtils.safe_load_resource("some/relative/path.tscn", PackedStringArray(["tscn"]))
	assert_null(result)


func test_rejects_non_res_path() -> void:
	var result := ResourceUtils.safe_load_resource("user://saves/file.tscn", PackedStringArray(["tscn"]))
	assert_null(result)


func test_rejects_wrong_extension() -> void:
	var result := ResourceUtils.safe_load_resource("res://scenes/file.tres", PackedStringArray(["tscn"]))
	assert_null(result)


func test_accepts_valid_resource() -> void:
	var result := ResourceUtils.safe_load_resource(
		"res://tests/fixtures/mock_saveable.tscn",
		PackedStringArray(["tscn"]),
	)
	assert_not_null(result)


func test_accepts_multiple_allowed_extensions() -> void:
	var result := ResourceUtils.safe_load_resource(
		"res://tests/fixtures/mock_saveable.tscn",
		PackedStringArray(["tres", "tscn"]),
	)
	assert_not_null(result)
