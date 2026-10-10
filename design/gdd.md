# walkers - Game Design Document

Numbers, not adjectives. References in `design/refs/`. Defaults below are for the M0 "Scout" build
(medium chassis, 6 medium legs, 1 pulse cannon) unless stated.

## 1. One-liner, player fantasy, story and main goal
- Store line: Build a spider-legged walking machine from salvage, then stride into a hostile wasteland to scavenge
  parts for a better one.
- Fantasy: I am an inventor-explorer. The machine under me is my own design, and I can feel every choice I made in
  how it walks. "Building and feeling like an inventor is in the very core of the game" (Klas); exploring is what
  pays for the next idea.
- Story and main goal: open (Klas, 2026-10-10: "there must be a larger reason for exploring"; Decisions log,
  section 18).

## 2. Pillars (max 3)
1. **Your build is your feel.** Building and feeling like an inventor is the core of the game. Each part change
   shows in how the walker moves and fights within 5 s of leaving the workshop. There are no walker types or
   classes: you evolve your one starting walker to your will, with wide room to expand (blocks and modules, 8.1).
   *We cut part count before we compromise this.*
2. **Legs that read.** The walk is the show: feet plant and never slide, and gait is readable at the default
   camera distance. *We cut enemy walkers and VFX polish before we compromise this.*
3. **Venture and return.** Every trip puts carried salvage at risk, and the further you go the more it pays.
   *We cut map size before we compromise this.*

## 3. Core loop
- **30 seconds:** steer the walker over uneven ground (WASD; the mouse orbits the camera and aims the guns), shoot
  drones (LMB), walk over scrap to pick it up.
- **5 minutes (one expedition):** leave the workshop, follow scrap nodes 60-200 m out, survive 2-4 drone encounters,
  then decide: push further for richer nodes, or walk back and bank. Bank in the workshop, buy one part, re-socket,
  and leave again with a different feel.
- **One session (30-60 min):** 6-10 expeditions; 3-5 new parts bought; one new zone reached that needs a build
  change (M1+: terrain gates such as a 2.0 m ledge or a 4 m gap). The player leaves with a machine that looks and moves
  differently from the one they started with, and a plan for the next part.

## 4. Why it is fun (the risk hypothesis)
**Hypothesis:** rebuilding is fun because a procedural IK gait turns part choices into movement you can see and
feel (speed, turn rate, stride, step-up height, sway), not just numbers on a stat screen.

**What kills it:** if every build walks about the same, the inventor fantasy collapses into a stat menu, and the
game becomes a mediocre shooter on legs.

**How M0 tests it:**
- Scenario `build_contrast`: Strider A (6 long legs) and Crawler B (8 short legs, 2 cannons, armor) from section
  8.1 differ by >= 40 % in measured top speed and max climb height, computed as (A - B) / A, on the same course,
  and neither stat is clamped. Speed, turn and climb are logged.
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
| Legs airborne at once | <= half, hanging legs included (6 legs: alternating tripod) | 4 legs: max 1 airborne (wave gait) |
| Body height above foot plane | 0.6 x mean leg reach (chassis underside), spring settle 0.15 s | |
| Leg stance (arched legs) | Each hip 0.5 x its own leg reach above the foot plane, on a strut under the chassis side; rest foot 0.43 x own reach out from the hip, end legs fanned up to 0.05 x reach fore-aft; bones 0.46 + 0.69 x reach (1.15 x reach, so the leg never straightens); bend plane vertical (pole up); planted feet stay within 0.99 x reach | same ratios for every leg, in any mix |
| Knee height | On level ground walking straight, in the body frame: above the hip by >= 0.15 x reach at rest (geometry 0.19) and >= 0.10 x reach for planted feet within 0.5 x reach fore-aft of rest. On any ground, and when turning or strafing, a leg may reach down with its knee below the hip, but the knee stays on the pole side of the hip-foot line by >= 0.05 x reach (the 0.99 x reach clamp leaves about 0.08): never straight, never flipped. Upper bone >= 15 deg above horizontal; shin 0-15 deg outward of vertical; fore-aft room from the rest foot to the 0.99 x reach limit >= 0.65 x reach | Crawler knee 0.41 m, Scout 0.69 m, Strider 1.10 m |
| Body tilt follows terrain | <= the build's slope grip (`max_slope`: Strider 30, Scout 35, Crawler 45 deg), smoothing 0.12 s | |
| Body bob amplitude while walking | 4 cm x mean leg reach, on flat ground (Crawler 2.4, Scout 4, Strider 6.4 cm) | |
| Max walkable slope | 35 deg | 25 - 45 deg |
| Stride step-up | 0.6 x leg reach above the leg's current foot (Scout 0.6 m), taken in a normal step with no climb | Crawler 0.36 - Strider 0.96 m |
| Max climb height (`climb`) | 0.9 x the shortest mounted leg's reach (Scout 0.90 m; the mean for a build of one leg type). A front foot reaches up onto a top at most 0.4 x reach above its own hip, then the body hauls (8.2). Step-down mirrors it to the same depth | Crawler 0.54 - Strider 1.44 m |
| Reach-up swing | 1.5 x the build's step time (Strider 0.35 s, Scout 0.27 s, Crawler 0.21 s at top speed). The foot rises to the edge + 0.15 x reach before it moves over the lip; a reaching or hanging pad is inside geometry on 0 ticks | scales with the step time |
| Haul | Advance <= 0.4 x top speed from the first front foot on top to the last foot up; rise or lower <= 1.5 m/s (2.5 cm per tick). Body pitch peaks at 10-25 deg, never above min(grip - 5, 25) deg. Climb time from the first reach to the last foot on top: 1.0-2.0 s on a ledge 0.75 x climb tall (Strider 1.08 m, Crawler 0.40 m), Klas tunes it at the next playtest. No stretch longer than 0.4 s without horizontal or vertical progress while input is held. A rise within stride step-up costs <= 0.3 s extra | |
| Hanging legs | A leg with no valid foothold lifts within 1 tick and hangs at its lift height (0.25 x reach), >= 0.05 m clear of geometry, pawing toward the face or edge on a 0.6 s cycle. At a face it cannot climb, each paw swings a front pad up the face to the highest foothold it tested, >= 0.6 x reach above the floor and at most its hip + 0.4 x reach, >= 0.05 m off the face, then drops back to the lift height. It counts as airborne. While any leg hangs, the centre of mass stays inside the planted feet's polygon by >= 0.1 x mean reach (Strider 0.16, Scout 0.10, Crawler 0.06 m). On ground with no rise or drop beyond stride step-up, no leg hangs | |
| Camera orbit distance | 8 m (scroll 5-12 m), FOV 70; spring-arm terrain collision, min 2 m unless rock is closer (rock wins) | |
| Mouse sensitivity | 0.15 deg/px; 0.10 deg/px while `aim` is held (the same screen motion per pixel at FOV 50); invert-Y off (constants in M0, settings menu M2) | |
| Camera position lag | 0.10 s smoothing; 0 lag on rotation | |
| Pulse cannon | 4 shots/s, 15 dmg, projectile 60 m/s, spread 1.0 deg x leg spread factor; 40 kg, top mount, traverse 180 deg/s (8.3) | 0.5 - 1.5 deg |
| Weapon traverse (its reticle follows the dot) | clamp(7200 / weapon mass in kg, 45, 720) deg/s, in yaw and in pitch, no ramp: the pulse cannon follows a 90 deg flick in 0.50 s (30 ticks) | 45 (>= 160 kg, 90 deg in 2.0 s) - 720 (<= 10 kg, 90 deg in 0.125 s) deg/s |
| Drone | 45 HP (3 hits), hitbox r 0.6 m, hover 3-6 m, 10 dmg/shot, 1 shot / 1.5 s, 0.6 s wind-up glow, bolt 25 m/s aimed at the walker's position with no lead (0.6 s flight at 15 m: dodgeable by strafing). Orbits at <= 6 m/s and holds still for its wind-up: stop within 0.1 s, hold 0.9 s (wind-up 0.6 s + 0.3 s after the shot), resume orbit speed over 0.3 s, so it is a still target for 0.9 s of every 1.5 s | |
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
| `aim` | RMB (zoom to FOV 50, mouse 0.10 deg/px) | walking |
| `interact` | F: enter the workshop when within 4 m. Hold 3 s anywhere: recall to the workshop (stuck recovery; carried scrap drops as a cache, like death) | walking |
| `zoom_in` / `zoom_out` | mouse wheel | walking |
| `build_place` | LMB on socket | workshop |
| `build_remove` | RMB on part | workshop |
| `build_exit` | Tab | workshop |
| `pause` | Esc | both |

**Tank controls, mouse aim** (Klas after the M0 build, 2026-10-10: "The weapons must follow the mouse"):
- The keys drive the body and never aim. W/S drive along the body's facing, A/D turn the body at its turn rate,
  and Q/E crab-strafe.
- The mouse moves the camera, and the camera aims. The mouse never turns the walker. Mouse X yaws the camera freely
  (360 deg). Mouse Y pitches it from -20 to 60 deg. -10 to 60 is the normal range. -20 to -10 is the aim-up range
  for drones close overhead: there the spring arm shortens against the ground (rock wins), and feet may leave the
  frame.
- The screen centre is the aim point P (8.3), marked by the camera dot (12): where the mouse aims, not where the
  walker heads.
- Every weapon turns toward P by itself, within its mount's arc and at its own traverse rate (8.3). Light guns are
  on the dot almost at once; heavy guns visibly lag behind it. Each weapon has its own reticle (12). A gray
  reticle means that weapon cannot reach P from its mount and does not fire.
- `fire` (LMB, held) fires every weapon whose reticle is live (not gray), each at its own rate.
- The body heading still counts (risk 8). The traverse is relative to the chassis, so turning toward a target with
  A/D adds the turn rate to every gun's swing (Scout, 90 deg: 0.50 s on the gun alone, about 0.32 s with A/D).
  Front, back and side mounts (M1) reach only +/- 90 deg around their face. The heading is also the line you travel,
  climb (the 45 deg approach rule, 8.2) and strafe across. Q/E strafing dodges bolts while the mouse keeps the
  dot on target.
- `aim` (RMB, held): FOV 70 -> 50 in 0.10 s, and the mouse drops 0.15 -> 0.10 deg/px, so the dot moves the same
  distance on screen per pixel. The turn rate is unchanged (the x 0.6 aim penalty is gone: the body no longer aims).
  It pauses recentring and releases the descent floor, as before.
