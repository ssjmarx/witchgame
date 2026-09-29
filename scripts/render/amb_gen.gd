## The background module contract (world.md §9): a texture served whole,
## refreshed by serve() when the module animates. Modules are world-blind --
## layout pure in the seed, animation pure in seed and slot; live reads (the sealed stencil) belong to CaFx alone.

class_name AmbGen
extends RefCounted

var texture: Image   # the served background, map-sized, opaque

## Refresh the texture for the given tick -- animated modules override; still modules inherit the no-op.
func serve(_tick: int) -> void:
	pass
