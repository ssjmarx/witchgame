# `world.md` — THE WORLD: Shared Engine & Simulation GDD v1.0

*The foundation under both games. The witch doc and the magical girl doc are deltas on this one; where a game doc disagrees with this doc about engine behavior, this doc wins. Where this doc and the code disagree, the code wins — GridWater is already code, and the sim section below is written from it.*

**Scope.** This doc owns: the room model, the cellular automata, the bridge, the actor shell and contact contract, the enemy frame, the lasso core, doors, pockets, death and lives machinery, the rendering and light rig, the level format, and the generator/checker framework. The game docs own: verbs, aiming, rosters, rooms, economies, and presentation. One 10 Hz integer world that renders itself; two heroines who visit it at 60 fps through the same customs office.

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
5. **Steam is the universal heat sink.** 1 heat + 1 pool water → 1 steam. Moisture at half density — wetness, soil damp — converts 2:1. Heat leaves actors only as steam.
6. **Actors cross doors; atoms never.** DOOR is always solid to CA flow, open or closed. Player-facing doors always mark room boundaries.
7. **Matter is conserved except at sanctioned sinks** — boundary flux, pockets, acid decay. The ledger asserts every tick; a drift is a bug, not a rounding error.
8. **The engine says what is moving and what is colliding; the actors decide what it means.**
9. **Determinism:** one PRNG per room, advanced only inside the tick. Render-side randomness is hash-based and never consumes sim entropy.
10. **Where the code and this document diverge, the code wins.**
11. **Some mechanics are occult.** The games decide which; the engine ships no tutorials.

## 1. Tech setup

- Godot 4.x, GDScript. Viewport 240×240, window 960×960, stretch viewport, integer scaling, nearest filtering
- Tiles: 16×16, each four 8×8 subtiles. Visible area 15×15
- Element tick: fixed 10 Hz, integer only, deterministic. Render 60 fps; simulation never does
- Rooms freeze when unobserved (the room containing the camera simulates). A one-room level is always live
- Modern conveniences in: coyote time, jump buffering, ledge tolerance
- **Performance discipline:** the CA runs in typed arrays (`PackedByteArray` and friends), zero allocations per tick, no GDScript in the hot loop. Actors ride Godot's C++ physics. Escape hatch: C#/GDExtension if profiling ever demands
- **Room size is an authoring decision, not a budget.** Small rooms mean tight challenges; big rooms mean lots of atoms. The GBC aesthetic is a style, not a hardware constraint. Profile the ceiling on target hardware once the engine is finished; grow from there. *(Open item.)*
- **Determinism rig:** one `RandomNumberGenerator` per room, `seed = level_seed ⊕ room_id`. Derive the room's fixed tile permutation at load, then advance per tick. Actor order is a per-tick PRNG shuffle. Render effects key on (tile hash, tick count), never wall-clock, never the PRNG.

## 2. Data model

**Per-tile packet** (~14 bytes/tile):

```
TERRAIN : AIR, STONE, WOOD, SOIL, BRAZIER, SPIKE, DOOR, DOOR_CLOSED
STONE_S : 4-bit occupancy — carve/cast granularity (DOOR/BRAZIER/SPIKE never subtiled).
          LOOSE flag: loose subtiles run the soil move rules; solid stone stays static
SOIL_S  : 4-bit occupancy — the nibble IS the matter (popcount = mass)
ICE_S   : 4-bit occupancy — 32 water ⇄ 1 subtile, displaces 64
FUEL    : 0–255, attached to solids (vine 60, wood 255, coal 255)     — outside the pool
FIRE    : 0–255, burning state (requires open air)                    — outside the pool
WATER, OIL, ACID, LAVA, SMOKE, STEAM : each 0–255 — the content pool
DAMP    : 0–255, held by solids (64 capacity per soil subtile)        — outside the pool
SURFACE : NONE, MOSS, VINE, COAL, SLIME, GLAZE
FLAGS   : COLD, LIT, SCORCHED, structural
FLOW    : exported per tile per tick (direction + strength) — derived, not matter
```

**The content pool.** Water, oil, acid, lava, smoke, and steam are separate 0–255 fields sharing one budget: their total in a tile never exceeds 255, reduced 64 per solid subtile. Mixtures are allowed and render layered by density — heaviest at the bottom, gas on top. Reactant pairs sharing a tile resolve immediately per the reaction matrix; non-reactants layer and stay. DAMP, FUEL, and FIRE belong to solids and live outside the pool. Overflow is ejected through the displacement rule, never destroyed. Gas thresholds rescale to 0–255 density.

