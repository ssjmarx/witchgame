## Every color the project draws with, collected in one class of constants.
## Day-one discipline (world.md §9): cold blue-gray base, water blues, and — since
## the fire lab — the warm bank: wood tans, gases, the fire cycle. Swap for DB16 when real art starts.

class_name Palette

# base layer -- the cold blue-gray world
const BG            := Color("#141a2a")
const STONE         := Color("#818b9d")
const STONE_DARK    := Color("#4d5666")

# water -- the blues
const WATER         := Color("#2f5fc0")
const WATER_SURFACE := Color("#7ba4ec")

# oil -- dark ochre gold, its own lane clear of the water blues and the wood tans
const OIL           := Color("#ad7b36")
const OIL_SURFACE   := Color("#ddb066")

# soil -- earth browns: fill, lit lip, soaked band (the damp front)
const SOIL          := Color("#7a5434")
const SOIL_LIP      := Color("#a0744a")
const SOIL_WET      := Color("#3a2514")

# wood -- dusty khaki tan against soil's umber; wet wood is WOOD dithered toward WOOD_DARK, not a third brown
const WOOD          := Color("#b29a66")
const WOOD_DARK     := Color("#5c3d24")

# gases (fire lab) -- pale steam, warm charcoal smoke; hue-split from the cool stone grays
const STEAM         := Color("#c9d6e4")
const STEAM_SURFACE := Color("#e6edf5")
const SMOKE         := Color("#4a443f")
const SMOKE_SURFACE := Color("#6a625b")

# fire -- the 3-frame warm cycle (world §9), hash-keyed per tile, never the PRNG
const FIRE_1        := Color("#d9541e")
const FIRE_2        := Color("#ef8f2a")
const FIRE_3        := Color("#f6c545")

# editor overlays
const GRID          := Color("#232b44")
const CURSOR        := Color("#ffffff")

# debug overlays (G) -- sealed red vs vented teal, then the annotation greens
const DBG_SEALED    := Color("#5e2833")   # trapped air — "why won't my water go in?"
const DBG_OPEN      := Color("#1e4a44")   # vented air
const LEVEL_DBG     := Color("#a0d8c0")   # where seek-level thinks the surface is
const FLOW_DBG      := Color("#5ae682")   # liquid flow arrows
const SOIL_FLOW_DBG := Color("#368c4e")   # solid flow arrows, dimmer than water's
