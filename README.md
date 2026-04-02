# godot-savekit

A Godot 4 addon for saving and loading game state. SaveKit serializes your scene tree to a JSON-compatible dictionary that you can persist however you like.

## Getting started

1. Enable the plugin in **Project > Project Settings > Plugins**.
2. Add any nodes you want to save to the `"saveable"` group.
3. Call `SaveManager.save_scene_tree()` to save, and `SaveManager.load_into_scene_tree(data)` to load.

```gdscript
# Save
var data: Dictionary = SaveManager.save_scene_tree()
var json := JSON.stringify(data)
FileAccess.open("user://save.json", FileAccess.WRITE).store_string(json)

# Load
var json := FileAccess.open("user://save.json", FileAccess.READ).get_as_text()
var data: Dictionary = JSON.parse_string(json)
SaveManager.load_into_scene_tree(data)
```

SaveKit handles the serialization and scene tree manipulation. Persisting the data to disk (or anywhere else) is up to you.

## Saving and loading nodes

Any node in the `"saveable"` group will be included when saving. There are two approaches for controlling what data gets saved and loaded: **custom methods** and **automatic reflection**.

### Custom save/load methods

Implement `save_to_dict` and `load_from_dict` on your node for full control:

```gdscript
extends CharacterBody2D

func save_to_dict(serializer: Serializer) -> Dictionary:
    return {
        "health": serializer.encode_var(health),
        "position": serializer.encode_var(global_position),
        "inventory": serializer.encode_var(inventory_resource),
    }

func load_from_dict(deserializer: Deserializer, data: Dictionary) -> void:
    health = deserializer.decode_var(data["health"], TYPE_INT)
    global_position = deserializer.decode_var(data["position"], TYPE_VECTOR2)
    inventory_resource = deserializer.decode_var(data["inventory"], TYPE_OBJECT)
```

Use `encode_var` / `decode_var` to handle type encoding. This is especially important for values like `Vector2`, `Color`, `Resource` references, and `Node` references, which need special encoding for JSON compatibility.

### Automatic reflection (no custom methods)

If a node does **not** implement `save_to_dict` / `load_from_dict`, SaveKit automatically saves and loads all `@export` and `@export_storage` properties that differ from their default values:

```gdscript
extends Node

@export var health: int = 100
@export var player_name: String = ""
@export_storage var score: float = 0.0
```

Properties at their default values are omitted from save data to keep it minimal.

### Mixing both approaches

A custom `save_to_dict` can delegate part of its work to the automatic behavior using `default_save_to_dict` / `default_load_from_dict`, and handle specific properties manually:

```gdscript
func save_to_dict(serializer: Serializer) -> Dictionary:
    var data := serializer.default_save_to_dict(self, PackedStringArray(["health", "score"]))
    data["custom_field"] = compute_custom_value()
    return data

func load_from_dict(deserializer: Deserializer, data: Dictionary) -> void:
    deserializer.default_load_from_dict(self, data, PackedStringArray(["health", "score"]))
    restore_custom_value(data.get("custom_field"))
```

The `only_properties` parameter filters which exported properties are handled automatically.

## Saving and loading resources

For resources that represent save-file data (inventories, quest state, etc.), extend `SaveableResource`:

```gdscript
class_name PlayerInventory
extends SaveableResource

@export var items: Array[String] = []
@export var gold: int = 0
```

`SaveableResource` works like automatic node saving: exported properties with non-default values are serialized. Override `save_to_dict` and `load_from_dict` for custom behavior.

When a `SaveableResource` is encountered as a property value during serialization, its full data is saved inline. Regular `Resource` subclasses (e.g., textures, scenes) are saved as **references** by path/UID, not by value.

```gdscript
# SaveableResource property: data is serialized into the save file
@export var inventory: PlayerInventory

# Regular Resource property: only a res:// reference is saved
@export var sprite_texture: Texture2D
```

`SaveableResource` emits `saved` and `loaded` signals, and `changed` after loading.

## SaveManager

`SaveManager` is installed as an autoload singleton when the plugin is enabled. It can also be instantiated as a regular node for independent save managers.

### Methods

| Method | Description |
|---|---|
| `save_scene_tree() -> Dictionary` | Saves all nodes in the saveable group and returns the save data. |
| `load_into_scene_tree(data: Dictionary)` | Loads save data into the scene tree, adding, updating, and removing nodes as needed. |

### Signals

| Signal | Description |
|---|---|
| `before_save` / `after_save` | Emitted at the start/end of `save_scene_tree`. |
| `before_load` / `after_load` | Emitted at the start/end of `load_into_scene_tree`. |
| `node_saved(node)` | Emitted after each node is saved. |
| `node_loaded(node)` | Emitted after each node is loaded. |
| `node_created(node)` | Emitted when a node is instantiated from a PackedScene during loading. |
| `node_removed(node)` | Emitted when a saveable node is removed because it was not in the save data. |

### Lifecycle hooks

Nodes in the saveable group can implement these methods to run logic at specific points in the save/load process:

| Method | When it runs |
|---|---|
| `before_save()` | Before any nodes are serialized. |
| `after_save()` | After all nodes have been serialized (called in reverse tree order). |
| `before_load()` | Before any nodes are loaded. Only called on nodes already in the tree. |
| `after_load()` | After all nodes have been loaded (called in reverse tree order). Includes newly created nodes. |

### Properties

| Property | Default | Description |
|---|---|---|
| `saveable_node_group` | `"saveable"` | The group name used to find saveable nodes. |
| `before_save_method` | `"before_save"` | Method name called before saving. |
| `after_save_method` | `"after_save"` | Method name called after saving. |
| `before_load_method` | `"before_load"` | Method name called before loading. |
| `after_load_method` | `"after_load"` | Method name called after loading. |

## Node instantiation during loading

If a node exists in the save data but not in the scene tree, SaveKit will attempt to instantiate it from the `PackedScene` it was originally created from (using `scene_file_path`). The new node is automatically added to the saveable group and to the correct parent.

Nodes that exist in the scene tree but are **not** in the save data are removed (via `queue_free`) during loading.

## Advanced usage

### Save path override

By default, nodes are keyed in save data by their scene tree path. To override this, add a `save_path_override` property:

```gdscript
var save_path_override: NodePath = ^"/root/World/Player"
```

This is useful when a node might move in the tree but should always map to the same save data entry.

### Encoding references in custom save methods

Within `save_to_dict`, use these serializer methods to encode references:

- `encode_var(value)` -- Encodes any supported value, automatically choosing the right strategy.
- `encode_resource_reference(resource)` -- Encodes a `res://` path reference to a resource (for assets in the PCK).
- `encode_node_reference(node)` -- Encodes a reference to another node in the scene tree.
- `save_resource(resource)` -- Saves a `SaveableResource` inline and returns a reference to it.

Within `load_from_dict`, use these deserializer methods to decode:

- `decode_var(value, expected_type, expected_class_name)` -- Decodes any saved value back to its runtime type.
- `decode_resource_reference(path, uid, class_name)` -- Loads a resource by path or UID.
- `load_resource(id)` -- Loads a previously saved `SaveableResource` by its ID.

## Running tests

Tests use [GUT](https://gut.readthedocs.io) and run via the Godot CLI:

```bash
godot --headless -s addons/gut/gut_cmdln.gd
```