**The actor state block.** Every actor — heroine, enemy, pot, thrown ball — carries:

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

**The smolder overlay.** A runtime per-fuel-tile timer, not packet data. Room resets clear it; snapshots don't carry it.

**Room record:** baseline / saved bytes / saved enemies / tagged / enemy_baseline, plus held-enemy exclusion marks — captured enemies are out of the baseline; nothing duplicates across a door.

**Conservation ledger.** One row per material (WATER; DAMP at 2:1; SOIL subtile; STONE subtile; OIL; ACID; LAVA at 64:1; ICE subtile at 32:1; SMOKE; STEAM), reactions as balanced integer transfers, plus: **boundary-flux** (exteriors, waterfalls, rain), **pocket-loss** (sanctioned destruction — the ledger calls it fine), **fauna flux** (spawn-stream entries and exits, booked like rain), and **actor holdings** — wetness at 2:1 water-equivalent, pot interiors, held enemies — attached and detached as flux, transferred at doors. Asserted every tick alongside the pool constraint (Σ content ≤ capacity). A drift is a bug.

## 3. Element simulation

```gdscript
func element_tick(room):
    var order = room.permutation        # fixed, derived from the room PRNG at load
    _apply_work_orders()               # THE BRIDGE — buffered actor orders,
                                      # tile order, then per-tick PRNG actor shuffle
    for idx in order: _liquid_pass(idx) # water (GridWater), oil, acid, lava, subtile solids
    _seek_level(); _export_flow()
    for idx in order: _fire_pass(idx)
    for idx in order: _gas_pass(idx)
    for idx in order: _growth_pass(idx)
    for idx in order: _phase_pass(idx)  # freeze, thaw, heat-melt, cast, glaze
    for idx in order: _smolder_pass(idx) # fuel warnings: build / hold / decay / complete
    ledger.assert_all()                # materials + pool + per-actor heat and wetness
```

**Water — GridWater is authoritative.** Built and tested; where this document and the code diverge, the code wins. Rules as shipped: FALL (exclusive, instant; water/air swaps are how bubbles rise — one cell per tick, columns fall coherently), POUR (over lips into dry space only, corner-safe, air-gated), CREEP (half-difference into dry space, gated), SEEK LEVEL (each horizontal run is one incompressible conduit; columns trade volume surface-to-surface until heads match, at PRESSURE_RATE per run-row; a full capped column between them is a rigid pipe). Invariant: every move downhill-or-level; Σ(water × height) never increases. Air is gated, not simulated. Determinism: alternating sweep per tick; the escape flood is an order-independent monotone fixpoint. Scan-order guarantee: each cell's pass runs once per tick; vertical moves only deposit into already-scanned rows; lateral CREEP cascades are convergent and intended. Pool-aware capacity: arriving water competes with resident oil and gas for the budget; overflow displaces per the rule below.

*Known approximations (accepted):* region labels one tick stale; donor headspace freely expandable; divided vessels can rest one line off level. *Planned patch:* small-diff rises into headroom escaped-to-sky (invariant permits diff ≥ water[above] + 2; keep the strict gate for pocketed headroom).

**Displacement.** A solid subtile reduces the tile's pool capacity by 64; four subtiles is fully solid. When capacity drops below current content, the excess ejects through normal flow rules. Matter is displaced, never destroyed.

