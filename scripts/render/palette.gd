## The palette law (world.md §9): one master -- DB16 plus documented guests --
## tile banks of at most four, sprite banks of at most three plus transparency,
## and no hex literal drawn outside this file.

class_name Palette

# -- Master: DB16 canonical, named so banks read without index math ------
const INK        := Color("#140c1c")   # near-black
const PLUM       := Color("#442434")   # dark maroon
const INDIGO     := Color("#30346d")   # deep blue
const TAUPE      := Color("#4e4a4e")   # warm gray
const RUST       := Color("#854c30")   # brown
const MOSS       := Color("#346524")   # dark green
const RED        := Color("#d04648")
const OLIVE      := Color("#757161")   # khaki gray
const CORNFLOWER := Color("#597dce")   # the water blue
const ORANGE     := Color("#d27d2c")
const SLATE      := Color("#8595a1")   # blue-gray
const GREEN      := Color("#6daa2c")
const TAN        := Color("#d2aa99")   # pink-tan
const CYAN       := Color("#6dc2ca")
const YELLOW     := Color("#dad45e")
const BONE       := Color("#deeed6")   # off-white
const MASTER: Array[Color] = [INK, PLUM, INDIGO, TAUPE, RUST, MOSS, RED, OLIVE, CORNFLOWER, ORANGE, SLATE, GREEN, TAN, CYAN, YELLOW, BONE]

# -- Guests: additions beyond DB16, one # reason per color -- the lock is procedural, never a ceiling
# -- Guests: additions beyond DB16, one # reason per color -- the lock is procedural, never a ceiling
const FLOOR_BLUE     := Color("#0e1628")   # the blue dungeon's floor: midnight navy, the whisper set
const MASONRY_BLUE   := Color("#142440")   # the blue dungeon's bricks, pillars, and flutes
const GLINT_BLUE     := Color("#182c50")   # the blue dungeon's glint
const FLOOR_RED      := Color("#3a1614")   # the red crypt's floor -- its masonry is RUST, its glints RED, both master
const FLOOR_GREEN    := Color("#14291a")   # the green grotto's floor -- its masonry is MOSS, its glints GREEN, both master
const FLOOR_YELLOW   := Color("#382812")   # the sandstone catacomb's floor
const MASONRY_YELLOW := Color("#7d6032")   # the sandstone catacomb's masonry -- its glints are TAN, master
const GUEST: Array[Color] = [FLOOR_BLUE, MASONRY_BLUE, GLINT_BLUE, FLOOR_RED, FLOOR_GREEN, FLOOR_YELLOW, MASONRY_YELLOW]

# -- Tile banks: at most four, index 0 darkest, a material's whole face ------
const BANK_AMBIENCE_BLUE: Array[Color] = [INK, FLOOR_BLUE, MASONRY_BLUE, GLINT_BLUE]    # the whisper set
const BANK_AMBIENCE_RED: Array[Color] = [INK, FLOOR_RED, RUST, RED]                     # the brick crypt
const BANK_AMBIENCE_GREEN: Array[Color] = [INK, FLOOR_GREEN, MOSS, GREEN]               # the moss grotto
const BANK_AMBIENCE_YELLOW: Array[Color] = [INK, FLOOR_YELLOW, MASONRY_YELLOW, TAN]    # the sandstone catacomb, the loudest set
const BANK_STONE: Array[Color] = [TAUPE, SLATE, BONE]               # seam, fill, bevel lip
const BANK_WOOD: Array[Color] = [PLUM, OLIVE, TAN]                  # plank seam, plank, lit edge
const BANK_SOIL: Array[Color] = [PLUM, RUST, TAN]                   # soaked band, fill, dry lip
const BANK_WATER: Array[Color] = [INDIGO, CORNFLOWER, CYAN, BONE]   # depth shade, body, wave shimmer, foam sparkle
const BANK_OIL: Array[Color] = [RUST, OLIVE, YELLOW]                # depth, body, sheen
const BANK_ACID: Array[Color] = [MOSS, GREEN, YELLOW, BONE]         # deep, body, bright, fume sparkle
const BANK_LAVA: Array[Color] = [INK, PLUM, RED, ORANGE]            # moving flecks, crust, body, hot surface
const BANK_SMOKE: Array[Color] = [PLUM, TAUPE]                      # body, surface
const BANK_STEAM: Array[Color] = [SLATE, BONE]                      # body, surface
const BANK_FIRE: Array[Color] = [RUST, RED, ORANGE, YELLOW]         # ember dark, then the flame cycle brightward

# -- Sprite banks: at most three plus transparency; the outline is a bank color ------
const SPRITE_WITCH: Array[Color] = [INK, INDIGO, RED]   # placeholder until her sheet is re-quantized (her look is witchgame.md's)

# -- Debug and editor overlays: exempt from the law, never shipped art ------
const DEBUG_GRID      := Color("#232b44")
const DEBUG_CURSOR    := Color("#ffffff")
const DEBUG_SEALED    := Color("#5e2833")
const DEBUG_OPEN      := Color("#1e4a44")
const DEBUG_LEVEL     := Color("#a0d8c0")
const DEBUG_FLOW      := Color("#5ae682")
const DEBUG_SOIL_FLOW := Color("#368c4e")
