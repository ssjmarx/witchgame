# `world.md` — THE WORLD: Shared Engine & Simulation GDD v1.3

*The foundation under both games. The witch doc and the magical girl doc are deltas on this one; where a game doc disagrees with this doc about engine behavior, this doc wins. Where this doc and the code disagree, the code wins — `TilePacket`, `GridWater`, `GridSand`, and `GridReactions` are already code, and the shipped sections below are written from them.*

**Scope.** This doc owns: the room model, the cellular automata, the bridge, the actor shell and contact contract, the enemy frame, the lasso core, doors, pockets, death and lives machinery, the rendering and light rig, the level format, and the generator/checker framework. The game docs own: verbs, aiming, rosters, rooms, economies, and presentation. One 10 Hz integer world that renders itself; two heroines who visit it at 60 fps through the same customs office.

**Where the code stands** *(synced at `2582b3b`)*. Shipped and therefore authoritative: the packet and its ledger (§2 as shipped), the terrain/liquid/solids/reactions quartet — `GridStone`, `GridWater`, `GridSand`, `GridReactions` — (§3 all-liquid movement densest-first with viscosity, the density sort pass, pressure-head seek level, displacement, both flow exports, soil/stone/ice movement, damp and soak), the renderer and palette (§9 lines marked *shipped*), and the `TestSandbox` harness with the water, packet, soil, and oil acceptance suites (six water examples, four packet tests, ten soil examples, eight oil examples — 3000 ticks to equilibrium, all through the shared drift-watched runner). Not yet code: the room model, oil's fire rules and acid/lava/gas behavior, fire, the driers, freeze/thaw, the bridge (§4), the actor machinery (§5–§8), the light rig, and the level format (§10). Shipped prose names its source; planned prose is design-ahead-of-code and says so.

**Changelog v1.3 — oil ships (`2582b3b`)**

- **GridWater is the liquid engine, not the water engine:** every pool liquid runs the four movement rules as its own pass, densest-first (`MOVERS` = lava, acid, water, oil — the loop order IS the drain order; gases join at the float lab). Oil flows, sinks under water, floats, and stratifies
- **Viscosity ships** (`VISCOSITY` = water 255, oil 32, acid 255, lava 16, smoke/steam 255): a throughput cap on every flow move — fall, pour, creep, seek-level transfer. It never changes an equilibrium, only the pace of arriving
- **The density sort pass is code:** vertically adjacent tiles trade when denser sits above lighter — pair rate = the slower material's SORT_RATE, take-both-then-add-both. Oil floats on water (OT1) and the three-phase basin stratifies (OT3) inside the 3000-tick window
- **Seek level runs on true pressure:** heads are density-weighted column integrals (Σ units × DENSITY) from each column's surface to the run row — hydrostatic pressure at the choke; the actionable floor is PRESSURE_MIN_DIFF × density; donors must carry m at the conduit row; a failed transfer falls through to the next pair (no more first-pair-wins-or-bust)
- **RISE_MIN_DIFF and CELL_UNITS retired:** the rise into headroom is density-aware — a full entry makes room by ejecting lighter residents in place, thickening at the interface, or, only at diff ≥ POOL_MAX × ρ, rising into escape-vented air above the m-surface. Deposits land at m's surface, the pool floor (m sinks), or the pool surface (m floats)
- **Displacement factored:** `_eject_lightest_up` is shared by rule five and the transfer pass; the displacement pass runs at the tick head, before the movers
- **Oil acceptance suite (OT1–OT4, UT1–UT4):** float, mixed-tile drain, three-phase stratification, soil sinks through oil (oil never soaks — the soak pass reads water only), the manometer equalizes by pressure, corner-dump spread, a sealed chamber refuses the trade, oil overtops while water never follows. The runner is shared now — one `_run_example` with a per-engine drift watch, per-material conservation, and subtile-mass checks; the water and soil suites route through it
- **Rendering:** liquids stack in one tile by material share, densest at the bottom, crest on the topmost material; oil gets its own palette rows (dark ochre, far from the water blues); waterfall streaks tint by the majority liquid; acid/lava/smoke/steam alias water colors until their labs
- **TEMP:** `GridWater.trace_seek` — the U-bend hunt's logging flag; delete when closed

**Changelog v1.2 — damp ships (`1bb3c45`)**

- **Damp is code (Lab E):** capacity **32 per soil subtile** (full tile: 128), exchanged **1:1** with water and steam — the retune from the old 64/2:1 design, and it preserves the worked example exactly: a full water tile over full soil soaks to **127** with the soil saturated at 128. DAMP and TAGS are packet columns; the ledger's tenth row books damp at 1:1. Doctrine law 5 splits: actor wetness stays 2:1, tile damp is 1:1 — two water-equivalences in one ledger
- **The reaction engine is the third system** (`GridReactions`): GridWater owns liquid motion, GridSand owns solid motion, reactions own transformation — pure packet transforms reading settled state, running after both movement passes, owning the packet assert while last. Reaction #1 is **soak**: a water-bearing tile drinks clamp(w/16, 1, 16) per tick into the first headroom down its column, passing through saturated soil (the **percolation skip** — the search moves, damp doesn't); a deep pool soaks only through its bottom tile
- **Wet tags — the body-state system's first brick:** a tags column of bit flags; WET gained above 50% of damp capacity, lost below 30% — hysteresis, because the tag is state. Per-tile for solids; connected-body tags for liquids are the planned extension
- **Moisture is mortar:** a wet tile reads the sticky row — no loose kind slides (mud glues stone); fall is never gated. Transit soil soaking mid-fall can freeze mid-column: suspended mud, emergent, accepted
- **Solid flow export:** GridSand carries its own flow arrays in water's pattern (wiped at its tick head, magnitudes sum, dominant direction); one tile-crossing subtile stamps **64 pool-units**, so rockslides and waterfalls read on one scale — two crossings = 128 > DIFFUSER_FLOW, a rockslide is a diffuser (intended, review-flagged)
- **Damp rides crossings:** a departing soil subtile carries an even share of its tile's damp (≤ 32) by unbooked transfer; the strand clamp moved **post-write** — the ST5 root cause was the clamp reading pre-write capacity and destroying legally carried damp on arrival writes. Law learned: **a guard evaluates the post-state**
- **Harness:** conservation is water + damp at 1:1; the per-engine **drift watch** pins the first offending tick and engine (a contiguous before/after fork — exhaustive, so drift cannot escape attribution); the soil suite is ten examples (ST1–ST10)
- **DRY re-priced by the retune (flagged, planned):** at 1:1, underfoot drying yields 8 steam/s and costs 8 heat/s (was 4/4); the witch's damp-wall grind halves (16 fizzles per full tile, was 32). Re-tune at the bridge lab

**Changelog v1.1 — synced to code (`d199585`, "soil! solids!")**

