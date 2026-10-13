# `world.md` — THE WORLD: Shared Engine & Simulation GDD

*The foundation under the three-game family. The witch doc, the magical girl doc, and the Amazon doc are deltas on this one; where a game doc disagrees with this doc about engine behavior, this doc wins. Where this doc and the code disagree, the code wins.*

*This doc is **final-form**: outlines of game systems that currently exist (written from the code) and systems planned to ship — no history, no decision provenance. Development evidence lives in `dev_log.md`; the working roadmap is `current_plan.md`.*

**Scope.** This doc owns: the room model, the cellular automata, the bridge, the actor shell and contact contract, the enemy frame, the lasso core, doors, pockets, death and lives machinery, the rendering and light rig, the level format, and the generator/checker framework. The game docs own: verbs, aiming, rosters, rooms, economies, and presentation. One 10 Hz integer world that renders itself; three heroines who visit it at 60 fps through the same customs office.

## 0. Doctrine

The laws. When in doubt, these decide.

1. **The picture is the state.** The sim renders itself; nothing draws what isn't true, and nothing true goes undrawn.
2. **Two layers, one customs office.** Actors live at 60 fps and carry heat and wetness. Matter lives at 10 Hz and carries neither. The bridge is the *entire* interface between them.
3. **Magic is the only fidelity break — localized per game.** Each game doc declares its exemptions (her lantern, her halo). The *consequences* of magic — steam, scorch, smolder, melt — are physical and stay inside the GBC bounds.
4. **Every exchange is an integer quantum.** No partial conversions, no rounding loss. All sub-tick rates are stochastic integer events tuned to an expected value; the PRNG makes them lumpy, the ledger only ever sees whole units.
5. **Steam is the universal heat sink.** 1 heat + 1 pool water → 1 steam. Water, steam, damp, and wetness are one unit since the 1:1:1:1 retune — one water-equivalence in one ledger, never conflated. Heat leaves actors only as steam.
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
- Rooms freeze when unobserved (the room containing the camera simulates). A one-room level is always live *(shipped — `Room`/`RoomState`, RT3; the labs keep their grids live)*
- Coyote time, jump buffering, ledge tolerance ride the actor shell *(planned — E3's remainder; the first actress shell is code, the conveniences are not)*
- **Performance discipline:** the CA runs in typed packed arrays (`PackedByteArray` and friends) — that part is shipped. Allocation-free ticks and a native hot loop are targets, not current fact: today the whole engine is GDScript and a tick does allocate (level snapshots, per-run arrays). Actors will ride Godot's C++ physics. Escape hatch: C#/GDExtension if profiling ever demands
- **Room size is an authoring decision, not a budget.** Small rooms mean tight challenges; big rooms mean lots of atoms. The GBC aesthetic is a style, not a hardware constraint. Profile the ceiling on target hardware once the engine is finished; grow from there. *(Open item.)*
- **Determinism rig:** one `RandomNumberGenerator` per room, `seed = level_seed ⊕ room_id`. Derive the room's fixed tile permutation at load, then advance per tick. Actor order is a per-tick PRNG shuffle. *(Shipped: `Room` seeds the per-room PRNG at construction and the bridge advances it — body shuffle and quanta rolls, all inside the tick; RT4 is the same-seed proof. The fixed tile permutation and the `level_seed ⊕ room_id` formula remain plan — `Room` takes its seed raw today.)* Render effects key on (tile hash, tick count), never wall-clock, never the PRNG *(shipped — the streak hashes)*.

## 2. Data model

**Per-tile packet — as shipped** (`TilePacket`): structure-of-arrays — one `PackedByteArray` column per field, one row per tile, the tile index is the row number. Fifteen census bytes per tile (column fifteen: `STRUCT_S`) plus the unbooked claim overlay and the reaction overlays, and a ten-row per-room ledger:

```
TERRAIN : AIR, BRAZIER, SPIKE, DOOR, DOOR_CLOSED — the retirement cut left terrain to the
		  fixtures; authored walls are matter now (world §3)
STONE_S : 4-bit occupancy — displaces 64; loose cells run the sand rules, fused cells sit them
		  out (the structure pass); the fire solver condenses steam against any stone_s face
SOIL_S  : 4-bit occupancy — the nibble IS the matter (popcount = mass)
WOOD_S  : 4-bit occupancy — displaces 64; burns per subtile through the burn pool (64
		  fuel-equivalents each at the flat rate, bone-dry ignition); damp capacity 16 per
		  subtile; renamed from ICE_S (the matter arc's ICE cut); loose wood rests buoyant
STRUCT_S : fused structure membership per subtile cell — overlay state, unbooked, census
		  column fifteen since the retirement cut: authored via the editor's struct brush;
		  the sim destroys, never creates; a member sits out the movement rules until its
		  piece is cut (world §3)
WATER, OIL, ACID, LAVA, SMOKE, STEAM : each 0–255 — the content pool
DAMP    : 32 capacity per soil subtile plus 16 per wood_s subtile, 1:1 with water and steam
TAGS    : bit flags per tile — WET shipped; poisoned/tainted/holy/fertile are planned rows
FIRE_S  : fire bits per tile — overlay state, never packet matter, never booked (shipped)
DEBUG_S : debug furniture per tile — WATER_SOURCE, DRAIN, STEAM_VENT, OPEN_AIR — overlay
		  state, never booked, census column thirteen (shipped)
ACTOR_S : claimed occupancy nibbles per tile — the bridge's displacement overlay: unbooked,
	  never audited, rebuilt at every tick head, never stored in the census (shipped at
	  the bridge lab)
LEDGER  : ten rows — six materials, three subtile kinds, damp; double-entry, asserted every tick (FUEL retired at the cut -- the burn pool rides the reaction overlay)
FLOW    : exported per tile per tick (direction + strength) — derived, not matter — one export
		  per engine: GridWater for liquid arrivals, GridSand for solid crossings
```

**The remaining arc** *(design-ahead-of-code — the plan of record is `current_plan.md`)*: the census pads to sixteen flat bytes with two reserved; TAGS retires (wet computed from damp at read); the density ladder retunes to powers of two; MOIST×4 and HEAT×4 are cut — tile damp stands and lava casts stone by contact (water + lava → steam + stone_s at the acid lab). Census: fifteen bytes today → sixteen at the arc's end.

**The content pool.** Water, oil, acid, lava, smoke, and steam are separate 0–255 fields sharing one budget: their total in a tile never exceeds 255, reduced 64 per solid subtile of any kind — solidity is matter now: capacity is 255 minus 64 per solid cell (a full tile of matter and every fixture read capacity 0; a chipped wall admits water into the notch). Mixtures are allowed; an over-budget tile ejects through the displacement rule — lightest material first, never destroyed. The density table is shipped (water 30, oil 20, acid 40, lava 50, smoke 10, steam 5 — the rest stack, heaviest at the bottom, gas on top) and drives lightest-first ejection, the seek-level pressure heads, and the sort pass (SORT_RATE, units per tick toward the rest layer — steam out-climbs acid's sink 8:1 — one trade per pair per tick); the reaction matrix is planned, and the layering render ships for liquids and gases with palette entries (water, oil, smoke, steam) — acid and lava alias water colors until their labs. DAMP belongs to solids and lives outside the pool; FIRE is overlay state, never matter. Gas thresholds rescale to 0–255 density.

**The actor state block** *(first cut shipped as `ThermalBody`)*. Every actor — heroine, enemy, pot, thrown ball — carries:

```
heat      : 0–64                  # thermal currency; actor-layer only; HEAT_MAX 64 since the retune
wetness   : 0–64                  # the 1:1 lattice since the retune; SATURATED ≡ 64 — one unit with water
weight    : byte + class L/M/H    # per-game resolution reads this (planned)
archetype : behavior + projectile profile + landed state (planned)
drip_mul  : drip rate multiplier, per-10 (10 = full rate, 0 = holds its water) — shipped
trajectory: ring buffer, ~1 s of position + heading at 60 fps (planned)
holdings  : pot contents, held-enemy refs — ledger-visible (planned)
```

Heroes are 16×32 (the shipped hitbox is 8×24 — a subtile wide, three tall) and span up to three tiles; every thermal operation picks one overlapped tile per tick via the PRNG (drip target, absorb source, boil site, steam emission) — *shipped, the `_pick_index` law; BT7 is the same-stream proof*. Underfoot operations target the support tile — *DRY shipped; MELT planned*. Per-tile volumes (the hitbox profile in nibbles), the entry tile, and the wake are owner-written at frame speed; the bridge spends them at tick speed.

**The smolder overlay** *(planned)*. A runtime per-fuel-tile timer, not packet data. Room resets clear it; snapshots don't carry it. *(The shipped contact-ignition timer, `GridReactions._ignition`, is this pattern's first code — overlay state, cleared on reset, never booked.)*

**Room record:** baseline / saved bytes / saved enemies / tagged / enemy_baseline, plus held-enemy exclusion marks — captured enemies are out of the baseline; nothing duplicates across a door.

**Conservation ledger.** The shipped core is `TilePacket`'s ten rows — the six pool materials, the three subtile kinds, and **DAMP at 1:1 water-equivalent** — asserted every tick alongside the per-tile pool constraint (Σ content ≤ capacity, no two subtile kinds claiming one cell) and the damp constraint (damp ≤ capacity: 32 × soil popcount + 16 × wood popcount); a drift is a bug. The family checksum — the whole pool + damp + every body's wetness — brackets every tick as the first rung of the actor-side ledger. Planned rows and books extend it: reactions as balanced integer transfers, plus **boundary-flux** (exteriors, waterfalls, rain), **pocket-loss** (sanctioned destruction — the ledger calls it fine), **fauna flux** (spawn-stream entries and exits, booked like rain), and **actor holdings** — wetness at 1:1 water-equivalent, pot interiors, held enemies — attached and detached as flux, transferred at doors. The finer per-actor books remain design.

## 3. Element simulation

The shipped tick — one room, fixed order. The ruling is **furniture and the bridge, then solids, then liquids, then reactions**: the sources dose before matter moves, the body's claim is live capacity before matter moves, sand's repack deficits are resolved by water's displacement pass the same tick, reactions read settled matter, and the reaction tick owns the packet assert (last engine's privilege — `Room.tick` runs debug → bridge → sand → water → react, so the full engine's ledger assert lands at the very end).

```gdscript
# shipped today — Room.tick() calls exactly this, in this order:
debug.tick()    # GridDebug: the furniture pass, gated by has_debug — sources dose and stamp
				#   (refused units un-made), drains take, open air eats the gases (world.md §3)
bridge.tick()   # ActorBridge: clear the claims -> rebuild every body's claim -> per-body
				#   passes in a PRNG-shuffled order, family-checksummed (world.md §4)
sand.tick()     # GridSand: flow reset -> expand the packet nibbles -> subtile pass, bottom-up,
				#   alternating sweep (tile crossings stamp solid flow and carry damp) ->
				#   repack (popcount deltas booked)
water.tick()    # GridWater: flow reset -> level snapshot -> analyze (bodies, regions, escape)
				#   -> displacement pass -> per-material cell pass densest-first (MOVERS: lava,
				#   acid, water, oil, smoke, steam; liquids flow and seek level, gases rise; every move
				#   viscosity-capped; absent materials skipped) -> the gas exchange pass (both gases present) -> density
				#   sort pass (two materials present) -> the O(1) volume checksum from the ledger + the optional early assert -> levels_changed
react.tick()    # GridReactions: soak pass (water -> damp, percolation skip; only when
				#   water exists) -> the fire solver + ignition delay (only when fire exists) -> condensation
				#   (steam present, fire-suppressed) -> tag pass (wet hysteresis) -> the packet assert (reactions run last, the load-bearing one)
```

**Debug furniture** *(shipped — `GridDebug`, the editor lab)*: sources and sinks as room markers, live during play, authored outside the play area in finished rooms. A water source doses 16 units per tick (SOURCE_DOSE; accepted units book through the pool and stamp the flow export in the feed's direction — refused units are un-made, the smoke precedent: no debt, no buffer); a drain takes what arrives, all six materials; a steam vent doses upward; an open-air tile eats the gases it touches and counts as open sky for the analyze pass while it stays air-passable (a drowned vent stops venting). The pass rides the tick head before the bridge, gated by `has_debug` — buried furniture is inert (seal a spring and you dam it) — and it never touches the PRNG. Furniture never books: census column fifteen, DT0–DT4 the proofs.

The full build adds the passes below — all *planned* except the reaction pass, which ships with soak, the fire solver, contact ignition, and condensation. Order stays a ruling: work orders at the head (bridge in, matter out), matter next, chemistry after movement, render last and never coupled. **Every rule in this doc is integer-only, deterministic, and free of the render clock.**

```gdscript
func element_tick(room):               # the full engine, once built
	var order = room.permutation        # fixed, derived from the room PRNG at load
	_apply_work_orders()               # THE BRIDGE — buffered actor orders,
									  # tile order, then per-tick PRNG actor shuffle
	_sand_pass(order)                  # loose subtiles first (GridSand, shipped above)
	_liquid_pass(order)                # liquids next (GridWater, shipped above): oil, acid, lava
	_seek_level(); _export_flow()
	for idx in order: _reaction_pass(idx)  # transformations (GridReactions, shipped: soak + fire solver + ignition + condensation) — chemistry after movement
	for idx in order: _fire_pass(idx)     # shipped — inside GridReactions.tick, gated by has_fire()
	for idx in order: _gas_pass(idx)      # shipped — inside GridWater.tick (rise + pinned creep + up-diagonal hop + exchange); never seek level
	for idx in order: _growth_pass(idx)
	# _phase_pass — COLD CUT (freeze, thaw, heat-melt, cast, glaze)
	# _smolder_pass — SMOLDER IS ACTOR-SIDE (beam owns the timer; CA keeps the steam and the fuel)
	ledger.assert_all()                # materials + pool + per-actor heat and wetness
```

**Liquids — GridWater is authoritative.** Built and tested; where this document and the code diverge, the code wins. Every pool liquid runs the same four rules as its own pass, densest-first (`MOVERS` = lava, acid, water, oil, smoke, steam — the loop order IS the drain order; the gases run their own rules), every move capped by the material's viscosity — a throughput limit that never changes an equilibrium, only the pace of arriving. Rules as shipped: FALL (exclusive, instant — up to the viscosity cap of what fits goes one tile down; columns fall coherently), POUR (over lips into dry space only — the target below one line — corner-safe, air-gated), CREEP (half-difference into dry space, capped and gated), SEEK LEVEL (each horizontal run is one incompressible conduit; per run per tick, one workable pair trades volume surface-to-surface — up to PRESSURE_RATE, capped by half the pressure difference, the receiving room, and viscosity; pressure heads are density-weighted column integrals from each column's surface to the run row — hydrostatic pressure at the choke, so oil's units weigh less than water's; the actionable floor is PRESSURE_MIN_DIFF × density; donors must carry m at the conduit row; a failed transfer falls through to the next pair; a full capped column between two heads is a rigid pipe). **The density sort pass** closes the liquid work: vertically adjacent tiles trade when denser sits above lighter — the upper's densest sinks, the lower's lightest rises — pair rate = the slower material's SORT_RATE, one trade per pair per tick, take-both-then-add-both so a full tile's freed budget always covers the incoming units. Invariant: every move downhill-or-level; Σ(units × density × height) never increases. Air is gated, not simulated — never stored, never swapped: each tick's analyze pass marks which air can reach open sky (escape) and which pocket it belongs to, and the gates rule on those marks — (a) escape to open sky, (c) the donor's own receding headspace, (d) rotation (pocket and body also touch higher up) — with sub-line films (≤ AIR_PASSABLE_MAX) passing freely as same-pocket shuffles. Determinism: alternating sweep per tick; the escape flood is an order-independent monotone fixpoint. Scan-order guarantee: each cell's pass runs once per tick; vertical moves only deposit into already-scanned rows; lateral CREEP cascades are convergent and intended. Pool-aware capacity: arriving liquid competes with resident liquid and gas for the budget; overflow displaces per the rule below.

*Known approximations (accepted):* region labels one tick stale; donor headspace freely expandable; divided vessels can rest one line off level. Rises into escaped-to-sky headroom exist — the threshold-gated rise above a full m-surface (diff ≥ POOL_MAX × ρ, escape-gated up the receiving column); pocketed headroom keeps the gate. Rise is priced in pressure, never in head cells.

**Displacement** *(shipped — rule five, `GridWater._displacement_pass`)*. A solid subtile reduces the tile's pool capacity by 64; four subtiles is fully solid. When capacity drops below current content, the excess ejects up its own column — solids sink, liquid climbs — depositing at the first free, escape-reachable tiles, **lightest material first** (steam before smoke before oil before water). Leftover excess persists to the next tick; the entry gates (the sand rules' landing check) should have prevented it. Matter is displaced, never destroyed.

