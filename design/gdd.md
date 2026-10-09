# walkers - Game Design Document

Numbers, not adjectives. References in `design/refs/`. Defaults below are for the M0 "Scout" build
(medium chassis, 6 medium legs, 1 pulse cannon) unless stated.

## 1. One-liner and player fantasy
- Store line: Build a spider-legged walking machine from salvage, then stride into a hostile wasteland to scavenge
  parts for a better one.
- Fantasy: I am an inventor-explorer. The machine under me is my own design, and I can feel every choice I made in
  how it walks.

## 2. Pillars (max 3)
1. **Your build is your feel.** Each part change shows in how the walker moves and fights within 5 s of leaving the
   workshop. *We cut part count before we compromise this.*
2. **Legs that read.** The walk is the show: feet plant and never slide, and gait is readable at the default
   camera distance. *We cut enemy walkers and VFX polish before we compromise this.*
3. **Venture and return.** Every trip puts carried salvage at risk, and the further you go the more it pays.
   *We cut map size before we compromise this.*

## 3. Core loop
- **30 seconds:** steer the walker over uneven ground (WASD, mouse orbit), stop to shoot drones (LMB), walk over
  scrap to pick it up.
- **5 minutes (one expedition):** leave the workshop, follow scrap nodes 60-200 m out, survive 2-4 drone encounters,
  then decide: push further for richer nodes, or walk back and bank. Bank in the workshop, buy one part, re-socket,
  and leave again with a different feel.
- **One session (30-60 min):** 6-10 expeditions; 3-5 new parts bought; one new zone reached that needs a build
  change (M1+: terrain gates such as a 1.5 m ledge or a 4 m gap). The player leaves with a machine that looks and moves
  differently from the one they started with, and a plan for the next part.

## 4. Why it is fun (the risk hypothesis)
**Hypothesis:** rebuilding is fun because a procedural IK gait turns part choices into movement you can see and
feel (speed, turn rate, stride, step-up height, sway), not just numbers on a stat screen.

**What kills it:** if every build walks about the same, the inventor fantasy collapses into a stat menu, and the
game becomes a mediocre shooter on legs.

**How M0 tests it:**
- Scenario `build_contrast`: Strider A (6 long legs) and Crawler B (8 short legs, 2 cannons, armor) from section
  8.1 differ by >= 40 % in measured top speed and max step-up height, computed as (A - B) / A, on the same course,
  and neither stat is clamped. Speed, turn and step-up are logged.
- Unit test: B's DPS x HP >= 1.8x A's, so the contrast is a choice and not one optimal build.
- Screenshots of A and B mid-stride side by side: an outsider can tell them apart from silhouette alone.
- Playtest question, answered by Klas and playtest-critic: "After swapping legs, did the walker feel different
  within the first 5 s?"

## 5. Feel targets (numbers)
Each number is a scenario or unit check. "Default" means the M0 Scout build.

| Target | Value | Range across builds |
|---|---|---|
| Input to visible body motion | <= 2 physics ticks (33 ms); the first leg group lifts within 1 tick so the start never reads as sliding | fixed |
| Top walk speed | 4.5 m/s | 2.5 (heavy) - 7.0 (light) m/s |
| Accel 0 to top speed | 0.25 s | 0.15 - 0.45 s |
| Decel to stop | 0.20 s | 0.12 - 0.35 s |
| Body turn rate (A/D, tank controls) | 120 deg/s, reached in 0.1 s | 60 - 180 deg/s |
| Strafe speed | 0.75 x top speed | fixed ratio |
| Step trigger: foot error from rest target | > 0.5 x leg reach | fixed ratio |
| Step duration | 0.18 s @ top speed, 0.30 s near idle, x sqrt(shortest mounted leg reach / 1.0 m) (Strider about 0.23 s; Crawler and any build with a short pair about 0.14 s); 4-leg wave steps shorter, tuned at T03 | scales with speed and the shortest leg |
| Felt change per leg purchase | >= 15 % in top speed, turn rate or step rate (telemetry `steps_per_s`); armor and top parts are judged in the first fight instead | Pillar 1 check |
| Foot lift height | 0.25 x leg reach | fixed ratio |
| Planted foot drift (sliding) | <= 2 cm per step | hard limit (Pillar 2) |
| Legs airborne at once | <= half (6 legs: alternating tripod) | 4 legs: max 1 airborne (wave gait) |
| Body height above foot plane | 0.6 x mean leg reach (chassis underside), spring settle 0.15 s | |
| Leg stance (arched legs) | Each hip 0.5 x its own leg reach above the foot plane, on a strut under the chassis side; rest foot 0.43 x own reach out from the hip, end legs fanned up to 0.05 x reach fore-aft; bones 0.46 + 0.69 x reach (1.15 x reach, so the leg never straightens); bend plane vertical (pole up); planted feet stay within 0.99 x reach | same ratios for every leg, in any mix |
| Knee height | On level ground walking straight, in the body frame: above the hip by >= 0.15 x reach at rest (geometry 0.19) and >= 0.10 x reach for planted feet within 0.5 x reach fore-aft of rest. On any ground, and when turning or strafing, a leg may reach down with its knee below the hip, but the knee stays on the pole side of the hip-foot line by >= 0.05 x reach (the 0.99 x reach clamp leaves about 0.08): never straight, never flipped. Upper bone >= 15 deg above horizontal; shin 0-15 deg outward of vertical; fore-aft room from the rest foot to the 0.99 x reach limit >= 0.65 x reach | Crawler knee 0.41 m, Scout 0.69 m, Strider 1.10 m |
| Body tilt follows terrain | <= the build's slope grip (`max_slope`: Strider 30, Scout 35, Crawler 45 deg), smoothing 0.12 s | |
| Body bob amplitude while walking | 4 cm x mean leg reach, on flat ground (Crawler 2.4, Scout 4, Strider 6.4 cm) | |
| Max walkable slope | 35 deg | 25 - 45 deg |
| Max step-up height | 0.6 x leg reach (Scout: 0.6 m); step-down at least as far: feet reach about 0.35 x reach below the foot plane unaided, and the body lowers up to 0.25 x reach toward a lower foothold first | 0.35 - 1.0 m |
| Camera orbit distance | 8 m (scroll 5-12 m), FOV 70; spring-arm terrain collision, min 2 m unless rock is closer (rock wins) | |
| Mouse sensitivity | 0.15 deg/px, invert-Y off (constants in M0, settings menu M2) | |
| Camera position lag | 0.10 s smoothing; 0 lag on rotation | |
| Pulse cannon | 4 shots/s, 15 dmg, projectile 60 m/s, spread 1.0 deg x leg spread factor | 0.5 - 1.5 deg |
| Drone | 45 HP (3 hits), hitbox r 0.6 m, hover 3-6 m, 10 dmg/shot, 1 shot / 1.5 s, 0.6 s wind-up glow, bolt 25 m/s (0.6 s flight at 15 m: dodgeable by strafing) | |
| Player chassis HP | 100 (Scout) | 70 - 180 |
| Feedback on taking hit | 0.12 s red rim flash + 0.15 s camera shake, 0.15 m amplitude | |
| Feedback on landing a hit | 0.06 s white flash on target, no hit-stop | |
| Scrap pickup | automatic within 2.5 m, 0.3 s magnet pull | |
| Pacing: first drone after leaving workshop | 45-75 s | |
| Pacing: scrap node spacing | one per 15-25 s of walking (Scout) | |
| Workshop exit to walking | <= 2 s | |

