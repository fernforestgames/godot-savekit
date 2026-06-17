## A saveable node with typed collection properties (typed Array and typed
## Dictionary), for reproducing https://github.com/fernforestgames/godot-savekit/issues/14
##
## Does NOT implement save_to_dict / load_from_dict, so the default reflection-based
## load path (which calls set()) is exercised.
extends Node

@export var numbers: Array[int] = []
@export var scores: Dictionary[String, int] = {}
