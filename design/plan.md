# walkers - production plan

Edited only by the lead, on `main`. Packets live in `design/tasks/<id>.md` (see `docs/task-template.md`).
Source of truth for numbers: `design/gdd.md` (section refs in brackets).

## Milestones
| Id | Name | Acceptance criteria (measurable) | Proof (scenarios / screenshots) | Status |
|---|---|---|---|---|
| M0 | Playable loop | 1. Scout walks at 4.5 m/s +/- 0.1, reaching it in 0.25 s +/- 0.05 [5]. 2. Planted foot drift <= 2 cm per step and airborne legs (swinging or hanging) never above the gait limit over 20 s on the 30 deg bumpy course and through the climb lane; while any leg hangs, the centre of mass stays inside the planted feet's polygon by >= 0.1 x mean reach; on the bumps no leg hangs or reaches up [5, 8.2]. 3. Strider A vs Crawler B: (A - B) / A >= 40 % in top speed and in climb height measured on the ledges lane (expected 1.44 vs 0.54 m, 0.625), with neither stat clamped, and B's DPS x HP >= 1.8x A's [4, 8.1]. 4. Workshop: place and remove a part, see the stat delta, exit is blocked with a reason while the build is invalid [8.6]. 5. Drone telegraphs >= 0.6 s before every shot, dies in 3 hits and holds still for 0.9 s of each 1.5 s cycle; a strafing Scout takes <= 40 % of the damage an idle Scout takes. Each mounted weapon has its own reticle, within 0.5 deg of where its shot goes. With P inside its arc and the weapon settled, a shot at spread 0 passes within 0.2 deg of P. With P outside its arc (the dot under the walker) the weapon fires 0 shots over 2.0 s of `fire` and its reticle is gray and dashed at the arc limit. The pulse cannon (40 kg) swings 90 deg in 0.50 s +/- 1 tick, as the traverse formula gives for its mass. Every M0 reference build brings a reticle onto a drone 90 deg off in 0.50 s with the body still and in <= 0.35 s with A/D toward it. A no-lead tracker that keeps the dot on the drone hits >= 80 % of shots fired during holds and kills within two holds, standing and strafing, with the Scout and with the Crawler [5, 8.3, 8.4, 12, 16]. 6. Full loop: collect scrap, bank (full repair), buy a part, socket it, die, wreck cache dropped, reclaim it, with no scrap duplicated. The first purchase happens on expedition 1-2, and the Strider reaches the 1.2 m ledge pocket by reaching and hauling, while the Scout's front legs paw at the face and it cannot climb it [7, 8.2, 8.5, 9]. 7. Tier 3 green: 0 log errors, frame p95 <= 16.7 ms, draw calls <= 1000 with 4 drones on screen [13]. 8. At 8 m and pitch -10 to 60 deg every foot is in frame and >= 12 px tall at 1080p (the -20 to -10 aim-up range is exempt); the drone wind-up reads in grayscale; the camera dot and every weapon reticle, live and gray, read in grayscale, live and gray >= 0.2 luma apart, and a chevron shows for each off-screen reticle; the foot dust lifts the floor's luma by 0.03-0.12 with no white pixel, and the Crawler's puff is >= 1.3x the Strider's across [6, 10, 12]. 9. Valley (GDD 9.1): every cliff sample >= 30 m and >= 60 deg; no build leaves the valley floor (max climb 1.44 m); of the reference builds, only the Strider reaches the 1.2 m ledge pocket and only the Crawler the talus pocket (the fixtures stand for long and short legs, not classes; GDD 8.1); every build that climbs into a pocket climbs back down out of it [9.1, 8.2]. | Scenarios: `walk_flat`, `gait_course`, `build_contrast`, `workshop_edit`, `aim_range`, `drone_fight`, `foot_fx`, `loop_full`, `map_bounds`, `perf_4_drones`. Test: `test_valley_geometry.gd`. Screenshots: `gait_course__midstride`, `gait_course__pitch_low`, `gait_course__pitch_high`, `build_contrast__a_vs_b`, `workshop_edit__stats`, `drone_fight__windup`, `drone_fight__windup_gray`, `drone_fight__reticle_swing`, `drone_fight__reticle_gray`, `drone_fight__aim_up`, `foot_fx__dust_weight`, `loop_full__hud` | planned |
| M1 | Vertical slice | Defined after the M0 review: the block chassis and its build rules (GDD 8.1: 4 x 2 blocks of 0.7 x 0.5 x 0.3 m, the flatter chassis the arched knees peak above), 4-12 legs including uneven builds, the leg-length ladder, modules including cargo and the carry limit, a 12-leg performance test early, blueprints (2-3 per zone, including the extreme leg lengths), 2nd zone and terrain gate, enemy walker sentinel, footstep audio, final toon shading [8.1, 9, 14] | tbd | planned |
| M2 | Content | 3 zones, all parts, gamepad, menu, save/load [14] | tbd | planned |

