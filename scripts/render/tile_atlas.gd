## The 8x8 tile atlas map (tileset lab): the one layout shared by the baker
## (placement) and the renderer (blits) -- role name to pixel rect. Every bank
## colors the same layout; the files live under assets/baked/ (pipeline law).

extends RefCounted

const GRID := 8   # cells across the atlas; five rows hold every role
const CELL := 8   # pixels per cell -- the matter grid's own resolution

## role -> atlas rect in pixels; lip and seam strips are 8x1 / 1x8 overlays.
const LAYOUT := {
	"stone_fill": Rect2i(0, 0, 8, 8),
	"stone_lip_t": Rect2i(8, 0, 8, 1), "stone_lip_r": Rect2i(16, 0, 1, 8),
	"stone_lip_b": Rect2i(24, 0, 8, 1), "stone_lip_l": Rect2i(32, 0, 1, 8),
	"stone_seam_t": Rect2i(40, 0, 8, 1), "stone_seam_r": Rect2i(48, 0, 1, 8),
	"stone_seam_b": Rect2i(56, 0, 8, 1), "stone_seam_l": Rect2i(0, 8, 1, 8),
	"wood_fill": Rect2i(8, 8, 8, 8),
	"wood_lip_t": Rect2i(16, 8, 8, 1), "wood_lip_r": Rect2i(24, 8, 1, 8),
	"wood_lip_b": Rect2i(32, 8, 8, 1), "wood_lip_l": Rect2i(40, 8, 1, 8),
	"wood_seam_t": Rect2i(48, 8, 8, 1), "wood_seam_r": Rect2i(56, 8, 1, 8),
	"wood_seam_b": Rect2i(0, 16, 8, 1), "wood_seam_l": Rect2i(8, 16, 1, 8),
	"soil_fill": Rect2i(16, 16, 8, 8), "soil_lip_t": Rect2i(24, 16, 8, 1),
	"soil_damp_25": Rect2i(32, 16, 8, 8), "soil_damp_50": Rect2i(40, 16, 8, 8),
	"soil_damp_75": Rect2i(48, 16, 8, 8), "soil_damp_full": Rect2i(56, 16, 8, 8),
	"smoke_25": Rect2i(0, 24, 8, 8), "smoke_50": Rect2i(8, 24, 8, 8),
	"smoke_75": Rect2i(16, 24, 8, 8), "smoke_full": Rect2i(24, 24, 8, 8),
	"steam_25": Rect2i(32, 24, 8, 8), "steam_50": Rect2i(40, 24, 8, 8),
	"steam_75": Rect2i(48, 24, 8, 8), "steam_full": Rect2i(56, 24, 8, 8),
	"fire_ember_0": Rect2i(0, 32, 8, 8), "fire_ember_1": Rect2i(8, 32, 8, 8),
	"fire_ember_2": Rect2i(16, 32, 8, 8), "fire_lick_0": Rect2i(24, 32, 8, 8),
	"fire_lick_1": Rect2i(32, 32, 8, 8), "fire_lick_2": Rect2i(40, 32, 8, 8),
}

## kind name -> the bank-colored bake; every file shares LAYOUT.
const FILES := {
	"stone": "res://assets/baked/tiles_stone.png",
	"wood": "res://assets/baked/tiles_wood.png",
	"soil": "res://assets/baked/tiles_soil.png",
	"smoke": "res://assets/baked/tiles_smoke.png",
	"steam": "res://assets/baked/tiles_steam.png",
	"fire": "res://assets/baked/tiles_fire.png",
}

## kind name -> the bank that colors it; the baker reads this, and so does the palette suite's file gate.
const BANKS := {
	"stone": Palette.BANK_STONE, "wood": Palette.BANK_WOOD, "soil": Palette.BANK_SOIL,
	"smoke": Palette.BANK_SMOKE, "steam": Palette.BANK_STEAM, "fire": Palette.BANK_FIRE,
}

## Load every atlas from its imported bake; returns kind name -> Image. Call once at renderer build.
func load_atlases() -> Dictionary:
	var out := {}
	for kind in FILES:
		var t := load(FILES[kind]) as Texture2D
		if t == null:
			push_error("tile atlas missing: %s -- run bake_tiles.gd and let the editor import" % FILES[kind])
			continue
		out[kind] = t.get_image()
	return out