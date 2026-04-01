## A saveable node that does NOT implement save_to_dict / load_from_dict,
## so SaveManager must fall back to the default reflection-based approach.
extends Node

@export var health: int = 100
@export var player_name: String = ""

# @export_storage should work equally well
@export_storage var score: float = 0.0