- **§2 rewritten from `TilePacket` as shipped:** ten structure-of-arrays columns (terrain, three subtile nibbles, six pool materials) plus a nine-row per-room ledger asserting every tick. FUEL, FIRE, DAMP, SURFACE, FLAGS are planned fields, arriving with fire and bridge work — they are not in the bytes today
- **One loose-solids field, no LOOSE flag:** every stone/soil/ice subtile falls and slides (`GridSand`); the flag — static stone unless marked — is the planned refinement. New shipped rulings: soil sinks through water, stone sinks faster, ice rests buoyant (no rising yet — the float lab)
- **Water rules updated from `GridWater`:** rise into headroom needs a full cell of head (RISE_MIN_DIFF 256) and escape-reachable headroom; top-up hysteresis PRESSURE_MIN_DIFF 2; a sub-line film (≤ 15) is air for pocket purposes; seek level moves one workable pair per run per tick; displacement ejects up the tile's own column, lightest material first, landing at the first free escape-reachable tile
- **Rendering split shipped/planned:** line fills and crest, the soil squeeze lift, waterfall streaks, soil quads, and debug overlays are code; dithering, shimmer, palette banks, and the light rig are not. Sub-line films draw nothing by design; stone and ice subtiles are not yet drawn
- Constants table split the same way: DIFFUSER_FLOW = 96 (was `<tune>`); FLOW_RATE = 3 retired — no such constant ever shipped; window 720×720; Godot 4.5
- Coyote time, jump buffering, ledge tolerance moved to E3 — no actor code exists yet. The determinism rig stays planned: the shipped engine is PRNG-free (pass order + sweep parity), and render randomness is already hash-keyed

**Changelog v1.0**

