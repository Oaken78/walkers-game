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
| Max climb height (`climb`) | 0.9 x mean leg reach (Scout 0.90 m). A front foot reaches up onto a top at most 0.4 x reach above its own hip, then the body hauls (8.2). Step-down mirrors it to the same depth | Crawler 0.54 - Strider 1.44 m |
| Reach-up swing | 1.5 x the build's step time (Strider 0.35 s, Scout 0.27 s, Crawler 0.21 s at top speed). The foot rises to the edge + 0.15 x reach before it moves over the lip; a reaching or hanging pad is inside geometry on 0 ticks | scales with the step time |
| Haul | Advance <= 0.4 x top speed from the first front foot on top to the last foot up; rise or lower <= 1.5 m/s (2.5 cm per tick). Body pitch peaks at 10-25 deg, never above min(grip - 5, 25) deg. Climb time from the first reach to the last foot on top: 1.0-2.0 s on a ledge 0.75 x climb tall (Strider 1.08 m, Crawler 0.40 m), Klas tunes it at the next playtest. No stretch longer than 0.4 s without horizontal or vertical progress while input is held. A rise within stride step-up costs <= 0.3 s extra | |
| Hanging legs | A leg with no valid foothold lifts within 1 tick and hangs at its lift height (0.25 x reach), >= 0.05 m clear of geometry, pawing toward the face or edge on a 0.6 s cycle. At a face it cannot climb, each paw swings a front pad up the face to the highest foothold it tested, >= 0.6 x reach above the floor and at most its hip + 0.4 x reach, >= 0.05 m off the face, then drops back to the lift height. It counts as airborne. While any leg hangs, the centre of mass stays inside the planted feet's polygon by >= 0.1 x mean reach (Strider 0.16, Scout 0.10, Crawler 0.06 m). On ground with no rise or drop beyond stride step-up, no leg hangs | |
| Camera orbit distance | 8 m (scroll 5-12 m), FOV 70; spring-arm terrain collision, min 2 m unless rock is closer (rock wins) | |
| Mouse sensitivity | 0.15 deg/px, invert-Y off (constants in M0, settings menu M2) | |
| Camera position lag | 0.10 s smoothing; 0 lag on rotation | |
| Pulse cannon | 4 shots/s, 15 dmg, projectile 60 m/s, spread 1.0 deg x leg spread factor | 0.5 - 1.5 deg |
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
| `aim` | RMB (zoom to FOV 50, -40 % turn rate) | walking |
| `interact` | F: enter the workshop when within 4 m. Hold 3 s anywhere: recall to the workshop (stuck recovery; carried scrap drops as a cache, like death) | walking |
| `zoom_in` / `zoom_out` | mouse wheel | walking |
| `build_place` | LMB on socket | workshop |
| `build_remove` | RMB on part | workshop |
| `build_exit` | Tab | workshop |
| `pause` | Esc | both |

**Tank controls:**
- W/S drive along the body's facing, A/D turn the body at its turn rate, and Q/E crab-strafe.
- The mouse orbits the camera independently and never turns the walker. Mouse X yaws the camera freely (360 deg).
  Mouse Y pitches it from -20 to 60 deg. -10 to 60 is the normal range. -20 to -10 is the aim-up range for
  drones close overhead: there the spring arm shortens against the ground (rock wins), and feet may leave the frame.
