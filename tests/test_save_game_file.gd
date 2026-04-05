@warning_ignore_start("unsafe_call_argument", "inferred_declaration", "unsafe_method_access")
extends GutTest

const SaveGameFile := preload("res://addons/savekit/save_game_file.gd")


# =============================================================================
# sanitize_save_name_components
# =============================================================================

func test_sanitize_simple_name() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["Save1"]))
	assert_eq(result, "Save1")


func test_sanitize_name_with_spaces() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["My Cool Save"]))
	assert_eq(result, "My Cool Save")


func test_sanitize_multi_component_preserves_hierarchy() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["Game", "Slot1"]))
	assert_eq(result, "Game/Slot1")


func test_sanitize_invalid_chars_within_component_do_not_break_hierarchy() -> void:
	# A slash inside a single component must be treated as an invalid
	# character within that component rather than introducing a new
	# directory separator.
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["Game/Extra", "Slot1"]))
	assert_eq(result, "Game_Extra/Slot1")


func test_sanitize_replaces_dots_with_underscores() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["my.save.file"]))
	assert_eq(result, "my_save_file")


func test_sanitize_replaces_invalid_filename_characters() -> void:
	# `?`, `*`, `|`, `:`, `"`, `<`, `>`, `%`, `\` are all invalid in filenames.
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["bad?name*"]))
	assert_eq(result, "bad_name_")


func test_sanitize_directory_traversal_is_neutralized() -> void:
	# A lone ".." cannot be simplified away, but the dot replacement
	# still ensures we never produce a literal parent-directory component.
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["..", "escape"]))
	assert_false(result.is_empty(), "Sanitized result should not be empty")
	assert_false(result.contains(".."), "Result should not contain '..'")


func test_sanitize_absolute_path_is_neutralized() -> void:
	# A leading "/" gets replaced with "_" by validate_filename,
	# ensuring the result is never absolute.
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray(["/etc/passwd"]))
	assert_false(result.is_absolute_path(), "Result should not be an absolute path")
	assert_false(result.is_empty(), "Result should not be empty")


func test_sanitize_empty_components_returns_empty() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray())
	assert_eq(result, "")


func test_sanitize_empty_string_component_returns_empty() -> void:
	var result := SaveGameFile.sanitize_save_name_components(PackedStringArray([""]))
	assert_eq(result, "")


func test_sanitize_is_never_absolute() -> void:
	# Regardless of what we throw at it, the result is never an absolute path.
	var inputs: Array[PackedStringArray] = [
		PackedStringArray(["/abs"]),
		PackedStringArray(["res://thing"]),
		PackedStringArray(["user://thing"]),
		PackedStringArray(["..", ".."]),
	]
	for input in inputs:
		var result := SaveGameFile.sanitize_save_name_components(input)
		assert_false(result.is_absolute_path(), "Expected relative path for input: %s" % [input])


# =============================================================================
# modified_at_datetime
# =============================================================================

func test_modified_at_datetime_getter_reflects_unix_time() -> void:
	var save_file := SaveGameFile.new()
	var unix_time := Time.get_unix_time_from_datetime_string("2024-01-15T12:30:45")
	save_file.modified_at_unix_time = unix_time
	assert_eq(save_file.modified_at_datetime, "2024-01-15T12:30:45")


func test_modified_at_datetime_setter_updates_unix_time() -> void:
	var save_file := SaveGameFile.new()
	save_file.modified_at_datetime = "2024-06-01T08:00:00"
	var expected := Time.get_unix_time_from_datetime_string("2024-06-01T08:00:00")
	assert_eq(save_file.modified_at_unix_time, expected)


func test_modified_at_datetime_roundtrip() -> void:
	var save_file := SaveGameFile.new()
	save_file.modified_at_datetime = "2026-04-05T13:06:35"
	assert_eq(save_file.modified_at_datetime, "2026-04-05T13:06:35")