- Extracted from `witchgame.md` v2.1 §1–§4 and its shared systems; the game docs become deltas
- **The bridge:** every actor carries **heat** and **wetness**; the CA stores no temperature, ever. All exchanges are integer quanta at 10 Hz; steam is the universal heat sink
- **HOT = 63 (SACRED).** Vents round up: 255 → 128 → 64 → 32 — three throws from blazing, two of them incendiary. Gains retuned: flap +4, dash +8, fire +4/t, lava +8/t
- **DRIP** is universal: ~4 water/s randomized, 2 wetness per water — every wet actor is a walking, leaking water source (~32 s carry window at saturation)
- **Smolder is CA-side** with hysteresis: HOT overlap or a game stimulus (the beam's burn band) builds a 4 s warning before ignition. Tags are fuel objects and get the warning too
- **Actors cross doors; atoms never.** Player-facing doors always mark room boundaries — the crossover/coop contract. Door crossing is the conservation interface
- **Pits are pockets:** one-way capture fixtures, any orientation, evil aura rendered on every one. Matter in = sanctioned loss; actors in = captured
- **Contact contract:** Godot physics owns detection and motion; actor modules own response. No actor code writes tiles — everything through work orders
- **Stun is flat 10 s**, universal. The lasso core is identical for both girls; differences live in projectile modules and frame data
- **Lives: 3** for both; 0 → level reset
- Determinism: one `RandomNumberGenerator` per room, advanced only inside the tick; all rates are stochastic integer events hitting an expected value

## 0. Doctrine

The laws. When in doubt, these decide.

1. **The picture is the state.** The sim renders itself; nothing draws what isn't true, and nothing true goes undrawn.
2. **Two layers, one customs office.** Actors live at 60 fps and carry heat and wetness. Matter lives at 10 Hz and carries neither. The bridge is the *entire* interface between them.
3. **Magic is the only fidelity break — localized per game.** Each game doc declares its exemptions (her lantern, her halo). The *consequences* of magic — steam, scorch, smolder, melt — are physical and stay inside the GBC bounds.
4. **Every exchange is an integer quantum.** No partial conversions, no rounding loss. All sub-tick rates are stochastic integer events tuned to an expected value; the PRNG makes them lumpy, the ledger only ever sees whole units.
5. **Steam is the universal heat sink.** 1 heat + 1 pool water → 1 steam. Actor wetness is half-density (2 wetness per water); soil damp is full-density (1:1) — two water-equivalence rates in one ledger, never conflated. Heat leaves actors only as steam.
6. **Actors cross doors; atoms never.** DOOR is always solid to CA flow, open or closed. Player-facing doors always mark room boundaries.
7. **Matter is conserved except at sanctioned sinks** — boundary flux, pockets, acid decay. The ledger asserts every tick; a drift is a bug, not a rounding error.
8. **The engine says what is moving and what is colliding; the actors decide what it means.**
9. **Determinism:** one PRNG per room, advanced only inside the tick. Render-side randomness is hash-based and never consumes sim entropy.
10. **Where the code and this document diverge, the code wins.**
11. **Some mechanics are occult.** The games decide which; the engine ships no tutorials.

## 1. Tech setup

- Godot 4.5, GDScript. Viewport 240×240, window 720×720, stretch viewport, integer scaling, nearest filtering *(shipped — `project.godot`; a second rig runs 4.7 — same-seed replay is engine-version-scoped)*
- Tiles: 16×16, each four 8×8 subtiles. Visible area 15×15 *(shipped — the harness runs one fixed 15×15 grid)*
- Element tick: fixed 10 Hz, integer only, deterministic. Render 60 fps; simulation never does *(shipped — the sandbox timers tick at 0.1 s)*
- Rooms freeze when unobserved (the room containing the camera simulates). A one-room level is always live *(planned — no room model yet; the harness is one grid, always live)*
- Coyote time, jump buffering, ledge tolerance ride the actor shell *(planned — E3; no actor code exists)*
- **Performance discipline:** the CA runs in typed packed arrays (`PackedByteArray` and friends) — that part is shipped. Allocation-free ticks and a native hot loop are targets, not current fact: today the whole engine is GDScript and a tick does allocate (level snapshots, per-run arrays). Actors will ride Godot's C++ physics. Escape hatch: C#/GDExtension if profiling ever demands
- **Room size is an authoring decision, not a budget.** Small rooms mean tight challenges; big rooms mean lots of atoms. The GBC aesthetic is a style, not a hardware constraint. Profile the ceiling on target hardware once the engine is finished; grow from there. *(Open item.)*
- **Determinism rig:** one `RandomNumberGenerator` per room, `seed = level_seed ⊕ room_id`. Derive the room's fixed tile permutation at load, then advance per tick. Actor order is a per-tick PRNG shuffle. *(Planned — arrives with the stochastic rates of §4; the shipped engine is PRNG-free, deterministic by pass order and alternating sweep parity.)* Render effects key on (tile hash, tick count), never wall-clock, never the PRNG *(shipped — the streak hashes)*.

## 2. Data model

**Per-tile packet — as shipped** (`TilePacket`): structure-of-arrays — one `PackedByteArray` column per field, one row per tile, the tile index is the row number. Twelve bytes per tile, plus a ten-row per-room ledger:

```
TERRAIN : AIR, STONE, WOOD, SOIL, BRAZIER, SPIKE, DOOR, DOOR_CLOSED
STONE_S : 4-bit occupancy — carve/cast granularity; every subtile column is loose in the
		  current engine — the LOOSE flag (static unless marked) is the planned refinement
SOIL_S  : 4-bit occupancy — the nibble IS the matter (popcount = mass)
ICE_S   : 4-bit occupancy — displaces 64; the 32-water freeze/thaw exchange is planned
WATER, OIL, ACID, LAVA, SMOKE, STEAM : each 0–255 — the content pool
DAMP    : held by soil — 32 capacity per soil subtile, 1:1 with water and steam
TAGS    : bit flags per tile — WET shipped; poisoned/tainted/holy/fertile are planned rows
LEDGER  : ten rows — six materials, three subtile kinds, damp; double-entry, asserted every tick
FLOW    : exported per tile per tick (direction + strength) — derived, not matter — one export
		  per engine: GridWater for liquid arrivals, GridSand for solid crossings
```

**Planned fields — none in the bytes today;** they arrive with fire and the bridge: FUEL (0–255, attached to solids — vine 60, wood 255, coal 255), FIRE (0–255, burning state, requires open air), SURFACE (NONE, MOSS, VINE, COAL, SLIME, GLAZE), FLAGS (COLD, LIT, SCORCHED, structural).

**The content pool.** Water, oil, acid, lava, smoke, and steam are separate 0–255 fields sharing one budget: their total in a tile never exceeds 255, reduced 64 per solid subtile of any kind — and only AIR and SOIL terrain holds a pool at all; every other terrain value is a full solid, capacity 0. Mixtures are allowed; an over-budget tile ejects through the displacement rule — lightest material first, never destroyed. The density table is shipped (water 30, oil 20, acid 40, lava 50, smoke 10, steam 5 — the rest stack, heaviest at the bottom, gas on top) and drives lightest-first ejection, the seek-level pressure heads, and the shipped sort pass today (SORT_RATE, units per tick toward the rest layer — steam out-climbs acid's sink 8:1 — one trade per pair per tick); the reaction matrix is planned, and the layering render ships only for liquids with palette entries (water, oil) — acid, lava, and the gases alias water colors until their labs. DAMP, FUEL, and FIRE belong to solids and live outside the pool. Gas thresholds rescale to 0–255 density.

**The actor state block** *(planned — no actors yet)*. Every actor — heroine, enemy, pot, thrown ball — carries:

```
heat      : 0–255                 # thermal currency; actor-layer only
wetness   : 0–254, even only      # the 2:1 lattice; SATURATED ≡ 254
weight    : byte + class L/M/H    # per-game resolution reads this
archetype : behavior + projectile profile + landed state
drip_mul  : drip rate multiplier (0 = holds its water)
trajectory: ring buffer, ~1 s of position + heading at 60 fps
holdings  : pot contents, held-enemy refs — ledger-visible
```

Heroes are 16×32 and span two tiles; every thermal operation picks one overlapped tile per tick via the PRNG (drip target, absorb source, boil site, steam emission). Underfoot operations (DRY, MELT) target the supporting tiles.

**The smolder overlay** *(planned)*. A runtime per-fuel-tile timer, not packet data. Room resets clear it; snapshots don't carry it.

**Room record:** baseline / saved bytes / saved enemies / tagged / enemy_baseline, plus held-enemy exclusion marks — captured enemies are out of the baseline; nothing duplicates across a door.

**Conservation ledger.** The shipped core is `TilePacket`'s ten rows — the six pool materials, the three subtile kinds, and **DAMP at 1:1 water-equivalent** — asserted every tick alongside the per-tile pool constraint (Σ content ≤ capacity, no two subtile kinds claiming one cell) and the damp constraint (damp ≤ 32 × soil popcount); a drift is a bug. Planned rows and books extend it: LAVA at 64:1, ICE at 32:1, reactions as balanced integer transfers, plus **boundary-flux** (exteriors, waterfalls, rain), **pocket-loss** (sanctioned destruction — the ledger calls it fine), **fauna flux** (spawn-stream entries and exits, booked like rain), and **actor holdings** — wetness at 2:1 water-equivalent, pot interiors, held enemies — attached and detached as flux, transferred at doors.

## 3. Element simulation

The shipped tick — one room, fixed order. The ruling is **solids, then liquids, then reactions**: sand's repack deficits are resolved by water's displacement pass the same tick, reactions read settled matter, and the reaction tick owns the packet assert (last engine's privilege — the full engine's ledger assert lands at the very end of `element_tick`).

```gdscript
# shipped today — the harness calls exactly this, in this order:
sand.tick()     # GridSand: flow reset -> expand the packet nibbles -> subtile pass, bottom-up,
				#   alternating sweep (tile crossings stamp solid flow and carry damp) ->
				#   repack (popcount deltas booked)
water.tick()    # GridWater: flow reset -> level snapshot -> analyze (bodies, regions, escape)
				#   -> displacement pass -> per-material cell pass densest-first (MOVERS: lava,
				#   acid, water, oil; every move viscosity-capped) with seek level after each
				#   material -> density sort pass -> volume + ledger asserts -> levels_changed
react.tick()    # GridReactions: soak pass (water -> damp, percolation skip) -> tag pass (wet
				#   hysteresis) -> the packet assert (reactions run last)
```

The full build adds the passes below — all *planned* except the reaction pass, which ships with soak as its only row. Order stays a ruling: work orders at the head (bridge in, matter out), matter next, chemistry after movement, render last and never coupled. **Every rule in this doc is integer-only, deterministic, and free of the render clock.**

```gdscript
func element_tick(room):               # the full engine, once built
	var order = room.permutation        # fixed, derived from the room PRNG at load
	_apply_work_orders()               # THE BRIDGE — buffered actor orders,
									  # tile order, then per-tick PRNG actor shuffle
	_sand_pass(order)                  # loose subtiles first (GridSand, shipped above)
	_liquid_pass(order)                # liquids next (GridWater, shipped above): oil, acid, lava
	_seek_level(); _export_flow()
	for idx in order: _reaction_pass(idx)  # transformations (GridReactions, shipped: soak) — chemistry after movement
	for idx in order: _fire_pass(idx)
	for idx in order: _gas_pass(idx)
	for idx in order: _growth_pass(idx)
	for idx in order: _phase_pass(idx)  # freeze, thaw, heat-melt, cast, glaze
	for idx in order: _smolder_pass(idx) # fuel warnings: build / hold / decay / complete
	ledger.assert_all()                # materials + pool + per-actor heat and wetness
```

**Liquids — GridWater is authoritative.** Built and tested; where this document and the code diverge, the code wins. Every pool liquid runs the same four rules as its own pass, densest-first (`MOVERS` = lava, acid, water, oil — the loop order IS the drain order; gases join at the float lab), every move capped by the material's viscosity — a throughput limit that never changes an equilibrium, only the pace of arriving. Rules as shipped: FALL (exclusive, instant — up to the viscosity cap of what fits goes one tile down; columns fall coherently), POUR (over lips into dry space only — the target below one line — corner-safe, air-gated), CREEP (half-difference into dry space, capped and gated), SEEK LEVEL (each horizontal run is one incompressible conduit; per run per tick, one workable pair trades volume surface-to-surface — up to PRESSURE_RATE, capped by half the pressure difference, the receiving room, and viscosity; pressure heads are density-weighted column integrals from each column's surface to the run row — hydrostatic pressure at the choke, so oil's units weigh less than water's; the actionable floor is PRESSURE_MIN_DIFF × density; donors must carry m at the conduit row; a failed transfer falls through to the next pair; a full capped column between two heads is a rigid pipe). **The density sort pass** closes the liquid work: vertically adjacent tiles trade when denser sits above lighter — the upper's densest sinks, the lower's lightest rises — pair rate = the slower material's SORT_RATE, one trade per pair per tick, take-both-then-add-both so a full tile's freed budget always covers the incoming units. Invariant: every move downhill-or-level; Σ(units × density × height) never increases. Air is gated, not simulated — never stored, never swapped: each tick's analyze pass marks which air can reach open sky (escape) and which pocket it belongs to, and the gates rule on those marks — (a) escape to open sky, (c) the donor's own receding headspace, (d) rotation (pocket and body also touch higher up) — with sub-line films (≤ AIR_PASSABLE_MAX) passing freely as same-pocket shuffles. Determinism: alternating sweep per tick; the escape flood is an order-independent monotone fixpoint. Scan-order guarantee: each cell's pass runs once per tick; vertical moves only deposit into already-scanned rows; lateral CREEP cascades are convergent and intended. Pool-aware capacity: arriving liquid competes with resident liquid and gas for the budget; overflow displaces per the rule below.

*Known approximations (accepted):* region labels one tick stale; donor headspace freely expandable; divided vessels can rest one line off level. *Shipped since that note was written:* rises into headroom escaped-to-sky exist — the threshold-gated rise above a full m-surface (diff ≥ POOL_MAX × ρ, escape-gated up the receiving column); pocketed headroom keeps the gate. Retired with v1.3: the head-unit rise rule (RISE_MIN_DIFF 256) — rise is priced in pressure, not head cells.

**Displacement** *(shipped — rule five, `GridWater._displacement_pass`)*. A solid subtile reduces the tile's pool capacity by 64; four subtiles is fully solid. When capacity drops below current content, the excess ejects up its own column — solids sink, liquid climbs — depositing at the first free, escape-reachable tiles, **lightest material first** (steam before smoke before oil before water). Leftover excess persists to the next tick; the entry gates (the sand rules' landing check) should have prevented it. Matter is displaced, never destroyed.

