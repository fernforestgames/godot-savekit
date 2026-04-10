# SaveKit for Godot

A library for saving and loading game state in Godot 4, with pluggable save file formats and a focus on ease of use.

Key features:

- **Easy to get started.** Add nodes to the `saveable` group, then use `SaveManager.save_game()` and `SaveManager.load_game()`.
- **Saves nodes and resources.** Built-in resources, like textures and packed scenes, are saved as references, while data from nodes and custom `SaveKitResource` subclasses is saved in its entirety. This avoids the code injection risks of Godot's `ResourceLoader`, while supporting complex data.
- **JSON and binary serialization built-in**, or implement your own custom save file format by extending `SaveKitSerializer` and `SaveKitDeserializer`.
- **Automatic by default, manual when you need it.** Reflection picks up exported properties for saving/loading automatically, or you can implement custom `save_to_dict` and `load_from_dict` methods for full control.

## Getting started

1. Enable the plugin in **Project > Project Settings > Plugins**. This also installs a `SaveManager` autoload.
2. Add all the nodes you want saved to the `saveable` group.
3. Call one method to save, another to load:

```gdscript
# Save to disk under user://save_games/MyGame/Slot 1.json
SaveManager.save_game(PackedStringArray(["MyGame", "Slot 1"]))

# Load it back later
SaveManager.load_game(PackedStringArray(["MyGame", "Slot 1"]))
```

This will iterate through nodes in the `saveable` group, serialize each node's exported properties, and write the file into `user://save_games/`. Then the reverse is done on load—creating or freeing nodes as needed so the scene tree matches the save file.

There are also other methods offering finer-grained control over the save/load process:

```gdscript
func save_scene_tree_in_memory() -> PackedByteArray
func save_scene_tree_to_disk(absolute_path: String) -> Error

func load_scene_tree_from_memory(data: PackedByteArray) -> bool
func load_scene_tree_from_file(absolute_path: String) -> Error
```

## Saving nodes

By default, SaveKit uses reflection to save all `@export` and `@export_storage` properties whose values differ from their defaults. For a lot of nodes, this is all you need:

```gdscript
extends CharacterBody2D

@export var health: int = 100
@export var player_name: String = ""
@export_storage var checkpoint: Vector2
```

When you need additional control, implement `save_to_dict` and `load_from_dict`:

```gdscript
extends RigidBody2D

func save_to_dict(s: SaveKitSerializer) -> Dictionary:
    return {
        "transform": s.encode_var(transform),
        "linear_velocity": s.encode_var(linear_velocity),
    }

func load_from_dict(s: SaveKitDeserializer, data: Dictionary) -> void:
    var t: Transform2D = s.decode_var(data["transform"], TYPE_TRANSFORM2D)
    PhysicsServer2D.body_set_state(get_rid(), PhysicsServer2D.BODY_STATE_TRANSFORM, t)

    linear_velocity = s.decode_var(data["linear_velocity"], TYPE_VECTOR2)
```

You can also mix the two approaches by calling `serializer.default_save_to_dict()` and `deserializer.default_load_from_dict()` from your implementation.

### Node instantiation

If a saved node isn't in the scene tree at load time, SaveKit will instantiate it from the `scene_file_path` it was saved with and parent it where it belongs. Conversely, nodes in the `saveable` group that *aren't* in the save data are freed, so the scene tree always matches the save file after loading.

## Saving resources

For resources that represent persisted data—e.g., inventories, quest state, per-entity stat blocks—extend `SaveKitResource` rather than plain `Resource`:

```gdscript
class_name Inventory
extends SaveKitResource

@export var gold: int = 0
@export var items: Array[Item]
```

Any `SaveKitResource` referenced from a saved node is serialized automatically, and deduplicated. Like nodes, `SaveKitResource` uses reflection over exported properties by default, but you can always implement `save_to_dict` and `load_from_dict` for custom behavior.

Note that plain `Resource` references (textures, scenes, and other things baked into the PCK) are saved as path/UID references. SaveKit will only ever load such resources from within the `res://` filesystem, avoiding the risk of code injection from user-provided resource files.

## Lifecycle hooks

There are a variety of signals and methods to hook into the saving and loading process—`before_save`, `after_save`, `before_load`, `after_load`, etc. See the `SaveManager` API documentation for more details.

## Save file formats

SaveKit includes two built-in file formats:

- **JSON** (`json_serializer.gd`, `json_deserializer.gd`) — human-readable, easy to diff and debug.
- **Binary** (`binary_serializer.gd`, `binary_deserializer.gd`) — compact, obfuscated.

JSON, the default, is recommended in most cases. File size is rarely a concern, and making saves human-readable is more friendly to your players.

You can also implement a custom file format by extending `SaveKitSerializer` and `SaveKitDeserializer` and implementing the abstract methods.

Assign `SaveManager.serializer_script` and `SaveManager.deserializer_script` to switch between formats or use your own:

```gdscript
SaveManager.serializer_script = preload("res://addons/savekit/binary_serializer.gd")
SaveManager.deserializer_script = preload("res://addons/savekit/binary_deserializer.gd")
SaveManager.save_file_extension = ".sav"
```

## Learn more

The [included demo](demo/) has a small interactive scene that is fully saveable, and includes a live view into the JSON file format.

All public classes (`SaveManager`, `SaveKitSerializer`, `SaveKitDeserializer`, `SaveKitResource`) have documentation comments that work with Godot's built-in help. Browse them from the editor for the full API reference.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
