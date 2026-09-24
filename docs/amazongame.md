# AMAZON DEMO — Vertical Slice GDD v1.0

*Delta doc on `world.md` v1.5 — shared engine, shared enemy IP, different verbs. Sibling of `witchgame.md` v3.0 and `magicalgirlgame.md` v2.0. Where this doc and `world.md` disagree about engine behavior, `world.md` wins.*

**Engine deltas we are the demanding customer of:** the **LOOSE flag** (world §3, planned — her sword is its first real client), the **wind system** (world's open item — authored gusts ship in this slice regardless of the draft field), and the **shard-actor pattern** (matter leaving the packet as actor holdings and returning on settle — the pot-interior precedent generalized; a new customer of two planned rows, no new law). **One heroine-value dispensation, declared openly:** `SANDAL_JUMP_V`.

**Goal:** one island, one dungeon three levels deep — seven rooms plus the beach on top — where every verb — slash, yank, brace, rout, herd, throw, swing, burn, gust — is operational with placeholder art. One mini-boss (the Taken), one boss (Old Goldhide). If this slice is fun with gray boxes, the game exists.

**Pitch:** a Game Boy Color–styled metroidvania where nothing dies — it flees. The enemies are tools, the level is a corral, and the pirate lords are friends she hasn't freed yet. Her fire is cargo, her light is a fuel budget, and the only thing that ever gets destroyed is terrain.

**Inheritance map:** tech (world §1) · data model (world §2) · element sim (world §3) · the bridge, heat and wetness, smolder (world §4) · rendering and light (world §9) · actor API and weight (world §6) · lasso core (world §7) · rooms, doors, death, lives, pockets (world §8) · level format (world §10).

**Changelog v1.0** — consolidation of brainstorm v0.1–v0.4

- **Rooms reset on exit. Completely.** The witch's snapshot doors are dead here; the island runs the family default — baseline on every cycle. Lasting change lives in game-side flags, never matter. **The rooms forget; the satchel never does**
- **No levels, no XP, no economy.** Tin is found (damage), laurels are found (health, four leaves per heart; past cap, one life each), jars and gadgets are found. Sustain is renewable (drops, respawning fauna); progress is not. No shop will ever be built
- **The pip economy, third reading.** The girl's impacts *spend* pips; her sword *fills* them (full = panic = rout); bronze carries **grip** pips her strikes *drain* (empty = freed). One damage stat, both directions. The pip is the family's HP: the girl spends them, the Amazon fills them, the witch ignores them, and the lords lose them
- **The flee is a system:** away-vector steering; a door is an exit only if it is *not between* the animal and her; doors close with her body or with matter; fences at one subtile; cower when boxed; panic decays while cowering (pens are renewable)
- **The lasso yanks** — the enemy to one tile away, into sword range. Two yanks and the animal is wary (side-steps casts, this visit). **Bronze is immune: the lasso zips *her* to *it***
- **Five throw arcs** from one formula: class base (heavy 1 / mid 2 / light 3) + effort (stand 0 / run 1 / shot-put 2). The shot-put is a motion input — back-forward-back-forward — because she is the athlete, and hers is the only game with execution
- **Carrying is two-handed** and restricting by class; the sword button becomes drop, the lasso button becomes throw
- **The quiver is one nibble:** fifteen arrows, a 4-bit field. The engine joke canon grows
- **Combo drops** on the rout: arrows (a nibble's worth), hearts, randomized jars
- **The winged sandals: "DOUBLE JUMP."** Jump height 10px → 20px. One jump, doubled; the card does not lie. `SANDAL_JUMP_V = 139` — her doc's one dispensation
- **Wind completes smolder instantly.** Smolder is a placed fuse; the bag of winds is the detonator
- **Her heat byte never moves.** Fire costs her hearts (quarter-rate while wet — the steam-budget nod at quarter scale); flame is cargo in the torch, the arrow, the jar. She is the only heroine who is never hot
- **The grip is the boss health bar** — pips in reverse, fixed pools, so exploration always shortens every future fight
- **Purification, not destruction:** the lords are taken, not evil; the host cannot be hurt; the win state is a friend back
- **Saffron is structure (b):** questgiver from the landing, taken mid-slice at the vault door — the mini-boss is the tutorial for the finale mechanic of the full game
- **Cut:** the spirit-pocket seal (expulsion is CA smoke, gone), snapshots, the rodeo (post-slice), the grapple-any-surface hook (post-slice, the movement capstone), petrify and the thunderbolt (post-slice, endgame)
- **Upstream amendments:** pip dots above enemies are family-wide now (the girl's precedent, our law); the girl's terrain-zip ruling stands from her doc

## 0. Design doctrine

1. **The picture is the state.** (inherited)
2. **Nobody dies; everybody routs.** The family's nonlethal law, third diction — the girl naps them, the witch shoos them, the Amazon scares them clean off the island
3. **Everything is found.** Metroid rulings: the map hides the numbers; the fauna renews the ammo; no counter ever grinds
4. **Fire is cargo, never conjured.** She is the family's Promethean — flame is carried in the torch, spent from the arrow, spread from the jar. Light is a fuel she budgets
5. **Her position is a verb.** The body is the repulsor; fear is steered by standing
6. **One damage stat, both directions.** Tin fills fear and drains grip — the same dots, the same slash
7. **Geometry decides; stats decorate.** The bands are forever; weight edits terrain; the jump is ten honest pixels (once, late, doubled, and honestly labeled)
8. **The rooms forget; the satchel never does.**
9. **You cannot hurt your friends.** A fight where the host takes harm is a fight built wrong; purification is the only win state
10. **Some mechanics are occult.** (inherited — no chalk. Dialogue is lore, never manual)

## 1. Tech setup

Inherited from world §1 in full: Godot 4.5, 240×240 / 720×720, integer scaling, 16×16 tiles with 8×8 subtiles, 10 Hz integer deterministic tick, per-room PRNG on the actor shell.

**Map:** one `LevelSpec`, **eight `RoomSpec`s** — the beach (open-sky, wide) and seven dungeon rooms across three descending levels. Rooms are modest (15×15 to ~30×15, authoring's call); doors connect; some drops are one-way (you came down here; getting back is the map's memory). Unobserved rooms freeze (inherited). **Door policy: baseline on cycle — every door, always.** The strip of the girl's demo and the chambers of the witch's are both linear; ours is a loop, and the loop is cheap because rooms forgive.

| Verb | Pad | KBM | Notes |
|---|---|---|---|
| Move | L-stick | A/D | run 64 px/s (4 t/s) — the athlete |
| Aim | R-stick | mouse | **always live, continuous, all directions** — her aim law is per-tool form: this is the bow's |
| Jump | A | Space | 10px (SACRED); **20px with sandals** |
| Dash | B | Shift | the lunge — 0.15 s @ 150 px/s |
| Sword | X | LMB | slash (pips) / terrain conscription / **drop** when loaded |
| Shield | hold RB | hold RMB | brace — the bands live on the face |
| Bow | Y | E | fires straight at aim, instantly. No charge, no arc |
| Lasso | RT | Q | yank · boss-zip · swing · **throw** when loaded |

Torch toggle and jar cycle on the d-pad / wheel (see §6). The shot-put is a motion, not a button: **← → ← → + release**, a 0.4 s window `<tune>`; her windup pose is the telegraph — no dotted preview, ever. *The witch aims continuously with a twinkling preview; the girl throws eight ways with none; the Amazon has form for each discipline — previewed, memorized, felt.*

## 2. Data model

Inherited from world §2 in full — packet, content pool, room records, ledger. **No game-side packet extensions.**

- **Game-side state, never CA state:** the quiver **nibble** (15), the jar satchel and its selector, tin and laurel flags, gadget flags (gauntlets, bag, sandals), the rout log, the friendship ledger, the combo meter, quest flags. The prize-inventory precedent, scaled to a satchel
- **Pickups are flags.** A collected tin is collected forever; the room may re-render its pedestal, the checker sees the flag
- **Freed lords are marked out of baseline, permanently** — the captured-enemy exclusion pattern, made forever. The room they ruled resets around their absence; the lord himself is at the camp
- **Shard traffic, both ways booked:** a flung subtile leaves the packet as actor holdings (mass + kind), returns on settle by work order. The pot-interior precedent, generalized — matter in an actor is ledger-visible, door-portable, conserved
- **Progression doors are flags** — a keyed door stays open across resets because door policy reads game state, never room state

## 3. Element simulation

Inherited from world §3 in full; `element_tick()` unchanged; GridWater authoritative.

**Exercised this slice:** water, oil (the lake), fuel, fire, smolder, steam, smoke, soil, **stone + the LOOSE flag + shards** (our demand), damp, **wind — authored gusts and the bag** (the system's first real customer), the pot interior (world pots, witch rules). **Dark:** acid, lava, glaze, ice and FREEZE (petrify's proving grounds are post-slice), growth and the botanicals, rain (the storm is the Undertow's to bring, post-slice), electricity (the thunderbolt is post-slice, hidden, endgame). The witch remains the full-catalogue customer; we are the kinetic one — again, and differently.

## 4. Rendering

Inherited from world §9: the room-sized Image at 10 Hz, the 8×4 bank, 2-bit grayscale, rows-are-conditions, Bayer dither, derived animation.

Our loads on the shared bank:

- **P0 her** — blonde wedge, white-dress triangle, gold-scale rows (breastplate, arm, shin), and **the round shield worn on the back: a disc silhouette no other heroine has**. Two 1×2 blue eye pixels, exempt row, canvas layer above the CanvasModulate. Cartoon law
- **P1 warm** — the torch, braziers, fire, Greek fire on the float layer, the Cinderkit
- **P4 docile** — cowering, panicked (round + trembling — the shape grammar's flight state), the campfire circle
- **P6 stationery** — the parrot's scribbled charts on the boat; camp chalk
- **P7 accent** — **pip dots above every enemy** (family-wide now), drop sparkles, pocket auras, grip dots

Her reads, no meters anywhere:

- **Pips are dots above the enemy** — filling on regulars, draining on bronze. The thermometer is the population
- **The quiver is the strap:** a fanned band across her back reads coarse arrow count. The nibble, rendered
- **The torch is its flame** — a three-frame cycle shrinking with fuel. Light is the meter
- **The combo is her posture** — the flourish tier climbs with the chain: stance pride, blade gleam, the spin on the rout. The drop pop is the readout
- **Possession is smoke** — a dark tint on the host (row swap), the expulsion a fleeing gas wisp. The packet has SMOKE; the villain wears it
- **The grip duel** — Saffron's telegraphs flicker her possession tint; the window is visible

**Light posture.** The beach sets the open ambient (dusk, warm). The dungeon runs **the witch's firelight profile**: braziers cast, her torch casts, and *she radiates nothing*. A dark room is a room her fuel can't reach — light is a resource she spends to see. The planted torch is a lamp she leaves behind (§6).

## 5. Penthesilea

16×32. Run 64 px/s. "Penny," from people who like her.

```
GRAVITY = 480
JUMP_V  = 98         # 10px — SACRED, shared legs
SANDAL_JUMP_V = 139  # 20px — HER ONE DISPENSATION, honestly labeled "double jump"
DASH    = 0.15 s @ 150 px/s
HEARTS  = 3 (cap 5), quarter-heart lattice, 1 s i-frames
```

**Locomotion (inherited laws):** wade at ≥128 liquid (half speed), swim witch rules (stroke = jump, 10px hop, no air meter), oil swimmable and grants no wetness — and it is fuel, and she may be carrying a torch. FLOW and wind push her, capped vs. run.

**Hearts — the contact rules:**

- Clay touch: ¼ heart. Copper touch: ½. Bronze and the Taken: 1. Spikes: ¼ + the engine's trajectory bounce
- **Fire and lava: hearts, never heat** — ¼/tick while wet, ½/tick dry. The steam-budget nod, quarter scale: a soaked Amazon has twice the fire in her
- **Pockets: death** — the aura warned her
- 0 hearts: slump, blinky eyes, 1.5 s — the family's non-event

**Her thermal profile — the cargo doctrine.** Her heat byte never moves; her verbs generate none; contact pays hearts, not heat. She never smolders fuel she crosses, never boils a puddle she stands in, never steams — **she is the only heroine the CA can't feel coming.** Her heat lives in her hand: the torch is a small held flame with a fuel meter and a byte of its own. The torch's heat dries her wetness through cross-talk — the torch is her drier, her light, and her ignition source, and it is cargo: drowned by water, fanned by wind, spent by the minute, relit at any flame.

**Her wetness — worn lightly.** The mop-ferry-drip loop, inherited; a doused Cinderkit carried close is a spare match that leaks. Crossover-proofed like the girl's, exercised where the Sump wants it.

**Death and lives.** Family law: death resets the room to baseline, respawn at the entry door, one life spent, a non-event. **Zero lives → the island reset:** every room to baseline, quiver and jars forfeited, hearts and lives restored — **and the satchel's permanents keep: tin, laurels counted, gauntlets, bag, sandals, every flag.** The rooms forgive; the satchel never forgets. (Dying to farm is a wash by construction: fauna renew but pay tier-1 drops.)

## 6. The arsenal

### The sword

One verb, two ledgers. **Vs. enemies:** a short-arc slash, an impact event — pips by tin, tier-scaled. **Vs. terrain:** a work order — the slash marks subtiles **LOOSE**, tier-gated:

| Gauntlets | Conscribes |
|---|---|
| Leather (hers at the landing) | wood (fuel granularity), soil |
| **Bronze** (found, R4 armory) | stone subtiles — the collapsed shaft opens |
| — | structural stone: never. Glaze: never. The locked doors of the full game |

She doesn't delete blocks — **she conscripts them**, and gravity does the demolition; the pile builds itself into 8px staircases. Her demolition upgrades are her mobility upgrades: she doesn't get a double jump, she makes stairs (and then, once, she does get one — §the sandals — and the doc says so plainly).

**The fling.** A conscribed subtile doesn't collapse at her feet — the work order books its mass out of the packet into a **shard actor**: a `RigidBody2D` whose holdings are one subtile, launched on the swing's impulse, real arc, real bounces, running the bands and spending pips by mass (light 1 · mid 2 · heavy 4). On settle, a work order returns it to GridSand where it lands. **The wall becomes ammo** — and kicking an existing LOOSE pile runs the same machinery: the broom. Perf cap: 8 live shards, a 4-subtile break clusters to 2. Room restore while airborne: shards die, mass returns with the baseline — the ledger never loses it.

### The shield — the bands, worn

Deflection is the girl's billiards turned inside out: the bands are **concentric rings on the shield face**, and the incoming contact's offset picks the ring.

| Band | Offset | The attack leaves at | Name |
|---|---|---|---|
| Center | < ¼ | returns to sender, 100% | **PASS** — the riposte |
| Body | ¼–¾ | ±45°, 75% | **FORK** |
| Rim | > ¾ | ±75°, 25% | **FLICK** — the graze |

**SACRED: struck angle + thrower angle = 90°, every deflection** — the same law, worn on an arm. A deflected attack is an impact: **if the PASS returns it to its sender, it spends the sender's pips.** Parry-to-stun is a skillshot. Weak points (boss telegraphs) pay **tin × 2** on the riposte — the skill lane. Bracing occupies the shield hand; see the torch, below, for the trade.

### The bow

**Continuous aim, all directions, fires straight — the instant it's loosed.** No charge, no arc: the arcade bow. Arrows stick where they land and are picked back up by touch — the refund is the economy's floor. **The quiver is one nibble:** fifteen arrows, a 4-bit field, the family's newest engine joke.

**Fire arrows — the timed match.** Nocked at a lit torch or brazier, an arrow **burns its own fuel in flight** (1/tick) and ignites fuel where it lands only if its remaining burn clears the threshold `<tune>`. Light it early and shoot it far, and it arrives a dead cinder. A lit arrow crossing an oil film ignites the film along its path. A lit arrow through a waterfall dies; a soaked arrow drips. *The torch is fire at arm's length, the arrow is fire at range on a timer, the jar is fire as an area — three speeds of fire, all cargo.*

### The lasso — the Olympic rig

- **The yank.** Cast on a regular enemy: it is pulled to **one tile away** — into sword range, live and mad. Heavies budge one tile slowly. **Two yanks and the animal is wary** — it side-steps casts for the rest of the visit. The soft cap on the yo-yo, without touching the strike loop
- **The boss-zip.** Bronze is immune — casting on a boss zips *her* to *it*. The gap-closer that puts her inside the lion. (It is also the grappling hook's ancestor: she learns the zip on lords before she owns it on walls — post-slice.)
- **The swing.** The witch's swing-ring physics, fully realized: pendulum on any authored anchor, **rope length under player control** (retract and extend mid-swing), release is tangential, re-throw mid-air to chain. Rings only this slice; the hook-any-surface is the full game's capstone. **The 10px jump stays significant forever because the rope is her verticality**
- **The rodeo** — roping a heavy and swinging *it* — is cut with honor: post-slice fantasy, tuned when there's time to be irresponsible

### The torch — and the plant

A held flame: fuel-metered, relit at any flame (braziers, fires, a carried doused Cinderkit), drowned by water, fanned or killed by wind, an ignition source on contact — *her own hand is open flame; there is no smolder mercy in it.* It occupies the shield hand. **Plant it** (the witch's staff precedent): a stuck torch is a static light turret and a standing ignition point — brace with the shield, fight in the light you left. Sword-and-torch is legal; shield-and-torch is not.

### Jars — the satchel

**A jar is 64 units of something, or exactly one subtile of solid, in the inventory, single-use — it breaks on spend.** The witch's pots are world objects with a fill-and-release cadence; the jar is the inverse pot — stockpiled from the world, spent from the hand. Cycle-select with the d-pad: **she holds the next jar aloft** — the no-menu selector; the held jar is the readout.

- **Water** — the douse, the puddle, the cinderkit's bath
- **Greek fire** — the match: oil splash plus spark on break; the slick lights where it holds open air, and **burning oil swims the float layer** (world law, our weapon). Pour it on a lake and the lake carries it. Burns *on* water — the all-weather arson jar, consumable and dear
- **Gravel** — one placed subtile anywhere: the portable 8px riser, rare and precious
- **Empty** — the scoop-verb on a throw: through a waterfall, it arrives full

**World pots** ship too (the witch's rules, mid-weight, scoop in flight) — she finds them, carries them, throws them. Jars are hers; pots are the world's.

### The bag of winds

Found in the flock's nest (R3). Inhale at any gust source — wild rooms, updrafts, a startled Brasswing — release a directed gust: **redistribute LOOSE piles** (she doesn't place blocks; she rearranges them, and the sand rules settle it), blow smoke and steam curtains open, shove light actors (capped vs. walk speed — a shove, never a flight), fan fire's ember-leaps across gaps. **And the ruling that makes the kit sing: a gust completes any smolder instantly.** Set the spark with an arrow through the grate, walk away, and detonate the fuse from safety — remote demolition built from two honest systems and no bomb item. Enemy wind detonates her fuses early; the Brasswings are fuse-tamperers.

## 7. The flee — the herding grammar

The game's signature system. The girl shoots the ball at the problem; **the Amazon stands so the problem runs through the ball.**

- **The vector.** Every tick, flee force points away from Penny's position — steering, not pathfinding. Her body is the repulsor; circle her and the animal orbits. Panic speed climbs with pip overflow: light panic is slow and steerable, deep panic is fast and wild — *the scare you set is the scare you must steer*
- **Doors.** An exit is eligible only if it is *not between* the animal and her — a fleeing thing takes exits that point away from her. Close a door two ways: **her body in it** (free, mobile, requires the shepherd's stance) or **matter in it** (a LOOSE pile, a gravel subtile, a dropped pot, a petrified statue — post-slice). Atoms don't cross doors; neither does a frightened animal through a blocked one
- **The fences — one subtile, 8px:** FIRE and burning oil, LAVA, the tips of spikes, pocket auras (the evil aura reads as death even to terror). *Not* fences: water, unlit oil, smoke, steam. Herding past a fire line is a precision job because they run tight to hazards
- **Currents don't fence — they carry.** A routed animal caught in FLOW goes for the ride; the flood is a herding tool
- **The cower.** Boxed in — no eligible door, fences all around — the animal stops, cowers, and **keeps its CA footprint while parked** (a cowering Drip is a pen with legs, seeping its corner). The panic timer runs while it cowers: calm animals are re-scareable. The whip — striking a panicked animal — restarts and extends the rout. The Snapcricket's CHIRP un-cowers the parked: the anti-stall animal is the anti-pen tool
- **The wary state** caps the lasso, never the whip
- **The rout is the defeat:** reaching an eligible door, the animal vanishes through — presumed fled, fauna-flux exit, one line in the rout log. Pocketed animals are routed too — gone is gone; the log doesn't ask where
- **Their footprints persist at sprint** — fear is a puzzle verb:

| Routed | While fleeing | The use |
|---|---|---|
| Drip | seeps its wet line | a pen with legs — damp lines, firebreaks, fuel-soak, anywhere she can steer it |
| Boar | plows, shatters weak walls | remote demolition |
| Cinderkit | lit, trailing smolder | the fireball with a steering wheel |
| Brasswing | gust-flapping | fans smolders, spreads fire — the enemy that weaponizes her fuses |
| Satyr | flips levers, pockets torches | flees *through* the room's machinery |

## 8. The grip — pips in reverse, and the Taking

Bronze (lords, the Taken) carries a **grip pool denominated in pips**: sub-boss 16, lord 24, the finale phased. Her strikes *drain* it; empty is the win — the dark smoke bursts off, the host sags, wakes, and knows her name. **The host cannot be hurt** (doctrine 9): the fight is a rescue wearing armor.

| Tin | Pips/slash | Clay (4) | Copper (12) | Sub (16) | Lord (24) |
|---|---|---|---|---|---|
| I (start) | 1 | 4 hits | 12 | 16 | 24 |
| II (found, R2 cache) | 2 | 2 | 6 | 8 | 12 |
| III (found, R6) | 3 | 2 | 4 | 6 | 8 |

**Bosses scale to exploration, downward, on purpose** — fixed pools, so every tin found shortens every future fight, forever, and no dynamic anything ever punishes a thorough player. The counter shrinking is the power fantasy; the fight staying real is the design's job, because bronze is where the unmitigated combat engine lives: attack schemes, phases, weak points, arena CA. **Shard and flung-mass damage is by weight class (light 1 · mid 2 · heavy 4), never tin** — the terrain lane has its own numbers, and the boss floor stays fair at tin I. The riposte pays tin × 2 on the telegraph window: the skill lane.

**The Taking.** The sorceress seizes a friend — the dark plume, the ally's moveset turned on Penny, the sorceress untouchable until the grip breaks. Saffron's duel at the vault door is its tutorial; the full game's finale is its exam. The fight must be beatable with no more than the story requires — the allies are warmth, never gates.

## 9. Enemies

Silhouette IP shared with the siblings — same creatures, our verbs — plus the island's own. **API law (world §6): every enemy must survive all three heroines.** Shape grammar inherited: angular hostile, round docile — *and the panicked read trembling-round: flight is the third state of the grammar.*

| Enemy | Wt | Pips | Alive | Routed | Carried/thrown |
|---|---|---|---|---|---|
| **Drip** | 1 | 4 | marches in chains | seeps the wet line | water balloon (witch precedent) |
| **Puffseed** | 1 | 4 | bobs in clumps | drifts | the smoke puff covers |
| **Snapcricket** | 1 | 4 | sprints, agitates | fast, flat | CHIRP: un-cowers parked animals — the anti-stall, and her anti-pen |
| **Willow Whisk** | 0 | 4 | erratic hover | leaf-light | drifts |
| **Cinderkit** | 1 | 4 | chases while lit; touch ¼ heart | lit: trails smolder — the arson courier | **doused: a carried ember — the torch's spare match** |
| **Smolderwisp** | — | ambient | the steam body | drifts | splashes condense it — a free Drip |
| **Boar** | 4 | 12 | charges, plows soil and weak walls | plows — the demolition ball | heavy arcs; wrecks what it lands on |
| **Brasswing** | 1 | 12 | flock volleys; gust-flaps | fans fires and smolders | the feather barrage is the shield's fodder |
| **Satyr** | 1 | 12 | flips levers; pockets the torch | flees through machinery | mid arcs; the trickster |
| **Saffron, taken** | 1 | grip 16 | the bolt volley; hexes the satchel (one jar becomes a wild animal) | — | — |
| **Old Goldhide** | 4 | grip 24 | **the hide turns the blade** | — | — |

Crossover stock (Shellback, Cobble, Turtle, Slime, Woodpecker, Wisp, Breeze, Eel) ships in the engine's family roster, dark this slice — the crossover content inherits them under our verbs.

## 10. The map: one island, three levels, seven rooms, one beach

| Room | Depth | Beat | Teaches |
|---|---|---|---|
| **B0 THE BEACH** | surface | The landing (§below), Saffron's briefing, the camp, clay patrols in the dunes, the first brazier, the torch's first light. **The 16px lip of the sand grotto, in plain sight from minute one** — the animals' secret spot, laurels behind it, unreachable | the kit: slash, yank, rout, drops; lore is conversation |
| **R1 THE WARRENS** | L1 | Clay nests in soil berms. First combo, first rout-through-a-door (let one go — the economy, demonstrated), the tin II cache behind a cracked strut | pips → panic → flee |
| **R2 THE SEEP** | L1 | A fuel curtain dry-blocks the pass. A penned Drip. **Herd the seep line across the curtain, then walk your dry gap** — or torch it and learn why not. A doorstop beat: stand in the doorway, keep the pen | fear is a verb; doors close |
| **R3 THE RIGGING** | L1 | Swing rings through the mast forest, sky gaps above, the **Brasswing flock** nesting. **The bag of winds in the nest.** The feather barrage is the shield's first exam | the swing; the riposte; the bow |
| **R4 THE SUMP** | L2 | The oil lake guards the armory. World pots on pedestals; the **Greek fire jar** on the path; the **bronze gauntlets** in the armory. Set piece: **burn the moat dry** — the surface fire crosses the lake consuming it, and she walks behind the flame front. Alternate: the ring ledge above | jars; conscription; oil |
| **R5 THE TAKEN GALLEY** | L2 | Saffron, at the vault door, is taken mid-sentence. **The grip duel** — bolt volleys, the satchel hex, the flickering telegraphs. Break it; she unseals the door and goes back to the boat, quietly | the grip; the Taking |
| **R6 THE VAULT APPROACH** | L3 | The composed exam: the stone-choked shaft (bronze gauntlets — conscript it, shard it, descend); the fuse behind the grate (**fire the arrow through, gust the smolder complete** — remote demolition); a Satyr in the lever corridor (scare it through; it flips what it flees past) | every verb, composed |
| **R7 GOLDHIDE'S HOLD** | L3 | The boss. The hoard is the arena and the ammunition — LOOSE gold piles shard into bowling. Three lanes: the riposte on his pounce, the mass of his own treasure, and the occult boar. Phases: his rage plows his own hoard — ammo up, floor down. **The winged sandals on the hoard throne behind him.** Post-fight: the old lion wakes — "…Penthesilea." The return trip; the lip; the closing image | the unmitigated engine |

**The landing.** All diegetic, all in-engine: the boat under animal power (the parrot calling trim, the ship's cat navigating by feel and being smug about it), Penny at the rail, Saffron at the tiller. The hull grounds itself on the sand, deliberately — the crew treats it as routine. Saffron's briefing is the whole tutorial text: *get to the bottom, defeat the pirates.* She lights the first torch at the landing brazier — the flame is given; keeping it is the game. The animals hop off around her and stay: the camp.

**The closing image.** The beach at dusk, the freed lion asleep against the beached hull, the animals clustered, Saffron at the tiller of the boat that will take her to the next island — and the sandals in the satchel, and the lip in the dunes that is now, finally, a hop. Fade. (And one occult beat for the full game's promise: a dark wisp surfaces off the harbor, watches, and sinks. No chalk.)

## 11. The camp and warmth

**The beached boat is the camp** — derived state, rebuilt from the game-side roster on every entry, growing all game. The rout log, romantically: after enough routs of a species, one turns up at the fire — presumed fled, now warming his hands. Saffron at the tiller (until she's taken; then back, a little quieter). The parrot, the cat, the rigging rats, a gull, and a toad who is thriving — every one of them someone Saffron transformed **because they asked** — the joke's rule: transformation is a service, the tone never once plays it as a curse, and nobody comments on any of it.

**The name gauge is the affection system:** *who calls her Penny* — nothing else, ever. Quests are strictly optional warmth, zero ending effect: the slice carries one (the cat's business — a fetch-flavored flag-test with a punchline), and Goldhide's arrival at camp is its reward. He starts with "Penthesilea." What he calls her afterward is the point of the whole game.

## 12. Placeholder art & audio

- Palette discipline from day one: the 8×4 bank, no arbitrary sets
- Her: 16×32 — blonde wedge, dress triangle, gold-scale rows, **the shield disc on her back** (the silhouette giveaway); two blue eye pixels. The torch flame, the auras, the plume are the only magic-adjacent renders, and two of those are just fire
- Enemies: circle/square placeholders encode mode; pip dots always; the panicked row trembles
- SFX: jsfxr — sword shing, the yank's whip-crack, the rout squeal, drop pops, jar shatter, torch whoosh, the gust, the lion's roar, the Taking's sting, and one chord for every snap-back-to-senses
- Music: one looping CC0 tune; the percussion breathes with the sim tick (inherited family law)

## 13. Build order

Engine stages E0–E5 are `world.md`'s.

1. **M0 — Island + her** *(needs E0, E5-cut-1)*: eight rooms, doors, the descent, run/jump/dash, the beach ambient, the landing cutscene skeleton with gray boxes. *Is it breezy — and does the grounding of the boat already charm?*
2. **M1 — Sword + pips + panic + flee** *(needs E3)*: slash, pip dots, thresholds, away-vector steering, door eligibility, doorstops, fences, cower, the whip, drops, clay roster + Boar. **The three numbers: the yank (1 tile), the margin (8px), the thresholds (4/12).** *Does a rout read as escape, not AI breakage? Does herding a Drip across a fuel curtain read with zero text?*
3. **M2 — Lasso + carry + arcs** *(needs E3)*: yank, wary, boss-zip stub, the swing, carry classes, the arc grid, the shot-put motion, world pots. *Does the arc grid live in the head? Does the shot-put read as the Olympian's flourish or a chore?*
4. **M3 — Fire + jars + torch** *(needs E4 + fire)*: the torch and the plant, braziers, fire arrows and the burn timer, smolder, jars, the oil lake, the Sump end-to-end. *Does light-as-fuel read as budget, not chore? Does the moat burning dry land as the set piece?*
5. **M4 — Conscription + shards** *(needs the LOOSE flag + contact contract)*: gauntlet tiers, LOOSE marking, shard actors out and back, the broom, the piles, the shaft. *Does the wall becoming ammo read as strength? Does a shard bowl run the bands honestly?*
6. **M5 — Wind + the Taken** *(needs authored wind)*: the bag, gusts, wind-completes-smolder, ember-leaps, Saffron's duel end-to-end. *Does the gust-detonation read as the kit's best trick? Does breaking Saffron out hurt, rightly?*
7. **M6 — Goldhide + sandals + close**: the three lanes, the phases, the hoard, the wake-up, the lip, the closing image, SFX/music. *Does the sandals joke land? If the player doesn't laugh at "DOUBLE JUMP," the slice has failed its funniest test*

**Explicit cuts (do not build):** XP, levels, shops, crafting — of any kind, ever; snapshot doors; the spirit-pocket seal; the rodeo (post-slice); the grapple hook (post-slice); petrify and the Stoneye charm (post-slice); the thunderbolt (post-slice, hidden, endgame); harpies (post-slice — the Rigging region's own); rain, acid, lava, glaze, freeze; numeric scores; dotted previews; HP bars on regulars (pips only); bosses beyond the two.

## 14. Tuning constants (game-side; engine constants live in world §13)

```
TILE = 16, SUBTILE = 8               # SACRED — shared
JUMP_HEIGHT = 10                     # SACRED — shared
SANDAL_JUMP = 20 (JUMP_V 139)        # her one dispensation — "double jump," honest
RUN = 64, GRAVITY = 480, DASH = 0.15 s @ 150
HEARTS = 3 (cap 5) · quarters · i-frames 1 s
DAMAGE: clay ¼ · copper ½ · bronze 1 · spikes ¼ + bounce · fire ¼/t wet, ½/t dry
PIPS: clay 4 · copper 12 · GRIP: sub 16 · lord 24
TIN I–IV = 1–4 pips/slash · riposte = tin × 2 · shard pips = mass (1/2/4), never tin
LAURELS: 4 = +1 heart · past cap = +1 life · QUIVER = 15 (one nibble)
ARROW: straight · sticks · recoverable · burn 1/t · ignite threshold <tune>
TORCH fuel <tune> · plant = light + ignition · relit at any flame
COMBO: decay 4 s · tiers 3/6/10 = arrows (1–4) / heart / random jar <tune>
YANK = 1 tile · WARY = 2 yanks/visit · FLEE margin = 8px · cower decays on timer
ARCS: base H1/M2/L3 + effort 0/1/2 (stand / run / ←→←→ shot-put)
CARRY: light free · mid walk, no dash · heavy half speed · all: two hands
LASSO_RANGE = 7 (shared) · swing = rings only (slice) · bronze: zip
WIND: gust completes smolder instantly — SACRED for this game
LIVES = 3 · zero → island reset · satchel keeps gear; consumables forfeit
SHARDS: cap 8 live · settle = work order back · restore = return with baseline
```

## 15. Slice exit checklist

- Does a rout read as escape — never as AI breakage?
- Can a player recite the arc grid after ten minutes, unprompted?
- Does the shot-put motion feel like the athlete's flourish — and is ←→←→ a home in a GBC frame, or a guest?
- Does herding a Drip across a fuel curtain read as *her idea*, with zero text?
- Does the yank-into-slash loop feel like a whip? Does the wary state read as the animal learning, not the game cheating?
- Does the boss-zip read as aggression, not accident?
- **Is the shield riposte the best feeling in the game?** (If not, stop and tune — it is the skill lane and the purification finisher)
- Does Goldhide teach "the CA is the weapon" without a word — three lanes, all viable, the hoard as ammo?
- Does the sandals joke land? The card says DOUBLE JUMP; the jump doubles; the player laughs — or the slice has failed its funniest test
- Does the 16px lip call from minute one, and does the hop pay it off?
- Does the torch read as budget and drama — the dark rooms worth the fuel — never as chore?
- Does the Saffron duel hurt, rightly? Does breaking her out feel like the win, not the checkpoint?
- Does the camp feel like coming home? Does anyone call her Penny yet — and does it mean something when they do?
- Does every room teach exactly one thing, with zero text?
- Did the boar-into-the-lion get found — and did whoever found it tell someone?
- Does the closing image land — the lion at the hull, the boat, the lip?

## Appendix A — level format: game checkers

`LevelSpec`/`RoomSpec` are world §10; the island is eight RoomSpecs. Our checker family:

- **Flee-solvability:** every rout-puzzle's target is reachable by some steer from some reachable stance, fences and margins accounted
- **Doorstop census:** every must-close door is closable by matter she can have, or by her body with a survivable stance
- **Arc reachability:** every throw target sits inside some arc cell (class × effort) from some reachable stance — the 15-cell grid as code
- **Lip audit:** riser solvability runs twice, pre- and post-sandals; every 16px lip is flagged sandal-gated and visible from its region's main path
- **Grip floor:** every bronze fight is beatable at tin I, leather gauntlets, no jars — the terrain lane guarantees it
- **Torch-fuel audit:** every dark stretch has reachable fuel, lit or lightable, before the dark
- **Shard cap:** worst-case authored breaks stay under 8 live shards
- **Fauna renewal:** every herding room's animals return on re-entry (the reset-on-exit guarantee, asserted)
- **Herd margins:** panicked paths clear fences by at least one subtile from every approach the puzzle requires

Test 8×8 vignettes, not rooms. Keep the seed, not the room. The loop — generated vignettes inspiring authored rooms — is the product.

## Appendix B — risk register (game-side; engine risks live in world App. B)

- **Flee steering:** the away-vector is steering, not pathfinding — the risk is jitter (oscillation against walls, door-shopping dither). The knob is damping and a short commit window, never scripted routes
- **The shot-put motion:** a fighting input in the family's first execution-demanding game. Test in M2 with strangers; if it whiffs, the fallback is a hold-and-release windup — but the motion is the athlete's signature, so it gets a real chance first
- **Wind stub risk (inherited open item):** authored gusts carry the slice; the map leans on wind exactly once (R6's fuse), never twice, until the draft field ships
- **Shard actors:** matter at 60 fps, capped at 8 — the determinism rig covers them (per-tick PRNG, Godot physics is family-accepted for projectiles already). The restore ruling (airborne shards die, mass returns) must be asserted — the ledger never loses it
- **Wary-state readability:** the side-step must read as the animal learning. If playtesters report "the lasso broke," the fix is the dodge's telegraph, never the cap
- **Boss-zip misfire:** casting at a boss meaning to yank a minion. The fix is targeting disambiguation (bronze highlights on cast), not a confirmation step
- **Grip pacing at high tin:** fixed pools mean late-game lords at 6–8 hits. The drama must live in phases and arena CA, not counters — assert the R7 fight stays a *fight* at tin III
- **Arrow starvation:** the drop economy is the only source; if the quiver pinches, the knob is tier-1 rates — never a shop
- **Reset-on-exit × puzzle state:** a half-herded room forgives on exit by design; the risk is player confusion (did it work?). The rout log line is the receipt — make the pop readable
- **Cower placement:** an animal must never cower *on* a door tile (it would become an unkillable doorstop). Doors are cower-fences; the steering slides off
- **The Taking's tone:** fighting Saffron must read as rescue. The host-cannot-be-hurt law carries it — every wasted slash refunded is the game saying *not her, never her*