**Flow export** *(shipped — one per engine)*. GridWater exports liquid arrivals; GridSand exports solid crossings — one subtile arrival stamps 64 pool-units (SUB_FLOW_MASS), so a landslide and a waterfall read on one scale (two crossings = 128 > DIFFUSER_FLOW: a rockslide is a diffuser — intended, review-flagged). Both follow the same pattern: arrays wiped at the owning engine's tick head, magnitudes sum, dominant direction by largest single arrival, first stamp wins ties. Gameplay *(planned consumers)*: pushes actors and loose objects (capped vs. walk speed). Rendering *(shipped consumers)*: strong downward flow draws waterfall streaks (above **FLOW_STREAK**); the debug overlay draws both engines' arrows. A tile with liquid-in-transit above **DIFFUSER_FLOW** is a *diffuser* — the condition is exported (the constant ships; consumers are game-side — the witch's beam cannot pass one). Consumers also read coarse level bands — DRY / WET / HALF / FULL — off `levels_changed`; fine units stay internal.

**Buoyancy** — the weight system (design-ahead-of-code, the buoyancy lab). Everything that floats does it by weight, and weight is countable: a wood_s is 1; the witch is 3; other actors carry their own; soil riding on top is 1 per subtile, stone_s is 4. Displacement buys lift: minus 1 weight per 32 water displaced. A wood subtile nets −1 submerged and 0 half-submerged — a lone plank floats half-out, a raft of N rides with (N + load)/2 members down, and a load sinks it until the balance returns. The check iterates: positive weight displaces and sinks one subtile, then re-checks with the displacement already paid; negative rises. Oil generalizes onto this machinery. The witch's side: no more infinite stroke-jumping — she floats to the top, rests with her bottom half submerged, and a stroke from the surface buys exactly 10 pixels above the water top (the SACRED jump, kept through the water). Walking the bottom requires ballast — the future grab mechanic's job.

**Soil (subtiles)** *(shipped — `GridSand`, ST1–ST11)*. 4-bit occupancy; popcount is matter, Σ popcount asserted every tick by the ledger's SOIL_S row. All sixteen shapes representable — transient shapes during falls and slides are the animation. Stability is what the rules produce for loose matter — a fused structure member sits the pass out entirely (world §3's authored freeze), and a burning subtile does not move — fire pins its fuel; the ember burns out where it lies and what it leaves behind falls. Moves as shipped: fall if below empty — one subtile per tick through air, gated single-cell sub-steps so nothing tunnels; through liquid, sink at the material's SUB_SINK rate (soil 1, stone 2, wood −1 = buoyant, rests — rising is the float lab, not yet code); slide diagonally if the diagonal-below is empty and the side is clear (corner rule); repose emerges — settled neighbors differ by ≤ ~1 subtile; piles are 8px staircases. 8px is a hop, never an auto-step. A landing subtile must find the tile enterable: terrain that holds a pool, and either the budget fits (255 − 64 per subtile) or the displaced liquid has escape-reachable headroom up the column (air-gate family). Soil sinks through water and the water closes in above it (ST4); a sealed basin exchanges soil for water exactly, one subtile per 64 (ST5); and **a sealed column sorts by density too** — the sealed-chamber swap: a crossing subtile may enter a full tile whose terrain holds a pool when the source absorbs the liquid the destination sheds (soil tolerates the one-unit clamp gap — its damp drinks the squeeze; stone and wood demand the exact fit), the liquid rising into the space each subtile vacates, booked both sides (`shift_pool`; ST11). *Shipped (Lab E):* moisture is mortar and damp is code — capacity 32 per soil subtile, exchanged 1:1 with water and steam (a full tile: 128; a full water tile over full soil soaks to exactly 127). Soak runs in the reaction pass: a water-bearing tile drinks clamp(w/16, 1, 16) per tick into the first headroom down its column — its own soil, else through saturated soil below (the percolation skip: the search moves, damp doesn't); a deep pool soaks only through its bottom tile; water never soaks across air, water-only tiles, or full-solid terrain. Damp rides crossings — a departing soil subtile carries an even share of its tile's damp (≤ 32). A tile gains the **WET** tag above 50% of damp capacity and loses it below 30%; a wet tile reads the sticky row — **no slide for any kind, fall never gated**. Render: pixel lines from the top of the occupied region, 8 damp per line — the creeping front. *Shipped:* fire's steam siege dries — the boil ladder drains damp at `BOIL_D` 4/2/1, so burning a wet slope can now trigger the landslide (the dried soil slides, burying fire, spikes, enemies). *Shipped:* DRY underfoot is code (§4.2) — a HOT body dries the damp underfoot, steam-converted, so the wet tag can clear under a heroine's feet and the landslide verb runs both ways. *Planned:* FIZZLE and the smolder-driven driers.

