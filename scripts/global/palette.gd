## Every color the project draws with, collected in one class of constants.
## Day-one discipline (world.md §9): cold blue-gray base, water blues, warm accent
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
const SOIL 			:= Color(0.478, 0.329, 0.204, 1.0)
const SOIL_LIP 		:= Color(0.627, 0.455, 0.29, 1.0)
const SOIL_WET		:= Color(0.226, 0.146, 0.078, 1.0)

# editor overlays
const GRID          := Color("#232b44")
const CURSOR        := Color("#eef0f4")

# debug overlays (G)
const DBG_SEALED    := Color("#5e2833")   # trapped air — "why won't my water go in?"
const DBG_OPEN      := Color("#1c3a39")   # vented air
const LEVEL_DBG     := Color("#a0d8c0")   # where seek-level thinks the surface is
const FLOW_DBG 		:= Color("5ae682ff")
const SOIL_FLOW_DBG	:= Color("368c4eff")