## 6. Player verbs, controls, input map
Verbs: walk, strafe, turn, look/orbit, aim, fire, collect (automatic), build (socket/unsocket part), bank.

| Action name | Default KB+M | Context |
|---|---|---|
| `move_forward` | W | walking |
| `move_back` | S | walking |
| `turn_left` | A | walking |
| `turn_right` | D | walking |
| `strafe_left` | Q | walking |
| `strafe_right` | E | walking |
| `fire` | LMB | walking |
| `aim` | RMB (zoom to FOV 50, -40 % turn rate) | walking |
| `interact` | F: enter the workshop when within 4 m. Hold 3 s anywhere: recall to the workshop (stuck recovery; carried scrap drops as a cache, like death) | walking |
| `zoom_in` / `zoom_out` | mouse wheel | walking |
| `build_place` | LMB on socket | workshop |
| `build_remove` | RMB on part | workshop |
| `build_exit` | Tab | workshop |
| `pause` | Esc | both |

**Tank controls:**
- W/S drive along the body's facing, A/D turn the body at its turn rate, and Q/E crab-strafe.
- The mouse orbits the camera independently (yaw free, pitch clamped -10 to 60 deg) and aims the turret.
- The turret can only fire within +/- 150 deg of the body's facing (8.3), so heavy threats behind you mean
  turning the body. This makes the turn rate a build stat you feel in every fight (Pillar 1).
- Turning in place re-plants the legs visibly, so the turn itself is a gait show (Pillar 2).
- The camera does not auto-follow the body's yaw. Behind-the-body recentring is on a 1.5 s delay after mouse
  idle and pauses while `aim` is held; this is a tuning knob for the gate.
- On a descent, where the ground behind the walker rises steeper than about 25 deg, the camera holds a pitch floor
  of that slope minus 5 deg (about 35 deg on the 40 deg talus), so the edge behind never hides the walker. It eases
  in and out; on flatter ground the camera returns to the player's own pitch. Gamepad is out of scope until M2, but the action names
already allow it.

## 7. Failure, success, difficulty curve
- **Failure:** chassis HP reaches 0 (shot by drones; M1+: enemy walkers). The walker collapses (legs fold, 1.0 s),
  then the player respawns in the workshop with the build intact. All carried scrap drops as a **wreck cache** at
  the death spot, and the cache can be reclaimed once. Dying again before reaching it destroys it.
  No other loss. The low cost keeps experimentation cheap (Pillar 1), and the cache keeps the stakes of Pillar 3.
- **Repair:** no regeneration in the field. HP is fully repaired on bank, so HP is the clock that makes
  "push or return" a decision.
- **Respawn:** banking respawns drones and scrap nodes in rings 1-2. Ring 0 nodes never respawn, so there is no
  risk-free farming.
- **Success per trip:** scrap banked in the workshop. Per session: a new part bought and a new place reached.
  The M0 session goal is reaching the ledge pocket (section 9).
- **Difficulty by distance from the workshop:**

| Ring | Distance | Drones per encounter | Scrap per node |
|---|---|---|---|
| 0 | 0-60 m | 0 | 5 (no respawn) |
| 1 | 60-150 m | 1-2 | 10 |
| 2 | 150-250 m | 2-3 | 20 |
| 3 (M1) | 250 m+ | 3-4 + 1 enemy walker | 35 |

## 8. Systems

### 8.1 Walker build (data) - `WalkerBuild` (pure, RefCounted)
- **State:** chassis id; map of socket id to part id.
- **Rules:**
  - The chassis defines sockets. M0 medium chassis: 8 leg sockets and 3 top sockets.
  - A part fits only its socket kind (leg or top).
  - M0: the build is valid when it has 4, 6 or 8 legs placed symmetrically (equal count per side), and total
    mass <= total leg lift. Leg types may be mixed.
  - M1: uneven builds are allowed. Rules:
    - Legs are sold singly at half the pair price.
    - A build needs at least 2 legs per side and 4-8 legs in total.
    - imbalance = |lift_left - lift_right| / lift.
    - top_speed x (1 - 0.5 x imbalance).
    - spread + 2.0 deg x imbalance.
    - Idle body roll toward the weak side is 10 deg x imbalance (visible sway).
    - Gait groups alternate by socket order, and each group keeps the centre of mass inside the support polygon.
  - M0 code keeps per-leg data with no pair assumption, so the M1 change is rules only.
  - Derived stats are computed only from the part list.

**M0 part catalog.** Legs are sold and placed in mirrored pairs (singly from M1).

| Part | Socket | Mass (kg) | Lift (kg) | Reach (m) | Slope grip | Spread (deg) | Other | Price (scrap) |
|---|---|---|---|---|---|---|---|---|
| Medium chassis | - | 125 | - | - | - | - | 100 HP, 8 leg + 3 top sockets | start |
| Short leg | leg | 35 | 110 | 0.6 | 45 deg | 0.5 | | 40 / pair |
| Medium leg | leg | 25 | 75 | 1.0 | 35 deg | 1.0 | | start |
| Long leg | leg | 20 | 85 | 1.6 | 30 deg | 1.5 | | 70 / pair |
| Pulse cannon | top | 40 | - | - | - | - | section 5 stats | 80 |
| Armor plate | top | 50 | - | - | - | - | +40 HP | 50 |