- Weapons point where the walker faces. Their yaw is always the body's heading; there is no turret yaw. Their
  elevation follows the camera: they aim at the height and range of the point under the screen centre (8.3).
  Turning the body (A/D, at the build's turn rate) is how you aim sideways. Q/E strafing dodges bolts while the
  guns stay on target. This makes the turn rate a build stat you feel in every fight (Pillar 1).
- `aim` (RMB, held): FOV 70 -> 50 in 0.10 s and turn rate x 0.6 for fine tracking (Scout 120 -> 72 deg/s). It
  pauses recentring and releases the descent floor, as before. It does not swing the camera to the heading; the
  weapon reticle (section 12) shows where the guns point.
- Turning in place re-plants the legs visibly, so the turn itself is a gait show (Pillar 2).
- The camera does not auto-follow the body's yaw. Behind-the-body recentring is on a 1.5 s delay after mouse
  idle and pauses while `aim` is held; this is a tuning knob for the gate.
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
| `step_up` | 0.6 x reach (the stride step-up, 8.2) |
| `climb` | 0.9 x reach (the max climb and step-down, 8.2; shown on the stat panel). Mixed builds use the mean reach like every other stat; T16 measures Scout + short pair and Scout + long pair, and the formula switches to the shortest leg if a measured climb falls more than 10 % below its stat |
| `max_slope` | lowest slope grip among the mounted legs |
| `spread` | 1.0 deg x mean leg spread factor (body sway) |
| `hp` | chassis hp + armor parts |

**Reference builds** (the unit test fixtures):

| Build | Parts | Load | Speed | Turn | Step-up | Climb | Slope | HP | DPS | Spread |
|---|---|---|---|---|---|---|---|---|---|---|
| Scout | 6 medium legs, 1 cannon | 0.70 | 4.50 | 120 | 0.60 | 0.90 | 35 | 100 | 60 | 1.0 |
| Strider (A) | 6 long legs, 1 cannon | 0.56 | 6.49 | 134 | 0.96 | 1.44 | 30 | 100 | 60 | 1.5 |
| Crawler (B) | 8 short legs, 2 cannons, armor | 0.61 | 3.80 | 109 | 0.36 | 0.54 | 45 | 140 | 120 | 0.5 |

- **Niche:** the Strider reaches ledges and escapes. The Crawler grips steep slopes and wins fights:
  DPS x HP is 2.8x the Strider's, and its spread is tight. Neither build dominates (Pillar 1).
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
  - *Footholds on a top* sit far enough past the edge that the shin clears the corner (at least 0.15 m). The climb
    height is a hard check: a foothold more than `climb` (+ 0.03 m) above the leg's current foot is never taken, even
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

### 8.3 Weapons - top socket parts
- **State:** cooldown, heat (M1).
- **Rules (aim model, Klas at the gate: yaw from the body, pitch from the camera):**
  - *Aim point P:* the camera's centre ray hits the world or an enemy (layers 1 and 3, never the player), up to
    120 m. With no hit, P is the point at 120 m.
  - *Aim range d and height h:* d is the horizontal distance from the body origin to P, clamped to 4-120 m (a
    camera looking down at the walker's own feet never points the guns into the ground under it). h is P's height.
  - *Convergence point Q:* d metres along the body's heading from the body origin, at height h. Every weapon aims
    at Q. Its yaw follows the heading (lateral convergence from its socket offset only, <= 4 deg at 4 m), and its
    elevation is the angle from its muzzle to Q. When the target sits on the heading, the shot lands where the
    camera looks.
  - *Elevation limits:* -10 to +45 deg, world-relative, so a body tilted up to 45 deg on the talus still aims level.
    At a limit the weapon still fires, and the reticle shows where the shot really lands.
  - *Response:* weapon elevation slews at 360 deg/s (a full mouse flick is followed within 0.15 s). Yaw is locked
    to the heading on every tick, with 0 lag.
  - *Crosshair far off the heading:* the weapons always fire along the heading. There is no arc lockout and nothing
    greys out. When the camera's yaw is more than 90 deg off the heading, d and h hold their last values, so the
    guns do not nod while you look behind you; they pick P up again within 90 deg.
  - *Projectiles* fly along the weapon's aim line at their own speed and do not inherit the walker's velocity, so a
    strafing or turning walker hits where the reticle shows, with no lead of its own.
  - *Several weapons:* LMB fires every mounted weapon. Each keeps its own rate (pulse cannon 4 shots/s), and their
    phases are spread evenly: weapon k of n fires k / (n x rate) s after the first, so two cannons fire every
    0.125 s, a steady rhythm rather than a double bang.
- **Tests:** fire rate cap; damage applied once per projectile; weapon yaw equals the body heading within 0.1 deg on
  every tick; with a target on the heading, the shot passes within 0.5 deg of the camera's aim point inside the
  elevation limits; elevation is clamped to -10..45 deg world-relative on a body tilted 39 deg; d is clamped to
  4 m when the camera looks straight down; d and h hold when the camera yaw is more than 90 deg off the heading;
  two weapons fire 0.125 s apart.

### 8.4 Enemies - drones (M0); enemy walkers (M1)
- **Drone states:** idle-hover, patrol, alert (sees the player within 35 m, line of sight), strafe (orbits at
  12-18 m, at <= 6 m/s, risk 8), wind-up (0.6 s, glows, holds still), fire, recover (0.3 s, holds still), dead
  (falls, drops 3-8 scrap).
- **Rules:** max 4 active drones. Drones leash back to their spawn when the player is more than 60 m away, and
  respawn on bank.
- **The telegraph is the opening.** A drone stops to shoot: at wind-up start it brakes from orbit speed to 0
  within 0.1 s and holds its position (hover bob <= 0.1 m) through the 0.6 s wind-up, the shot and a 0.3 s
  recovery, then regains orbit speed over 0.3 s. That makes 0.9 s still in every 1.5 s cycle. Pulses
  (60 m/s, 0.25 s to 15 m) fired at a holding drone on the heading hit with no lead. A drone that is orbiting
  moves 1.5 m during that flight, more than its 0.6 m radius, so straight shots at it miss: the player fires on the
  glow. Each player choice has a cost:
  - *Stand and trade:* face the drone, fire from the start of its wind-up, and the third pulse lands about 0.75 s
    in, after the drone's own bolt has left, so a standing walker takes the hit.
  - *Strafe and shoot:* dodge with Q/E while holding the heading on the drone with A/D (a 3.4 m/s strafe drifts
    the bearing about 13 deg/s at 15 m, against a drone 2.3 deg wide).
  - *Strafe only:* take no hit and deal no damage.
- **Encounters stagger the wind-ups:** drones in one encounter start their wind-ups >= 0.4 s apart, so their holds
  rarely overlap and the walker swings between them. That is where turn rate decides a fight (Pillar 1).
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
| Cliff walls | >= 30 m tall and >= 60 deg along the whole floor edge, so no build can leave (max climb 1.44 m, max slope grip 45 deg). These are the map bounds; there are no invisible walls |
| Floor | Gentle 0-10 deg overall. Bumpy patches up to 30 deg (the gait show). Boulders 0.3-1.0 m high (0.5-0.8 m in the M0 valley) as climb content: the Crawler (climb 0.54 m) hauls over only the smallest and goes around the rest, the Scout (0.90 m) and the Strider (1.44 m) haul over all of them; a boulder within stride step-up is stepped onto in stride |
| Workshop | On a bench at the north end, 20-40 m from the head wall. Ring distances are measured from it |
| Dry wash | A winding riverbed from the workshop down to the far end. It is the main path and the route the test scenarios walk |
| Ledge pocket | West wall, ring 2, 160-240 m from the workshop. A 1.2 m ledge leads up to it; one 60-scrap node. The Scout (climb 0.90 m) can't climb it, and its front legs paw at the face; the Strider (1.44 m) reaches and hauls up |
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
  - **Deltas show better or worse, not just up or down.** A better change has a filled accent mark; a worse change
    has a hollow neutral-grey mark (>= 0.25 luma apart); the sign keeps the direction. Higher is better for speed,
    turn, step-up, climb, slope, HP and DPS; lower is better for spread and load.
  - **A blocked exit answers:** Tab or a click on the disabled exit pulses the reason text for 0.3 s, and the Load row
    shows a "!" while load is above 1.0.
- **Field HUD:**
  - **Aim: a camera dot and a world-space weapon reticle.** The camera is free, so the screen centre shows where
    you look, and the reticle shows where the guns will hit. The gap between them is the "turn this way" cue.
    Numbers are at 1080p and scale with resolution:
    - *Camera dot:* 6 px, player body `#E6E1D6` with a 1 px ink `#14161A` outline, at the screen centre. It sets P
      (8.3).
    - *Weapon reticle:* a ring 28 px across with a 3 px stroke, in player accent `#FF8A3D` with a 2 px ink outline,
      so it reads in grayscale against sky and ground. It sits at the screen projection of the first hit along the
      line from the weapons to Q (layers 1 and 3, up to 120 m), computed from the same tick's weapon pose (no lag).
      Over an enemy hurtbox the stroke goes from 3 to 5 px. It never takes the threat hue (rule 2).
    - *Merge:* when the reticle centre is within 12 px of the dot, the dot hides and the ring shows a 4 px centre
      pip: on target.
    - *At an elevation limit (-10 or +45 deg):* the ring is drawn dashed (8 segments, about 50 % duty) only when it
      matters: the dot is on an enemy hurtbox, or `fire` is held or was released less than 0.5 s ago. A shot that
      cannot reach the dot then reads as such. Otherwise the ring stays solid at its true landing point, because at
      the default pitch 20 the guns cannot reach the ground under the dot nearer than about 12 m, and an always-on
      dashed ring teaches nothing.
    - *Hit confirmation:* when a player projectile hits a hurtbox, the ring's stroke flashes player body `#E6E1D6`
      for 0.06 s, so a hit reads even when the ring covers a distant target.
    - *Off screen or behind the camera:* a 32 px accent chevron at the screen edge, 24 px inset, points to where the
      guns aim. To bring them to the dot, the player turns the body toward the dot. No other HUD element sits within
      40 px of the chevron.
    - All aim marks use `mouse_filter = IGNORE`.
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
   turns toward camera yaw, with Q/E strafe kept. Klas decides at the T03/T04 gate. Closed 2026-10-09: tank kept;
   weapons follow the body's heading and the camera's pitch (sections 6, 8.3 and 12; Decisions log).
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
8. **Sideways aim depends on turn rate** (Pillar 1). A drone orbiting faster than the walker can turn cannot be
   tracked, and the fight turns into waiting. Bound: drone orbit speed <= 6 m/s (<= 29 deg/s at 12 m), so even the
   slowest reference build while aiming (Crawler 109 x 0.6 = 65 deg/s) turns >= 2.2x faster than a drone moves
   across its view. Builds near the 60 deg/s turn floor (aiming 36 deg/s, 1.2x) are the M1 heavy end and need a
   check there. A drone's 0.9 s hold per 1.5 s cycle (8.4) is the opening, so hits need turn rate, not leading
   skill. Spike (T07 `drone_fight`), all checks against a drone orbiting at 15 m, 6 m/s, 4 m up, cycling as in 8.4:
   - Every M0 reference build brings its heading onto a drone 90 deg off in <= 1.0 s (Crawler 90 / 109 + 0.1 s
     ramp = 0.93 s).
   - A scripted tracker aims at the drone's current position, never ahead of it. It holds A/D toward the drone's
     bearing, releases when the bearing error is within its own stopping distance (yaw rate x 0.1 s ramp / 2) +
     0.5 deg, and fires continuously.
   - With the Scout and with the Crawler, the tracker hits >= 80 % of shots fired between hold start + 0.15 s and
     hold end - 0.25 s (so they land while the drone holds), and kills a drone within its first two holds
     (<= 3.0 s from the first hold start).
   - The hit rate on shots fired while the drone orbits is reported, not asserted. It shows that the opening, not
     luck, carries the fight.
   Fallback: a longer hold (1.1 s), or drop the x 0.6 aim turn penalty.
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

## 18. Open questions
- Answered at the gate (2026-10-09): tank controls hold up with a free camera; weapons follow the body's heading
  and the camera's pitch (Decisions log).
- Blueprints are kept on death (current default). Should they instead be carried like scrap, for more stakes?
- The economy is estimated, not simulated: about 90 scrap per trip. Check real income in `loop_full` and retune
  prices before M1.
- Does keeping orange hold up in a colourblind check (playtest-critic with a deuteranopia filter at the M0 review)?
