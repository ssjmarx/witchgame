## The CA's second painter (world.md §9): ambiance under the tiles, effects
## over them. CaFx owns the seed, the bank, and the live sealed stencil; the
## background module serves its texture through one slot. Never the CA's stream.

class_name CaFx
extends RefCounted

const TILE := 16   # pixels per tile, the renderer's constant mirrored
const DOMAIN_SALT := 0x50F1A5   # the ambiance domain: room seed XOR this -- a different stream from the CA, by construction

var stone: GridStone
var water: GridWater
var bank: Array[Color] = []   # the active dungeon set -- the module's whole palette
var set_index := 0            # the active set id, 0-3 (the editor's M cycles it)
var _seed := 0                # the domain seed: root of every module's streams
var _sealed: Image            # the live stencil: bank-dark at checker positions, transparent between
var amb: AmbCave              # the background module -- each dungeon gets its own at its lab; today all four sets serve the cave, recolored

## Bind the sim pair, derive the domain seed, and build set zero; FX reads state, it never writes it.
func _init(terrain: GridStone, field: GridWater, p_seed := 0) -> void:
	stone = terrain
	water = field
	_seed = p_seed ^ DOMAIN_SALT
	set_ambience(0)

## Switch the dungeon set: re-point the bank, re-bake the stencil, rebuild the module -- identity is (seed, set), so switching re-derives the whole backdrop deterministically.
func set_ambience(k: int) -> void:
	set_index = wrapi(k, 0, 4)   # wrapi's max is exclusive: the four sets live in [0, 4)
	match set_index:
		1: bank = Palette.BANK_AMBIENCE_RED
		2: bank = Palette.BANK_AMBIENCE_GREEN
		3: bank = Palette.BANK_AMBIENCE_YELLOW
		_: bank = Palette.BANK_AMBIENCE_BLUE
	_bake_sealed()
	amb = AmbCave.new(stone.width, stone.height, bank, _seed)

## The under-pass: serve the module's background, then the live sealed stencil over it, tile by tile -- escape stays the one opinion every shade follows.
func under(image: Image) -> void:
	amb.serve(water.tick_count)
	image.blit_rect(amb.texture, Rect2i(0, 0, image.get_width(), image.get_height()), Vector2i.ZERO)
	for y in stone.height:
		for x in stone.width:
			if water.is_air_sealed(x, y):
				image.blend_rect(_sealed, Rect2i(0, 0, TILE, TILE), Vector2i(x * TILE, y * TILE))

## The over-pass: the effects layer (currents, waves, splashes, bubbles, licks) -- empty until the next lab, wired so the painter's order never changes again.
func over(_image: Image) -> void:
	pass

## Bake the sealed stencil: bank-dark at checker positions, transparent between -- a dithered darkening that composes over any background, generated or authored.
func _bake_sealed() -> void:
	_sealed = Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	_sealed.fill(Color.TRANSPARENT)
	for yy in TILE:
		for xx in TILE:
			if (xx + yy) % 2 == 1:
				_sealed.set_pixel(xx, yy, bank[0])