- **Starting inventory:** chassis, 6 medium legs, 1 pulse cannon (the Scout). Banked scrap: 0.

**Derived stats:**

| Stat | Formula |
|---|---|
| `mass` | chassis mass + sum of part masses |
| `lift` | sum of leg lift values |
| `load` | mass / lift (must be <= 1.0) |
| `reach` | mean leg reach (m) |
| `top_speed` | clamp(4.5 x sqrt(reach) x gait_factor x (1.7 - load), 2.5, 7.0) m/s. gait_factor = 1.0 for 6-8 legs, 0.85 for 4 legs. The clamp is a safety rail only; no armed build of 6+ legs may reach it |
| `turn_rate` | clamp(250 - 100 x load - 10 x legs, 60, 180) deg/s |
| `step_up` | 0.6 x reach |
| `max_slope` | lowest slope grip among the mounted legs |
| `spread` | 1.0 deg x mean leg spread factor (body sway) |
| `hp` | chassis hp + armor parts |

**Reference builds** (the unit test fixtures):

| Build | Parts | Load | Speed | Turn | Step-up | Slope | HP | DPS | Spread |
|---|---|---|---|---|---|---|---|---|---|
| Scout | 6 medium legs, 1 cannon | 0.70 | 4.50 | 120 | 0.60 | 35 | 100 | 60 | 1.0 |
| Strider (A) | 6 long legs, 1 cannon | 0.56 | 6.49 | 134 | 0.96 | 30 | 100 | 60 | 1.5 |
| Crawler (B) | 8 short legs, 2 cannons, armor | 0.61 | 3.80 | 109 | 0.36 | 45 | 140 | 120 | 0.5 |

- **Niche:** the Strider reaches ledges and escapes. The Crawler grips steep slopes and wins fights:
  DPS x HP is 2.8x the Strider's, and its spread is tight. Neither build dominates (Pillar 1).
- **Edge cases:** removing a leg that makes the build invalid is allowed in the workshop, but the exit is blocked
  with a reason string ("Overloaded: 412/380 kg", "Needs 4, 6 or 8 legs", "Legs unbalanced").
- **Tests:**
  - Each reference build matches its table row within 0.01.
  - Contrast, computed as (A - B) / A: >= 40 % in speed and in step-up, and neither A nor B is clamped.
  - B's DPS x HP >= 1.8x A's.
  - Validity reason strings.

