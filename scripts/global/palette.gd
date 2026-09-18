## Every color the project draws with, collected in one class of constants.
## Day-one discipline (GDD §10): cold blue-gray base, water blues, warm accent
## reserved for fire later. Swap for DB16 when real art starts.

class_name Palette

# base layer
const BG            := Color("#141a2a")
const STONE         := Color("#818b9d")
const STONE_DARK    := Color("#4d5666")

# water
const WATER         := Color("#2f5fc0")
const WATER_SURFACE := Color("#7ba4ec")

# soil
const SOIL 			:= Color8(122, 84, 52)
const SOIL_LIP 		:= Color8(160, 116, 74)

# editor overlays
const GRID          := Color("#232b44")
const CURSOR        := Color("#eef0f4")

# debug overlays (G)
const DBG_SEALED    := Color("#5e2833")   # trapped air — "why won't my water go in?"
const DBG_OPEN      := Color("#1c3a39")   # vented air
const LEVEL_DBG     := Color("#a0d8c0")   # where seek-level thinks the surface is
const FLOW_DBG 		:= Color("5ae682ff")