## M0 order
- T00 (lead) first.
- Then T01, T02 and T05 in parallel. T03 (which owns its own test course) and T04 start after T01 and T02
  merge.
- **Gate:** after T03 and T04, T14 puts T04's rig into `gait_course` (with `WalkerBody.yaw_source` for the
  fallback) and adds the `gait_course__pitch_low` / `__pitch_high` shots. Then run `gait_course` and
  `build_contrast` plus a playtest-critic pass, and Klas
  plays the tank controls (fallback: body turns to camera yaw). If risk 1, 2 or 3 from GDD section 16 fails, stop and redesign before content work.
  **Passed 2026-10-09:** Klas kept tank steering (weapons follow the body's heading and the camera's pitch; GDD log),
  the gait and build contrast hold; the climbing redesign (T16) came out of the gate feedback.
- T13 (walker hardening from the T03 review, boulder lag first) and T15 (descent camera, Klas's gate decision)
  run in parallel after T14 merges, while Klas plays the gate.
- T16 (climbing, reach and haul: Klas's gate decision) starts after T13 merges. The climb pose check (GDD 16 risk 7)
  passed with the descent drop at 0.32 x reach.
- After the gate: T06, T07, T08 and T09 (max 3 devs at once). Then T11. T12 integrates last, including the HUD.
- After T16 (2026-10-10): T11 (look), T18 (walker API) and T19 (foot dust and decal) run in parallel with disjoint
  paths. Every shot changes in T11 and T19, so baselines are approved on main after each merge, and the later
  branch merges main and re-runs its shots. A playtest-critic pass on main after both judges actors against the
  new world (GDD 10 rule 4).
- Then (max 3 at once, as slots free): T20 (HUD) and T21 (proof runs) need nothing from wave 1; T12 (game loop)
  starts after T18 merges (it owns walker_body.gd for the collapse) and instances the HUD once T20 merges. After
  all of them: the M0 review (tier 3 on every scenario, code-reviewer, playtest-critic, Klas plays the build).
- Cut first if scope slips: the armor plate, then the compass. The ink outline is already moved to M1.

## After the M0 build (Klas played it, 2026-10-10)
Klas's verdict on walkers-playtest-20261010-1224 (built from 53f1370):
1. Loop: "Yes, the loop is satisfying."
2. Legs: "Planted feet reads well, prints are good. Dust doesn't look like dust. It looks like white blobs." Dust
   change: "I want the dust cloud to scale as a function of Walker weight divided by number of legs, so essentially
   weight per leg."
3. Look: "Orange stands out but I assume that any graphics is placeholders at this point. Nothing I want in the
   final game." "The color palette is fine for now. It's hard to judge since we are working with placeholder models
   and no textures." So until real models and textures exist, playtest questions ask about reads and feel, not
   about hues or materials.
4. HUD and aim: "HUD is fine for now but the aiming must change. The weapons must follow the mouse vertically,
   within their movement range. Each weapon should have their own reticle. For example, a roof mounted gun could
   have a 360 degree range but limited range when aiming down. A front mounted gun could have 180 degree range both
   vertically and horizontally. Guns that can't follow the mouse have their reticle as far as they can reach but the
   reticle is grayed out and the gun won't shoot. Heavy guns have their reticles follow more slowly. Small guns are
   almost instant. The dot "reticle" is where the mouse aims, not where the Walker is heading."

Next, in order (each starts after the one before it, unless noted):
1. **Done 2026-10-10 (83587d5): game-designer: per-weapon aim and dust by weight per leg.** Rewrite GDD 6 (controls), 8.3 (weapons: a yaw and
   pitch arc per mount position, a traverse rate that falls with the weapon's mass, fire only while the target lies
   inside the arc), 12 (the camera dot is the mouse aim point; one reticle per weapon, gray and silent at its arc
   limit), 16 risk 8 (turn rate no longer gates every shot: what keeps the body heading and Pillar 1 meaningful?), 10
   rule 1 (dust size from chassis-and-parts mass / leg count, with a curve and a cap, reading as dust, not as white
   blobs), and M0 criterion 5 (its "weapon yaw equals the body heading" checks go). Close the 2026-10-10 Decisions log
   rows. List open questions for Klas (for example: where the M0 pulse cannon mounts and what its arc is, and whether
   the top mount's 360 deg breaks the fights the drones were tuned for).
2. **Packets written 2026-10-10 (design/tasks/T22.md, T23.md); dispatch in parallel:** T22 per-weapon aim (mount arcs, traverse, fire gate, reticles,
   drone_fight and aim_range rework; gameplay-dev, with the reticles possibly split out to visuals-dev) and T23 dust
   (look plus scale by weight per leg, in scripts/fx/foot_fx.gd; visuals-dev). Their owned paths are disjoint.
   The GDD's four aim questions (section 18) are built at their defaults: cannon 180 deg/s, roof yaw 360, fire
   mid-swing, recentring paused while `fire` or `aim` is held. Klas judges them in the M0 build.
3. **M0 review** after T22 merges (criterion 5 changes with the aim): tier 3 on every scenario, code-reviewer,
   playtest-critic, then a playtest build for Klas via the playtest-build skill.
- **Later design gaps (Klas, 2026-10-10, recorded in the GDD Decisions log and section 18):** NPCs with a purpose
  instead of spawning enemies (goals, routes, natural spawn and despawn points, the word NPC, maybe a local AI model
  such as Gemma), and a story with a main goal that gives exploring a larger reason. Lead's proposal: a game-designer
  pass on both before M1 is written, since M1's enemy walker sentinel should already be an NPC with a purpose. The
  Gemma question gets its own spike.
- Merged branches stay until Klas asks to delete them.

## Tasks
Status: ready, in-progress, review-passed, done.

| Id | Title | Owned paths | Tier | Status | Branch |
|---|---|---|---|---|---|
| T00 | Input map (GDD section 6 names: turn_*, strafe_*, interact on F) + collision layers in project.godot (lead) | project.godot, test/unit/test_input_map.gd | 2 | done | main |
| T01 | WalkerBuild data, part catalog, stat formulas, validity | scripts/walker/walker_build.gd, scripts/walker/part_catalog.gd, test/unit/test_walker_build.gd | 2 | done | worktree-agent-a21795ac19081cafb, merged ada5280 |
| T02 | TwoBoneIK + GaitSolver (pure) | scripts/walker/two_bone_ik.gd, scripts/walker/gait_solver.gd, test/unit/test_two_bone_ik.gd, test/unit/test_gait_solver.gd | 2 | done | worktree-agent-ab4347227a88ecff3, merged 6c723ee |
| T03 | Walker body controller + greybox leg rig | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/test/gait_course.gd, scenes/walker/, scenes/test/gait_course.tscn, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, test/scenarios/walk_flat.json, test/scenarios/gait_course.json, test/scenarios/gait_slopes.json, test/scenarios/build_contrast.json | 3 | done | worktree-agent-ad532fa106554226e, merged adc1aa8 |
| T04 | Orbit camera rig (8 m, lag 0.10 s, zoom, aim, spring-arm collision) | scripts/camera/, scenes/camera/, test/unit/test_orbit_camera.gd, test/integration/test_orbit_camera_rig.gd, test/scenarios/camera_orbit.json | 3 | done | worktree-agent-a71d1078987d3e4d0, merged a3954ea |
| T05 | Greybox valley map (GDD 9.1): cliff bounds, wash, workshop bench, ledge + talus pockets, node and drone-site markers | scenes/world/, scripts/world/, assets/world/, test/integration/test_valley_geometry.gd, test/scenarios/valley_overview.json | 3 | done | worktree-agent-a919dedea3b3d2cd4, merged 3207acb |
| T06 | Pulse cannon, projectiles and the aim model (dot + world reticle, aim-up pitch -20), damage contract, risk 8 and 9 spikes | scripts/weapons/, scenes/weapons/, scripts/combat/, ui/aim/, scripts/test/aim_range.gd, scenes/test/aim_range.tscn, test/scenarios/aim_range.json, test/unit/test_weapon.gd, test/unit/test_aim_math.gd, test/unit/test_combat.gd, scripts/camera/orbit_camera.gd (pitch_min only), test/unit/test_orbit_camera.gd, test/scenarios/camera_orbit.json | 3 | done | feat/walkers-pulse-cannon, merged 0d76145 |
| T07 | Drone enemy: brain, hold-to-shoot telegraph, bolts, leash, encounters (lean; starts after T06 merges) | scripts/enemies/, scenes/enemies/, test/unit/test_drone_brain.gd, scripts/test/drone_fight.gd, scenes/test/drone_fight.tscn, test/scenarios/drone_fight.json | 3 | done | feat/walkers-drone, merged c961bfb |
| T08 | Salvage economy, scrap nodes, wreck cache, bank (emits `banked` for the repair), recall hold | scripts/economy/, scenes/pickups/, test/unit/test_economy.gd, scripts/test/economy_course.gd, scenes/test/economy_course.tscn, test/scenarios/economy_loop.json | 3 | done | feat/walkers-economy, merged d094bc9 |
| T09 | Workshop scene + build UI (inventory, mirrored leg pairs, stat deltas, exit reason); starts after T08 merges (Economy.spend) | scenes/workshop/, ui/workshop/, scripts/workshop/, test/unit/test_workshop.gd, test/scenarios/workshop_edit.json | 3 | done | art/walkers-workshop, merged da8819d |
| T11 | Look pass: actor toon ramp, palette materials, world bands, fog, sky, glow, grain; ledge and alcove reads (dust and decal moved to T19, outline to M1) | shaders/, assets/materials/, assets/world/, scenes/world/, scripts/world/terrain_builder.gd and valley.gd (colours), scripts/walker/walker_leg.gd (material functions only), scripts/enemies/drone.gd and drone_bolt_pool.gd (materials only), scenes/pickups/wreck_cache.tscn (crate material), test/unit/test_look.gd, test/scenarios/look_check.json | 3 | done | art/walkers-look-pass, merged b8667af |
| T18 | Walker API: socket_transform, top_mounts + draw_cannons, chassis_size/center, apply_build(allow_invalid); socket_anchors.gd and DisplayBuild go | scripts/walker/walker_body.gd, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, scripts/workshop/workshop.gd, workshop_course.gd, socket_anchors.gd, test/unit/test_workshop.gd, scripts/weapons/weapon_rig.gd, test/unit/test_weapon.gd, scripts/combat/player_hurtbox.gd, test/unit/test_combat.gd, scripts/test/*.gd and scripts/camera/view_probe.gd (walker reads only) | 3 | done | feat/walkers-walker-api, merged 7cdbc0f |
| T19 | Foot plant read: dust puff 0.2 s and contact decal fading over 2 s (GDD 10 rule 1) | scripts/fx/, scenes/fx/, assets/fx/, scenes/walker/walker.tscn (FootFx child only), test/unit/test_foot_fx.gd, test/scenarios/foot_fx.json | 3 | done | art/walkers-foot-fx, merged 475999d |
| T14 | Gate rig: orbit camera on the test course (un-bobbed anchor), steer-mode toggle, free play, pitch_low/high shots with foot boxes | scripts/test/gait_course.gd, scenes/test/gait_course.tscn, test/scenarios/gait_course.json, test/scenarios/gait_rig.json, scripts/camera/orbit_camera.gd, test/unit/test_orbit_camera.gd, scripts/walker/walker_body.gd (anchor only) | 3 | done | art/walkers-gate-rig, merged c7bc5e8 |
| T15 | Descent camera: pitch floor (slope behind - 5 deg) on steep ground, gait_camera scenario | scripts/camera/orbit_camera.gd, test/unit/test_orbit_camera.gd, test/scenarios/gait_camera.json | 3 | done | art/walkers-descent-camera, merged 6376f87 |
| T17 | View stutter: smooth camera and walker at any refresh rate, F9 frame-time readout (Klas, playtest of 1a777b6) | scripts/camera/, scenes/camera/, test/unit/test_orbit_camera.gd, test/scenarios/camera_smooth.json, autoload/dev_harness.gd (readout only) | 3 | done | fix/walkers-view-stutter, merged 38ba789 |
| T16 | Climbing: reach and haul (climb 0.9 x reach, hanging legs, step-down mirror, ledge pocket 1.2 m), gait_climb scenario | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/walker/walker_build.gd, test/unit/test_walker_build.gd, scripts/test/gait_course.gd, scenes/test/gait_course.tscn, scripts/test/valley_pockets.gd, scenes/test/valley_pockets.tscn, scripts/world/valley_layout.gd (LEDGE_RISE), test/integration/test_valley_geometry.gd, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, test/scenarios/ (gait_climb new, gait_*, walk_flat, build_contrast, valley_pockets) | 3 | done | feat/walkers-climbing, merged 2fbad22 |
| T13 | Walker controller hardening (T03 review follow-ups): face-height wall test, slide along faces, stall and cost limits, tilt smoothing, spawn resolve, valley pocket scenario | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/test/gait_course.gd, scenes/test/gait_course.tscn, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, test/scenarios/gait_slopes.json, test/scenarios/gait_talus.json, test/scenarios/walk_flat.json, test/scenarios/gait_course.json, test/scenarios/build_contrast.json, test/scenarios/gait_rig.json, new test/scenarios/gait_*.json, scripts/test/valley_pockets.gd, test/scenarios/valley_pockets.json | 3 | done | fix/walkers-walker-hardening, merged eff475a |
| T12 | Integration: game loop (boot to workshop, exit, bank at the bench, death collapse, recall, reclaim, pause), loop_full; starts after T18 merges, instances T20's HUD once merged | scenes/main.tscn, scripts/main.gd, scripts/game/, scripts/walker/walker_body.gd (collapse only), scripts/enemies/drone_field.gd (clear_all fix only), scripts/test/loop_pilot.gd, test/unit/test_game_flow.gd, test/unit/test_walker_body.gd (collapse tests), test/scenarios/loop_full.json | 3 | done | feat/walkers-game-loop, merged 49bd192 |
| T20 | Field HUD: HP bar, carried/banked scrap, compass, enter and recall prompts, toast; `bind` API for T12 | ui/hud/, scenes/test/hud_check.tscn, scripts/test/hud_check.gd, test/unit/test_field_hud.gd, test/scenarios/hud_check.json | 3 | done | art/walkers-field-hud, merged 5ff8813 |
| T21 | M0 proof runs on the real valley: map_bounds (three builds push every wall) and perf_4_drones (four drones, up-valley view, ledge-guard read) | scenes/test/valley_run.tscn, scripts/test/valley_run.gd, test/scenarios/map_bounds.json, test/scenarios/perf_4_drones.json | 3 | done | feat/walkers-proof-runs, merged 308be56 |
| T22 | Per-weapon aim: the mouse aims, roof arc, traverse by mass, fire gate, one reticle per weapon (gray at the limit), aim turn penalty off, recentring paused on fire, aim_range and drone_fight reworked | scripts/weapons/, scenes/weapons/, ui/aim/, scripts/camera/orbit_camera.gd (aim sensitivity, recentring pause), scripts/walker/walker_body.gd (aim_turn_factor only), scripts/test/aim_range.gd, scenes/test/aim_range.tscn, scripts/test/drone_fight.gd, scenes/test/drone_fight.tscn, test/scenarios/aim_range.json, test/scenarios/drone_fight.json, test/unit/test_aim_math.gd, test/unit/test_weapon.gd, test/unit/test_orbit_camera.gd, test/unit/test_walker_body.gd (aim factor only) | 3 | in-progress | feat/walkers-weapon-aim |
| T23 | Foot dust that reads as dust, sized by weight per leg (GDD 10 rule 1) | scripts/fx/, scenes/fx/, assets/fx/, test/unit/test_foot_fx.gd, test/scenarios/foot_fx.json | 3 | in-progress | art/walkers-dust |

## Notes for packets not yet written (from the T01-T05 reviews, 2026-10-09)
- Gate (lead): give the camera an un-bobbed anchor (its 0.1 s lag only half-filters the 2.8 Hz body bob). Judge
  `start_pitch` facing down-valley (the critic suggests 12-15 deg). With a fixed 1.5 m `target_offset` the Crawler's
  camera sits 0.47 m off the ground at pitch -10; consider a per-build offset. Include a walker tilted 30-39 deg in
  the feet-in-frame check (criterion 8): from behind and above, its uphill feet tuck under the chassis.
- Lead follow-ups from the T03 review: the 4-leg gait_factor stays 0.85 (the quad sustains 0.99 of its stat,
  GDD log 2026-10-09); TwoBoneIK.solve allocates a Solution per leg per tick (T02 code), so reuse one if the
  perf budget needs it. Arched knees and the shortest-leg cadence are approved (GDD log 2026-10-09) and built in
  T03 round 2.
- T03: a 4-5 leg wave with one stuck leg stands still until the player steers off (the hovering leg holds the
  only airborne slot; accepted, judge it at the gate). Turning tripods can make a leg wait about 2.5 step
  durations. Check stop/start at top speed on a tripod with real 0.25 s acceleration: the fake walker dragged a
  planted foot to 1.28 x reach. `gait_course` should also run a 4-leg build into a blocked foot.
- T15 follow-ups (code-reviewer, round 3, optional): the sight line starts from the ground under the root, not the
  lowest foot; the drop ahead has no sight test (walking down the 29 deg patch lifts the camera about 4 deg at pitch
  20); the smoothstep ease-in peaks at about 0.8 deg per frame (not asserted); the two Scout runs that stop early are
  not labelled; the decision-evidence shots gait_camera__camera_midface_p45/_p50 and gait_rig__crawler_descend_p45
  stay NEW (never baselined) and can be removed.
- T13 follow-ups: the ledge pocket alcove is too dark for actors to pop (walker pads luma 0.33-0.44 against the
  floor's 0.50; GDD 10 rule 4): a lighting fix in scenes/world/ for visuals-dev, with pad luma >= floor + 0.1 in
  `valley_pockets__scout_blocked_at_ledge`. Klas decides whether the slide keeps 100 % of the along-face speed (the
  critic recommends it) after the next playtest build.
- T17 finding (Klas, 2026-10-09, confirmed): the view stutter was Windows composing windowed apps at the main
  display's refresh. On a secondary 60 Hz screen next to a 59.99 Hz main display the whole picture judders, and
  making the playing screen the main display removes it. T17 measured the camera and walker smooth at 60-240 Hz
  and with uneven pacing. Mitigation: F11 exclusive fullscreen (T17). A display settings menu (window mode,
  vsync) belongs to M2's menu work.
- T17 follow-ups (optional, camera owner next time): restore the turn-uneven `yaw_speed_cv` check and add a unit
  test for `OrbitMath.follow`/`recenter_step` over alternating deltas; guard recentring with `_snap_frame`;
  `_measure_slopes` could take the interpolated origin in `_ease_floor` (raw in `_reset_floor`); the probe's tick-rate
  reset should read the project setting; the hitch label should print `hitch_ms`. Uneven frame pacing is covered only
  by real-hardware play (the fixed-fps tools cannot emulate it).
- T06 (aim model superseded 2026-10-10 by GDD 6, 8.3, 12 and 16 risk 8: per-weapon aim, T22): the camera dot, the weapon reticle and any HUD Control at screen centre use `mouse_filter = IGNORE`, so they
  never swallow mouse look. Aim model (gate, written 2026-10-09): GDD 6, 8.3 (convergence point Q, world-relative
  elevation -10..45, even firing phases), 12 (dot, reticle, merge pip, dashed at a limit, edge chevron) and risk 9.
  The camera's pitch minimum moves -10 -> -20 (aim-up range, spring arm shortens against the ground): a change in
  scripts/camera/ that T06 owns; the risk 9 spike is a shot at pitch -20 at a target 12 m out and 6 m up.
- T07 (its risk 8 tracker superseded 2026-10-10 by GDD 16 risk 8, T22): drones orbit at <= 6 m/s and hold still to shoot (brake within 0.1 s, hold 0.9 s, resume over 0.3 s; wind-ups
  in one encounter >= 0.4 s apart; bolt aimed at the chassis with no lead; GDD 8.4). `drone_fight` carries the risk 8
  spike as GDD 16 states it (no-lead tracker, >= 80 % of hold shots, kill within two holds; criterion 5). Keep T07
  lean (Klas, 2026-10-09: not much effort on the drone design now): build GDD 8.4 as written, no new design rounds.
- T06/T07: the walker's movement collider is the chassis box plus a 0.06 m sphere per hip (T03 round 5). Hits use a
  chassis-sized hurtbox too, so shots between the legs miss (M0 criterion 5).
- T18 follow-ups (optional): `drone.gd:206` and test_drone_brain.gd still read the walker's Chassis node (use
  `chassis_center()`); view_probe's `drawn_foot_position` reads leg child 3, so give WalkerLeg a named pad accessor.
- T19 follow-ups: 1 of 52 Strider climb plants prints 0.80 m from the drawn pad (the landing snap; FootFx could
  re-anchor to `drawn_foot_position(leg)` 0.1 s after the plant); the Crawler's prints merge into continuous treads
  (design question: should a print's life or size follow the step rate?); `demo_row`, `arm_freeze_after_plant` and
  `release_freeze` on FootFx are screenshot aids that could move to a test-only script; re-measure print and puff
  luma after T11 lands.
- T20 follow-ups: the top-centre stack (compass, toast, prompt or recall) reaches y 166 at 720p over the sky where
  drones fly; check in play that no wind-up hides under a plate; the `MarkLabel` theme-notification counter exists
  only for a test.
- T21 follow-ups (code review, deferred under playable-first): perf_4_drones checks `drones_in_view == 4` on one
  frame only; the drones orbit at 13-17.5 m at one speed and drift apart (in_view 2 at the window's end): give them
  one radius with phase offsets and assert `in_view_min >= 4` over the window; the up-valley drones circle behind
  the camera; drone-to-cliff distance has no sign; map_bounds measures the end distance to the nearest edge, not
  the pushed one, and the Strider's 2.5 m (accepted) has 4 cm margin: assert per-push closest and rebound instead.
  Walker bugs for the climbing follow-ups: the Crawler hangs at the ledge-alcove mouth (-100.3, 196.3) and ignores
  S (`MAPBOUNDSTUCK build=crawler point=e22_0 kind=diag45`); a Scout jammed on the 40 deg talus slope at wall
  (105, 164) before the start-level rule hid it. Valley data: the ledge-guard DroneSite is 16 m from the west wall
  (rule: 20 m).
- T11 follow-ups (deferred under playable-first): the accent lit band (#FFB191) drifts about 6 deg toward the threat
  hue; the drone wind-up peak (0.49) sits near the sky (0.61) in grayscale, so the telegraph fades into the sky
  (game-designer, M0 criterion 8); scrap and bolt bloom not yet seen in a valley shot; grain may be too faint
  (Klas's eye); pads vs the wash and dark ground lose luma contrast (Klas, 2026-10-10: no cue now, judge in play).
- Walker API (done as T18; the block-layout table and fixed slots wait for M1), from the T06 and T09 hand-backs:
  - `socket_transform(socket_id)` for all 8 leg and 3 top sockets, at fixed slots, read from a block-layout table
    (the 4 x 2 build of GDD 8.1, socket id = block cell + face, today's ids kept as aliases) so M1 adds blocks with
    no API change; M0 keeps today's socket positions and plays as built;
    - today the hips re-space by how many legs are mounted, so a free socket has no position;
    - T09's socket_anchors.gd and T06's Tops reading go away;
  - `top_mounts()` plus a `draw_cannons` flag, so WeaponRig stops hiding the Tops children;
  - `chassis_size()` and its offset, so PlayerHurtbox stops reading the Chassis mesh;
  - a way to draw an invalid build in the workshop (`apply_build(build, allow_invalid)`), so T09's DisplayBuild
    subclass goes away;
  - `stats()["climb"]`, if T16 does not add it.
- T08 follow-ups (playtest-critic, optional, after the merge):
  - node value reads by ring: the crystal cluster grows with `amount` (a new GDD 10 rule, game-designer first);
  - a findable wreck cache: a brighter beam and a crate that splits from the sand by luma. The orange "your stuff"
    cache colour needs a GDD 10 entry;
  - the "node every 15-25 s" pacing row needs a measurable definition (game-designer);
  - straight-line from the workshop to the first drone site is about 31 s against the 45-75 s target, so T07/T12
    measure it with real walking;
  - T12 adds a shot of the talus pocket beam from the wash at about 100 m.
- T11: the valley ledge face and the cliff wall share one luma (0.277 vs 0.284), and the pocket floor matches the
  valley floor, so the 1.2 m gate reads only by its silhouette. Add a lit band on the ledge lip (T16 critique).
- T12 wiring notes from the T06, T08 and T09 reviews:
  - **Workshop:**
    - `setup(build, inventory, economy)` works before or after add_child and edits build and inventory in place.
    - `exit_requested(build)` fires once per visit with that very build, never while it is invalid; then the
      workshop ignores input until the next `setup()`.
    - After exit, free the workshop or disable and hide it, and make the field camera current: it brings its own
      Camera3D, WorldEnvironment and two lights (one on render layer 2).
    - Capture the mouse when the field starts.
    - The workshop owns its walker. Never put the field walker in it; turning the field walker's input off and back
      on is T12's job.
    - Climb on any HUD comes from `BuildStats.of()`.
  - **Economy:** connect `Economy.banked` to `Health.repair_full()` and the drone respawn. The Collector's
    `enabled = false` during the death collapse and true after respawn; `RecallHold.recall_requested` goes to
    `economy.recall(position)` plus the move home.
  - **Combat:**
    - PlayerHurtbox is safe before its walker is ready.
    - Enemy projectile queries on layer 2 use areas only.
    - `impacted` carries `counted`.
    - Keep the bottom-right 40 px around the edge chevron free of HUD.
  - **Drones (T07):**
    - Spawn: `DroneField.target = walker`, then `spawn_sites()`; connect `Economy.banked` to `respawn_all()`.
    - `shot_fired` can arrive up to 0.6 s after `died` (a falling husk still fires). A bolt's `source` can be a husk,
      or null once that drone is freed.
    - Scrap drops when the husk lands (0.7-1.1 s after `died`); a respawn in between loses it.
    - Loose scrap survives `respawn_all` and is removed by `clear_all`. `clear_all` does not yet disable pending
      husks: copy the `ai_enabled` / `auto_step` disable from `DroneEncounter.clear()`.
    - Drones have no world collision. Keep DroneSite markers >= 20 m from cliff faces and run drone_fight on the real
      valley (`perf_4_drones`); a terrain-aware orbit is the follow-up if they still clip.
    - Feedback on the player: listen to `PlayerHurtbox.hit_taken` for the rim flash and shake.
    - Juice pass: a bolt-in-flight shot with bolt readability (>= 8 px, >= 0.3 luma against sky and ground).
  - **T11 look pass:** the workshop's camera-mounted chassis light in motion, and the field walker's hull and leg
    tones; the Load "!" may need a row tint.
- Climbing follow-ups (T16 closed at round 7: Klas played ee9ad87 and called it good enough, 2026-10-09; revisit
  later, not in M0):
  - Landing jumps: the drawn pad jumps at touchdown, up to 1.4 m on the Strider (`max_landing_snap_m`,
    `max_landing_slide_m`, reported). The reach branch of `_fit_landing` moves pads between levels; a level-safe
    fit deadlocks tall descents (a rear leg at full reach on the deck needs a margin shift its own reach forbids).
    Needs a design call first: let the support shift count a swinging leg's landing, or let that leg step first.
  - Stride swings clip lips (`pad_inside_stride_ticks`, reported); climb swings read 1-4 `pad_inside_ticks` in four
    runs (asserted at those values).
  - The shin clips the lip corner during a reach (the knee is over the top while the pad is still below it;
    `gait_climb_shots__reach_p55` is its baseline). Add a shin-segment geometry test.
  - A ledge edge met at more than 45 deg stops with the feet hanging instead of sliding along (GDD 5 "Approach
    angle"); no scenario covers it.
  - `_line_return` acts while a leg hangs, against its doc comment; the 0.5 m sideways sway needs a playtest look.
  - Strafing into a ledge meets it side-on (the 45 deg rule measures the heading), so the walker slides along
    instead of climbing; Klas may want strafing to climb.
- Leg-count assumptions in code, for the M1 block chassis (T16 round 7 hand-back, file:line at f1236f1):
  `gait_solver.gd:47-58` (two halves for 6+ legs, a wave below); `walker_body.gd:1287` (`group_count() > 2` cadence);
  `walker_build.gd:21,182` (`FOUR_LEGS` gait factor 0.85); `walker_body.gd:485` (default `WalkerBuild.scout()`);
  `walker_body.gd:1217, 1271-1272` (front leg = first per side, row neighbours by index); `walker_body.gd:1625, 1628,
  3265, 3330` (planes and support need >= 3 planted feet); `gait_course.gd:775, 1316, 1928` (`leg_reach(0)` as the
  build's reach).
- Same-side pad overlap (T13 item 10 / T16 item 6, open): pads still stack on one spot during some climbs and turns (the metric reads its -0.34 floor). The proposals measured cost 13-26 % of flat speed, so none was adopted; revisit with the walker API task or at the M1 climber leg.
- T07: the ledge-guard drone site sits in the west wall's shadow strip; check the fight reads there.
- T08: pocket pickups at least 0.5 m tall or with a vertical beam (the talus scrap sits behind a 4.1 m lip).
- T09: a vertical home landmark on the bench, at least 20 m tall (toward_home has nothing to steer to).
- T11: harden the wash (threshold the vertex-colour weight into a flat band), soft smoke with fog back on, sage
  sky top; `assets/world/ground_streak.tres` is unused and can go.
  In grayscale the orange foot tops sit only 0.08 luma below the floor (0.61 vs 0.69); give the contact decal a dark value.
  On the T03 course, lit pads (#F38741, luma 0.60) match the dark ground stripes (0.60-0.63), so pads read by hue
  alone. Klas decides at the gate, from the pitch shots, whether pads need a luminance cue before the M1 outline.
- T12: `%WashPath` starts at (2, 8) in front of the workshop; `perf_4_drones` should also measure a ring-2 view
  looking up-valley.