### 8.2 Locomotion - body controller and gait
- **Body:** CharacterBody3D, moved kinematically from input and build stats, with the accel and decel from
  section 5. Height and tilt are fitted to the plane of the planted feet (least-squares, then smoothed). The
  chassis and the hips never sink into the ground: where that plane runs below the terrain (over a crest or a
  ledge edge) the body rises until they clear it, at most 1.5 m/s (it slows its advance to climb, it never hops),
  and waits if the legs cannot reach that far. Ground steeper than the build's grip that stands taller than its
  step-up stops the body like a wall; it never rises over it (a lower steep obstacle is stepped onto). Where the ground ahead rises or falls (a slope's foot, a ledge or shelf edge), the body
  pitches toward the next footholds it can stand on before its feet get there, as a climber leans into a slope;
  tilt still follows the planted feet on even ground.
- **Gait (`GaitSolver`, pure):** legs split into alternating groups: two tripods for 6+ legs; for 4-5 legs a wave
  gait with one leg per group.
  A leg may step when its foot error is > 0.5 x reach and its group is active. The next group starts when every
  foot of the active group is planted, or 85 % into the step, but a leg never lifts while that would put more legs
  in the air than the section 5 limit.
- **Foot targets:** a downward raycast from rest position + velocity x step duration x 0.5. A target more than
  step_up above the leg's current foot, or steeper than the max slope, is invalid. The leg then takes the farthest valid foothold
  between its current foot and the target, a shorter step. Only when none is valid does the leg block, and the
  body stops on that side. On a steep slope inside its grip a walker takes short steps and slows; a vertical face
  taller than step_up still blocks.
- **IK (`TwoBoneIK`, pure):** analytic two-bone solve with a pole vector pointing up (bend plane vertical), and stretch
  clamped at 99 % of the bone length. The bones total 1.15 x leg reach, so at the 0.99 x reach planted-foot limit
  (section 5) the knee is still bent. There is no engine IK node, so the solve is unit-testable.
- **Edge cases:** a foot target that is unreachable for more than 0.5 s makes the leg hover at its rest pose.
  Moving the walker by an external push (M1) replants every foot within 0.3 s.
- **Tests:** IK end effector within 1 mm of the target for reachable targets; airborne count never above the
  gait limit; zero planted foot drift over a 10 s straight walk (scenario); step-up blocked at 0.61 x reach.

### 8.3 Weapons - top socket parts
- **State:** cooldown, heat (M1).
- **Rules:** a weapon fires at the camera crosshair ray hit point. Its turret yaws at 360 deg/s within +/- 150 deg
  of the body's forward direction, and pitches -10 to 45 deg. A target outside the turret arc does not fire, and the crosshair greys out.
- **Tests:** fire rate cap; damage applied once per projectile; no fire while the target is out of arc.

### 8.4 Enemies - drones (M0); enemy walkers (M1)
- **Drone states:** idle-hover, patrol, alert (sees the player within 35 m, line of sight), strafe (orbits at
  12-18 m), wind-up (0.6 s, glows), fire, dead (falls, drops 3-8 scrap).
- **Rules:** max 4 active drones. Drones leash back to their spawn when the player is more than 60 m away, and
  respawn on bank.
- **Combat check:** a strafing Scout takes <= 40 % of the damage that an idle Scout takes in `drone_fight`, so
  speed matters in combat (Pillar 1).
- **Tests:** state transitions as pure functions; telegraph is >= 0.6 s before every shot; leash.

### 8.5 Salvage and economy
- **State:** `carried_scrap`, `banked_scrap`, wreck cache (position, amount) or none, depleted node ids.
- **Rules:**
  - Nodes are depleted on pickup and respawn when the player banks (except in ring 0).
  - Banking moves carried scrap to banked scrap.
  - Death moves carried scrap into the cache and replaces any older cache.
- **Prices:** see the 8.1 catalog (40-80 scrap). Starting with 0 banked scrap, the first purchase (a short leg pair
  at 40) lands after 1-2 expeditions. `loop_full` logs the expedition on which it happens.
- **Blueprints (M1):**
  - Each zone hides 2-3 blueprints in exploration pockets behind terrain gates.
  - A blueprint unlocks a part for purchase with scrap; scrap still buys every copy.
  - A blueprint is banked the moment it is picked up and is never lost on death: exploration is rewarded, while
    carried scrap stays the stake.
  - M0 has scrap only, and all M0 parts are unlocked.
- **Tests:** bank, death and reclaim sequences; a second death destroys the old cache; no scrap duplication.

### 8.6 Workshop
- **State:** owned parts (inventory) and the current build.
- **Rules:** the walker is lifted onto a stand with the camera orbiting it. Hovering a socket highlights it, and
  a stat panel shows the delta before placing. Buying a part adds it to inventory.
- **Tests:** placing or removing updates stats; exit is blocked while the build is invalid; purchase deducts scrap.

## 9. Content scope per milestone
| | M0 | M1 vertical slice | M2 |
|---|---|---|---|
| Chassis | 1 (medium) | 2 (+light) | 3 (+heavy) |
| Legs | 3 (short, medium, long) | 5 (+wide-foot, climber) | 7 |
| Top parts | 2 (pulse cannon, armor plate) | 5 (+shield, scanner, cargo pod) | 9 |
| Enemies | 1 drone | + walker sentinel | + drone carrier |
| Map | The valley (9.1): 400 m long, floor about 200 m wide, rings 0-2, a ledge pocket (Strider) and a talus pocket (Crawler) | 2 zones + terrain gates | 3 zones |
| Audio | placeholder | footsteps per leg, weapon set | full pass |

### 9.1 M0 map: the valley
Layout reference: `design/refs/valley.jpg`. The point of the shape: rings become bands along the valley, so
"deeper" is always down-valley and "home" is always up-valley. Push-or-return (Pillar 3) is then a direction you
can see, with no minimap.

```
            up-valley = home
 ████████████████████████████████  cliff wall, >= 30 m tall, >= 60 deg
 ██   [W] workshop on a bench    ██  ring 0   0-60 m     no drones
 ██      ~~ dry wash ~~          ██
 ██           ~~~        ░ talus ██  ring 1   60-150 m
 ██ ▓ ledge          ~~  ░ pocket██
 ██ ▓ pocket           ~~        ██  ring 2   150-250 m
 ██                 ~~           ██
 ██   ruins + smoke column  ▒▒▒  ██  far end: ruins block the valley (M1 gate)
 ████████████████████████████████
```

| Element | Spec |
|---|---|
| Footprint | 400 x 400 m area; the valley runs 400 m north to south. Walkable floor about 200 m wide (minimum 150 m anywhere) |
| Cliff walls | >= 30 m tall and >= 60 deg along the whole floor edge, so no build can leave (max step-up 1.0 m, max slope grip 45 deg). These are the map bounds; there are no invisible walls |
| Floor | Gentle 0-10 deg overall. Bumpy patches up to 30 deg (the gait show). Boulders 0.3-1.0 m high as step-up content: the Crawler (0.36 m) goes around them, the Strider (0.96 m) steps over |
| Workshop | On a bench at the north end, 20-40 m from the head wall. Ring distances are measured from it |
| Dry wash | A winding riverbed from the workshop down to the far end. It is the main path and the route the test scenarios walk |
| Ledge pocket | West wall, ring 2, 160-240 m from the workshop. A 0.8 m ledge leads up to it; one 60-scrap node. The Scout can't climb it; the Strider can |
| Talus pocket | East wall, ring 2, 150-220 m from the workshop. A 40 deg talus slope leads up to it; one 60-scrap node. Only the Crawler (45 deg grip) can climb it; the Scout (35 deg) and Strider (30 deg) can't |
| Far end | Ruins half buried in a dune bank close the valley at 270-300 m, the gate to the M1 zone. The smoke column behind them, at about 350 m, is the down-valley landmark and is visible from the workshop |
| Scrap nodes | Ring 0: 2 nodes (5 scrap each, no respawn). Ring 1: 3 nodes (10 each). Ring 2: 3 nodes (20 each) plus the two pockets (60 each). Wash nodes are 70-110 m apart, and side nodes fill the gaps, so a node comes into view every 15-25 s of walking (section 5) |
| Drone encounters | Three sites along the wash at about 140 m (1-2 drones), 190 m (2-3) and 235 m (2-3), plus 1 drone guarding the ledge pocket. The first site at about 140 m keeps "first drone after 45-75 s" (section 5) once ring 0 pickups are counted |

- **Income check:** clearing rings 1 and 2 without the pockets yields 90 scrap plus drone drops, which matches
  the economy estimate in section 18.
- **Tests:**
  - T05 geometry check: sample the floor edge; every cliff sample is >= 30 m above the floor and >= 60 deg.
  - `map_bounds` scenario (T12, needs the walker): the Strider and the Crawler walk into both walls and into the
    far-end ruins. Neither leaves the floor polygon or climbs more than 2 m above the floor, except inside the
    pockets.
  - `loop_full` (T12): the Strider reaches the ledge pocket but not the talus pocket, and the Crawler the
    reverse.

## 10. Visual direction
**Readability rules (in priority order):**
1. At 8 m camera distance and any pitch from -10 to 60 deg, every foot of the player walker stays in frame and
   is >= 12 px tall at 1080p. Seen from behind, every foot is also clear of the chassis and the ground; side-on,
   the near row is clear and the far row may hide behind the chassis. Its plant moment is readable: a dust puff of 0.2 s and a contact decal that fades
   in 2 s. These two are readability, not polish, and cannot be cut (Pillar 2).
2. Threats glow magenta-red. Nothing else in the world uses that hue. The drone wind-up ramps its emissive from
   0 to 3 over 0.6 s. Because the orange accent is only 39 deg from the threat hue, threats must also read in
   grayscale: the wind-up is a luminance change, and drones have a distinct ring silhouette.
3. Scrap is cyan with a pulse of 1.2 s period, visible from 40 m. Nothing else is cyan.
4. The player walker uses warm orange accents. The world stays in desaturated mid tones, so actors pop.

**Palette:**

| Role | Hex |
|---|---|
| Player accent | `#FF8A3D` |
| Player body | `#E6E1D6` |
| Threat | `#E8345A` |
| Salvage | `#3DE0E8` |
| Outline ink | `#14161A` |

World palette, from the 50 % style mix (look-test mockup):

| Role | Hex |
|---|---|
| Sky top / horizon and fog | `#90A092` / `#DACFB6` |
| Far rock (300 m+) | `#A58B78` |
| Rock base / lit band / shadow band | `#9B7D69` / `#BBA189` / `#6D5548` |
| Ground / ground streaks | `#CAB294` / `#B99F82` |
| Ruins | `#93806E` |
| Smoke | `#57514D` |
| Foreground rocks | `#352D28` |
| Shrubs | `#7E8F63` (olive, kept well away from salvage cyan) |

**Shading:**
- Flat colour bands: each rock face gets a base, one lit band and one shadow band, with no smooth gradients on
  solids. Actors use a toon ramp with 3 bands and a hard terminator.
- Ink outline (M1, see the Decisions log): 2.3 px at 720p, 3.5 px at 1080p, on actors and rocks; terrain gets
  1 px or none, depending on budget.
- Distance fog in the horizon colour: 14 % at 100 m, 30 % at 300 m. Smoke and haze are part of the look, not
  weather.
- Film grain at 4.5 % opacity. Faint sky mottling at 2.5 %.
- No bloom except on emissives (threat, salvage).

**References (`design/refs/`, 12 images from Klas):**
- **Style:** a 50/50 mix of `crystal.webp` (ink lines, flat colour bands, glowing crystals) and
  `burried runied city.jfif` (sepia haze, smoke column, ruins half buried in dunes). The palette and shading
  numbers above come from the look-test mockup at 50 % (https://claude.ai/artifact/Uykcqe7akg85GnsyMJu31K).
- **Walkers:**
  - `small walker.png` and `fat walker.png`: compact 4-leg bodies, the heavy end of the build range.
  - `box like walker.jfif`: a cabin on spindly legs kicking up dust (the dust-puff read).
  - `nimble walker.webp` and `giant walker.jpg`: long-leg spider silhouettes, the Strider end. The giant
    walker also shows scale against humans, and orange emissive seams.
- **Landforms:**
  - `canyon-river.jpg` and `desert-arc.jpg`: the canyon and mesa language for M0.
  - `fog.jpg`: a cloud-sea plateau for a later zone.
  - `valley.jpg`: the M0 map layout and the muted palette. A wide valley floor between cliff walls (natural map
    bounds), a meandering dry wash that leads the eye outward, cloud shadows and sunlit patches, and a rain shaft
    as a distant landmark.
  - `open-pit.jpg`: actually a slot canyon. An overhanging wall with vertical varnish streaks (these read well as
    flat ink bands), an arch, olive shrubs and a wet sand floor.
- **Muted world:** the refs' red sandstone is desaturated toward dusty beige-grey so the orange accent and the
  threat red stay readable. Actor hues are unchanged.
- **Earlier pitch references** (Borderlands, Robocraft, Kenshi) still stand for outlines and the garage.

## 11. Audio direction
- M0: placeholders only (cut-first per Klas).
- Target: each foot plant is a heavy metal clunk with a 3 % pitch variance per leg. A walking rhythm you can
  hear tells you the gait, so the audio serves Pillar 2.
- Drone wind-up has a rising whine of 0.6 s that matches the visual telegraph.
- Scrap pickup is a bright tick.

## 12. UX and UI flows
- **Boot:** loads straight into the workshop with a valid Scout build. Main menu comes later (M2).
- **Workshop:** part list on the left, walker on a stand in the centre, stat panel with deltas on the right,
  and an "Exit [Tab]" button that is disabled with its reason shown when the build is invalid.
- **Field HUD:**
  - Crosshair.
  - Chassis HP bar (bottom left).
  - Carried and banked scrap (top right).
  - Compass marker to the workshop and to the wreck cache.
  - The HUD covers <= 8 % of the screen area.
- **Death:** collapse 1.0 s, fade 0.5 s, workshop. A toast says "Wreck cache: N scrap at <distance> m".

## 13. Tech constraints
| Item | Value |
|---|---|
| Dimension and renderer | 3D, Forward+, Jolt physics (Godot 4.7 default) |
| Resolution | 1280x720 base, stretch `canvas_items` / `expand`, target 1920x1080 |
| Frame rate | 60 fps. Frame time p95 <= 16.7 ms, max <= 33 ms on a GTX 1660 / Ryzen 5 3600-class PC |
| Draw calls | <= 1000 (outlines add a pass) |
| Static memory | <= 768 MB |
| Orphan nodes | 0 |
| Simulation caps | player walker <= 8 legs; <= 4 active drones; <= 40 live projectiles |
| Physics tick | 60 Hz. Gait and IK run in `_physics_process`, visuals interpolated |
| Platform | Windows PC, KB+M |
| 3D collision layers | 1 world, 2 player, 3 enemies, 4 player_projectiles, 5 enemy_projectiles, 6 pickups, 7 triggers. Foot raycasts mask world only |

## 14. Milestones
- **M0 Playable loop (<= 2 weeks of agent work):** walk, build and fight on one map. Acceptance criteria are in
  `design/plan.md`.
- **M1 Vertical slice:** second zone behind a terrain gate, enemy walker sentinel, 5 legs and 5 top parts, real
  footstep audio, toon and outline shading at final quality, and a flatter chassis so the arched knees peak above it.
- **M2 Content:** 3 zones, all parts, gamepad, main menu, save/load.

## 15. Out of scope
- Multiplayer.
- Freeform beam building.
- Player-tuned physics gaits.
- Procedural world generation.
- Story or dialogue.
- Mobile.
- Gamepad before M2.
- Save/load before M2. M0 sessions are single-run.

## 16. Risks and unknowns (spike tasks)
1. **IK gait reads well and never slides** (Pillar 2). Spike: the T03 greybox walker on the 30 deg bumpy test
   course, with drift metrics.
2. **Builds feel different enough** (section 4). Spike: the `build_contrast` scenario with A/B metrics, checked
   before any content work.
3. **Tank controls feel clunky with a free camera** (driving one way while looking another). Fallback: the body
   turns toward camera yaw, with Q/E strafe kept. Klas decides at the T03/T04 gate.
4. **Toon outline cost** on a 400 m terrain. The outline is built in M1; measure its draw calls there.
   M0 ships the toon ramp without it.
5. **Kinematic body vs Jolt projectiles and drones.** Collision layers are fixed in T00 (section 13).
6. **The valley feels like a corridor.** The floor stays at least 150 m wide, the wash winds, and there are side
   nodes and two pockets off the path. Playtest-critic checks this at the M0 review.

## 17. Decisions log (append-only)
| Date | Decision | Why | Rejected alternatives |
|---|---|---|---|
| 2026-10-08 | Concept: build-your-own spider walker; fantasy inventor + explorer | Klas's pitch | Lemmings-like, horde survival, walking sim |
| 2026-10-08 | 3D, Forward+, PC KB+M, 30-60 min sessions | Klas | 2D; mobile; short roguelike runs |
| 2026-10-08 | Procedural IK gait on a kinematic body; build changes stats and silhouette | Always walks; low risk; testable | Full physics joints (tuning risk), hybrid balance |
| 2026-10-08 | Snap parts on chassis sockets | Fast to read and validate | Freeform beams, tuning-only |
| 2026-10-08 | Salvage economy drives exploration (scrap to parts) | Klas | Pure terrain gates |
| 2026-10-08 | Failure = shot by drones (M0) / enemy walkers (M1); weapons are socket parts | Klas | Tip-over only, resource timer |
| 2026-10-08 | Death drops carried scrap as a one-time wreck cache; build kept | Stakes without punishing experiments | Losing a part; no loss |
| 2026-10-08 | 3rd-person orbit camera, body turns to camera yaw | Legs read; standard shooter control | Top-down, tank controls |
| 2026-10-08 | Superseded: tank controls (W/S drive, A/D turn, Q/E strafe, free mouse camera and turret aim, turret +/- 150 deg) | Klas: try tank; turn rate becomes a felt build stat in fights | Body turns to camera yaw (kept as fallback at the gate); 360 deg turret; fixed forward guns |
| 2026-10-08 | Clean sci-fi toon look; refs Borderlands, Robocraft, Kenshi | Klas | Low-poly flat, dieselpunk |
| 2026-10-08 | Speed range by build 2.5-7 m/s, Scout 4.5 m/s | The build is the feel (Pillar 1) | Fixed heavy, fixed nimble |
| 2026-10-08 | M0 = walk + build + 1 drone enemy; cut first: enemy walkers, audio/VFX polish | Tests the risk hypothesis and failure state | Walk+build only; combat only |
| 2026-10-08 | Custom analytic two-bone IK in GDScript, no engine IK node | Unit-testable, no engine-version risk | SkeletonModifier3D IK nodes |
| 2026-10-08 | Leg catalog short/medium/long with lift, reach, slope grip, spread; legs sold in pairs | Heavy builds win by tank (HP, DPS, tight spread) and slope grip, long legs by speed and ledges: no single optimal build | Long legs dominating; clamped heavy speeds |
| 2026-10-08 | Full repair on bank, no field regen; drones and ring 1-2 nodes respawn on bank, ring 0 never | HP is the push-or-return clock; no risk-free farming | Field regen; paid repair |
| 2026-10-08 | M0 map gets one 0.8 m ledge pocket (60 scrap) as the session goal | Gives step-up a use and tests "a build opens a place" before M1 | Gates only in M1 |
| 2026-10-08 | Keep orange player accent; threats must also read in grayscale (luminance wind-up, ring silhouette) | Klas prefers the warm look | Yellow #F5C542 |
| 2026-10-08 | Ink outline moved from M0 to M1; M0 ships toon ramp, palette, dust puff and contact decal | Keep M0 within two weeks; outline cost is its own spike | Outline in M0 |
| 2026-10-08 | Uneven leg builds from M1 with an imbalance penalty; M0 stays symmetric | Klas wants uneven builds; M0 tests the gait risk on the simplest case | Strict symmetry forever; uneven in M0 |
| 2026-10-08 | Two currencies from M1: scrap buys, blueprints unlock; blueprints are in exploration pockets and kept on death | Klas: both scrap and blueprints; exploration pays separately from risk | Scrap only; blueprints dropped by enemy walkers |
| 2026-10-08 | Input to motion <= 2 physics ticks; drone bolts 25 m/s; turret arc +/- 150 deg; hold-E recall | game-designer critique: start must not slide, speed must matter in combat, stuck recovery | Hitscan drones |
| 2026-10-08 | Clarification: stuck recall is hold `interact` (F) for 3 s; the earlier "hold-E recall" row predates tank controls, where E became `strafe_right` | Avoid a key clash; section 6 is authoritative | Recall on E |
| 2026-10-08 | World palette muted (dusty, desaturated sandstone); actor hues unchanged | Klas: keep orange and red; red rock in the refs would swallow them | Pale player + violet threats; rely on shape only |
| 2026-10-08 | M0 biome: canyon mesa (muted); later zones: buried ruined city, cloud-sea plateau | Mesas give the ledge pocket and natural rings | Ruined city or open flats for M0 |
| 2026-10-08 | design/ has a .gdignore | Keep reference images and docs out of the Godot import | Import everything |
| 2026-10-08 | Style anchor: 50/50 mix of crystal.webp and the buried ruined city; palette, fog, ink and grain numbers from the look-test mockup | Klas picked 50 % on the mockup slider | Pure comic (crystal.webp); semi-real renders |
| 2026-10-08 | M0 map is a valley (ref valley.jpg): cliff walls as bounds, workshop at the head, dry wash as the main path, ruins closing the far end | Rings become a readable direction (deeper = down-valley); no invisible walls; cheap greybox; ready M1 gate | Open 400 x 400 m area with concentric rings |
| 2026-10-08 | Second M0 pocket: a 40 deg talus slope only the Crawler can climb, mirroring the Strider's 0.8 m ledge pocket | Makes the Crawler's slope grip (the "both" niche) matter in M0, not only in fights | Ledge pocket only |
| 2026-10-08 | Clarification: the 4-5 leg wave gait lifts one leg at a time (one leg per group); only 6+ legs use two tripod groups | 8.2 said "two alternating groups" for every gait, but section 5 caps 4 legs at 1 airborne; two groups of 2 would break it | Two diagonal pairs (trot) for 4 legs |
| 2026-10-08 | Clarification: the airborne limit beats the 85 % handover; the next group gets the turn at 85 % but its legs lift only within the limit | A literal 85 % overlap puts all 6 legs of a tripod in the air, against Pillar 2 and M0 criterion 2 | Overlapping swings at 85 % |
| 2026-10-08 | Clarification: medium legs (catalog price "start") are not for sale in M0; the player has only the starting 6 | Klas confirmed; the shop sells only short and long legs, so every leg purchase changes the feel | Medium legs buyable to reach 8 |
| 2026-10-09 | Camera: rock beats the 2 m arm minimum; with rock closer than 2 m the arm goes shorter | Klas, from the T04 reviews: a camera inside rock reads as a bug, a close-up of your own walker reads as intentional | Keep 2 m always and accept seeing inside rock |
| 2026-10-09 | Recentring pauses while `aim` is held; its 1.5 s timer restarts on release | Klas, from the T04 playtest review: strafing while waiting out a drone wind-up would swing the view off the drone | Also pause after firing (needs T06); no pause |
| 2026-10-09 | Accepted for M0: one near foot may leave the frame at aim FOV 50; revisit at the T03/T04 gate | Klas: aiming is about the target, and every foot reads at FOV 70 | Raise or pull back the camera while aiming |
| 2026-10-09 | Walkers descend what they climb: step-down >= step-up; the body lowers toward a lower foothold before the feet reach for it | Klas, from the T03 code review: with a step-down of about 0.3 x reach a Strider is trapped in the 0.8 m ledge pocket and a Crawler on any 0.3 m boulder | Walk off the edge and drop; keep the limit and give ledges ramps |
| 2026-10-09 | Step duration scales with the build's mean leg reach: x sqrt(reach / 1.0 m) | Klas, from the T03 playtest review: every build stepped on the same beat; long legs should lope and short legs scuttle (Pillar 1) | One 0.18 s step for every build |
| 2026-10-09 | The 4-leg wave steps faster, and the 4-leg gait_factor is then set from the measured sustained speed, so the stat panel tells the truth | Klas, from the T03 playtest review: the quad covered about 55 % of its 3.1 m/s stat and lurched at nearly every step | Keep the lurch and only fix the stat; trot (two diagonal pairs) |
| 2026-10-09 | Arched legs: each hip 0.5 x its own reach above the foot plane on a strut (the chassis underside stays at 0.6 x mean reach), rest foot 0.5 x reach out, bones 1.15 x reach split 0.46/0.69, pole up. Knee +0.19 x reach above the hip at rest, +0.14 at stride end | Klas, from the game-designer's proposal: the playtest-critic saw the legs read as a table or a crab, and a 0.55 x reach shin can never lift the knee above a 0.6 x reach hip (Pillar 2). Keeps body height, step-up, camera and all 8.1 stats. Per-leg hip height also lets short legs on a medium body reach the ground (today about 0.92 x their reach at rest, so rule 5 holds the body) | Body down to 0.4 x reach with bones = reach (knee below the hip at the reach limit; the Strider loses height; step-up breaks); body 0.6 with bones 1.3 x reach (stride room -6 %, shin leans in; a short pair on a medium body cannot stand); pole change alone (<= 0.005 x reach) |
| 2026-10-09 | Amends the cadence row: step duration scales with the shortest mounted leg, x sqrt(shortest reach / 1.0 m); builds with one leg type are unchanged | Klas, from the game-designer's first-purchase check: a short pair on the Scout moved every felt stat by < 10 % (speed -2/+7 %, cadence -7/-5 %); now it steps 29 % more often. The gait must cycle as fast as its shortest leg's stride room allows, or rule 5 holds the body | Mean reach (a pair is diluted to 1/3); per-leg swing time (only a 2-3 tick flam); short-leg lift 110 -> 90 (still < 11 %, Crawler 2.95 m/s) |
| 2026-10-09 | Pillar 1 bar: a leg purchase moves top speed, turn rate or step rate by >= 15 %; armor and top parts are judged in the first fight (45-75 s out) | Klas: the pillar says "moves and fights"; armor (+40 % HP) and a 2nd cannon (DPS x2) change walking by only about 10 % | Every part passes the 15 % walk bar (needs heavier mass costs); no numeric bar |
| 2026-10-09 | A flatter chassis, so the knees peak above it as in the nimble-walker reference, waits for the M1 art pass; M0 keeps the greybox box | Klas: with arched legs the knees already read in greybox (Scout knee 0.69 m beside a 0.65-0.97 m chassis) | Flatten the greybox chassis in T03 now |
| 2026-10-09 | An invalid foot target (too high or too steep) makes the leg take the farthest valid foothold toward it, a shorter step; the leg blocks only when none is valid. Step-up is measured from the leg's current foot | Lead, from the T03 round-2 code review: full-length steps (about 0.55 m) rise about 0.43 m on 38 deg ground, past the Crawler's 0.36 m step-up, so it stalled at the foot of the slope its 45 deg grip is meant to climb (9.1 talus pocket). Vertical faces still block, and the slope check still stops the Scout and Strider | Measure step-up from the planted-foot plane (all feet are still on flat ground at the slope's foot, so the entry stays blocked, and a raised plane lets a foot accept a deck above step_up) |
| 2026-10-09 | Body tilt follows the terrain up to the build's slope grip (`max_slope`, the lowest among its legs), not a fixed 25 deg | Klas, from the T03 round-2 code review: at 25 deg on the 40 deg talus the Crawler's nose sits about 5 cm off the slope with its collider in it, so its only map niche fails. Tilting as far as it grips keeps the chassis parallel to any slope it can walk, and shows grip on the body. The camera does not pitch with the body | One 45 deg cap for every build (a Scout or Strider on uneven footholds could tilt past its own grip); keep 25 deg and give the Crawler a different niche |
| 2026-10-09 | Rest foot 0.42 x reach out from the hip (from 0.5) | T03 round-3 tuning inside the knee targets: at 0.5 the short pair's knee reached only 0.094 against the 0.10 bar | |
| 2026-10-09 | Withdrawn: the foot lead while the body is held uses the actual velocity (8.2, added earlier today) | Lead, measured in T03 round 3: leg holds no longer stop the body, so a lead from the near-zero actual speed puts feet at rest while the body resumes at full speed; the short pair covered 50.4 m on the bumps against 85.3 m | |
| 2026-10-09 | The chassis and hips never sink into the ground: where the planted-feet plane runs below the terrain (crests, ledge edges) the body rises to clear it; collider contacts are never ignored | Lead, from the T03 round-3 code review: over the 40 deg crest the Crawler's hips sat 0.33 m inside the slope (collider about 0.25 m), and the Scout sank 0.1 m on the plain bumps. Climbing the talus is the Crawler's niche, so it must read | Keep the plane fit and hide the overlap with art |
| 2026-10-09 | Body bob scales with leg length: 4 cm x mean leg reach (Crawler 2.4 cm, Scout 4, Strider 6.4), replacing 3-5 cm for every build | Klas, from the T03 round-3 reviews: a full bob stretches short legs toward their reach limit, and round 3 had faded it to zero on short legs. Scaling keeps a step rhythm on every build: long legs lope, short legs patter | 3-5 cm for every build; no bob on short legs (the Crawler reads planted, but the short pair, the usual first purchase, only reads as smoother) |
| 2026-10-09 | Knee rule: the above-the-hip bars hold on level ground walking straight, in the body frame. On any ground and when turning or strafing a knee may sit below its hip, but never straightens or flips (bend >= 0.05 x reach) | Klas, from the T03 round-3 playtest-critic: the downhill leg reaching down a slope with its knee below the hip reads as reaching (gait_slopes__steep), and 'never below the hip' cannot hold on a body tilted to its grip | Never below the hip anywhere (needs longer bones or higher hips, changing the approved arched legs) |
| 2026-10-09 | The body pitches toward the next footholds ahead of a slope's foot or a shelf edge, instead of only following the planted feet | Lead, from the T03 round-4 code review: with hips held clear, a Crawler whose tilt lags its feet stalls at the foot of the 40 deg talus (its front rim meets the slope at 6.7 deg tilt). A side-view pose search shows the real talus profile (9.1) is climbable with 0.15 m of reach to spare, but only if the body leans 7-12 deg into the slope 0.6-0.9 m before the corner and levels before the shelf edge | Round the talus edges in the valley; let hips sink into the slope |
| 2026-10-09 | Rest foot 0.43 x reach out from the hip (from 0.42); end legs fan 0.06 x reach fore-aft (from 0.08) | Lead, from the T03 round-5 playtest-critic: at 0.42 the shin sits only 0.1 deg outward, at the edge of the 0-15 deg target; 0.43 gives about 0.9 deg with no visible change (knee rise about 0.115, fore-aft room 0.68) | Keep 0.42 |
| 2026-10-09 | The clearance rise is capped at 1.5 m/s (2.5 cm per 60 Hz tick); when the body needs more, the walker slows its advance until it catches up. Ground steeper than the build's grip blocks like a wall and is never risen over | Lead, from the T03 round-5 reviews: the push-up rose up to 0.12 m in one tick (a visible hop on the Strider in the boulders, four times the Crawler's whole bob), and the Strider's body rode 0.41 m up the 40 deg talus it cannot climb. Pillar 2: a build slows to climb, and its limits read. Klas can overrule the cap at the gate | No cap (judge at the gate); allow a hop above the cap |
| 2026-10-09 | Pitch-ahead leans only toward footholds the build can stand on (rise <= step-up, slope <= grip) | Lead, from the T03 round-5 code review: leaning toward any ray hit tilted a blocked Scout 12.7 deg up a face it cannot climb and the Strider 10.6 deg at a wall, on flat ground | Lean toward any surface |
| 2026-10-09 | End legs fan 0.05 x reach fore-aft (from 0.06, set earlier today) | T03 round-6 tuning: at 0.06 the short pair's planted knee rise fell to 0.099 against the 0.10 bar; 0.05 keeps fore-aft room at 0.69 and the shin about 1 deg outward | Loosen the knee bar |
| 2026-10-09 | Over-grip ground blocks only where it stands taller than the build's step-up; a lower steep obstacle (a boulder, a small ledge) is stepped onto | Lead, from T03 round 6: blocking every over-grip contact turned 0.9 m boulders into walls for the Strider (step-up about 1.0 m), though a ledge of that height is not one; step-up already says what a leg can climb onto. Strider boulder run 22.2 -> 31.5 m | Hysteresis on the contact slope alone |
| 2026-10-09 | The 4-leg gait_factor stays 0.85 | Lead, measured on main after the T03 merge: with the faster 4-leg wave the quad sustains 31.58 m in 10.2 s on flat ground (0.99 of its 3.124 m/s stat) with no leg holds, so the stat panel already tells the truth | Raise the factor (untested above 0.85) |
| 2026-10-09 | Readability rule 1: side-on, the far row of feet may hide behind the chassis; seen from behind, every foot stays clear of the chassis and the ground | Klas at the gate ("it is acceptable"), from the T14 playtest review: at pitch 20 abeam the chassis hides the whole far row (Crawler 4 pads, Scout 3), as in the approved midstride view, while the near row carries the whole gait. Showing it would need pitch >= 42-47 deg or a lower chassis (M1) | Raise the camera side-on; lower the chassis now |
| 2026-10-09 | On descents steeper than about 25 deg the camera holds a pitch floor of the slope minus 5 deg (about 35 on the talus), easing in and out | Klas at the gate ("yes"), from the T14 playtest review: walking down the talus at pitch 20 the shelf edge cuts the line of sight, and recentring puts the camera there on every trip back from the talus pocket (Pillar 3). At pitch 35 every foot is clear. Numbers to confirm with mid-face and foot shots | Global minimum pitch of 35 (loses the look-out range); leave it to the player |

## 18. Open questions
- Do tank controls hold up with a free camera? Klas feels it at the T03/T04 gate (fallback in section 16).
- Blueprints are kept on death (current default). Should they instead be carried like scrap, for more stakes?
- The economy is estimated, not simulated: about 90 scrap per trip. Check real income in `loop_full` and retune
  prices before M1.
- Does keeping orange hold up in a colourblind check (playtest-critic with a deuteranopia filter at the M0 review)?