- Turning in place re-plants the legs visibly, so the turn itself is a gait show (Pillar 2).
- The camera does not auto-follow the body's yaw. Behind-the-body recentring is on a 1.5 s delay after mouse
  idle. It pauses while `aim` or `fire` is held, and its timer restarts on release. Recentring now also moves P and
  every gun with it, so it is the first knob to turn off if it fights the aim in play (section 18).
- On a descent, where the ground behind the walker rises steeper than about 25 deg for at least 1.5 m (a slope, not
  a boulder or a single ledge) and stands in the line of sight to the walker's feet, or drops that steeply just
  ahead, the camera holds a pitch floor of that slope
  minus 5 deg (about 35 deg on the 40 deg talus), so the edge behind never hides the walker. It eases in over about
  0.45 s and out over about 0.8 s; on flatter ground the camera returns to the player's own pitch. The floor lets go
  while `aim` is held. Gamepad is out of scope until M2, but the action names
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
- **Build principle: no fixed walker types or classes** (Klas, 2026-10-09: "You evolve your starting Walker to your
  will. It may be two very long legs or 12 very short for example."). Every later rule serves this one.
  - Every stat, gait and limit derives from the mounted parts (leg count, each leg's length, placement), never from a
    build name or type. A formula may use the leg count, but it must hold for any valid count, not a listed set.
  - A build needs at least 4 legs (Klas, 2026-10-09: "Since 2 legs poses a problem, make it a minimum 4"). Past
    that, the leg count is the player's choice; 12 very short legs is a build the game must allow.
  - Scout, Strider and Crawler (below) are test fixtures and example builds, not classes. The game does not label the
    player's walker with a build name.
  - **Block chassis** (Klas, 2026-10-09): the chassis is built from blocks that can be expanded like Lego. Each block
    has 6 sockets, one per direction (left, right, top, bottom, front, back). A socket takes another block or a
    module. Modules include weapons, cargo containers and drone hatches, and the list is meant to grow: wide room for
    expansion is a design goal. A cargo container raises the scrap the walker can carry per trip. A drone hatch
    launches the player's own drones: a far-future idea that may never be built, not in M1 or M2. Legs are the one
    module limited to a block's left or right socket, never its top, bottom, front or back. Today's medium chassis is
    the 8-block build; M0 keeps it as one fixed part with its 8 leg sockets (4 per side) and 3 top sockets.
  - Where an M0 rule narrows the leg count, placement or length (4, 6 or 8 legs, symmetric, three leg lengths), it is
    an M0 scope limit, not a design rule.
  - **Build rules from M1** (Klas, 2026-10-09, all four as the game-designer recommended):
    - *Layout:* today's chassis is 4 blocks long and 2 wide. A block is 0.7 x 0.5 x 0.3 m, so hips sit at a 0.7 m
      pitch. The 4 x 2 build has 4 left and 4 right sockets (today's 8 leg sockets), 8 top, 8 bottom, 2 front and 2
      back. A socket that faces an attached block is closed. Blocks may stack; in M1 legs mount only on bottom-layer
      blocks, so hips stay on short struts and the knees stay visible (Pillar 2).
    - *Leg length:* a ladder of 9 lengths, 0.4, 0.5, 0.6, 0.8, 1.0, 1.25, 1.6, 2.0 and 2.5 m (about x1.25 per step).
      Today's short, medium and long legs are steps 3, 5 and 7. The player pays scrap to grow or shrink an owned leg
      one step; a leg's mass, lift, grip and spread follow curves through today's three legs. The extreme lengths
      (0.4, 0.5, 2.0 and 2.5 m) are unlocked by blueprints found out exploring.
    - *Economy:* a block is 1/8 of today's chassis: 15.625 kg, 12.5 HP and 15 scrap; the player starts owning 8, so
      the 8-block build keeps today's 125 kg and 100 HP. Everything the player owns stays in inventory, and
      re-socketing is free, so experimenting stays cheap (section 7). A walker carries at most 60 scrap per trip, +40
      per cargo container: a full walker heads home (Pillar 3).
    - *Limits:* mass against leg lift is the main limit, felt in speed and turning; there is no power resource. M1
      hard caps: 12 legs (raised only after a 12-leg performance test passes) and 4 weapons. A weapon on any face
      aims at the mouse aim point within its face's arc (8.3, from 2026-10-10), so where a gun is socketed is a
      build choice. A module on a bottom socket lowers the ground clearance by its depth, shown as a stat.
  - Not yet decided: the chassis size cap (blocks long, wide and high); the cargo container's mass and price; which
    other modules ship when and what they do; the gait for 9-12 legs; and the stats the new shapes stretch (the top
    speed range, the turn rate floor, the camera distance for large builds).
- **State:** chassis id; map of socket id to part id.
- **Rules:**
  - The chassis defines sockets. M0 medium chassis (the 8-block build as one fixed part): 8 leg sockets and 3 top
    sockets.
  - A part fits only its socket kind (leg or top).
  - M0: the build is valid when it has 4, 6 or 8 legs placed symmetrically (equal count per side), and total
    mass <= total leg lift. Leg types may be mixed.
  - M1: uneven builds are allowed. Rules:
    - Legs are sold singly at half the pair price.
    - A build needs at least 2 legs per side and at least 4 legs in total. The earlier upper limit of 8 is withdrawn
      by the build principle (12 legs is Klas's example); whether a cap remains past 12 is open.
    - imbalance = |lift_left - lift_right| / lift.
    - top_speed x (1 - 0.5 x imbalance).
    - spread + 2.0 deg x imbalance.
    - Idle body roll toward the weak side is 10 deg x imbalance (visible sway).
    - Gait groups alternate by socket order, and each group keeps the centre of mass inside the support polygon.
  - M0 code keeps per-leg data with no pair assumption, so uneven builds are a rules change only (the block chassis
    is more than rules: hips and colliders come from the block layout).
  - Derived stats are computed only from the part list.

**M0 part catalog.** Legs are sold and placed in mirrored pairs (singly from M1).

| Part | Socket | Mass (kg) | Lift (kg) | Reach (m) | Slope grip | Spread (deg) | Other | Price (scrap) |
|---|---|---|---|---|---|---|---|---|
| Medium chassis | - | 125 | - | - | - | - | 100 HP, 8 leg + 3 top sockets; the 8-block build as one fixed part | start |
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
| `step_up` | 0.6 x reach (the stride step-up, 8.2) |
| `climb` | 0.9 x the shortest mounted leg's reach (the max climb and step-down, 8.2; shown on the stat panel). For a build of one leg type this equals 0.9 x reach. Switched from the mean reach after T16 measured a mixed build 17 % short of it (Decisions log) |
| `max_slope` | lowest slope grip among the mounted legs |
| `spread` | 1.0 deg x mean leg spread factor (body sway) |
| `hp` | chassis hp + armor parts |

**Reference builds** (unit test fixtures and example builds, not classes; see the build principle above):

| Build | Parts | Load | Speed | Turn | Step-up | Climb | Slope | HP | DPS | Spread |
|---|---|---|---|---|---|---|---|---|---|---|
| Scout | 6 medium legs, 1 cannon | 0.70 | 4.50 | 120 | 0.60 | 0.90 | 35 | 100 | 60 | 1.0 |
| Strider (A) | 6 long legs, 1 cannon | 0.56 | 6.49 | 134 | 0.96 | 1.44 | 30 | 100 | 60 | 1.5 |
| Crawler (B) | 8 short legs, 2 cannons, armor | 0.61 | 3.80 | 109 | 0.36 | 0.54 | 45 | 140 | 120 | 0.5 |

- **Niche:** niches belong to the parts, and the fixtures show them. Long legs reach ledges and escape (the
  Strider). Short legs grip steep slopes, and their lift carries the guns and armor that win fights (the Crawler:
  DPS x HP is 2.8x the Strider's, and its spread is tight). Neither build dominates (Pillar 1).
- **Edge cases:** removing a leg that makes the build invalid is allowed in the workshop, but the exit is blocked
  with a reason string ("Overloaded: 412/380 kg", "Needs 4, 6 or 8 legs", "Legs unbalanced").
- **Tests:**
  - Each reference build matches its table row within 0.01.
  - Contrast, computed as (A - B) / A: >= 40 % in speed and in climb (expected 0.625), and neither A nor B is
    clamped.
  - B's DPS x HP >= 1.8x A's.
  - Validity reason strings.

### 8.2 Locomotion - body controller and gait
- **Body:** CharacterBody3D, moved kinematically from input and build stats, with the accel and decel from
  section 5. Height and tilt are fitted to the plane of the planted feet (least-squares, then smoothed). The
  chassis and the hips never sink into the ground: where that plane runs below the terrain (over a crest or a
  ledge edge) the body rises until they clear it, at most 1.5 m/s (it slows its advance to climb, it never hops),
  and waits if the legs cannot reach that far. Ground steeper than the build's grip that stands taller than its
  climb stops the body like a wall; it never rises over it (a lower steep obstacle is climbed: stepped onto in
  stride up to step_up, reached and hauled up to climb). Where the ground ahead rises or falls (a slope's foot, a ledge or shelf edge), the body
  pitches toward the next footholds it can stand on before its feet get there, as a climber leans into a slope;
  tilt still follows the planted feet on even ground.
- **Climb (reach and haul):** climbing looks like effort, never a teleport.
  - *Reach:* a front-row leg (the first mounted leg on each side) whose stride target is blocked by a rise may plant
    on the top up to `climb` (0.9 x mean reach) above its current foot. The foothold must lie at most 0.4 x its own
    reach above its hip, within 0.95 x reach of the hip with the knee bend >= 0.05 x reach, on ground inside grip,
    and >= 0.15 m past the edge. A short-legged build whose chassis nose meets the face pitches its nose up first
    (pitch-ahead), then reaches. The reach swing follows section 5.
  - *Haul:* once both front feet are on top, the body pitches nose-up toward the top, up to min(grip - 5, 25) deg,
    rises at most 1.5 m/s and advances at most 0.4 x top speed until the last foot is up (section 5).
  - *Follow-on:* every other leg may step up to `climb` above its current foot once its hip has passed over the edge
    of the higher ground. Until then a leg with no valid foothold hangs.
  - *Step-down mirrors it:* at an edge the body (chassis centre) lowers by up to 0.32 x reach and pitches nose-down, up to
    min(grip - 5, 25) deg. A front leg may plant up to `climb` below its current foot, within 0.95 x reach of its
    hip. The body lowers at most 1.5 m/s and advances at most 0.4 x top speed, and following legs step down as their
    hips pass the edge. At a drop deeper than `climb` the front legs hang over the edge and the body stops; it never
    walks off.
  - *Approach angle:* a walker climbs (or steps down) a ledge it meets within 45 deg of head-on, its heading measured
    against the face's normal. Met at a shallower angle the face counts as one it cannot climb: the walker slides
    along it at full along-face speed. To climb, the player turns into the ledge.
  - *Footholds on a top* sit far enough past the edge that the shin clears the corner (at least 0.15 m). The climb
    height is a hard check: a foothold more than `climb` (+ 0.66 % of the mean reach: 1 cm on the Strider, 0.4 cm on the Crawler) above the leg's current foot is never taken, even
    when the leg could reach it.
- **Gait (`GaitSolver`, pure):** legs split into alternating groups: two tripods for 6+ legs; for 4-5 legs a wave
  gait with one leg per group.
  A leg may step when its foot error is > 0.5 x reach and its group is active. The next group starts when every
  foot of the active group is planted, or 85 % into the step, but a leg never lifts while that would put more legs
  in the air than the section 5 limit. A hanging leg counts as airborne, so planted legs never number fewer than
  the leg count minus the gait limit (4 legs: 3, 6 legs: 3, 8 legs: 4). While any leg hangs, the centre of mass
  (the chassis centre, projected along gravity) stays inside the polygon of the planted feet by >= 0.1 x mean
  reach; a body move that would break this is shortened like a move that would break reach.
- **Foot targets:** a downward raycast from rest position + velocity x step duration x 0.5. A target more than
  step_up above the leg's current foot is invalid unless the climb rules above allow it, and a target steeper than
  the max slope is always invalid. The leg then takes the farthest valid foothold
  between its current foot and the target, a shorter step. When none is valid, the leg hangs and paws toward the
  face or edge (section 5) if the airborne limit and the centre-of-mass margin allow it, and the body keeps moving
  while both hold; otherwise the leg stays planted and the body stops on that side. On a steep slope inside its
  grip a walker takes short steps and slows; a vertical face taller than `climb` still blocks, with the front legs
  pawing at it.
- **IK (`TwoBoneIK`, pure):** analytic two-bone solve with a pole vector pointing up (bend plane vertical), and stretch
  clamped at 99 % of the bone length. The bones total 1.15 x leg reach, so at the 0.99 x reach planted-foot limit
  (section 5) the knee is still bent. There is no engine IK node, so the solve is unit-testable.
- **Edge cases:** a foot target that is unreachable for more than 0.5 s makes the leg hover at its rest pose.
  Moving the walker by an external push (M1) replants every foot within 0.3 s.
- **Tests:** IK end effector within 1 mm of the target for reachable targets; airborne count, hanging legs
  included, never above the gait limit; zero planted foot drift over a 10 s straight walk (scenario); a following
  leg whose hip has not passed an edge rejects a foothold 0.61 x reach above its foot; every build climbs a ledge of
  0.89 x reach and descends it again, and is blocked at 0.91 x reach with its front feet pawing and no foot planted
  above 0.9 x reach; the centre-of-mass margin stays >= 0.1 x mean reach whenever a leg hangs; no leg hangs and no
  leg reaches up on the 30 deg bumps.

### 8.3 Weapons - socketed parts that aim themselves
Fantasy: I point, and every gun I bolted on swings to it as fast as its weight allows, as far as its mount lets it.
Loop: put the dot on a target -> the reticles slide onto it (light guns at once, heavy guns lagging; gray where a
mount cannot reach) -> fire, and turn or strafe the body to dodge and to bring a lagging or gray gun on.
- **State:** per weapon: its yaw and pitch in the chassis frame, cooldown, live or gray; heat (M1).
- **Rules (aim model, Klas after the M0 build, 2026-10-10: each weapon follows the mouse within its own arc):**
  - *Aim point P* (unchanged): the camera's centre ray hits the world or an enemy (layers 1 and 3, never the
    player), up to 120 m. With no hit, P is the point at 120 m. P is where the mouse aims, and the camera dot marks
    it (12). Every weapon aims at the same P.
  - *Aim line:* each weapon aims from its pivot (its socket point) straight at P, and its muzzle sits on that line.
    So a settled weapon inside its arc hits P exactly, wherever the camera is. There is no convergence point and no
    range or height clamp.
  - *Mount arcs* belong to the socket face the weapon sits on, not to the weapon type, and are measured in the
    chassis frame, so they tilt with the body. Yaw 0 is the face's outward direction (for top and bottom: the
    heading). Pitch 0 is the chassis plane, positive up. A later weapon may narrow its face's arc, never widen it.

    | Mount (socket face) | Yaw arc | Pitch arc | In M0 |
    |---|---|---|---|
    | Top (roof) | 360 deg, unlimited | -20 to +75 deg | yes: top_0 (front left), top_1 (front right), top_2 (rear centre) |
    | Front, back, left, right | -90 to +90 deg around the face's outward direction | -90 to +90 deg | no: M1 block chassis (8.1); Klas's example, re-checked against the legs then |
    | Bottom | 360 deg | -75 to +20 deg (the top, mirrored) | no: M1 |

  - *Traverse rate:* rate = clamp(7200 / m, 45, 720) deg/s, where m is the weapon part's own mass in kg. The same
    rate applies in yaw and in pitch, and each axis is rate-limited on its own with no acceleration ramp, so a swing
    takes angle / rate, to the tick. 10 kg or lighter: 720 deg/s (90 deg in 0.125 s, 7.5 ticks: almost instant).
    40 kg: 180 deg/s (0.50 s). 80 kg: 90 deg/s (1.0 s). 160 kg or heavier: 45 deg/s (2.0 s: visibly slow). The
    floor of 45 deg/s is 1.5x the fastest drone's angular rate (6 m/s at 12 m = 29 deg/s), so every gun can track
    an orbiting drone (risk 8). 7200 is the one tuning constant.
  - *The body carries the guns:* traverse turns a weapon relative to the chassis. Turning the body toward P adds the
    turn rate to the swing, and turning away subtracts it. A weapon whose rate is at least the body's turn rate holds
    a still P while the body turns; the pulse cannon (180) outturns every M0 build (at most 134 deg/s, 8.1).
  - *Path:* a 360 deg mount swings the shortest way round. A limited mount swings inside its arc only, never through
    its dead zone.
  - *Fire gate:* each tick a weapon finds the yaw and pitch that put its line on P.
    - *Live:* that pose lies inside its arc (with 0.5 deg of tolerance, so a reticle at the limit does not flicker).
      The weapon turns toward P, and while `fire` is held it fires on its own cooldown along its current line, even
      mid-swing. Its reticle shows that line, so a heavy gun that is still swinging sprays where its reticle sweeps.
    - *Gray:* that pose lies outside the arc. The weapon turns to the point of its arc nearest P and stops there,
      and it does not fire. It goes live again on the tick P comes back inside.
    - A P within 1.5 m of a weapon's pivot leaves that weapon holding its pose, gray.
  - *M0 pulse cannon:* 40 kg (8.1 catalog), on any of the 3 top sockets, roof arc (yaw 360, pitch -20 to +75),
    traverse 180 deg/s in yaw and in pitch; 4 shots/s, 15 dmg, 60 m/s, spread 1.0 deg x leg spread factor (5).
    On flat ground with a level body, -20 reaches the ground about 2.9 m out on the Scout (Crawler about 2.2 m,
    Strider about 3.9 m; pivot about 0.45 m above the chassis underside). At the default camera pitch 20 the dot
    lands about 6 m ahead, inside the arc for every reference build, so only a dot near the walker's own feet turns
    a roof gun gray.
  - *Projectiles* fly along the weapon's aim line at their own speed and do not inherit the walker's velocity, so a
    strafing or turning walker hits where the reticle shows, with no lead of its own. They collide with layers 1 and
    3 only and pass through their own walker, so a rear gun can fire over the front ones.
  - *Several weapons:* LMB fires every live weapon. Each keeps its own rate (pulse cannon 4 shots/s). Phases are
    fixed by mount order (top_0, top_1, top_2): weapon k of n mounted fires k / (n x rate) s after the first, so two
    cannons fire every 0.125 s, a steady rhythm rather than a double bang. A gray weapon skips its slots, and the
    others keep their phases (no re-phasing).
- **Edge cases:** arcs are chassis-relative (this replaces the world-relative -10..+45 deg limits). A Crawler tilted
  39 deg nose-up on the talus reaches no lower than world +19 deg straight ahead (up the slope, where the ground is
  anyway) and down to world -59 deg straight behind. A camera looking straight down puts P under the walker: every
  roof gun goes gray, which reads "you cannot shoot your own feet".
- **Tests:**
  - `traverse_rate`: 5 and 10 kg -> 720, 40 kg -> 180, 80 kg -> 90, 160 and 300 kg -> 45 deg/s (within 0.01); it
    never rises with mass.
  - Swing: a pulse cannon on a still Scout, with P stepped 90 deg in yaw, is within 1 deg of P after 30 +/- 1 ticks
    and never turns faster than 3.0 deg per tick (+0.5 %); a 30 deg pitch step takes 10 +/- 1 ticks.
  - Body assist: from the same start with A/D held toward P, within 1 deg of P in <= 0.35 s for every reference
    build (Scout about 0.32 s). Hold: with P still and the Strider turning at 134 deg/s for 1.0 s, a settled cannon
    stays within 1 deg of P.
  - Arc gate: with P at -19.0 deg from the pivot the cannon is live and fires 8 +/- 1 shots in 2.0 s of `fire`; at
    -20.4 deg it is still live; at -20.6 deg it is gray, fires 0 shots in 2.0 s, and its barrel sits at
    -20.0 +/- 0.1 deg on P's bearing.
  - Shot lands at P: with spread 0 and a settled cannon, P inside the arc at 5, 15 and 60 m and the camera at yaw
    0, 90 and 180 deg from the heading, the projectile passes within 0.2 deg of P seen from the pivot.
  - Chassis frame: on a body tilted 39 deg nose-up, the lowest pitch straight ahead is world +19 +/- 0.5 deg.
  - Default view: on flat ground at camera pitch 20, every reference build's cannons are live.
  - The drawn barrel matches the aim pose within 0.1 deg on every tick.
  - Fire rate cap; damage applied once per projectile; projectiles never hit layer 2.
  - Two cannons fire 0.125 s apart; with top_1 gray, top_0 alone fires every 0.25 s on its own phase.

### 8.4 Enemies - drones (M0); enemy walkers (M1)
- **Drone states:** idle-hover, patrol, alert (sees the player within 35 m, line of sight), strafe (orbits at
  12-18 m, at <= 6 m/s, risk 8), wind-up (0.6 s, glows, holds still), fire, recover (0.3 s, holds still), dead
  (falls, drops 3-8 scrap).
- **Rules:** max 4 active drones. Drones leash back to their spawn when the player is more than 60 m away, and
  respawn on bank.
- **The telegraph is the opening.** A drone stops to shoot: at wind-up start it brakes from orbit speed to 0
  within 0.1 s and holds its position (hover bob <= 0.1 m) through the 0.6 s wind-up, the shot and a 0.3 s
  recovery, then regains orbit speed over 0.3 s. That makes 0.9 s still in every 1.5 s cycle. Pulses
  (60 m/s, 0.25 s to 15 m) fired at a holding drone under the dot, with the weapon's reticle on it, hit with no
  lead. A drone that is orbiting moves 1.5 m during that flight, more than its 0.6 m radius, so straight shots at it
  miss: the player fires on the glow. Each player choice has a cost:
  - *Stand and trade:* put the dot on the drone, fire from the start of its wind-up, and the third pulse lands about
    0.75 s in, after the drone's own bolt has left, so a standing walker takes the hit.
  - *Strafe and shoot:* dodge with Q/E while the mouse keeps the dot on the drone (a 3.4 m/s strafe drifts the
    bearing about 13 deg/s at 15 m, well inside the cannon's 180 deg/s traverse, against a drone 2.3 deg wide).
  - *Strafe only:* take no hit and deal no damage.
- **Encounters stagger the wind-ups:** drones in one encounter start their wind-ups >= 0.4 s apart, so their holds
  rarely overlap and the guns swing between them. The swing time (gun traverse plus body turn, 8.3) decides a
  fight (Pillar 1, risk 8).
- **Bolt:** fired at the walker's chassis position at the moment of the shot, with no lead.
- **Combat check:** a strafing Scout takes <= 40 % of the damage that an idle Scout takes in `drone_fight`, so
  speed matters in combat (Pillar 1). A strafing Scout clears its 0.53 m chassis half-width in about 0.25 s
  (accel included), well inside the bolt's 0.6 s flight at 15 m. The hold does not change this, because the bolt
  is aimed at the walker, not the other way round. The 3-hit kill (45 HP, 15 dmg) is unchanged.
- **Tests:** state transitions as pure functions; telegraph is >= 0.6 s before every shot; the drone's speed is 0
  (<= 0.05 m/s) from 0.1 s after wind-up start until the end of recovery; holds in one encounter start >= 0.4 s
  apart; the bolt aims at the chassis position at fire time; leash.

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
| Chassis | 1 (medium, the 8-block build as one fixed part) | 2 (+light); to be restated as blocks (8.1) | 3 (+heavy); to be restated as blocks (8.1) |
| Legs | 3 (short, medium, long) | 5 (+wide-foot, climber) | 7 |
| Top parts | 2 (pulse cannon, armor plate) | 5 (+shield, scanner, cargo pod) | 9 |
| Enemies | 1 drone | + walker sentinel | + drone carrier |
| Map | The valley (9.1): 400 m long, floor about 200 m wide, rings 0-2, a ledge pocket (climb >= 1.2 m: long legs, e.g. the Strider) and a talus pocket (45 deg grip: short legs, e.g. the Crawler) | 2 zones + terrain gates | 3 zones |
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
| Cliff walls | >= 30 m tall and >= 60 deg along the whole floor edge, so no build can leave (max climb 1.44 m, max slope grip 45 deg). These are the map bounds; there are no invisible walls |
| Floor | Gentle 0-10 deg overall. Bumpy patches up to 30 deg (the gait show). Boulders 0.3-1.0 m high (0.5-0.8 m in the M0 valley) as climb content: the Crawler (climb 0.54 m) hauls over only the smallest and goes around the rest, the Scout (0.90 m) and the Strider (1.44 m) haul over all of them; a boulder within stride step-up is stepped onto in stride |
| Workshop | On a bench at the north end, 20-40 m from the head wall. Ring distances are measured from it |
| Dry wash | A winding riverbed from the workshop down to the far end. It is the main path and the route the test scenarios walk |
| Ledge pocket | West wall, ring 2, 160-240 m from the workshop. A 1.2 m ledge leads up to it; one 60-scrap node. The Scout (climb 0.90 m) can't climb it, and its front legs paw at the face; the Strider (1.44 m) reaches and hauls up |
| Talus pocket | East wall, ring 2, 150-220 m from the workshop. A 40 deg talus slope leads up to it; one 60-scrap node. Only a build with 45 deg grip (in M0, all short legs, as on the Crawler) can climb it; the Scout (35 deg) and Strider (30 deg) can't |
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
   the near row is clear and the far row may hide behind the chassis. Its plant moment is readable: a dust puff and
   a contact decal that fades in 2 s. These two are readability, not polish, and cannot be cut (Pillar 2). The dust
   (Klas, 2026-10-10: it read as "white blobs"; it must read as dust and scale with weight per leg):
   - *Size from weight per leg:* w = build `mass` / leg count (8.1: chassis plus every part, legs included). Puff
     width W = clamp(1.0 m x w / 50 kg, 0.5, 2.0) m across; height 0.5 x W. Scout 315 / 6 = 52.5 kg -> 1.05 m;
     Strider 285 / 6 = 47.5 kg -> 0.95 m; Crawler 535 / 8 = 66.9 kg -> 1.34 m (1.41x the Strider). The floor is at
     25 kg per leg and the cap at 100 kg per leg (an M0 build tops out about 110 kg per leg: 4 short legs at full
     load). Linear, so M0's narrow spread (47-67 kg) still shows: a heavy-footed build kicks up more dust than a
     long-legged one. (Doubled 2026-10-10 after T23's first shots: at 0.5 m per 50 kg the Crawler's puff was only
     about 10 px wider than the Strider's at the play camera.)
   - *Soft, not round:* each puff is 5 soft sprites at seeded offsets within 0.3 x W of the pad, each 0.5 x W
     across, with a radial alpha falloff: at 0.9 of a sprite's radius the alpha is <= 0.1 x its centre's, and 0 at
     the rim. No single disc, no hard edge.
   - *Ground-tinted, never white:* colour `#BFAF99` (was `#D9C7AE`; the ground `#CAB294` family: hue 33 +/- 5 deg, saturation
     0.15-0.30), lit by the scene as the ground is (an up-facing normal, not a camera-facing one), so it darkens in
     shadow with the ground. At its peak a puff lifts the local floor's grayscale luma by 0.03-0.12, measured on the
     valley floor in sun and in shadow (the striped test flats are lighter than the valley and are not the measure);
     no puff pixel has saturation below 0.08 with luma above 0.75 (never white).
   - *Low opacity:* peak alpha 0.45, reached within 0.08 s of the plant (that is the plant read), <= 0.25 by 0.4 s,
     0 at the end of life.
   - *Drift and settle:* life 0.8 s +/- 1 tick (was 0.2 s: a 12-frame flash reads as a blob). The sprites burst
     outward at 0.8 m/s, slowing to 0 by 0.4 s; the puff rises to its full height by 0.3 s, then sinks by 30 % while
     it fades. It stays in the world and does not follow the walker.
   - *Cost:* <= 2 draw calls per walker for all its puffs; the pool covers the Crawler at top speed (about 29
     plants/s x 0.8 s = 23 live puffs) with no allocation after `_ready`.
   - *Tests:* W for the three fixtures within 0.005 m, plus the floor and the cap; the alpha curve at 0.08, 0.4 and
     0.8 s; the sprite falloff; shots `foot_fx_valley__dust_weight` and `__dust_weight_crawler` (the Strider and
     the Crawler mid-walk on the valley floor at the play camera, 8 m and pitch 20) and `__width_strider` /
     `__width_crawler` (one puff each), checked with the pixels tool for the luma lift, no white pixel and a
     measured Crawler / Strider puff width ratio >= 1.3 (the width gap is reported: 14 px at 720p in T23); and a
     plant in the chassis's shadow with a lift <= 0.12. Playtest question for Klas: "Does the dust read as dust, and does a heavier foot kick up
     more?"
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
  - **Deltas show better or worse, not just up or down.** A better change has a filled accent mark; a worse change
    has a hollow neutral-grey mark (>= 0.25 luma apart); the sign keeps the direction. Higher is better for speed,
    turn, step-up, climb, slope, HP and DPS; lower is better for spread and load.
  - **A blocked exit answers:** Tab or a click on the disabled exit pulses the reason text for 0.3 s, and the Load row
    shows a "!" while load is above 1.0.
- **Field HUD:**
  - **Aim: one camera dot, and one reticle per weapon** (Klas, 2026-10-10). The dot is where the mouse aims. Each
    reticle is where that weapon's shot goes now. A reticle trailing the dot is a weapon still swinging (heavy guns
    trail further); a gray one is a weapon that cannot reach the dot from its mount. Numbers are at 1080p and scale
    with resolution:
    - *Camera dot:* 6 px, player body `#E6E1D6` with a 1 px ink `#14161A` outline, at the screen centre. It marks P
      (8.3), never the walker's heading. Always drawn, on top of the reticles.
    - *Weapon reticle, one per mounted weapon (0-3 in M0):* a ring 28 px across with a 3 px stroke, in player accent
      `#FF8A3D` with a 2 px ink outline, so it reads in grayscale against sky and ground. It sits at the screen
      projection of the first hit along that weapon's current barrel line (layers 1 and 3, up to 120 m; with no
      hit, the point at 120 m), from the same tick's weapon pose: it lags the dot only by the weapon's own traverse.
      A settled live weapon's ring is centred on the dot, so the dot inside the ring means on target, and the rings of
      weapons that agree overlap as one. Over an enemy hurtbox the stroke goes from 3 to 5 px. It never takes the
      threat hue (rule 2). The merge pip of the heading-aim HUD goes.
    - *Gray, at the arc limit:* while P lies outside a weapon's arc, its ring stops at the furthest point the barrel
      reaches (the first hit along the clamped line). It turns neutral gray `#646464` (saturation 0, >= 0.2 luma
      below the live ring in grayscale), and it is drawn dashed (8 segments, about 50 % duty), so it reads by shape
      as well as by tone; the ink outline stays. It shows whenever the weapon is gray, and that weapon does not
      fire (8.3). It goes back to the solid accent ring on the tick P comes back inside the arc.
    - *Hit confirmation:* when a player projectile hits a hurtbox, the stroke of the ring of the weapon that fired it
      flashes player body `#E6E1D6` for 0.06 s, so a hit reads even when the ring covers a distant target.
    - *Off screen or behind the camera:* a 32 px chevron per off-screen reticle, at the screen edge, 24 px inset,
      points to where that weapon aims, in its ring's colour (accent or gray). It shows mostly mid-swing after a big
      flick. No other HUD element sits within 40 px of a chevron.
    - All aim marks use `mouse_filter = IGNORE`.
    - *Tests:* one ring per mounted weapon; each ring within 0.5 deg of where its weapon's next projectile first
      hits; on flat ground at camera pitch 20 every ring is live; with the dot on the ground under the walker every
      roof ring is gray and dashed and fires 0 shots; live and gray rings >= 0.2 luma apart in grayscale. Shots:
      `drone_fight__reticle_swing` (rings trailing the dot mid-flick) and `drone_fight__reticle_gray` (the dot at
      the walker's feet, gray dashed rings at the limit).
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
| Simulation caps | player walker <= 8 legs in M0 (the 8.1 build principle goes past 8; the cap after M0 is open); <= 4 active drones; <= 40 live projectiles |
| Physics tick | 60 Hz. Gait and IK run in `_physics_process`, visuals interpolated |
| Platform | Windows PC, KB+M |
| 3D collision layers | 1 world, 2 player, 3 enemies, 4 player_projectiles, 5 enemy_projectiles, 6 pickups, 7 triggers. Foot raycasts mask world only |

## 14. Milestones
- **M0 Playable loop (<= 2 weeks of agent work):** walk, build and fight on one map. Acceptance criteria are in
  `design/plan.md`.
  - Criterion 5 (combat and aim), rewritten 2026-10-10 for per-weapon aim; the plan.md M0 row carries the same text:
    the drone telegraphs >= 0.6 s before every shot, dies in 3 hits and holds still for 0.9 s of each 1.5 s cycle; a
    strafing Scout takes <= 40 % of the damage an idle Scout takes. Each mounted weapon has its own reticle, within
    0.5 deg of where its shot goes. With P inside its arc and the weapon settled, a shot at spread 0 passes within
    0.2 deg of P. With P outside its arc (the dot under the walker) the weapon fires 0 shots over 2.0 s of `fire`
    and its reticle is gray and dashed at the arc limit. The pulse cannon (40 kg) swings 90 deg in 0.50 s +/- 1
    tick, as the traverse formula gives for its mass. Every M0 reference build brings a reticle onto a drone 90 deg
    off in 0.50 s with the body still and in <= 0.35 s with A/D toward it. A no-lead tracker that keeps the dot on
    the drone hits >= 80 % of shots fired during holds and kills within two holds, standing and strafing, with the
    Scout and with the Crawler [5, 8.3, 8.4, 12, 16].
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
   turns toward camera yaw, with Q/E strafe kept. Klas decides at the T03/T04 gate. Closed 2026-10-09: tank kept;
   weapons follow the body's heading and the camera's pitch (sections 6, 8.3 and 12; Decisions log). After the M0
   build (2026-10-10) tank steering stays, and the weapons aim at the mouse instead (8.3; risk 8).
4. **Toon outline cost** on a 400 m terrain. The outline is built in M1; measure its draw calls there.
   M0 ships the toon ramp without it.
5. **Kinematic body vs Jolt projectiles and drones.** Collision layers are fixed in T00 (section 13).
6. **The valley feels like a corridor.** The floor stays at least 150 m wide, the wash winds, and there are side
   nodes and two pockets off the path. Playtest-critic checks this at the M0 review.
7. **Climb pose feasibility** (Pillars 1 and 2). Reach and haul (8.2) at 0.9 x reach, up and down, may not fit the
   real chassis, hips and bones within pitch <= min(grip - 5, 25) deg, knee bend >= 0.05 x reach and a
   centre-of-mass margin >= 0.1 x mean reach. Spike: a side-view pose search per build (Scout, Strider, Crawler) with
   the real chassis box, hip positions and bones, before any controller work. Fallback: climb 0.8 x reach and the
   ledge pocket at 1.07 m. Checked 2026-10-09: passes, with the descent drop raised to 0.32 x reach (Decisions log).
8. **The heading and the build still matter when every gun aims itself** (Pillar 1; rewritten 2026-10-10 for
   per-weapon aim). Turn rate no longer gates every shot. With a 360 deg roof mount and a 180 deg/s cannon a player
   could fight without ever turning, and then turn rate and socket choice stop showing in fights, so every build
   fights alike. The answer, in order of weight:
   - *The body carries the guns.* Traverse is chassis-relative (8.3), so A/D toward a target adds the turn rate to
     the swing: 90 deg takes 0.50 s on the gun alone and <= 0.35 s with A/D (Scout about 0.32 s). Turning into a
     fight is faster, and a faster-turning build swings faster.
   - *Heavy guns need the body.* A gun slower than its build's turn rate drifts off a still target while the body
     turns, and its slow swing rewards turning the body instead. M0's cannon (180 deg/s) outturns every M0 build;
     from M1 a 120 kg gun (60 deg/s) on a 120 deg/s walker makes gun mass against turn rate a pairing you feel.
   - *The mount sets the arc.* Only top and bottom mounts turn 360 deg; front, back and side mounts (M1) reach
     +/- 90 deg around their face, so a front gun needs the heading on the target. Roof guns cannot reach low and
     near (-20 deg), and that dead zone grows with leg length (nearest ground about 2.2 m on the Crawler, 3.9 m on
     the Strider).
   - *Gun mass still loads the walker* (8.1): a second cannon costs speed and turn rate.
   Bound: the traverse floor (45 deg/s) is >= 1.5x the fastest drone's angular rate (29 deg/s at 12 m), so no gun
   is too slow to track; a drone's 0.9 s hold per 1.5 s cycle (8.4) stays the opening, so hits need aim, not leading
   skill. Spike (T22 `drone_fight`), against a drone orbiting at 15 m, 6 m/s, 4 m up, cycling as in 8.4:
   - *Swing:* for every M0 reference build, a reticle reaches a drone 90 deg off in yaw that has started its wind-up
     in 0.50 s +/- 1 tick with the body still, and in <= 0.35 s with A/D toward it: turning cuts the swing by
     >= 30 %.
   - *Tracker:* a scripted tracker puts the dot on the drone's current position every tick (never ahead of it),
     holds `fire` and does not turn the body. With the Scout and with the Crawler, standing and strafing (Q/E), it
     hits >= 80 % of shots fired between hold start + 0.15 s and hold end - 0.25 s (so they land while the drone
     holds) and kills a drone within its first two holds (<= 3.0 s from the first hold start).
   - *Reported, not asserted:* the hit rate on shots fired while the drone orbits (the opening, not luck, carries
     the fight); against two drones 90 deg apart with wind-ups >= 0.4 s apart, the time to kill both and the damage
     taken, with and without A/D toward the next drone; in Klas's playtest, the share of fight time with A/D held.
   - *Playtest question for Klas:* "Did you turn the body in fights, and did it help?"
   Fallback if the heading stops mattering in play: narrow the roof yaw to +/- 150 deg (a 60 deg dead zone behind,
   the 2026-10-08 turret arc), or lower the traverse constant 7200 -> 4800 (pulse cannon 120 deg/s, 90 deg in
   0.75 s), so turning the body pays more.
9. **Aiming up at close, high drones.** At camera pitch -10 the centre ray rises only 10 deg from a camera 8 m back,
   so a drone 12 m out and higher than about 4.2 m (drones hover 3-6 m) cannot be put under the dot. Mitigation:
   the aim-up range down to -20 deg (section 6). The spring arm shortens to about 5-6 m against flat ground, and
   the ray then reaches about 6.3 m at 12 m for every build. Spike (T06): a shot at pitch -20 with a drone at 12 m
   and 6 m hover; the drone sits under the dot and the walker's chassis is in frame. Fallback: raise the camera's
   target offset while `aim` is held, or cap drone hover at 4 m.

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
| 2026-10-09 | Walkers reach and haul (8.2): stride step-up stays 0.6 x reach; a new `climb` stat of 0.9 x mean reach (Scout 0.90, Strider 1.44, Crawler 0.54 m, contrast 0.625) lets the front legs plant up to 0.4 x reach above their hips. The body then pitches up to min(grip - 5, 25) deg and hauls at <= 0.4 x top speed, and the other legs follow as their hips pass the edge; step-down mirrors it. A leg with no foothold hangs and paws at too-tall faces and too-deep drops; it counts as airborne, and the centre of mass stays inside the planted feet by >= 0.1 x mean reach. Ledge pocket 0.8 -> 1.2 m, boulders stay 0.5-0.8 m, M1 gate ledge 1.5 -> 2.0 m. Defaults until measured: mixed builds take climb from the mean reach (T16 measures Scout + short pair and Scout + long pair; the lead switches to the shortest leg if a measured climb falls more than 10 % below its stat); haul time 1.0-2.0 s on a ledge 0.75 x climb tall, which Klas tunes at the next playtest | Klas, from the game-designer's proposal (T03 gate feedback): "the front legs should have been able to reach the ledges and climb. Not every leg has to touch ground. Make them more agile." Raising the pocket by the same 1.5x as climb keeps every M0 build's pocket access as before (Pillars 1 and 3) | Taller step only (step-up 0.8 x reach, nothing reaches or hangs); a free per-tick pose solver (frame cost on a controller already at 40-75 ms ticks, climb height not repeatable so the pocket gates blur; kept for the M1 climber leg); pocket kept at 0.8 m (the Scout would reach it, so the session goal no longer needs a part); legs hang only during a haul (the build's limit would not show); boulders scaled 1.5x so the Crawler still goes around |
| 2026-10-09 | Climb pose check (risk 7) passed with one change: on a descent the body lowers up to 0.32 x reach (chassis centre, pitch on top) instead of 0.25; feet on a top land clear of the corner; the climb height is a hard foothold check | Lead, from the code-reviewer's side-view pose search: every build climbs 0.9 x reach (Crawler tightest, +3 cm), but at 0.25 the Strider descends only 0.845 x reach (1.35 of 1.44 m), so it could be trapped on a shelf, which breaks "walkers descend what they climb" (Klas). At 0.32 all three descend 0.9 x reach (+2-5 cm). Geometry alone would let the Scout plant on the 1.2 m pocket ledge, so the climb limit must be enforced | Climb 0.84 x reach (all builds lose climb); pitch cap 31 deg (above the Strider's grip) |
| 2026-10-09 | Descent floor refined: only sustained slopes (>= 1.5 m of ground steeper than 25 deg, more than a step-up tall) trigger it, it also looks ahead for a drop, it eases in over about 0.45 s and out over about 0.8 s, it lets go while aiming, and it stays slope minus 5 | Lead, from the T15 reviews (code-reviewer and playtest-critic): the steepest-single-sample measure lifted the camera to 45-50 deg at every boulder and ledge, where nothing can hide the walker; the lift started 0.4 s after the edge and snapped in 0.23 s. A 12 m zoom needs slope minus 5 (slope minus 10 hides the feet). Aiming is deliberate, as with recentring. Klas can overrule the aim rule | Steepest single sample; slope minus 10; floor while aiming |
| 2026-10-09 | The descent floor triggers only when the steep slope stands in the line of sight from the camera to the walker's feet (replacing a fixed 1.5 m start limit), uses the steepest full sample segment, and eases its target too | Lead, from the T15 round-2 reviews: averaging over a partial segment made the floor pop 2-3 deg every 0.75 m down the face; a fixed start limit missed a Crawler waiting 1.5-2.6 m from the talus foot at pitch 17-20 with the camera over the face | Fixed 1.5 m start limit; mean slope |
| 2026-10-09 | The descent floor stays at slope minus 5 (the walker stays visible; on the 40 deg talus the pads stack per side) | Klas, from the T15 mid-face shots at 35, 45 and 50 deg: slope plus 10 (50 deg) reads 2-3 pads per side instead of 1 but doubles the camera move and takes the horizon and drones out of frame (Pillar 3); the player can still pitch up by hand | Slope plus 10 |
| 2026-10-09 | Gate (risk 3): tank steering stays, Q/E strafe kept. Weapons point where the walker faces horizontally and follow the camera's pitch vertically; no free turret yaw. Section 6 and 8.3 to be rewritten for this aim model | Klas at the T03/T04 gate, after playtesting the Windows build: "Keep tank steering. Any weapon is pointed where the walker is directed horizontally and follows the camera vertically. Keep strafing". Turning the body is now how you aim sideways, so the turn rate is felt in every fight (Pillar 1) | Camera-yaw fallback (body turns to camera yaw); hybrid (camera-yaw while aiming); free turret +/- 150 deg |
| 2026-10-09 | After play: the descent camera floor stays as built, sliding along an unclimbable face keeps full along-face speed, the start pitch stays 20 deg | Klas at the gate, from the playtest build | Softer or no descent floor; slide damped to 70 %; start pitch 15 deg |
| 2026-10-09 | Aim model details, building on Klas's gate row: the weapons aim at a convergence point Q on the body's heading, at the horizontal range (4-120 m) and height of the camera centre ray's hit P. Elevation is -10..+45 deg world-relative, slewing at 360 deg/s; yaw is locked to the heading. The weapons always fire (no arc lockout), and range and height hold when the camera looks more than 90 deg off the heading. Several weapons fire in even phases (two cannons every 0.125 s). HUD: a 6 px camera dot plus a 28 px world-space weapon reticle that merges into an on-target pip within 12 px, is dashed at an elevation limit, and becomes an edge chevron when off screen. RMB keeps FOV 50, the x 0.6 turn and the paused recentring, and does not swing the camera. Camera pitch -10 -> -20 (aim-up range, feet may leave the frame below -10). Risk 3 closed; new risks 8 (turn-rate tracking, drone orbit <= 6 m/s) and 9 (aiming up at close drones) | Game-designer, from Klas's gate decision ("Keep tank steering. Any weapon is pointed where the walker is directed horizontally and follows the camera vertically. Keep strafing"). Aiming at the camera ray's range and height means a target on the heading is hit exactly where the player looks. The free camera keeps the legs in view from any side (Pillar 2) and keeps Klas's T04 rule that aiming never swings the view off a drone. The dot-to-reticle gap shows the turn the build still has to make, so the turn rate is seen as well as felt (Pillar 1). World-relative limits let a Crawler tilted 39 deg on the talus still shoot level (T06 note). Pitch -20 lets the dot reach drones at 12 m and 6 m hover | Weapon elevation = the camera's own look angle (at the default 20 deg pitch the guns would fire into the ground 10 m ahead); RMB swings the camera behind the heading so the screen centre is the weapon line (breaks the T04 aim rule and hides the legs side-on in fights); one centre crosshair only (lies whenever the camera is off the heading); body-relative limits; firing all weapons at once; keep pitch -10 and cap drone hover at 4 m |
| 2026-10-09 | Klas confirmed the aim model details: the camera dot plus world-space weapon reticle, the aim-up range down to -20 deg, the x 0.6 turn rate while `aim` is held, and the guns holding their last range and height when the camera looks more than 90 deg off the heading | Klas, choosing the game-designer's recommendation on each: the camera stays free in fights so the legs read from any side (Pillar 2), close high drones can be aimed at, fine tracking when zoomed, no guns nodding at nothing | RMB swings the camera behind the body with one centre crosshair; keep -10 deg and cap drone hover at 4 m; full turn rate while aiming; guns keep following the camera when looking behind |
| 2026-10-09 | Drones hold still to shoot: they brake to 0 within 0.1 s at wind-up start and hold for the 0.6 s wind-up, the shot and a 0.3 s recovery, so they are still for 0.9 s of every 1.5 s, and the telegraph is the opening. Wind-ups in one encounter start >= 0.4 s apart. The drone bolt aims at the walker's position with no lead, and player projectiles do not inherit the walker's velocity. Risk 8's tracker aims at the drone's current position and must land >= 80 % of shots during holds and kill within two holds | Game-designer, from the lead's T07 check: at 60 m/s a pulse takes 0.25 s to reach 15 m, while a drone orbiting at 6 m/s moves 1.5 m, more than its 0.6 m radius, so straight aim always missed and the risk 8 spike tested leading skill, not turn rate. Holding on the glow makes the telegraph both the threat and the opening: stand and trade a hit, strafe and shoot (A/D and Q/E together), or only dodge. Staggered holds make the walker swing between drones, so turn rate decides fights (Pillar 1). The strafing-Scout bar and the 3-hit kill hold unchanged | Lead marker on the reticle (a moving pip is hard to track with digital A/D at a fixed turn rate, and it adds HUD); projectile magnetism or a 1.5 m hitbox (hits stop depending on aim, hiding turn rate); faster pulses at 150 m/s (still 0.6 m of drift, so half miss, and the pulse no longer reads in flight); a slower orbit of 2.4 m/s or less (drones read as parked and the fight goes flat) |
| 2026-10-09 | A hit during a drone's wind-up does not cancel its shot: a drone always fires | Klas, on the game-designer's recommendation: standing and trading still costs a hit, so dodging with Q/E stays the skill and the strafing bar (<= 40 % of the idle damage) keeps its meaning; revisit if fights feel like trading | A hit during the wind-up interrupts the shot |
| 2026-10-09 | A front leg pawing at a face it cannot climb swings its pad up the face each 0.6 s cycle (>= 0.6 x reach above the floor, at most hip + 0.4 x reach, >= 0.05 m off the face); between paws it idles at the 0.25 x reach lift height | Lead, from the T16 playtest critique: at 0.25 x reach the pad sits 15-30 px up a 1.2 m face and reads as one foot twitching, not as trying to get up, which is the moment Klas asked for and the one that shows the Scout why the ledge pocket is shut (Pillar 1). Refines Klas's paw-and-hang decision; Klas tunes it at the next playtest | Paw at the lift height only; a full reach-up attempt every cycle |
| 2026-10-09 | Aim marks: the dashed at-limit ring shows only when the dot is on an enemy or `fire` is held or was released < 0.5 s ago; the ring flashes player body white for 0.06 s on a hit | Lead, from the T06 playtest critique: at the default pitch 20 the dot lands about 6 m ahead and the guns reach the ground only at about 12 m, so the ring was dashed nearly all the time while walking and the state taught nothing; at drone range (12-15 m) the 28 px ring covers most of the target, hiding the target's own hit flash. Klas can tune both at the playtest | Lower the elevation limit to about -25 deg (barrels nod at the feet while walking, changes 8.3); always-on dashed ring; a reduced-opacity limited ring |
| 2026-10-09 | Workshop stat deltas mark better (filled accent) or worse (hollow grey), with the sign kept for direction; a blocked exit pulses its reason and flags the Load row | Lead, from the T09 playtest critique: with ▲/▼ alone the long-leg pair read ▲▼▲▲▼▲▼ while better/worse was better, worse, better, better, worse, worse, better (spread up is worse, load down is better), so a glance at the trade-off misled; the trade-off read is the point of the workshop (Pillar 1). Klas can tune it at the playtest | Colour-only good/bad (fails grayscale and rule 2); arrows only |
| 2026-10-09 | `climb` = 0.9 x the shortest mounted leg's reach, not the mean reach | Lead, applying the switch rule written into 8.1: T16 measured the Scout + short pair at 0.65 m against a mean-reach stat of 0.78 m (17 % short), and it climbed a block it could not step back down from, which breaks "a walker never climbs what it cannot descend" (8.2). With the shortest leg its climb is 0.54 m and the hard climb check keeps it off taller blocks. The Scout + long pair (measured 1.05 m) drops to 0.90 m: the stat stays honest and conservative. The reference builds (one leg type each) are unchanged | Keep the mean reach and let the 1.5 s margin-break fallback free the trapped build; allow only one front leg to hang at a time |
| 2026-10-09 | Face rule: a steep face the chassis cannot clear in a stride (its underside height, body height x mean reach less 3 cm: Crawler 0.33, Scout 0.57, Strider 0.93 m) is reached up onto and hauled over even when it is within the stride step-up; each leg's stride step-up is 0.6 x its own reach; a reaching foothold lies at most 0.4 x the leg's reach above its hip | Lead, from the T16 round-1 review and critique (implemented in round 2): builds held on the rise cap below their step-up (Strider 0.90 m with no reach-up, Crawler 0.30 m), because step-up says what a foot can step onto, not what a body can step over | One climb rule from the step-up up |
| 2026-10-09 | The climb tolerance is 0.66 % of the mean reach (1 cm on the Strider, 0.4 cm on the Crawler), not a flat 3 cm, and a step-down foothold lies 0.30 m (was 0.22) out from the face. The 1.5 m/s rise cap (5, Haul) applies to stride step-ups, reaches and hauls; walking up a slope inside the build's grip is exempt | Lead, from T16 round 2: a flat 3 cm let the Crawler climb a 0.55 m ledge it cannot step back down from (the descent lowers the body 0.32 x reach); the Crawler on the 40 deg talus rises about 0.06 m per tick at speed, which is walking, not hauling | Lower the body further for the descent; one rise cap for slopes too |
| 2026-10-09 | No fallback that breaks the support margin: a leg that cannot hang inside the 0.1 x mean reach margin waits while the body shifts, and the build must be able to descend every block it can climb | Lead, from the T16 round-2 review: a 1.5 s 'margin break' let the move go ahead below the floor, ratcheted the floor down after every break, and still left the Scout + short pair looping on top of a 0.65 m block | A timed margin break as an anti-trap net |
| 2026-10-09 | Drone details from T07: a drone killed during its wind-up still fires at the end of the 0.6 s wind-up (Klas's "a drone always fires" covers a killing hit); PATROL means drifting back home (entered by the leash or 3 s without sight, which also ends the provoked state); a drone hit inside its leash reacts without sight; it starts a wind-up only with line of sight, and its first shot comes >= 1.5 s after it notices the walker; the 4-drone cap counts engaged drones across the whole field; a dead drone drops its 3-8 scrap as loose 1-scrap pickups; the drone ring has an ink rim that never glows, so the wind-up reads in grayscale against the sky (rule 2) | Lead, from the T07 implementer's interpretations, code review and playtest critique (Klas: keep the drone work light). In grayscale the lit ring (0.50-0.60) matched the sky (0.61), so the telegraph read as the drone fading out | A killing hit cancels the shot (it let the Crawler kill 0.5 s into the wind-up and trade nothing); waiting for the M1 ink outline |
| 2026-10-09 | Risk 8's heading check (every reference build onto a drone 90 deg off in <= 1.0 s) is measured against a drone that has started its wind-up, because the player turns on the glow; against a drone orbiting away the Scout takes 1.02 s and the Crawler 1.13 s (reported). GDD 13's cap reads 40 live player projectiles plus 8 drone bolts | Lead, from T07: the GDD's own 0.93 s Crawler figure assumes a still target, and the tracker lands 100 % of hold shots, so a player does not feel 0.13 s; the projectile cap was written before drone bolts existed, and the measured cost (0.2 ms p99 for 4 drones and their bolts) leaves room | A longer hold (GDD 16 fallback); a 32 + 8 split of the 40 |
| 2026-10-09 | A walker climbs or steps down a ledge only when it meets the face within 45 deg of head-on; at a shallower angle it slides along the face, as at one it cannot climb | Klas, from T16 round 6: at 60 deg the walkers slid along the face and never climbed, at 30 deg they climb and descend | Climb at any angle with W into the face |
| 2026-10-09 | Build principle: no fixed walker types or classes. The player evolves the one starting walker to their will; every stat, gait and limit derives from the mounted parts, never from a build name. Scout, Strider and Crawler are test fixtures and example builds, not classes, and niches belong to the parts (long legs reach, short legs grip and carry). M0 keeps its 4, 6 or 8 symmetric legs and three leg lengths as a scope limit. The M1 upper limit of 8 legs is withdrawn; the cap past 12 and discrete versus grown leg length are open (8.1) | Klas, after the climbing playtest: "I want to make clear that there shall be no fixed type or class of Walkers. You evolve your starting Walker to your will. It may be two very long legs or 12 very short for example." Pillar 1 and the inventor fantasy (section 1): the machine is the player's own design | Named classes with variants (the inventor fantasy shrinks to a pick-list); a fixed range of 4-8 legs (rules out Klas's 12-leg example) |
| 2026-10-09 | A build needs at least 4 legs | Klas, 2026-10-09: "Since 2 legs poses a problem, make it a minimum 4." With 4 or more legs and one in the air, 3 feet stay planted, so the support rule (centre of mass inside the planted feet by >= 0.1 x mean reach, 8.2) and the climb with a hanging leg hold for every build | 2 or 3 legs (biped balance, a tripod gait) |
| 2026-10-09 | Block chassis: the chassis is built from blocks that can be expanded like Lego; each block has 6 sockets, one per direction; a leg mounts only on a block's left or right socket. Today's medium chassis is the 8-block build, kept in M0 as one fixed part (8 leg and 3 top sockets). The layout, block price, mass and HP, attachment and stacking, and the block and leg limits are open (8.1) | Klas, 2026-10-09: "My wish is that the chassis is built from blocks that can be expanded like Legos. The corresponding build for the current chassis would be 8 blocks. Each block has 6 sockets, one in each direction." and "Legs can only be placed on left or right side." The body grows with the walker, which serves the build principle and Pillar 1 | A fixed chassis with fixed sockets; a segmented spine of 2-socket segments; legs on any face |
| 2026-10-09 | Any socket takes another block or a module. Modules include weapons, cargo containers and drone hatches, and the list is meant to grow; legs stay the one module limited to left and right sockets. Wide room for expansion is a design goal, and building is named the core of the game in section 1 and Pillar 1. Which modules ship when, module facing and the limits on building are open (8.1) | Klas, 2026-10-09: "Sockets can take other blocks, weapons, cargo containers drone hatches etc. I want a lot of possibilities for expansion. Building and feeling like an inventor is in the very core of the game." | Fixed top-only weapon sockets; bottom sockets left empty; a short closed part list |
| 2026-10-09 | A cargo container raises the scrap a walker can carry per trip; its capacity, mass and price are still proposals. A drone hatch launches the player's own drones, but it is a far-future idea that may never be built, not in M1 or M2 | Klas, 2026-10-09: cargo containers "Yes"; drone hatches "Yes about drone hatches but don't mind that for a long time. We might not implement it." | Cargo that only protects scrap on death; hatches in M1 as a spotter drone |
| 2026-10-09 | Build rules from M1: a 4 x 2 layout of 0.7 x 0.5 x 0.3 m blocks (closed sockets where blocks meet, stacking allowed, legs on bottom-layer blocks only in M1); a ladder of 9 leg lengths (0.4-2.5 m, about x1.25 per step) grown or shrunk one step for scrap, extreme lengths unlocked by blueprints; a block is 1/8 of today's chassis (15.625 kg, 12.5 HP, 15 scrap), owned parts re-socket for free; a 60-scrap carry limit, +40 per cargo container; mass against lift is the main limit with no power resource, M1 caps of 12 legs and 4 weapons, weapons aim along the heading on any face, a bottom module costs ground clearance | Klas, 2026-10-09, choosing the game-designer's recommendation on each of four questions | 8 x 1 layout; legs on stacked blocks; more fixed leg parts or a continuous length; paid re-socketing; no carry limit; a power resource; broadside guns |
| 2026-10-10 | A respawn after death or a recall is a workshop visit: it banks the carried 0 (Economy.banked fires for 0), so HP is fully repaired and drones and ring 1-2 scrap nodes respawn, as on any return home (provisional, judge in play) | Lead proposal for T12, Klas: "The respawn works for now". One rule for every workshop visit; the way back to the wreck cache is a real fight, which gives "dying again before reaching it destroys it" (7) its stakes; dying yields nothing that walking home and banking does not | Repair only on death, with killed drones and taken nodes staying as they were (an easy walk back to the cache) |
| 2026-10-10 | Per-weapon aim: each weapon turns toward the mouse aim point, in yaw and pitch, within its own mount's arc (for example a roof gun 360 deg in yaw but limited downward; a front gun 180 deg both ways), at a traverse rate that falls with its weight (heavy guns slow, small guns almost instant). Each weapon has its own reticle; at its arc limit the reticle stops at the furthest point it reaches, turns gray and the gun does not fire. The camera dot marks the mouse aim point, not the walker's heading. Sections 6, 8.3, 12, 16 (risk 8) and M0 criterion 5 are rewritten next (plan.md, 'After the M0 build') | Klas, after playing the M0 build: "the aiming must change. The weapons must follow the mouse vertically, within their movement range. Each weapon should have their own reticle" | Weapons fixed to the body's heading with the camera's pitch (2026-10-09 gate decision) |
| 2026-10-10 | The foot dust cloud scales with weight per leg (walker mass / leg count) and must read as dust, not white blobs. Section 10 rule 1 is rewritten next | Klas, after playing the M0 build: "Dust doesn't look like dust", "I want the dust cloud to scale as a function of Walker weight divided by number of legs" | One puff size for every walker (2026-10-10, T19) |
| 2026-10-10 | Direction for later milestones: no enemy simply spawns; every NPC has a purpose. At start, NPCs are out at various locations, each with a goal (for example walking from a far factory to a mine, loading resources and returning). New NPCs spawn at natural places (a building, the map edge) with a purpose at once (cross the map and despawn; leave a building, do a task elsewhere, return and despawn). The GDD says NPC (non-playable character) instead of enemy. A local AI model (for example Gemma) for NPC behaviour is to be considered. Sections 8.4, 7 and 9 are reworked in a later design pass (plan.md, 'After the M0 build') | Klas, 2026-10-10: "I don't want enemies to just spawn. I want every enemy to have a purpose" | Drones that wait at sites and respawn on every workshop visit (M0, provisional) |
| 2026-10-10 | The GDD needs a story and a main goal: a larger reason to explore than the invent-explore loop alone. Section 15's "Story or dialogue" no longer rules story out; what form it takes is open (section 18) | Klas, 2026-10-10: "The invent-explore loop is satisfying to a point but there must be a larger reason for exploring" | Loop-only game with no overarching goal |
| 2026-10-10 | Per-weapon aim model (8.3): every weapon aims from its pivot straight at P (the camera centre ray's hit, unchanged), within an arc that belongs to its socket face and is chassis-relative: top yaw 360 / pitch -20..+75 deg; front, back, left and right yaw and pitch +/- 90 deg (M1); bottom yaw 360 / pitch -75..+20 (M1). Traverse = clamp(7200 / weapon mass kg, 45, 720) deg/s in yaw and pitch, no ramp, relative to the chassis, so a body turn adds or subtracts. A weapon is live while P is inside its arc (0.5 deg tolerance) and then fires on its cooldown along its current line, even mid-swing; outside, it stops at the arc point nearest P, goes gray and does not fire. The M0 pulse cannon: 40 kg, any top socket, 180 deg/s. Projectiles pass through their own walker. Fixed firing phases by mount order; a gray weapon skips its slots. Retired: the convergence point Q, the 4-120 m range clamp, the world-relative -10..+45 deg elevation, the 360 deg/s slew and the 90 deg range-and-height hold. 8.1's M1 rule "a weapon on any face aims along the heading" and the heading wording in 8.4 now read per-weapon aim | Klas after the M0 build (row above): "The weapons must follow the mouse vertically, within their movement range ... a roof mounted gun could have a 360 degree range but limited range when aiming down. A front mounted gun could have 180 degree range both vertically and horizontally ... Heavy guns have their reticles follow more slowly. Small guns are almost instant." Arcs on the face make socket choice a build decision (Pillar 1); 1 / mass is the simplest curve with a wide spread (16x from cap to floor); -20 deg lets every reference build reach the dot at the default pitch 20, so the gray ring means something; the 45 deg/s floor still tracks any drone; firing mid-swing keeps the reticle honest with one rule | Arcs per weapon type (the same gun would feel the same everywhere, so placement stops mattering); world-relative arcs (a mount is a physical joint; the gray ring explains the tilt case); sqrt(mass) traverse (too flat: 40 vs 160 kg only 2x apart); an acceleration ramp (swing time no longer angle / rate, harder to test and to feel); fire only once within 2 deg of P (a second rule; heavy guns would go silent mid-swing with no cue); re-phasing the live weapons (rhythm jumps whenever a gun goes gray) |
| 2026-10-10 | HUD for per-weapon aim (12): the camera dot marks P and is always drawn on top; one 28 px accent ring per mounted weapon at the first hit along that weapon's current barrel line; at the arc limit the ring stops at the furthest reachable point, turns gray `#646464` (>= 0.2 luma below the live ring) and dashed, and its weapon is silent; one chevron per off-screen ring in its ring's colour; the hit flash goes to the ring of the weapon that hit; the merge pip goes | Klas, after the M0 build: "Each weapon should have their own reticle ... Guns that can't follow the mouse have their reticle as far as they can reach but the reticle is grayed out and the gun won't shoot ... The dot reticle is where the mouse aims, not where the Walker is heading." Gray alone is about 0.2 luma from the accent; dashing (T06's existing pattern) keeps the read in grayscale and for colourblind players. With the dot always drawn, "dot inside the ring" is the on-target read for any number of rings | Gray only (weak in grayscale); hide a gray ring (Klas wants it shown); keep the merge pip (it would hide the dot that every other ring still chases) |
| 2026-10-10 | Controls for mouse aim (6): the keys only drive the body; RMB keeps FOV 50 and gets mouse 0.10 deg/px, and the x 0.6 turn penalty while aiming goes; recentring also pauses while `fire` is held and restarts its 1.5 s timer on release | The body no longer aims, so slowing its turn while zoomed would only slow the swing assist and the dodge; 0.15 x tan(25) / tan(35) = 0.10 keeps the dot's screen motion per pixel; recentring now drags P and every gun with it, so it must not run mid-fight | Keep x 0.6 (no remaining purpose); same sensitivity zoomed (fine aim jumps by 1.4x); remove recentring outright (Klas has not asked; kept as the first knob, section 18) |
| 2026-10-10 | Risk 8 rewritten: turn rate no longer gates every shot; the heading and the build stay meaningful through chassis-relative traverse (A/D toward a target cuts a 90 deg swing from 0.50 s to <= 0.35 s), heavy guns slower than the turn rate (M1), face arcs (front mounts need the heading, M1) and the roof's near-low dead zone that grows with leg length. Spike in T22 `drone_fight`; fallback: roof yaw +/- 150 deg or traverse constant 4800. M0 criterion 5 (14, mirrored in the plan.md M0 row) swaps the "weapon yaw equals the heading" and heading-onto-drone checks for the arc gate, traverse by mass, a reticle per weapon and shot-at-P checks; the telegraph, 3-hit kill, hold cycle and strafing damage bar are kept; the no-lead tracker now aims with the dot and runs standing and strafing | Klas's per-weapon aim (rows above). Pillar 1 must show in fights for M0's one gun, which a roof cannon could otherwise skip; making the body a traverse booster keeps A/D useful without narrowing the 360 deg roof Klas described | Narrow the roof to +/- 150 deg now (against Klas's example; kept as the fallback); a slow M0 cannon so the body must turn (fights would feel sluggish with the only gun in the game); accept that heading no longer matters in fights |
| 2026-10-10 | Dust by weight per leg (10 rule 1): puff width W = clamp(0.5 m x (build mass / legs) / 50 kg, 0.25, 1.0) m, height 0.5 x W (Scout 0.53, Strider 0.48, Crawler 0.67 m); five soft sprites with a radial falloff; colour `#D9C7AE` from the ground family, lit by the scene, peak alpha 0.45, luma lift 0.03-0.12, no pixel above luma 0.85; life 0.8 s (was 0.2 s) with an outward burst, a rise and a settle; <= 2 draw calls per walker | Klas, after the M0 build: "Dust doesn't look like dust. It looks like white blobs" and "scale as a function of Walker weight divided by number of legs". The built puff (T19) was a near-white `#FAF2E0` at alpha 1.0 for 12 frames: an opaque bright flash. Linear scaling makes M0's 47-67 kg per leg spread show (Crawler 1.41x Strider); an energy-like cube root would show only 1.12x | Cube-root scaling (invisible in M0); scale with leg reach (Klas asked for weight per leg); per-surface sampled tint now (one ground family in M0; M1 zones); keep 0.2 s and only fix the colour (a short life still reads as a pop, not as dust) |
| 2026-10-10 | Closes the two 2026-10-10 rows "Per-weapon aim" and "The foot dust cloud scales with weight per leg": GDD sections 3, 5, 6, 8.1 (M1 weapon rule), 8.3, 8.4 (heading wording), 10 rule 1, 12, 14 (criterion 5), 16 (risks 3 and 8) and 18 rewritten as in the five rows above | Game-designer pass, plan.md "After the M0 build", step 1 | |
| 2026-10-10 | Dust tuning after T23's first shots (10 rule 1): W doubles to clamp(1.0 m x w / 50 kg, 0.5, 2.0) (Scout 1.05, Strider 0.95, Crawler 1.34 m); the dust is lit with an up-facing normal so it darkens in shadow like the ground; the 0.03-0.12 lift is measured on the valley floor in sun and shadow, and the absolute "no pixel above luma 0.85" cap goes (the saturation rule still bans white); the proof shot moves to the play camera (8 m, pitch 20) with a >= 20 px width gap at 720p | Playtest-critic on T23 round 1: at 0.5 m per 50 kg the Crawler's puff was about 10 px wider than the Strider's at the play camera, so Klas could not answer "does a heavier foot kick up more?". Code-reviewer and critic: the unshaded puff lifted shadowed ground by 0.14-0.18 (a grey glow, and doubling the size would double it). The light test stripes render at 0.865, above the old 0.85 cap, so the cap was unmeetable there | Raise alpha (pushes shadow and dark ground toward blobs); a non-linear law such as (w / 50)^2 for a 2x gap (Klas asked for weight per leg; ask him after he plays); keep the dust unshaded (kept only as the fallback if the lit material reads darker than the floor) |
| 2026-10-10 | The dust's >= 20 px width gap becomes a reported number (T23 round 2 measured 14 px at 720p for one puff, ratio 1.37); W stays at 1.0 m per 50 kg; the proof shots live in a valley scenario, `foot_fx_valley` | The 20 px was the critic's estimate, not a measurement. Another 1.4x would make the Crawler's puff about 1.9 m, wider than its leg row; Klas judges "does a heavier foot kick up more?" in the build (playable first) | Grow W again to 1.4 m per 50 kg; a non-linear law (both open for after Klas plays) |
| 2026-10-10 | Dust colour `#D9C7AE` -> `#BFAF99` (same hue 34-35 deg and saturation 0.20, value 0.85 -> 0.75) | T23 round 2: once lit (and converted from sRGB to linear, as instance colours must be), `#D9C7AE` lifted the valley floor by 0.123, just over the 0.12 cap; `#BFAF99` lifts it by 0.07-0.08 | `#D5C3AA` (round 1, unshaded; lifted 0.123 lit) |

## 18. Open questions
- Story and main goal (Klas, 2026-10-10): what is the larger reason to explore, and how does the world tell it?
- NPCs with a purpose (Klas, 2026-10-10): which NPCs exist (haulers, miners, guards, travellers), which are
  hostile and when, and how the player's actions touch their routes (raid a convoy, block a mine)?
- A local AI model (for example Gemma) for NPC behaviour: what does it decide that scripted goals cannot, and what
  does it cost in build size (the playtest zip must stay under 100 MB), frame time and test determinism? A spike
  before any commitment.
- Answered at the gate (2026-10-09): tank controls hold up with a free camera; weapons follow the body's heading
  and the camera's pitch (Decisions log). Superseded after the M0 build (2026-10-10): weapons aim at the mouse (8.3).
- Per-weapon aim (2026-10-10), each with the default T22 builds until Klas answers after play:
  - Pulse cannon traverse: 180 deg/s (40 kg, a 90 deg flick followed in 0.50 s) makes M0's only gun visibly
    mid-weight. Should it feel almost instant instead? Default 180; one constant (7200) to retune.
  - Do 360 deg roof guns make the drone fights too easy? Mouse aim plus Q/E makes strafe-and-shoot nearly free.
    Default: keep the drones as tuned and read `drone_fight`'s damage and time-to-kill reports; the lever is the
    encounter (more drones, staggered wind-ups) in the NPC pass, with roof yaw +/- 150 deg as the fallback (risk 8).
  - Firing mid-swing: a live gun fires along its current line before it reaches P (a heavy gun sprays as it
    sweeps). Default yes (the reticle shows it); the alternative is to hold fire until within 2 deg of P.
  - Recentring behind the body now drags the aim. Default: it pauses while `fire` or `aim` is held; the
    alternative is no recentring in the field.
- Blueprints are kept on death (current default). Should they instead be carried like scrap, for more stakes?
- The economy is estimated, not simulated: about 90 scrap per trip. Check real income in `loop_full` and retune
  prices before M1.
- Does keeping orange hold up in a colourblind check (playtest-critic with a deuteranopia filter at the M0 review)?