**Moisture** *(design-ahead-of-code, the groundwater lab — supersedes the tile DAMP column, the even-share crossing handoff, and the top-down render band). Moisture belongs to the subtile: soil carries 32, wood 16, and the value travels with its subtile — the crossing handoff is exact, no even-share, no migration between neighbors. Soak drinks bottom-up, the lowest soil subtile with headroom first. Mortar is per-subtile and analog: a wet subtile does not slide, its dry neighbor may — the WET tag, hysteresis and all, retires with the TAGS column. Wood_s must be bone-dry to ignite. Render darkens the subtile itself, not the tile. DRY and the boil ladder keep reading the tile total.

**Structures** — stone_s and wood_s, authored matter (the structure pass is code — bedrock stages two and three, BK0–BK11; authored walls convert pre-fused at the retirement cut; the doctrine locked at the bedrock and movement sessions). A STRUCTURE is a set of stone_s/wood_s subtile cells an author fused — the editor's structure brush today, the player's fuse ability tomorrow (out of scope until then). Membership is census state, never derived; **the sim destroys structures, never creates them.** Every member subtile is either structure (frozen) or loose (moves), and authorship decides — not connectivity. Connectivity is orthogonal subtile adjacency only — diagonals never connect, within a tile or across it (the tile-is-one-place ruling is retired). When a member subtile dies — burned, dissolved, erased — the piece re-partitions: every orthogonally connected run of two or more members is its own structure from there; a lone member reverts to the loose rules (stone sinks at 2, soil at 1, wood rests buoyant). Members never run the per-subtile movement rules — a structure is rigid, permanently; **all structure motion is whole-piece, and none of it lives in the structure pass:** an **unsupported piece falls as a unit** (the compromise rule, made real — C3's burned aqueduct comes down as beams, not dust); a piece **on a slope slides by its contact patch** — one patch offering multiple downhill options slides toward the piece's center of mass, and a center of mass directly over the patch is *balanced* (no slide); multiple patches vote — synchronous desires slide, opposed desires balance; a piece **in liquid moves with the liquid's current field** (the currents lab; float and sink by the weight system's lift, §13); and a piece **in hand is luggage** — her lasso is universal, one grasp set: enemies, pots, and structures, one thing at a time, a structure taken only within her weight cap and, while carried, rotated in 90° increments for the toss or the placement — building a bridge with tetris blocks on the shard-actor pattern (the Amazon's fling rides the same machinery). Lab owners: gravity, slope, and float ride the buoyancy lab's weight system; advection rides the currents lab; pickup rides the shard-actor pattern — until each lands, a cut piece holds exactly where it stands. The anchored graph is retired with it: no boundary anchor, no terrain anchor, no dissolution on lost support — authorship freezes, and only cutting (or the later motion labs) moves anything. The collision mirror already reads subtile solidity — conversion stays invisible to her feet. *Rulings locked at the movement session: structures are authored and never sim-created; diagonals never connect; cuts partition — runs of ≥2 survive as separate structures, singletons go loose; whole-piece motion is later-lab (unit fall, slope balance, current advection, lasso pickup within her weight cap); and SOIL terrain stays dead — it exits the enum at the retirement cut with a census migration, not before (saved bytes carry indices).*

**Wood terrain and fuel** *(retired at the bedrock lab's stage three — wood is matter now)*. WOOD terrain and the FUEL column are gone: authored walls convert to pre-fused 4/4 wood_s, and the burn rides the reaction overlay — 64 fuel-equivalents per wood_s subtile, drained at the flat `BURN_RATE` 24, bone-dry ignition (any damp refuses), each emptied subtile's bit clearing through the cut so burned beams re-partition mid-fire. A converted wall holds damp at 16 per subtile (a full tile's 64, matching the old flat cap). Vine and coal fuel values, loose-fuel buoyancy, and scorch remain planned.

**Reactions — the third system** *(shipped: `GridReactions` — soak, the fire solver, contact ignition, condensation; the subtile-breath air model at the bedrock lab)*. Movement has two owners — GridWater for liquids, GridSand for solids — and transformation has a third: a reaction engine that binds the packet and the stone facade, reads settled state, and runs after both movement passes. Reactions #1–#4 are soak, fire, ignition, and condensation; the planned roster is the matrix below — acid's dissolve, lava's cast, freeze, glaze — each a row in one pass, never a rule bolted into a movement engine.

*Beyond soak, fire, and condensation: design ahead of code. The packet hosts the pool columns and the density/sort tables, and the displacement pass will eject any of them — but acid and lava have no rules, reactions, or renders yet; oil is burnable fuel (the solver reads pool oil at `OIL_PER_FUEL`), though its planned float-layer travel is not authored.*

**Oil** *(movement shipped — `GridWater` MOVERS; reactions planned)*. Pool liquid, fuel 255. Movement is live: oil runs the four flow rules at viscosity 32 (water runs unthrottled at 255), floats above water through the sort pass, and never soaks into soil — the soak pass reads water only (OT4). Oil with water above trades down through the sort pass; within a tile they layer by share. *Shipped:* pool oil is burnable fuel — `OIL_PER_FUEL` 4 (255 oil burns at four times a 255 fuel tile), flash-catches after one contact tick (`IGNITE_OIL` 1), and refuses to catch while water sits on top of it. *Planned:* burning oil travels the float layer and self-limits as it consumes — the one sanctioned fire that swims. **Oil grants no wetness** — an actor in oil neither soaks nor dries (bridge-side, planned), but a HOT actor standing in it is standing in fuel (§4.4).

**Acid** *(column shipped; rules planned)*. Pool liquid. 64 acid dissolves one subtile of stone or soil (or 64 fuel of wood), consuming itself. Acid decays and is purged below 64. Deliberately unlike water, which is conserved forever.

**Lava and the rock cycle** (design-ahead-of-code, the melt lab). Lava is permanent fire: every 64 units in a tile is one fire subtile for heat and ignition — the boil ladder, the contact-ignition stimulus — with no air gate (it is molten rock, not flame; it never starves and never smothers). The cast: 64 water + 64 lava → one stone_s at zero heat + 64 steam (water keeps its 1:1 into steam; lava keeps its 64:1 into stone), formed in the lava's tile, one quantum per tile per tick, and the quantum holds when steam has no room. Stone_s carries heat exactly as a witch does: 64 capacity per subtile, gained +4 per tick under lava contact (same or adjacent tile), spent 1:1 as steam against pool water in the same or adjacent tile at her tier rates (4 shallow, 16 at 128+), no ambient cooling, no exchange with actors. At full heat AND lava contact, the subtile melts back — 64 lava, booked. New stone_s is cast at zero heat: the re-melt timer is physics, sixteen ticks of continuous contact — pour water on lava faster than it boils and the rock wins; stop pouring and the cycle churns back. That is the game.

**Fire** *(shipped — the `GridReactions` fire solver, FT1–FT11)*. A burning tile is fire bits on its own fuel — no projection: the flame above fuel is the renderer's lick, and a tile's fire lives exactly as long as its own fuel. Per tick, per burning tile: burn fuel constant (`BURN_RATE` 24 — never ventilation-modulated; bits pace everything but the burn), pool oil at `OIL_PER_FUEL` 4; vent smoke at `SMOKE_PER_UNIT` 4 as a production rate — created matter books where it fits, the remainder is un-made (no debt, no buffer; the source's own headroom first, then the breathiest orthogonal, compass order breaking ties — a chimney is a neighbor like any other, never the first-choice dump); engulf one more bit; and each bit boils water and damp up the tiered ladder at Chebyshev rings 0/1/2 (`BOIL_W` 8/4/2, `BOIL_D` 4/2/1 — standing water at twice the damp rate everywhere; the rings ignore occlusion by ruling: stone-slowed distant boil is the readable distinction; water-steam boils in place where it stands, damp-steam is created matter vented from its source). The air gate is all-adjacent: the tile itself or any orthogonal holds pool_free ≥ `AIR_MIN` 16 (LINE) — starved flame dies at the starve, unbreathing flame smothers (FT2's sealed niche self-smothers once its own smoke jams the vents). The universal snuff stays: drown it or bury it. Burning needs the FUEL field or pool oil (`_burnable`; the spark's bit carries neither and dies); FUEL 0 → out (WOOD → AIR: arson is level editing; scorch planned). Damp siege is the boil ladder — two fires besiege the damp out and catch (FT4). Spread is the shipped **contact ignition delay**: cold fuel in orthogonal contact accrues ticks toward catch — `IGNITE_WOOD` 5 (the front walks 2 tiles/s), `IGNITE_OIL` 1 (oil flashes), the timer is the material's (multiple burning neighbors never stack it), catches land from a pending list after the sweep (same-pass catches must not cascade), damp fuel refuses, oil under a water layer waits (FT3, FT4); wind ember-leaps planned. **Ignition by heat — as opposed to open flame — always goes through smolder (§4.4), still planned.** Open CA fire spreads with no warning: it is already matter.

**Gas** *(shipped — `GridWater`'s gas rules, GT0–GT9; condensation in `GridReactions`)*. Smoke and steam, each 0–255 in the pool, joined `MOVERS` at the fire lab and run their own rules: **rise** first (the fall inverted, viscosity-capped); **lateral creep** only when pinned above — half-difference into lower-gas neighbors, both sides, cascading convergently (GT2's ceiling spread); an **up-diagonal hop** when blocked above and beside — one solid flanking corner is a corner to round, both is the sealed crack (GT4's lip); and the horizontal **exchange pass** — gas-holding neighbors trade ratios at half-difference capped by `GAS_SWAP` 16, both givers taken before any add, refused adds refunded — so mixtures stratify horizontally (GT6, GT7). Gases never seek level: a gas column is not a pressure vessel, and the sort pass is the only elevator a gas needs through liquid. **Condensation** is code: steam rains into water at `CONDENSE_RATE` 2 in place on tiles orthogonally touching cool STONE (wood insulates), suppressed within Chebyshev `FIRE_DIST` 4 of active fire — the enclosed water cycle (GT3's rain, GT5's sealed cavity). **Currents** (design-ahead-of-code, the currents lab — wind, grown up). A current is a solved field over a body, not matter moving: per air pocket or liquid body, a direction and a magnitude resolved from sources toward sinks. Sources are authored — a water source, or the new air-source tile; sinks are the escape doctrine's own furniture — air seeks open-air tiles, liquid seeks drains. The solve routes through the body's live geometry with total magnitude conserved from source to sink, so a chokepoint concentrates the same flux into less area (faster, never more) and a widening weakens it; sealed sections hold static — if it has nowhere to go, it doesn't go. The entry gate, extended to flow itself. The field re-solves as contents change: dam it, breach it, choke it — player-editable hydraulics. Coupling: smoke and steam advect through air currents, light floaters ride liquid currents, actors get pushed game-side. Render is its own CaFx module (parked while CaFx is locked; the debug arrows carry it first). The abstraction is deliberate — a readable field beats honest fluid dynamics.

**Rain** *(planned — deferred with boundary flux, post-arc; C3 authors with the shipped furniture (sources and drains) until/unless a rain system returns with world's boundary flux)*. Exterior rooms expose open-sky columns; exposed tiles gain water per tick; wind slants it; water leaving the map is boundary flux.

**Electricity** *(planned — deferred to M5, the eel's lab)* exists only as conductive bodies. A spark is a flood through a connected wet body — the sim's own body graph. Wet paths are wires.

**Botanical triggers** *(planned — owned by the beam lab (M3))* (the sensor family — no tech in these worlds, forest spirits only): gate-fungus (wet contact), pitcher plant (level switch), snap-grass (flow switch), scorch-bloom (fire contact). Field state, queryable by level logic.

**Body-state subsystem** *(potential, planned)*. Per-body quality flags for connected like-material bodies — water: poisoned, tainted, holy; soil: fertile or not. Quality, not phase: water, steam, and ice are three distinct elements with phase-change rules, never tags on one body. Potential system. *(The WET tag is this system's first brick, shipped — per-tile for solids; connected-body tags are the planned extension.)*

**Reaction matrix** *(planned beyond soak and the fire lab's shipped rows — every cell is a puzzle verb; bold cells are code)*:

| | |
|---|---|
| water + cold → ice (32 ⇄ 1 subtile) | ice + heat → water |
| lava + water → stone subtile + steam | acid + stone/soil → AIR (−64 acid) |
| **oil + fire → surface burn** | acid + water → poison body |
| soil + water → damp (1:1, integer) | soil + sustained fire → glaze |
| **fire without open air → out** | **damp + fire → steam siege** |

Heat arrives at this matrix only through the bridge — never as a stored field.

## 4. The bridge — actors ↔ matter

### 4.1 Two layers, one customs office

Actors mutate heat and wetness freely at 60 fps (flap costs, throw vents, contact gains). Matter only ever changes at 10 Hz. An actor's heat "waits for the bus": generated at frame speed, relevant at tick speed. All actor→CA effects buffer as work orders and apply at the head of the tick, in tile order, then per-tick PRNG-shuffled actor order. The banned bug class: **any code path where an actor writes tiles directly.** *Shipped at the bridge lab:* the work orders are the claim and displacement passes, the shuffle is a Fisher–Yates on the room PRNG, and the ban holds in code — `Witch` owns pixels, `ThermalBody` owns state, `ActorBridge` owns tiles.

### 4.2 The thermal exchanges

All rates are expected values of stochastic integer events rolled on the room PRNG. Tiers key off the tile's water content. *Shipped as `ActorBridge` (BT1–BT14) at the 1:1:1:1 retune — water, steam, damp, and wetness are one unit. MELT stays reserved.*

| Exchange | Direction | Rate | Quantum |
|---|---|---|---|
| **ABSORB** | pool water → wetness | tier: <128 → 4/s · ≥128 → 16/s · =255 → instant to saturation | 1 water → 1 wetness |
| **DRIP** | wetness → pool water | ~4 water/s, randomized, drip_mul-scaled | 1 wetness → 1 water, PRNG-picked overlapped tile |
| **BOIL** | heat + pool water → steam | same tiers; instant at 255 = min(heat, water) | 1 : 1 : 1, steam lands in the tile |
| **CROSS-TALK** | heat + own wetness → steam | 8 wetness/s flat | 1 wetness + 1 heat → 1 steam |
| **DRY** | heat + soil damp underfoot → steam | 8 damp/s | 1 damp + 1 heat → 1 steam |
| **MELT** | heat + ice underfoot → water | 16 water-eq/s (one subtile / 2 s) | 1 heat per water; CA-side, billed |
| **FIRE/LAVA contact** | CA → actor heat | +4 / +8 per tick | — |
| *(reserved)* **FREEZE** | mirrored MELT | post-slice | — |

Laws and consequences:

- **Steam is the only exit for heat.** CROSS-TALK is one rule with two reads: air-drying when the actor is hot, coolant when it's wet. Wetness reduces heat exactly as pool water does.
- **The dunk is a steam bomb, and it self-caps.** At a full tile, min(heat, water) converts in one tick; steam replaces water *within the pool budget* — one tile's worth, never a flood. A heroine at 255 diving into a full pool arrives at 0 heat inside one steam cloud.
- **The carry window.** SATURATED (64, since the 1:1:1:1 retune) drips out over ~16 seconds of walking. Mop here, sweat there, walk fast. *The retune halved the window — the knobs are DRIP and WETNESS_MAX, never a second lattice.* A cold magical girl can ferry water as wetness and boil it on delivery; the witch can drop a hot enemy in a puddle and watch it cool, hissing, on its own.
- **Rain is emergent anti-air.** Rain fills her tile; a hot body boils it as it lands. No authored rule.
- **Drip and cross-talk run concurrently** (a hot, wet actor mostly steams, partly drips). Suppressing drip when hot is a one-line playtest knob.
- **No actor→actor heat or wetness transfer in v1.** Contact effects are archetype modules (a Cinderkit's touch); the only actor-to-actor water channel is drip-then-boil — a held wet enemy cools a hot holder by leaking.

### 4.3 Magic orders

Game-issued, zero heat, still through customs — magic pays no heat, but it goes through the bridge like everything else. The engine executes: **IGNITE** (fuel → FIRE directly, bypassing smolder — the witch's verb; her damp-fizzle rule is game-side) and **FIZZLE** (DAMP −8 + steam — the witch's beam and ignite on wet fuel).

### 4.4 Smolder — actor-side

Smolder — actor-side (ruling at the matter-arc session; supersedes the CA-side plan). The 4 s warning timer is not a simulation concern: the actor layer — the beam, the wisp, a hot body — owns build/hold/decay/complete and the fizzle. The CA keeps only the physics: steam where the fizzle hisses, fuel where the completion catches, moisture where the grind dries. The stimulus crosses the customs office like every work order.

**Shipped versus planned — the two ignition timers.** The fire lab shipped the **contact ignition delay** (§3 fire — cold fuel catching from a burning orthogonal neighbor, `IGNITE_WOOD` 5 ticks) as code; this section's **smolder** (heat-stimulus — a HOT actor or game stimulus building a 4 s warning) remains design-ahead-of-code. They are different machines with different stimuli and different clocks — the shipped delay is the material's timer (multiple burning neighbors never stack it); the planned smolder is the tile's. Never let prose or code merge them.

### 4.5 The door protocol

Actors cross doors; atoms never. At a crossing the engine snapshots the actor's holdings — heat, wetness, pot contents, held enemies — books them as ledger transfers between rooms, marks held enemies out of the source baseline, and freezes the exited room when unobserved. The engine validates water-equivalents on both sides: **actors through doors is the interface.** Player-facing doors always mark room boundaries.

### 4.6 Per-actor ledgers

Heat and wetness assert every tick: gains − spends = current. A lost heat point is a bug, same as a lost water unit. *(Shipped as the family checksum — pool + damp + Σ wetness brackets every tick; the per-actor gain/spend books remain design, and until they land the family sum can hide a swap between two bodies' tiles.)*

## 5. Actors, physics, contact

**The engine owns what moves and what collides.** Heroes are `CharacterBody2D`; projectiles and thrown enemies are `RigidBody2D` with custom integrators; the lasso tip, pockets, and sensors are `Area2D`. CA surfaces (fire, lava, spikes, liquid tiers) are tile-sampled at the tick, not physics shapes.

**Shipped at the bridge lab — the first cut:** `CollisionMirror` is the matter-to-physics half of the contact contract (the CA is truth, so colliders mirror the packet's solid map at 8×8 subtile resolution, re-diffed every tick — fire burns the floor out from under her; boundary walls on three sides, open sky above); `ThermalBody` is the actor's thermal half (§2); and **the witch walks** — `Witch`, a `CharacterBody2D` on a body, the 8×24 hitbox (a subtile wide, three tall), the 10px jump in code (SACRED), the capacity-aware wade line, swim at SWIM_GRAV 120 with the stroke (gated on sinking) and the crouch dive, the outlined sheet driving her anim state. She never writes a tile — everything crosses the bridge. **Still planned:** typed contact events, response modules, the trajectory ring, stun, `RigidBody2D` projectiles, `Area2D` sensors.

**Contact events** are typed, and carry the geometry (offset, normal, relative velocity) and the state (weight class, archetype, heat, wetness, module payloads). **Modules own the response:** collision-response modules and per-frame trajectory-edit modules attach per actor. The magical girl's bands, pips, spin, and bank behavior are modules on her shots; the witch hangs a gravity module for launch arcs and enemy-specific landed powers on the same hooks. Gameplay events are bespoke and owned by the actor that generated them.

**Universal movement laws:**

- Liquid ≥ 128 in the tile → **half speed** (wading) *(shipped — the line is capacity-aware: half the tile's free capacity in liquid, so a soil-bottomed pool reads true)*. Submerged → **swim**: SWIM_GRAV 120, vy clamp, stroke = jump, 10px surface hop *(shipped in `Witch`)*
- FLOW and wind on the actor's tile push it (capped vs. walk speed)
- Oil is swimmable exactly like water **except** it grants no wetness — and it's fuel
- Every heroine jumps exactly 10 px (the Amazon's sandal double-jump is her doc's one declared dispensation, game-side). Identical legs is the engine joke

**Spike tiles:** top contact only. The engine bounces the actor back along its trajectory ring and emits the event; damage is game policy (the magical girl loses a heart; the witch takes forced panic). The **trajectory ring** (~1 s of position + heading at 60 fps, per actor) is engine infrastructure — the witch's panic breadcrumbs and the spike bounce both read it.

**Stun:** flat 10 s, recapturable — the universal downed state.

## 6. The actor API — universal stats, per-game interfaces

Every actor presents: weight (byte + L/M/H class), heat, wetness, archetype (alive behavior, projectile profile, landed state), drip multiplier, module slots. The four-column frame — *Alive / As projectile / Landed state* — is the engine schema; rosters and behaviors are per-game.

**Weight resolution is per-game law reading one engine byte.** The witch's world treats it one way; the magical girl's bands are equal-mass forever, weight editing terrain instead; the Amazon's five throw arcs key off the same class byte. Universal stats, per-game interfaces — this is the crossover pattern, and it is law: **every enemy must interface with every heroine's verbs, across all three games.** No enemy may assume its native game.

**Shape grammar:** hostile reads angular; stunned/projectile reads round; size = weight. Sprites re-quantize through the palette law's banks — one table, single source of truth, when real art starts. A bank per state (hostile / docile / stunned / burning / wet), so a state machine reads across the room. Pips are a game module, not engine state.

**The pot** is an actor whose interior is a tile: a 255-unit content pool plus 4-bit enemy occupancy (up to four; each nibble costs 64 capacity). Reactions run inside. Contents are holdings — ledger-visible, door-portable.

**Pockets** capture any actor. The engine fires the capture event with the actor's manifest; scoring hooks are game-side.

## 7. The lasso core

Identical core for the whole family (the Amazon's yank and boss-zip are her modules on it). FSM: IDLE → FIRE_TIP (straight, 7 tiles, loose rope render) → SNATCH (0.15 s, auto-reel) → CARRIED (one at a time). Aim within 1.5 tiles of her feet = **gentle drop**: placed docile, unharmed, exactly where put.

**The water-cast is core, not flavor:** the tip travels, refracts, slows — a fishing-line cast. The preview bends identically; the kink is the surface line, so depth reads on sight. Hit = auto-reel; no manual reeling. Range is measured in tiles — water costs time, not cover. Underwater enemies are fishable.

Previews are twinkling dotted lines (random phase per dot, hash-based). Per-game: projectile modules, windup and follow-through frame data, and aiming. Aiming lives on the actors — the witch aims continuously (sprite-center anchor: stick vector or mouse, dotted preview, same anchor for her light); the magical girl throws in one of eight directions, straight before spin, no preview; the Amazon has form for each discipline — previewed, memorized, felt (per-tool aim law, her doc's).

## 8. Rooms, doors, death, lives

**The room model.** One CA domain per room, any size — authoring decides (small rooms are tight challenges; large rooms are many atoms). The magical girl's strip is one room; its reaches are beat annotations, not boundaries. Unobserved rooms freeze. *Shipped as `Room`/`RoomState` (RT1–RT4): the sextet around one packet — debug furniture and the bridge at the tick head — the per-room PRNG (seeded at construction, advanced only inside ticks), snapshot/restore as value copies on both sides — byte-exact, assert-green outside the tick, the stored baseline surviving later ticks (the aliasing canary) — and the blank reset path. Unobserved rooms are frozen by absence: the harness never ticks them. `RoomSpec`, door policy, pockets, death, and lives remain design — the editor (`TestEditor`) is the format's seed, four persistent rooms with their census bytes on disk (§10).

**Door policy is authored per door** — baseline on cycle, snapshot on cycle, restore on exit — machinery here, policy in the game docs.

**Pits are pockets.** One-way capture fixtures, any orientation — floor pits, wall pockets, ceiling wells. Every one renders its **evil aura**: magic-class, unmistakable, the warning is the promise. Matter entering is lost, booked as pocket-loss flux — the ledger calls it fine, nothing flies out, ever. **Any actor can fall in.** A heroine falls in: death. A thrown enemy or ball: captured (the magical girl scores off the event; in the witch's dungeons they are rare, and losing an enemy to one is a tragedy the room reset forgives).

**Death is the same for every heroine.** The room resets to baseline; she respawns at the door she entered from; one life is spent; presentation is a non-event (slump, blinky eyes, 1.5 s). Baseline restore means nothing stays lost — pocketed enemies return, spent fuel returns, the room forgives completely.

**Lives: 3 to start, all three games.** The magical girl earns hers (her prize ladder); the witch finds hers (world secrets); the Amazon's overflow laurels pay hers (four leaves past the heart cap is a life). **Zero lives → level reset:** every room to baseline, inventories and tags erased, back to the very beginning. (The witch's entry-door ritual is her doc's voluntary version of the same reset.)

## 9. Rendering and light

One `Image` the size of the room, redrawn once per tick, pushed through an `ImageTexture`, drawn under actors *(shipped — `ElementRenderer`)*. The sim state is the picture; debugging is looking at the room. All physical state stays in GBC bounds.

**Shipped render** (`ElementRenderer` + `Palette`): beveled stone; liquids drawn as visible lines — units >> 4, one LINE per line — stacked by material share within a tile, densest at the bottom (`LIQ_DRAW` density order; the gases draw their own top-down pass, `GAS_DRAW`), surface crest on the topmost material; oil carries its own bank (dark ochre, far from the water blues) and so do smoke (warm charcoal) and steam (pale blue-white) — acid and lava still alias water until their labs; covered tiles filling solid, and **sub-line films (< 16 units) drawing nothing by design**; the waterline lifts over the tile's own soil subtiles — a squeezed pool reads higher (both bottom subtiles +4 flat, doubled and capped +6 when a top slot is also filled; one bottom subtile doubles the lines, capped +2, or +4 with a top slot; clamped at 15); waterfall streaks replace the fill on strong downward flow (above FLOW_STREAK 48 — hash-keyed on tile + tick, never a PRNG; tinted by the majority liquid); soil subtiles as 8×8 quads with a lit lip where uncovered and damp darkening from the top of the occupied region — 8 damp per pixel line, the creeping front — matter subtiles as 8×8 cells on the seam rule — lit lips on exposure, dark seams against matter that is not their structure, silence between two members — so a fused beam renders seamless while loose cells read individually (world §3); stone fills beveled, wood plain — dusty khaki tan against soil's umber; wet wood dithered toward the dark row (fire quads ride either solid); gases drawn top-down — checker dither at eight units per line from the tile's top, fully solid past 121, the row count from the tile's total gas with the rows split across smoke and steam by share, lightest band on top (the liquid stack partition, mirrored; sub-eight films draw nothing), and every liquid read — lines, crests, the covered check — excludes the gases (`_liquid_total`); and the rain is liquid's picture only — a flow stamp with no liquid beneath it is gas in transit, and a gas-majority tile never rains; fire bits on top of everything the tile holds as a 3-frame palette cycle (`BANK_FIRE` brightward — hash-keyed per tile, never the PRNG); the debug overlay (G) tints sealed vs vented air, draws per-segment level lines, water and solid flow arrows, the tile grid, and the hover cursor; debug furniture glyphs — source spout, drain grate, steam vent, open-air brackets — draw over everything: author furniture, never part of the world picture.

**Shipped ambiance** *(the editor lab — `CaFx`, `AmbGen`, `AmbCave`)*: a second painter brackets the tile pass. The under-pass serves a map-sized background texture — the module contract: world-blind, layout pure in the seed, animation pure in seed and slot; the cave's bake is the void default, lumpy rock masses, and thick spike edges, with drip eras as the one motion verb (ERA_LEN 32 ticks, 1–4 drips per era, hashed on the slot so replays replay) — then composes the live sealed stencil over it: bank-dark checker dither at sealed air, escape the one opinion every shade follows. The over-pass is the effects layer (currents, waves, splashes, bubbles, licks) — empty, wired so the painter's order never changes again. The FX domain is the room seed XOR a salt: a different stream from the CA by construction, never the sim PRNG (§0 law 9). Four dungeon sets — whisper blue, brick crypt, moss grotto, sandstone catacomb — recolor the same cave today; a backdrop's identity is (seed, set).

**Shipped palette law** *(the editor lab — `Palette`, `TestPalette` PT0–PT3)*: master is DB16 canonical, named so banks read without index math; guests are additions beyond DB16, one # reason each — the lock is procedural, never a ceiling. Tile banks hold at most four colors (a material's whole face, index 0 darkest); sprite banks at most three plus transparency (the outline is a bank color); no `Color(...)` literal outside `palette.gd` — the audit enforces it; debug and editor overlays are exempt, never shipped art.

**Palette** *(planned beyond the shipped law)*: per-room remaps tint the active bank while semantic slots stay pinned; sprites re-quantized through the palette when real art starts. Heroine eyes: two 1×2 unshaded pixels on a canvas layer above the CanvasModulate — cartoon law, per-game color.

- Water *(planned beyond the shipped lines)*: dithered films below one line; 60 fps shimmer over 10 Hz steps (the period-authentic split)
- Mixtures render layered by density within a tile *(planned)*
- Subtile solids: 8×8 quads — terrain editing at hardware-tile resolution *(shipped for soil; stone and wood pending)*
- Damp front: pixel lines from the top of the tile's **occupied region** — 8 damp per line, 16 at saturation — so a bottom-only tile still shows a level; percolation is visible *(shipped)*
- Gas: checker dither by density, top-down, bands split by ratio *(shipped — eight units per line)*. Fire: 3-frame palette cycle *(shipped)*. Scorch: permanent dark flag *(planned)*
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

**The editor lab is the format's seed** *(shipped — `TestEditor`)*: four persistent rooms on the F-keys, census bytes saved to `user://editor` slots — the save format's first real artifact. `LevelSpec`/`RoomSpec` remain design; when they land, the editor writes them or a converter does.

Generator notes: run several that disagree — maze output as topology for large rooms; a terrain generator that runs the sim itself (pour water, let it settle, place exit, fuel, and soil relative to where the pools sit); an LLM writing structured specs that a deterministic compiler builds. **Checkers are the real artifact** — the design invariants as code. Engine invariant checkers: riser solvability (8px steps vs the 10px jump), pool legality, ledger closure, pocket-aura coverage (no unwarned capture). Game checkers live in the game docs (the lens audit, band solvability, stream economy, flap tax). Test 8×8 vignettes, not rooms. Keep the seed, not the room. Contact sheets for human curation. The loop — generated rooms inspiring hand-authored ones — is the product.

## 11. Build order — the engine substrate

*Suite and harness inventory: nine registered suites (water, soil, oil, fire — which carries the gas examples — bridge, rooms, palette, debug, structures), run headlessly by `run_all` behind the compile gate; the witch lab and the room editor stay playgrounds, not suites. This section is about stages.*

- **E0 — World:** packet, ledger, the render Image — **shipped** (`TilePacket`, `ElementRenderer`; asserts hold over long runs; the ambiance layer — `CaFx`/`AmbGen`/`AmbCave` under the tiles) — and the room model with it (`Room`/`RoomState`: one CA domain per room, the per-room PRNG, snapshot/restore, unobserved rooms never ticked; RT1–RT4). `RoomSpec` is still design — the editor (`TestEditor`) ships its first real artifact, the save bytes
- **E1 — Liquids:** **shipped** — GridWater as the liquid engine (per-material passes, viscosity, the density sort pass, pressure-head seek level) + flow export + displacement (authoritative), acceptance-tested (water + oil suites); the editor lab widened the export — sort trades and displacement arrivals stamp it too, gas bubbles read UP
- **E2 — Matter:** **shipped** — soil/stone/wood subtiles, the reaction engine, soak, wet tags, and mortar are code (`GridSand`, `GridReactions`); oil movement is code (`GridWater` MOVERS + viscosity + sort); **fire is code** — the fire solver, contact ignition, condensation, gas movement and exchange, the per-subtile wood burn (`GridReactions`, `GridWater`; FT1–FT11, GT0–GT9); the sealed-chamber density swap is code (ST11); **the authored-structure pass is code** — fuse, freeze, cut, burn, census column fifteen, and the terrain retirement (authored walls are pre-fused 4/4 matter; a chipped wall admits water; `GridStructures`, `TilePacket.struct_s`; BK0–BK11); acid, lava, and glaze columns exist in the packet without rules; the bridge drier DRY shipped
- **E3 — Actors:** **first cut shipped** — the thermal shell (`ThermalBody`), the matter-to-physics contact contract (`CollisionMirror`), one heroine's locomotion (`Witch`: 10px jump, capacity-aware wade, swim), claims and displacement (BT8–BT13). The typed contact events, response modules, trajectory ring, lasso core, stun/capture, thrown profiles, and pots as actors remain design
- **E4 — Bridge:** **the thermal half is code** — ABSORB/DRIP/BOIL/CROSS-TALK/DRY, fire/lava contact, the claim column and displacement, the per-tick shuffle, the family checksum (BT1–BT14). Smolder (§4.4), MELT, the magic orders (§4.3), the door protocol, pockets, and per-actor ledgers beyond the family sum remain design
- **E5 — Light:** the palette module is code (`Palette` — the bank law, PT0–PT3; the ambiance layer with it: `CaFx`/`AmbGen`/`AmbCave`); the rig, profiles, and the effects over-pass remain design

The witch's M0–M2.5 map onto E0–E2 + E5; her later milestones build on E3/E4 — and her M4 substrate (the bridge's thermal half, her legs) is code; the panic clock and her verbs wait on the rest. The magical girl builds almost entirely on E3/E4 — her combat *is* modules on this substrate. The Amazon is E2's demanding customer too — the LOOSE flag, the shard-actor pattern, and the wind system — and builds her kinetic combat on E3/E4.

## 12. Engine exit checklist

- Soak test: minutes of random-input simulation, ledger green, zero drift, no float in the CA — assert it *(the ledger and volume asserts run every tick in code today; the harness adds a per-engine drift watch — first offending tick and engine — catching destroy-and-book pairs the double-entry cannot see; the minutes-long soak rig is pending)*
- Same seed → identical replay (per-tick state hash; PRNG advanced only in the tick) *(RT4 ships the proof)*
- The steam bomb self-caps: 255 heat in a full tile → 255 steam in one tile, no overflow, budget-neutral by construction
- Heat and wetness ledgers assert per actor; a hot body entering water cools by exactly the water it boiled *(the family sum is code; the per-actor books are pending)*
- No code path where an actor writes a tile (review-ban the class; grep it in CI)
- Door crossing: holdings transfer exactly; held enemies never duplicate; the exited room freezes mid-flow with no mass teleport
- Pocket loss books; a captured heroine respawns at her entry door with the room at baseline
- Tiers read correctly across a two-tile heroine (head in steam, feet in water) — stochastic picks, PRNG'd, never wall-clock *(shipped — the PRNG-picked tile law)*
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
MOVERS: lava, acid, water, oil, smoke, steam   # densest first; the loop order IS the drain order — liquids seek level, the gases run their own rules
VISCOSITY: water 255 · oil 32 · acid 255 · lava 16 · smoke/steam 255   # flow-throughput cap; <tune>
SAND_FALL = 1 subtile/tick           # all kinds, through air
SUB_SINK: stone 2 · soil 1 · wood −1  # through liquid; wood rests buoyant (no rising until the buoyancy lab)
DAMP_PER_SUB = 32                    # soil damp capacity per subtile; 1:1 with water and steam
SOAK = clamp(w/16, 1, 16) per tick   # reaction #1; the ceiling never binds (w ≤ 255 floors it at 15)
WET_TAG: gain > 50% of capacity · lose < 30%   # hysteresis — the tag is state, not derived
SLIDE_WET = no kind slides           # the mortar row; fall is never gated
SUB_FLOW_MASS = 64                   # one solid tile-crossing = 64 pool-units of flow
TEST_TICKS = 3000                    # acceptance runs to equilibrium (fire timing tests run short and restore)
GAS_SWAP = 16                        # horizontal gas exchange cap, per gas per pair per tick
BURN_RATE = 24                       # fuel-units burned per tick per burning tile — constant, never ventilation-read
OIL_PER_FUEL = 4                     # one oil unit carries four fuel-units of energy
SMOKE_PER_UNIT = 4                   # smoke per material unit burned — a production rate; the un-vented remainder is un-made
IGNITE_WOOD = 5 · IGNITE_OIL = 1     # contact ticks to catch — the front walks 2 tiles/s; oil flashes
BOIL_W = 8/4/2 · BOIL_D = 4/2/1     # water and damp boiled per fire bit at Chebyshev distance 0/1/2 — water 2× damp everywhere
CONDENSE_RATE = 2 · FIRE_DIST = 4   # steam -> water per tick on cool stone; suppressed within this Chebyshev radius of fire
AIR_MIN = 16                         # pool_free the breath set must hold (LINE); see BREATH below
SUB_DENSITY: stone 60 · soil 55 · wood 15   # a solid rests in any pool material denser than itself, falls through the lighter (gas at the air rate)
BURN_POOL_PER_SUB = 64               # fuel-equivalents per wood_s subtile — the burn pool, drained at BURN_RATE
WOOD_DAMP_PER_SUB = 16               # wood damp capacity per subtile (a full tile: 64); render-darkens past half
SOURCE_DOSE = 16                     # debug furniture: units per tick a source emits; refused units un-made
ERA_LEN = 32 · DRIPS 1–4/era · DRIP_FALL_MAX = 16   # the cave's drip eras — ambiance, pure in seed and slot; <tune>

# ── shipped — ActorBridge, ThermalBody, Witch, Room ──
HOT = 63                             # SACRED — smolder threshold (ThermalBody; smolder itself is still design)
HEAT_MAX = 64                        # even maxed, she converts less than she displaces
WETNESS_MAX = 64                     # 1:1 with water — the 2:1 even lattice retired at the retune; SATURATED ≡ 64
DRIP_SCALE = 10                      # drip_mul is per-10: 10 = full rate, 0 = holds
TIERS by tile water: <128 → 4/s · ≥128 → 16/s · =255 → instant (to saturation / min(heat, water))
DRIP = 4 water/s, randomized, drip_mul-scaled   # carry window ≈ 16 s at saturation — the retune halved it
CROSS_TALK = 8 wetness/s flat (1 wet : 1 heat : 1 steam)
DRY = 8 damp/s underfoot (1 damp : 1 heat : 1 steam)   # the bridge drier — the re-tuned price shipped
CONTACT: FIRE +4/t, LAVA +8/t        # overlapped-tile contact heat, capped at HEAT_MAX
JUMP_HEIGHT = 10, GRAVITY = 480, JUMP_V = 98   # SACRED — in code (Witch); identical legs
SWIM_GRAV = 120 · stroke = jump      # the wade line is capacity-aware: half the tile's free capacity in liquid
The 10px surface stroke joins JUMP_HEIGHT as SACRED — the same jump, through water.
CLAIM: occupancy nibbles per tile, clamp 4 — overlay, unbooked, cleared every tick head and on restore

# ── planned — not yet code (E2 acid/lava · E3 lasso and contact events · E4 smolder/doors/pockets) ──
SANDAL_JUMP_V = 139                  # the Amazon's one declared dispensation (game-side) — "DOUBLE JUMP" doubles the 10px jump
ACID_SUB = 64, purge below 64        # acid is not conserved; water is
LAVA_SUB = 64 water (displaces 64)
SMOLDER = 4 s build · 0.5 s hold · 2× decay · wet/bury resets

# ── shipped — the matter-arc fire (GridReactions) ──
BREATH = each fire subtile drinks its own cell + its two corner faces (TL north+west · TR north+east · BL south+west · BR south+east); 4/4 unions to the tile + all four orthogonals; a fire on woodless ground (oil) drinks the tile + all four orthogonals -- pool matter is not positioned
SMOTHER = the igniting material's delay, inverted -- wood 5 · oil 1 · a starving fire pauses (no burn, no boil, no catch, no stimulus) and dies when starved that long
FIRE PIN = a burning subtile does not move -- the ember burns out where it lies · a fire with no wood and no oil gutters: the burn pool is meaningless without fuel

# ── planned — matter arc remainder (the plan of record: current_plan.md) ──
CAST = the contact cast at the acid lab: water + lava → steam + stone_s, one quantum per tile per tick · no new columns
LAVA_QUANTUM = 64 lava per fire-equivalent subtile (heat + ignition + boil; no air gate)
ACID_BITE = 64 stone_s / 32 soil_s / 16 wood_s · 1 subtile/tick/tile · ACID_HALF = 64t · floor 1/tick
WEIGHT = wood_s 1 · witch 3 · soil rider 1 · stone_s rider 4 · actors their own · lift −1 per 32 water · one subtile per step — the buoyancy lab


STUN = 10 s flat · LASSO_RANGE = 7 · SNATCH = 0.15 s · GENTLE_DROP ≤ 1.5 tiles
LIVES = 3 · 0 → level reset

## Appendix — risk register

- **Bridge ordering:** orders at the tick head, PRNG body shuffle — shipped: `Room.tick` runs bridge → sand → water → react, the shuffle is Fisher–Yates on the room PRNG, the family checksum is the thermal assert. The finer per-actor gain/spend books remain design; until they land, the family sum can hide a swap between two bodies' tiles
- **The instant tier:** min(heat, water) in one tick must stay budget-neutral — steam replaces water in the pool by construction; assert it, because this is the steam bomb
- **Multi-tile actors:** one PRNG'd tile pick per operation; mixed-tile heroine states resolve stochastically — accepted lumpiness, deterministic because seeded *(shipped — the `_pick_index` law; BT7 is the same-stream proof)*
- **LOOSE_STONE:** soil rules on stone subtiles — shipped exactly so in `GridSand` (every subtile is loose today; the flag is the planned refinement); Σ popcount extends to STONE; shatter-into-water must eject by flow, never vanish
- **Pockets as trigger volumes:** nothing may push a heroine in unwarned — the aura is the promise; review any FLOW source aimed at a pocket mouth
- **Smolder edges:** the 0.5 s hold exists for bouncing contacts; decay must not negative-clip; wet-fizzle on completion must reset cleanly
- **Room-size ceiling:** open item — profile after E-complete; the 112×15 strip is the current largest authored room; target 4× headroom
- **Wind system:** still TBD; authored draft fields, gas advection, and rain slant all block on it
- **One water-equivalence since the retune:** water, steam, damp, and wetness are a single unit — the family checksum (pool + damp + Σ wetness) is the one tripwire, and the w0 conservation checks and the drift watch stand guard. The old 2:1 wetness warning is retired with its lattice; code and docs must never resurrect it
- **DRY shipped at the re-tuned price:** the 1:1 retune doubled underfoot drying's steam yield and heat cost (8/8, was 4/4) and halved the witch's damp-wall grind (16 fizzles per full tile, was 32) C2/C5's authored damp amounts may still need a pass
- **Two driers in code now:** fire's boil ladder (`BOIL_D` 4/2/1 at distance; damp-steam is created matter, vented from its source) and the bridge's DRY (heat + damp underfoot → steam, 8/s). The wet tag can clear under a heroine's feet — the landslide verb runs both ways; playtest it
- **Smoke is a production rate, not an invariant:** un-vented smoke is un-made — no debt, no buffer. The fire-lab policy (smoke never shrinks, never grows past 4 × burned) is the test tripwire; if smoke ever becomes bookkeeping-strict, the solver's capacity story changes
- **The two ignition timers:** the shipped contact delay (`IGNITE_WOOD` 5 ticks, the material's timer, front at 2 tiles/s) and the planned heat-stimulus smolder (4 s, the tile's) coexist in design — §4.4. Never let prose or code merge them; the pace belongs to the first, the warning to the second
- **The claim overlay is unaudited by design:** `solid_capacity` is the ledger's legality line and the claim never books — its safety hangs on two clears (every tick head, every restore). If a claim ever survives either, `pool_capacity` lies while the assert stays green; the BT displacement proofs (BT10–BT12) are the tripwire
- **Fire breathing through actors:** the air gate refunds claimed volume (+64 per nibble) — fire is a hazard, never starved by a body. No example yet burns a tile under a standing body; author one when smoke meets boots
- **The halved carry window:** the 1:1:1:1 retune halved wetness capacity (64) and the carry window (~16 s at DRIP 4/s). The mop-ferry verbs drain faster; the knobs are DRIP and WETNESS_MAX, never a second lattice — retime the fire-walk endurance numbers in the game docs at their next pass
- **The sealed swap's clamp gap:** soil tolerates a one-unit squeeze (its damp drinks it); stone and wood demand the exact fit — ST6's retimed check (its label renamed at the cleanup pass to say what its body asserts) and ST11 pin it, but any future material with different damp math must re-answer the question
- **The ambiance contract is world-blind by law:** background modules read no live sim state — the sealed stencil is `CaFx`'s alone. A module that reads the room has broken the contract; and the FX domain (seed XOR salt) must never touch the room PRNG — §0 law 9 is the tripwire
- **The palette linter's exemption is narrow by design:** `scripts/testing/` may construct `Color(...)` literals for comparison; any literal elsewhere outside `palette.gd` fails the audit. Keep the exemption that narrow when new suites land
- **The editor's save bytes predate the level format:** the `user://editor` slots are census dumps, not `RoomSpec` — when the format lands, the editor writes it or a converter does; decide then, and keep the old slots loadable