**Flow export** *(shipped — one per engine)*. GridWater exports liquid arrivals; GridSand exports solid crossings — one subtile arrival stamps 64 pool-units (SUB_FLOW_MASS), so a landslide and a waterfall read on one scale (two crossings = 128 > DIFFUSER_FLOW: a rockslide is a diffuser — intended, review-flagged). Both follow the same pattern: arrays wiped at the owning engine's tick head, magnitudes sum, dominant direction by largest single arrival, first stamp wins ties. Gameplay *(planned consumers)*: pushes actors and loose objects (capped vs. walk speed). Rendering *(shipped consumers)*: strong downward flow draws waterfall streaks (above **FLOW_STREAK**); the debug overlay draws both engines' arrows. A tile with liquid-in-transit above **DIFFUSER_FLOW** is a *diffuser* — the condition is exported (the constant ships; consumers are game-side — the witch's beam cannot pass one). Consumers also read coarse level bands — DRY / WET / HALF / FULL — off `levels_changed`; fine units stay internal.

**Soil (subtiles)** *(shipped — `GridSand`, ST1–ST10)*. 4-bit occupancy; popcount is matter, Σ popcount asserted every tick by the ledger's SOIL_S row. All sixteen shapes representable — transient shapes during falls and slides are the animation. Stability is what the rules produce, not a stored constraint. Moves as shipped: fall if below empty — one subtile per tick through air, gated single-cell sub-steps so nothing tunnels; through liquid, sink at the material's SUB_SINK rate (soil 1, stone 2, ice −1 = buoyant, rests — rising is the float lab, not yet code); slide diagonally if the diagonal-below is empty and the side is clear (corner rule); repose emerges — settled neighbors differ by ≤ ~1 subtile; piles are 8px staircases. 8px is a hop, never an auto-step. A landing subtile must find the tile enterable: terrain that holds a pool, and either the budget fits (255 − 64 per subtile) or the displaced liquid has escape-reachable headroom up the column (air-gate family). Soil sinks through water and the water closes in above it (ST4); a sealed basin exchanges soil for water exactly, one subtile per 64 (ST5); a sealed column refuses the exchange outright (ST6). *Shipped (Lab E):* moisture is mortar and damp is code — capacity 32 per soil subtile, exchanged 1:1 with water and steam (a full tile: 128; a full water tile over full soil soaks to exactly 127). Soak runs in the reaction pass: a water-bearing tile drinks clamp(w/16, 1, 16) per tick into the first headroom down its column — its own soil, else through saturated soil below (the percolation skip: the search moves, damp doesn't); a deep pool soaks only through its bottom tile; water never soaks across air, water-only tiles, or full-solid terrain. Damp rides crossings — a departing soil subtile carries an even share of its tile's damp (≤ 32). A tile gains the **WET** tag above 50% of damp capacity and loses it below 30%; a wet tile reads the sticky row — **no slide for any kind, fall never gated**. Render: pixel lines from the top of the occupied region, 8 damp per line — the creeping front. *Planned:* every drier — DRY underfoot (§4.2), fire's steam siege, FIZZLE — the bridge and fire labs; the first drier to ship is what makes fire drying a wet slope the landslide trigger (buries fire, spikes, enemies). Until one ships, damp only grows.

**Stone subtiles** *(shipped loose — `GridSand`; the flag is planned)*. In the current engine every stone subtile runs the sand rules — fall, corner-rule slide, sink at SUB_SINK 2 — and piles by them; there is no LOOSE flag yet. The plan keeps the flag as a refinement: static occupancy unless marked **LOOSE**. Carved by acid (64 acid destroys one subtile), cast by lava (64 lava + water → one subtile + steam) — both reactions planned. Wood is carved at fuel granularity. Doors never carve. Glaze is immune. The ledger conserves STONE subtile count across solid and loose states (the STONE_S row books every popcount delta); shatter moves matter, never deletes it.

**Reactions — the third system** *(shipped: `GridReactions`, soak only)*. Movement has two owners — GridWater for liquids, GridSand for solids — and transformation has a third: a reaction engine that binds the packet and the stone facade, reads settled state, and runs after both movement passes. Reaction #1 is soak; the planned roster is the matrix below — acid's dissolve, lava's cast, freeze, glaze, fire's siege — each a row in one pass, never a rule bolted into a movement engine.

*From oil through the reaction matrix: design ahead of code. The packet hosts the pool columns and the density/sort tables, and the displacement pass will eject any of them — but beyond soak, no rules, reactions, or renders exist for these materials yet.*

**Oil** *(movement shipped — `GridWater` MOVERS; reactions planned)*. Pool liquid, fuel 255. Movement is live: oil runs the four flow rules at viscosity 32 (water runs unthrottled at 255), floats above water through the sort pass, and never soaks into soil — the soak pass reads water only (OT4). Oil with water above trades down through the sort pass; within a tile they layer by share. *Planned:* burning oil travels the float layer and self-limits as it consumes — the one sanctioned fire that swims. **Oil grants no wetness** — an actor in oil neither soaks nor dries (bridge-side, planned), but a HOT actor standing in it is standing in fuel (§4.4).

**Acid** *(column shipped; rules planned)*. Pool liquid. 64 acid dissolves one subtile of stone or soil (or 64 fuel of wood), consuming itself. Acid decays and is purged below 64. Deliberately unlike water, which is conserved forever.

**Ice** *(column shipped — `GridSand`; every reaction planned)*. Subtile solid; one subtile displaces 64 pool capacity. Buoyancy is shipped as rest: SUB_SINK −1, submerged ice does not sink — and does not rise either; rising is the float lab. *Planned:* 32 water freeze into one subtile — freezing expands; the freeze check requires the displaced material somewhere to go (air-gate family); submerged ice migrates up a subtile per tick; water above ice swaps down; ice freezing under existing ice pushes it up. Thaw returns 32 water per subtile. **Heat-melt** (§4.2): ice under a hot actor's feet thaws at MELT_RATE, 1 heat per water, billed through the bridge — the CA reaction, not an aura. Snow (post-slice) uses the same reaction.

**Lava** *(column shipped; rules planned)*. Stone that forgot it's solid. Pool liquid, slow; ignites fuel on contact; water contact casts one stone subtile per 64 lava and makes steam. Fire as masonry.

**Glaze** *(planned)*. Sustained fire on a soil surface vitrifies it. Opaque, acid-proof. The counter-material: acid digs, glaze routes.

**Fire** *(planned)*. A burning tile requires open air — pool capacity minus water and solid subtiles ≥ 16. Less smothers (steam wisp if water). The universal snuff: drown it or bury it. Loose fuel obeys buoyancy: heavies sink after a beat afloat; burning fuel on water burns one beat, boils a little water, sinks, snuffs. Spread: orthogonal, free; wind ember-leaps one gap downwind. Damp siege: drain 4/tick, steam. Fuel 0 → out (WOOD → AIR: arson is level editing; else SCORCHED). **Ignition by heat — as opposed to open flame — always goes through smolder (§4.4).** Open CA fire spreads with no warning: it is already matter.

**Gas** *(columns shipped; rules planned)*. Smoke and steam, each 0–255 in the pool. Smoke rises and pools under ceilings, advects downwind (draft fields are authored wind — *wind system TBD, open item*). Steam rises, spreads along the ceiling, and condenses off cool stone as slow drizzle — the enclosed water cycle.

**Rain** *(planned)*. Exterior rooms expose open-sky columns; exposed tiles gain water per tick; wind slants it; water leaving the map is boundary flux.

**Electricity** *(planned)* exists only as conductive bodies. A spark is a flood through a connected wet body — the sim's own body graph. Wet paths are wires.

**Botanical triggers** *(planned)* (the sensor family — no tech in these worlds, forest spirits only): gate-fungus (wet contact), pitcher plant (level switch), snap-grass (flow switch), scorch-bloom (fire contact). Field state, queryable by level logic.

**Body-state subsystem** *(potential, planned)*. Per-body quality flags for connected like-material bodies — water: poisoned, tainted, holy; soil: fertile or not. Quality, not phase: water, steam, and ice are three distinct elements with phase-change rules, never tags on one body. Potential system. *(The WET tag is this system's first brick, shipped — per-tile for solids; connected-body tags are the planned extension.)*

**Reaction matrix** *(planned beyond soak — every cell is a puzzle verb)*:

| | |
|---|---|
| water + cold → ice (32 ⇄ 1 subtile) | ice + heat → water |
| lava + water → stone subtile + steam | acid + stone/soil → AIR (−64 acid) |
| oil + fire → surface burn | acid + water → poison body |
| soil + water → damp (1:1, integer) | soil + sustained fire → glaze |
| fire without open air → out | damp + fire → steam siege |

Heat arrives at this matrix only through the bridge — never as a stored field.

## 4. The bridge — actors ↔ matter

### 4.1 Two layers, one customs office

Actors mutate heat and wetness freely at 60 fps (flap costs, throw vents, contact gains). Matter only ever changes at 10 Hz. An actor's heat "waits for the bus": generated at frame speed, relevant at tick speed. All actor→CA effects buffer as work orders and apply at the head of the tick, in tile order, then per-tick PRNG-shuffled actor order. The banned bug class: **any code path where an actor writes tiles directly.**

### 4.2 The thermal exchanges

All rates are expected values of stochastic integer events rolled on the room PRNG. Tiers key off the tile's water content.

| Exchange | Direction | Rate | Quantum |
|---|---|---|---|
| **ABSORB** | pool water → wetness | tier: <128 → 4/s · ≥128 → 16/s · =255 → instant to saturation | 1 water → 2 wetness |
| **DRIP** | wetness → pool water | ~4 water/s, randomized | 2 wetness → 1 water, random overlapped tile |
| **BOIL** | heat + pool water → steam | same tiers; instant at 255 = min(heat, water) | 1 : 1 : 1, steam lands in the tile |
| **CROSS-TALK** | heat + own wetness → steam | 16 wetness/s flat | 2 wetness + 1 heat → 1 steam |
| **DRY** | heat + soil damp underfoot → steam | 8 damp/s | 1 damp + 1 heat → 1 steam |
| **MELT** | heat + ice underfoot → water | 16 water-eq/s (one subtile / 2 s) | 1 heat per water; CA-side, billed |
| **FIRE/LAVA contact** | CA → actor heat | +4 / +8 per tick | — |
| *(reserved)* **FREEZE** | mirrored MELT | post-slice | — |

Laws and consequences:

- **Steam is the only exit for heat.** CROSS-TALK is one rule with two reads: air-drying when the actor is hot, coolant when it's wet. Wetness reduces heat exactly as pool water does.
- **The dunk is a steam bomb, and it self-caps.** At a full tile, min(heat, water) converts in one tick; steam replaces water *within the pool budget* — one tile's worth, never a flood. A heroine at 255 diving into a full pool arrives at 0 heat inside one steam cloud.
- **The carry window.** SATURATED (254) drips out over ~32 seconds of walking. Mop here, sweat there, walk fast. A cold magical girl can ferry water as wetness and boil it on delivery; the witch can drop a hot enemy in a puddle and watch it cool, hissing, on its own.
- **Rain is emergent anti-air.** Rain fills her tile; a hot body boils it as it lands. No authored rule.
- **Drip and cross-talk run concurrently** (a hot, wet actor mostly steams, partly drips). Suppressing drip when hot is a one-line playtest knob.
- **No actor→actor heat or wetness transfer in v1.** Contact effects are archetype modules (a Cinderkit's touch); the only actor-to-actor water channel is drip-then-boil — a held wet enemy cools a hot holder by leaking.

### 4.3 Magic orders

Game-issued, zero heat, still through customs — magic pays no heat, but it goes through the bridge like everything else. The engine executes: **IGNITE** (fuel → FIRE directly, bypassing smolder — the witch's verb; her damp-fizzle rule is game-side) and **FIZZLE** (DAMP −8 + steam — the witch's beam and ignite on wet fuel).

### 4.4 Smolder — the CA's own warning

Anything with FUEL > 0 is burnable, and burnable-by-heat gets a four-second warning. The CA tracks it itself, because the CA is in charge of itself:

- **Stimulus:** a HOT actor (heat ≥ 63) overlapping the tile, or a game stimulus flag sampled at the tick (the witch's beam burn band)
- **Build:** 4 s to completion. Completion attempts ignition — dry fuel → FIRE; wet fuel → fizzle (hiss, steam, DAMP −8, smolder resets). The stubborn can smolder a wall dry, four seconds per fizzle
- **Hysteresis:** stimulus lost → 0.5 s hold → decay at 2× build rate. A ball bouncing on and off fuel teases smoke, never ignites
- **Wetting or burying resets instantly**
- Overlay, not packet: room resets clear it, snapshots don't save it
- **Tags are fuel objects.** A hot girl leaning on her own tag gets the warning; open fire reaching that wall gives none
- No heat field anywhere, ever. Heat is a per-actor byte; its shadows on the world are smolder timers and steam

### 4.5 The door protocol

Actors cross doors; atoms never. At a crossing the engine snapshots the actor's holdings — heat, wetness, pot contents, held enemies — books them as ledger transfers between rooms, marks held enemies out of the source baseline, and freezes the exited room when unobserved. The engine validates water-equivalents on both sides: **actors through doors is the interface.** Player-facing doors always mark room boundaries.

### 4.6 Per-actor ledgers

Heat and wetness assert every tick: gains − spends = current. A lost heat point is a bug, same as a lost water unit.

## 5. Actors, physics, contact

**The engine owns what moves and what collides.** Heroes are `CharacterBody2D`; projectiles and thrown enemies are `RigidBody2D` with custom integrators; the lasso tip, pockets, and sensors are `Area2D`. CA surfaces (fire, lava, spikes, liquid tiers) are tile-sampled at the tick, not physics shapes.

**Contact events** are typed, and carry the geometry (offset, normal, relative velocity) and the state (weight class, archetype, heat, wetness, module payloads). **Modules own the response:** collision-response modules and per-frame trajectory-edit modules attach per actor. The magical girl's bands, pips, spin, and bank behavior are modules on her shots; the witch hangs a gravity module for launch arcs and enemy-specific landed powers on the same hooks. Gameplay events are bespoke and owned by the actor that generated them.

**Universal movement laws:**

- Liquid ≥ 128 in the tile → **half speed** (wading). Submerged → **swim**: SWIM_GRAV 120, vy clamp, stroke = jump, 10px surface hop
- FLOW and wind on the actor's tile push it (capped vs. walk speed)
- Oil is swimmable exactly like water **except** it grants no wetness — and it's fuel
- Both heroines jump exactly 10 px. Identical legs is the engine joke

**Spike tiles:** top contact only. The engine bounces the actor back along its trajectory ring and emits the event; damage is game policy (the magical girl loses a heart; the witch takes forced panic). The **trajectory ring** (~1 s of position + heading at 60 fps, per actor) is engine infrastructure — the witch's panic breadcrumbs and the spike bounce both read it.

**Stun:** flat 10 s, recapturable — the universal downed state.

## 6. The actor API — universal stats, per-game interfaces

Every actor presents: weight (byte + L/M/H class), heat, wetness, archetype (alive behavior, projectile profile, landed state), drip multiplier, module slots. The four-column frame — *Alive / As projectile / Landed state* — is the engine schema; rosters and behaviors are per-game.

**Weight resolution is per-game law reading one engine byte.** The witch's world treats it one way; the magical girl's bands are equal-mass forever, weight editing terrain instead. Universal stats, per-game interfaces — this is the crossover pattern, and it is law: **every enemy must interface with both heroines' verbs.** No enemy may assume its native game.

**Shape grammar:** hostile reads angular; stunned/projectile reads round; size = weight. Sprites are 2-bit grayscale, baked at boot through the Palette module — one table, single source of truth. Rows are conditions: a row per state (hostile / docile / stunned / burning / wet), so a state machine reads across the room. Pips are a game module, not engine state.

**The pot** is an actor whose interior is a tile: a 255-unit content pool plus 4-bit enemy occupancy (up to four; each nibble costs 64 capacity). Reactions run inside. Contents are holdings — ledger-visible, door-portable.

**Pockets** capture any actor. The engine fires the capture event with the actor's manifest; scoring hooks are game-side.

## 7. The lasso core

Identical for both girls. FSM: IDLE → FIRE_TIP (straight, 7 tiles, loose rope render) → SNATCH (0.15 s, auto-reel) → CARRIED (one at a time). Aim within 1.5 tiles of her feet = **gentle drop**: placed docile, unharmed, exactly where put.

**The water-cast is core, not flavor:** the tip travels, refracts, slows — a fishing-line cast. The preview bends identically; the kink is the surface line, so depth reads on sight. Hit = auto-reel; no manual reeling. Range is measured in tiles — water costs time, not cover. Underwater enemies are fishable.

Previews are twinkling dotted lines (random phase per dot, hash-based). Per-game: projectile modules, windup and follow-through frame data, and aiming. Aiming lives on the actors — the witch aims continuously (sprite-center anchor: stick vector or mouse, dotted preview, same anchor for her light); the magical girl throws in one of eight directions, straight before spin, no preview.

## 8. Rooms, doors, death, lives

**The room model.** One CA domain per room, any size — authoring decides (small rooms are tight challenges; large rooms are many atoms). The magical girl's strip is one room; its reaches are beat annotations, not boundaries. Unobserved rooms freeze.

**Door policy is authored per door** — baseline on cycle, snapshot on cycle, restore on exit — machinery here, policy in the game docs.

**Pits are pockets.** One-way capture fixtures, any orientation — floor pits, wall pockets, ceiling wells. Every one renders its **evil aura**: magic-class, unmistakable, the warning is the promise. Matter entering is lost, booked as pocket-loss flux — the ledger calls it fine, nothing flies out, ever. **Any actor can fall in.** A heroine falls in: death. A thrown enemy or ball: captured (the magical girl scores off the event; in the witch's dungeons they are rare, and losing an enemy to one is a tragedy the room reset forgives).

**Death is the same for both characters.** The room resets to baseline; she respawns at the door she entered from; one life is spent; presentation is a non-event (slump, blinky eyes, 1.5 s). Baseline restore means nothing stays lost — pocketed enemies return, spent fuel returns, the room forgives completely.

**Lives: 3 to start, both games.** The magical girl earns hers (her prize ladder); the witch finds hers (world secrets). **Zero lives → level reset:** every room to baseline, inventories and tags erased, back to the very beginning. (The witch's entry-door ritual is her doc's voluntary version of the same reset.)

## 9. Rendering and light

One `Image` the size of the room, redrawn once per tick, pushed through an `ImageTexture`, drawn under actors *(shipped — `ElementRenderer`)*. The sim state is the picture; debugging is looking at the room. All physical state stays in GBC bounds.

**Shipped render** (`ElementRenderer` + `Palette`): beveled stone; liquids drawn as visible lines — units >> 4, one LINE per line — stacked by material share within a tile, densest at the bottom (`MAT_DRAW` density order), surface crest on the topmost material; oil carries its own palette rows (dark ochre, far from the water blues), the other materials alias water until their labs; covered tiles filling solid, and **sub-line films (< 16 units) drawing nothing by design**; the waterline lifts over the tile's own soil subtiles — a squeezed pool reads higher (both bottom subtiles +4 flat, doubled and capped +6 when a top slot is also filled; one bottom subtile doubles the lines, capped +2, or +4 with a top slot; clamped at 15); waterfall streaks replace the fill on strong downward flow (above FLOW_STREAK 48 — hash-keyed on tile + tick, never a PRNG; tinted by the majority liquid); soil subtiles as 8×8 quads with a lit lip where uncovered and damp darkening from the top of the occupied region — 8 damp per pixel line, the creeping front — stone and ice subtiles are *not yet drawn*; the debug overlay (G) tints sealed vs vented air, draws per-segment level lines, water and solid flow arrows, the tile grid, and the hover cursor. The palette is one constants class today — base, water, oil, soil and wet-soil, editor and debug colors — swapped for the bank below when real art starts.

**Palette bank** *(planned)*: eight rows × four colors for the whole screen. Sprites authored 2-bit grayscale, baked through the Palette module — field and sprite colors can never drift. Rows are conditions; per-room remaps tint the bank while semantic slots stay pinned. Heroine eyes: two 1×2 unshaded pixels on a canvas layer above the CanvasModulate — cartoon law, per-game color.

- Water *(planned beyond the shipped lines)*: dithered films below one line; 60 fps shimmer over 10 Hz steps (the period-authentic split)
- Mixtures render layered by density within a tile *(planned)*
- Subtile solids: 8×8 quads — terrain editing at hardware-tile resolution *(shipped for soil; stone and ice pending)*
- Damp front: pixel lines from the top of the tile's **occupied region** — 8 damp per line, 16 at saturation — so a bottom-only tile still shows a level; percolation is visible *(shipped)*
- Gas: Bayer dither by density. Fire: 3-frame palette cycle. Scorch: permanent dark flag *(planned)*
- Derived animation, all in palette-and-dither language: splash disturbance decays per tick (a restored room comes back calm); waterfalls are streaks on high downward flow — the renderer reads the flow field *(shipped)*; spray and waves keyed on (tile hash, tick count) *(planned)*
- Growth: four blips over four seconds; blip one shows roots toward the chosen target *(planned)*
- Smolder: the four-second mirror animation *(planned)*
- Dotted previews: twinkling, stateful line colors *(planned)*

**Light rig (mechanics engine, assignments game-side)** *(planned — E5)*: CanvasModulate ambient, omni supports, focus cones with occluder polylines regenerated on tile and subtile changes, LIT mask by visibility-checked fan, dithered gradient textures. **Scene lighting profiles** per room: ambient level, firelight toggle (the witch's rooms run near-black blue with a fire-light pool of 6 — arson as illumination; firelight is a witch ability, off for the magical girl). Heroines may radiate — the witch's lantern, the magical girl's indoor self-glow at lantern radius (a full screen). Radiance is magic; what it does to steam and shadows is the rig's business.

## 10. Level format and generators

```
LevelSpec {
	meta:  { seed, name, tile_w, tile_h, palette: 8×[4], music, lighting: profile }
	rooms:  [ RoomSpec ]
}
RoomSpec {
	rect: Rect2i                     # tiles within the level
	terrain: 2D [TERRAIN]
	stone_sub, soil_sub: 2D nibble maps (stone carries the LOOSE flag)
	pool (sparse → per-type): water, oil, acid, lava, smoke, steam
	solids-held: fuel, damp
	surfaces: moss, vine, coal, slime, glaze
	flags: cold_tiles, scorch, secrets
	wind: draft field (authored vectors — system TBD)
	rain: open-sky column list
	fixtures: brazier, spike, plate, lever, hook, pedestal,
			  swing_ring, beam_dump, pocket { orientation },
			  stream_gate, door { to, locked, policy }
	spawns: [ { enemy | pot, x, y, patrol?, contents? } ]
	markers: chalk, plumb targets
	beats: [ authored annotations ]    # authoring metadata, e.g. the strip's reaches
}
```

Generator notes: run several that disagree — maze output as topology for large rooms; a terrain generator that runs the sim itself (pour water, let it settle, place exit, fuel, and soil relative to where the pools sit); an LLM writing structured specs that a deterministic compiler builds. **Checkers are the real artifact** — the design invariants as code. Engine invariant checkers: riser solvability (8px steps vs the 10px jump), pool legality, ledger closure, pocket-aura coverage (no unwarned capture). Game checkers live in the game docs (the lens audit, band solvability, stream economy, flap tax). Test 8×8 vignettes, not rooms. Keep the seed, not the room. Contact sheets for human curation. The loop — generated rooms inspiring hand-authored ones — is the product.

## 11. Build order — the engine substrate

*Status at `2582b3b`:* E0 and E1 are code; E2 is mostly code; E3–E5 not started. The shipped test harness is `TestSandbox` plus the water, soil, and oil scenes — a 10 Hz timer, F-key diagram presets carved into the 15×15 grid (each scene binds its own set — F6 and F8 are dead keys on the authoring rig), K runs the acceptance suites headlessly through the shared `_run_example` runner (six water examples, four packet unit tests, ten soil examples, eight oil examples — OT1–OT4, UT1–UT4 — 3000 ticks to equilibrium, every tick drift-watched per engine) — the precursor of §10's vignette rig.

- **E0 — World:** packet, ledger, the render Image — **shipped** (`TilePacket`, `ElementRenderer`; asserts hold over long runs). The room model is not: one fixed grid, no `RoomSpec`, no freezing
- **E1 — Liquids:** **shipped** — GridWater as the liquid engine (per-material passes, viscosity, the density sort pass, pressure-head seek level) + flow export + displacement (authoritative), acceptance-tested (water + oil suites)
- **E2 — Matter:** **mostly shipped** — soil/stone/ice subtiles, the reaction engine, soak, wet tags, and mortar are code (`GridSand`, `GridReactions`); oil movement is code (`GridWater` MOVERS + viscosity + sort); acid, lava, and glaze columns exist in the packet without rules; fire, freeze/thaw, and the driers are design
- **E3 — Actors:** the shell, contact contract, trajectory ring, lasso core, stun/capture, thrown profiles, pots as actors — not started
- **E4 — Bridge:** thermal exchanges, smolder, door protocol, pockets, per-actor ledgers — not started
- **E5 — Light:** rig, profiles, palette module — not started

The witch's M0–M2.5 map onto E0–E2 + E5; her later milestones build on E3/E4. The magical girl builds almost entirely on E3/E4 — her combat *is* modules on this substrate.

## 12. Engine exit checklist

- Soak test: minutes of random-input simulation, ledger green, zero drift, no float in the CA — assert it *(the ledger and volume asserts run every tick in code today; the harness adds a per-engine drift watch — first offending tick and engine — catching destroy-and-book pairs the double-entry cannot see; the minutes-long soak rig is pending)*
- Same seed → identical replay (per-tick state hash; PRNG advanced only in the tick)
- The steam bomb self-caps: 255 heat in a full tile → 255 steam in one tile, no overflow, budget-neutral by construction
- Heat and wetness ledgers assert per actor; a hot body entering water cools by exactly the water it boiled
- No code path where an actor writes a tile (review-ban the class; grep it in CI)
- Door crossing: holdings transfer exactly; held enemies never duplicate; the exited room freezes mid-flow with no mass teleport
- Pocket loss books; a captured heroine respawns at her entry door with the room at baseline
- Tiers read correctly across a two-tile heroine (head in steam, feet in water) — stochastic picks, PRNG'd, never wall-clock
- 60 fps at authored room scale, typed arrays, zero per-tick allocations
- The picture is the state: the debug view is the render

## 13. Tuning constants

```
# ── shipped — constants in code today ──────────────────────────────
TILE = 16, SUBTILE = 8               # SACRED — the subtile is the hardware tile
TICK = 10 Hz                         # sim; render 60, never coupled
POOL = 255 per tile, −64 per solid subtile (any kind)
LINE = 16                            # SACRED — water units per visible scanline
AIR_PASSABLE_MAX = 15                # a sub-line film is air for pocket purposes
PRESSURE_RATE = 64                   # per run-row transfer, capped by half the pressure diff
PRESSURE_MIN_DIFF = 2                # top-up hysteresis — in donor-material quanta (× density[m])
DIFFUSER_FLOW = 96                   # flow_mag above this marks a diffuser
FLOW_STREAK = 48                     # downward flow above this draws waterfall streaks
DENSITY: water 30 · oil 20 · acid 40 · lava 50 · smoke 10 · steam 5
SORT_RATE: 2/2/1/1/3/8               # toward the rest layer; steam out-climbs acid 8:1
MOVERS: lava, acid, water, oil       # densest first — the loop order IS the drain order
VISCOSITY: water 255 · oil 32 · acid 255 · lava 16 · smoke/steam 255   # flow-throughput cap; <tune>
SAND_FALL = 1 subtile/tick           # all kinds, through air
SUB_SINK: stone 2 · soil 1 · ice −1  # through liquid; ice rests (no rising yet)
DAMP_PER_SUB = 32                    # soil damp capacity per subtile; 1:1 with water and steam
SOAK = clamp(w/16, 1, 16) per tick   # reaction #1; the ceiling never binds (w ≤ 255 floors it at 15)
WET_TAG: gain > 50% of capacity · lose < 30%   # hysteresis — the tag is state, not derived
SLIDE_WET = no kind slides           # the mortar row; fall is never gated
SUB_FLOW_MASS = 64                   # one solid tile-crossing = 64 pool-units of flow
TEST_TICKS = 3000                    # acceptance runs to equilibrium

# ── planned — not yet code (E2 reactions, E3 actors, E4 bridge) ────
JUMP_HEIGHT = 10                     # SACRED — both girls, identical legs
GRAVITY = 480, JUMP_V = 98           # sqrt(2·g·h), h = 10
ACID_SUB = 64, purge below 64        # acid is not conserved; water is
LAVA_SUB = 64, ICE_SUB = 32 water (displaces 64)
BURN_DRAIN: wood 8, vine 12, coal 1
OPEN_AIR_MIN = 16
HOT = 63                             # SACRED — smolder threshold, the tells
WETNESS: 0–254 even, SATURATED = 254
TIERS by tile water: <128 → 4/s · ≥128 → 16/s · =255 → instant
DRIP = 4 water/s (2 wetness per water)        # carry window ≈ 32 s
CROSS_TALK = 16 wetness/s (8 steam/s, −8 heat/s)
DRY = 8 damp/s underfoot (1 damp : 1 steam : 1 heat)   # re-priced by the 1:1 retune — re-tune at E4
MELT = 16 water-eq/s underfoot (1 heat per water, 32 per subtile)
CONTACT: FIRE +4/t, LAVA +8/t
SMOLDER = 4 s build · 0.5 s hold · 2× decay · wet/bury resets
STUN = 10 s flat · LASSO_RANGE = 7 · SNATCH = 0.15 s · GENTLE_DROP ≤ 1.5 tiles
SWIM_GRAV = 120 · WADE = half speed at ≥128 liquid
LIVES = 3 · 0 → level reset
# retired: FLOW_RATE = 3 — never shipped; flow speeds are the rule formulas above
# retired: SOIL_SUB 64 / DAMP 2:1 — superseded by DAMP_PER_SUB 32 at 1:1 (v1.2)
# retired: CELL_UNITS 256 / RISE_MIN_DIFF 256 — head math replaced by density-weighted pressure (v1.3)
```

## Appendix A — supersessions (what this doc retires)

| Source | Retired by |
|---|---|
| witch v2.1 §1–§4 | absorbed here; `witchgame` v3.0 is a delta doc |
| witch "damp meter" | actor **wetness** (0–254 even); tile DAMP unchanged |
| witch DRY_RATE 3/s, drip 1-per-2 | universal DRIP + CROSS-TALK |
| witch SOAK_RATE <tune> | the tier table |
| witch immune to heat | she has heat (fire/lava contact); she generates none |
| beam-specific smolder | CA-side smolder, hysteresis, universal — same 4 s |
| witch wading (BOOTS ad hoc) | half speed at ≥128 liquid, universal |
| MG "inert below HOT" | the bridge is always live; HOT gates smolder and tells |
| MG heat ladder | vent ⌊H/2⌋, keep ⌈H/2⌉ — 255→128→64→32; gains halved |
| MG MELT aura | CA reaction underfoot |
| MG ball LIT ≥ 64 | one threshold: HOT = 63 |
| MG spouts / recycle | pockets are one-way, forever |
| MG stun scaled by speed | flat 10 s |
| MG strip as a domain type | one room; reaches are beat annotations |
| MG star-well | cut (the nap garden replaces the finale) |

## Appendix B — risk register

- **Bridge ordering:** orders at tick head, tile order, PRNG actor shuffle. The matter ledger catches ejection bugs; the per-actor ledgers catch thermal drift. Both assert every tick
- **The instant tier:** min(heat, water) in one tick must stay budget-neutral — steam replaces water in the pool by construction; assert it, because this is the steam bomb
- **Multi-tile actors:** one PRNG'd tile pick per operation; mixed-tile heroine states resolve stochastically — accepted lumpiness, deterministic because seeded
- **LOOSE_STONE:** soil rules on stone subtiles — shipped exactly so in `GridSand` (every subtile is loose today; the flag is the planned refinement); Σ popcount extends to STONE; shatter-into-water must eject by flow, never vanish
- **Pockets as trigger volumes:** nothing may push a heroine in unwarned — the aura is the promise; review any FLOW source aimed at a pocket mouth
- **Smolder edges:** the 0.5 s hold exists for bouncing contacts; decay must not negative-clip; wet-fizzle on completion must reset cleanly
- **Room-size ceiling:** open item — profile after E-complete; the 112×15 strip is the current largest authored room; target 4× headroom
- **Wind system:** still TBD; authored draft fields, gas advection, and rain slant all block on it
- **Two water-equivalences:** actor wetness is 2:1, tile damp is 1:1 — both booked in one ledger. Code and docs must never borrow one rate for the other; the w0 conservation checks and the drift watch are the tripwires
- **DRY re-priced:** the 1:1 retune doubled underfoot drying's steam yield and heat cost (8/8, was 4/4) and halved the witch's damp-wall grind (16 fizzles per full tile, was 32) — re-tune at the bridge lab; C2/C5's authored damp amounts may need a pass
- **Nothing dries yet:** in the shipped engine damp only grows — the wet tag, once gained, never clears without a tool. The first drier ships with fire or the bridge; until then, mudslides are one-way