**Flow export.** Per tile per tick, direction + strength, from instrumented moves. Gameplay: pushes actors and loose objects (capped vs. walk speed). Rendering: deltas drive waterfalls and splash. A tile with water-in-transit above **DIFFUSER_FLOW** is a *diffuser* — the engine exports the condition; consumers are game-side (the witch's beam cannot pass one).

**Soil (subtiles).** 4-bit occupancy; popcount is matter, Σ popcount asserted. All sixteen shapes representable — transient shapes during falls and slides are the animation. Stability is what the rules produce, not a stored constraint. Moves: fall if below empty; slide diagonally if the diagonal-below is empty and the side is clear (corner rule); repose emerges — settled neighbors differ by ≤ ~1 subtile; piles are 8px staircases. 8px is a hop, never an auto-step. Moisture is mortar: saturated subtiles don't slide; fire drying a wet slope triggers a landslide (buries fire, spikes, enemies). Damp accounting: capacity 64 per soil subtile; arriving water splits half-flows / half-absorbs (integer halves; remainders flow); exchange 2 damp per 1 water, integer-only; damp percolates downward through saturated soil. A full water tile over full soil soaks to ~127 water with the soil saturated. Render: darken the top ⌈damp/64⌉ subtiles — the creeping front.

**Stone subtiles.** Static occupancy — unless flagged **LOOSE**, in which case they run the soil move rules (fall, corner-rule slide) and pile by them. Carved by acid (64 acid destroys one subtile), cast by lava (64 lava + water → one subtile + steam). Wood is carved at fuel granularity. Doors never carve. Glaze is immune. The ledger conserves STONE subtile count across solid and loose states; shatter moves matter, never deletes it.

**Oil.** Pool liquid, fuel 255. Density rule owned by the oil — oil with water above swaps down; within a tile they layer. Burning oil travels the float layer and self-limits as it consumes. The one sanctioned fire that swims. **Oil grants no wetness** — an actor in oil neither soaks nor dries, but a HOT actor standing in it is standing in fuel (§4.4).

**Acid.** Pool liquid. 64 acid dissolves one subtile of stone or soil (or 64 fuel of wood), consuming itself. Acid decays and is purged below 64. Deliberately unlike water, which is conserved forever.

**Ice.** Subtile solid. 32 water freeze into one subtile; one subtile displaces 64 pool capacity — freezing expands. The freeze check requires the displaced material somewhere to go (air-gate family). Ice floats: submerged ice migrates up a subtile per tick; water above ice swaps down; ice freezing under existing ice pushes it up. Thaw returns 32 water per subtile. **Heat-melt** (§4.2): ice under a hot actor's feet thaws at MELT_RATE, 1 heat per water, billed through the bridge — the CA reaction, not an aura. Snow (post-slice) uses the same reaction.

**Lava.** Stone that forgot it's solid. Pool liquid, slow; ignites fuel on contact; water contact casts one stone subtile per 64 lava and makes steam. Fire as masonry.

**Glaze.** Sustained fire on a soil surface vitrifies it. Opaque, acid-proof. The counter-material: acid digs, glaze routes.

**Fire.** A burning tile requires open air — pool capacity minus water and solid subtiles ≥ 16. Less smothers (steam wisp if water). The universal snuff: drown it or bury it. Loose fuel obeys buoyancy: heavies sink after a beat afloat; burning fuel on water burns one beat, boils a little water, sinks, snuffs. Spread: orthogonal, free; wind ember-leaps one gap downwind. Damp siege: drain 4/tick, steam. Fuel 0 → out (WOOD → AIR: arson is level editing; else SCORCHED). **Ignition by heat — as opposed to open flame — always goes through smolder (§4.4).** Open CA fire spreads with no warning: it is already matter.

**Gas.** Smoke and steam, each 0–255 in the pool. Smoke rises and pools under ceilings, advects downwind (draft fields are authored wind — *wind system TBD, open item*). Steam rises, spreads along the ceiling, and condenses off cool stone as slow drizzle — the enclosed water cycle.

**Rain.** Exterior rooms expose open-sky columns; exposed tiles gain water per tick; wind slants it; water leaving the map is boundary flux.

**Electricity** exists only as conductive bodies. A spark is a flood through a connected wet body — the sim's own body graph. Wet paths are wires.

**Botanical triggers** (the sensor family — no tech in these worlds, forest spirits only): gate-fungus (wet contact), pitcher plant (level switch), snap-grass (flow switch), scorch-bloom (fire contact). Field state, queryable by level logic.

**Body-state subsystem.** Per-body quality flags for connected like-material bodies — water: poisoned, tainted, holy; soil: fertile or not. Quality, not phase: water, steam, and ice are three distinct elements with phase-change rules, never tags on one body. Potential system.

**Reaction matrix** (every cell is a puzzle verb):

| | |
|---|---|
| water + cold → ice (32 ⇄ 1 subtile) | ice + heat → water |
| lava + water → stone subtile + steam | acid + stone/soil → AIR (−64 acid) |
| oil + fire → surface burn | acid + water → poison body |
| soil + water → damp (2:1, integer) | soil + sustained fire → glaze |
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
| **DRY** | heat + soil damp underfoot → steam | 8 damp/s | 2 damp + 1 heat → 1 steam |
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

One `Image` the size of the room, 10 Hz, `ImageTexture`, under actors. The sim state is the picture; debugging is looking at the room. All physical state stays in GBC bounds.

**Palette bank:** eight rows × four colors for the whole screen. Sprites authored 2-bit grayscale, baked through the Palette module — field and sprite colors can never drift. Rows are conditions; per-room remaps tint the bank while semantic slots stay pinned. Heroine eyes: two 1×2 unshaded pixels on a canvas layer above the CanvasModulate — cartoon law, per-game color.

- Water: fill fraction, dithered below 64; films above soil's low surface; 60 fps shimmer over 10 Hz steps (the period-authentic split)
- Mixtures render layered by density within a tile
- Subtile solids: 8×8 quads — terrain editing at hardware-tile resolution
- Damp front: top ⌈damp/64⌉ subtiles darken; percolation is visible
- Gas: Bayer dither by density. Fire: 3-frame palette cycle. Scorch: permanent dark flag
- Derived animation, all in palette-and-dither language: splash disturbance decays per tick (a restored room comes back calm); waterfalls are streaks on high downward flow — the renderer reads the flow field; spray and waves keyed on (tile hash, tick count)
- Growth: four blips over four seconds; blip one shows roots toward the chosen target
- Smolder: the four-second mirror animation
- Dotted previews: twinkling, stateful line colors

**Light rig (mechanics engine, assignments game-side):** CanvasModulate ambient, omni supports, focus cones with occluder polylines regenerated on tile and subtile changes, LIT mask by visibility-checked fan, dithered gradient textures. **Scene lighting profiles** per room: ambient level, firelight toggle (the witch's rooms run near-black blue with a fire-light pool of 6 — arson as illumination; firelight is a witch ability, off for the magical girl). Heroines may radiate — the witch's lantern, the magical girl's indoor self-glow at lantern radius (a full screen). Radiance is magic; what it does to steam and shadows is the rig's business.

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

- **E0 — World:** packet, room, ledger, the render Image. Soak tests green, asserts hold over long runs
- **E1 — Water:** GridWater + flow export + displacement (authoritative)
- **E2 — Matter:** soil/stone subtiles + LOOSE, oil, acid, lava, ice, glaze, the reaction matrix, freeze/thaw
- **E3 — Actors:** the shell, contact contract, trajectory ring, lasso core, stun/capture, thrown profiles, pots as actors
- **E4 — Bridge:** thermal exchanges, smolder, door protocol, pockets, per-actor ledgers
- **E5 — Light:** rig, profiles, palette module

The witch's M0–M2.5 map onto E0–E2 + E5; her later milestones build on E3/E4. The magical girl builds almost entirely on E3/E4 — her combat *is* modules on this substrate.

## 12. Engine exit checklist

- Soak test: minutes of random-input simulation, ledger green, zero drift, no float in the CA — assert it
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
TILE = 16, SUBTILE = 8               # SACRED — the subtile is the hardware tile
JUMP_HEIGHT = 10                     # SACRED — both girls, identical legs
GRAVITY = 480, JUMP_V = 98           # sqrt(2·g·h), h = 10
TICK = 10 Hz                         # sim; render 60, never coupled
POOL = 255 per tile, −64 per solid subtile
SOIL_SUB = 64 units, DAMP 2:1        # integer quanta only
ACID_SUB = 64, purge below 64        # acid is not conserved; water is
LAVA_SUB = 64, ICE_SUB = 32 water (displaces 64)
BURN_DRAIN: wood 8, vine 12, coal 1
OPEN_AIR_MIN = 16
HOT = 63                             # SACRED — smolder threshold, the tells
WETNESS: 0–254 even, SATURATED = 254
TIERS by tile water: <128 → 4/s · ≥128 → 16/s · =255 → instant
DRIP = 4 water/s (2 wetness per water)        # carry window ≈ 32 s
CROSS_TALK = 16 wetness/s (8 steam/s, −8 heat/s)
DRY = 8 damp/s underfoot (2 damp : 1 steam : 1 heat)
MELT = 16 water-eq/s underfoot (1 heat per water, 32 per subtile)
CONTACT: FIRE +4/t, LAVA +8/t
SMOLDER = 4 s build · 0.5 s hold · 2× decay · wet/bury resets
STUN = 10 s flat · LASSO_RANGE = 7 · SNATCH = 0.15 s · GENTLE_DROP ≤ 1.5 tiles
SWIM_GRAV = 120 · WADE = half speed at ≥128 liquid
FLOW_RATE = 3, PRESSURE_RATE = 64
DIFFUSER_FLOW = <tune>
LIVES = 3 · 0 → level reset
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
- **LOOSE_STONE:** soil rules on stone subtiles; Σ popcount extends to STONE; shatter-into-water must eject by flow, never vanish
- **Pockets as trigger volumes:** nothing may push a heroine in unwarned — the aura is the promise; review any FLOW source aimed at a pocket mouth
- **Smolder edges:** the 0.5 s hold exists for bouncing contacts; decay must not negative-clip; wet-fizzle on completion must reset cleanly
- **Room-size ceiling:** open item — profile after E-complete; the 112×15 strip is the current largest authored room; target 4× headroom
- **Wind system:** still TBD; authored draft fields, gas advection, and rain slant all block on it
