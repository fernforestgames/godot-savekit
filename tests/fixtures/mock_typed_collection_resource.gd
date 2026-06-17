## A SaveKitResource with typed collection properties (typed Array and typed
## Dictionary), mirroring the README's `Array[Item]` example, for reproducing
## https://github.com/fernforestgames/godot-savekit/issues/14
##
## Uses the default reflection-based SaveKitResource.load_from_dict (which calls
## set()), so it exercises the resource load path rather than the node one.
extends SaveKitResource

@export var numbers: Array[int] = []
@export var scores: Dictionary[String, int] = {}
