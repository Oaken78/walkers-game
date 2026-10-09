# walkers - production plan

Edited only by the lead, on `main`. Packets live in `design/tasks/<id>.md` (see `docs/task-template.md`).
Source of truth for numbers: `design/gdd.md` (section refs in brackets).

## Milestones
| Id | Name | Acceptance criteria (measurable) | Proof (scenarios / screenshots) | Status |
|---|---|---|---|---|
| M0 | Playable loop | 1. Scout walks at 4.5 m/s +/- 0.1, reaching it in 0.25 s +/- 0.05 [5]. 2. Planted foot drift <= 2 cm per step and airborne legs never above the gait limit over 20 s on the 30 deg bumpy course [5, 8.2]. 3. Strider A vs Crawler B: (A - B) / A >= 40 % in top speed and step-up with neither stat clamped, and B's DPS x HP >= 1.8x A's [4, 8.1]. 4. Workshop: place and remove a part, see the stat delta, exit is blocked with a reason while the build is invalid [8.6]. 5. Drone telegraphs >= 0.6 s before every shot and dies in 3 hits; a strafing Scout takes <= 40 % of the damage an idle Scout takes [5, 8.4]. 6. Full loop: collect scrap, bank (full repair), buy a part, socket it, die, wreck cache dropped, reclaim it, with no scrap duplicated. The first purchase happens on expedition 1-2, and the Strider reaches the 0.8 m ledge pocket while the Scout cannot [7, 8.5, 9]. 7. Tier 3 green: 0 log errors, frame p95 <= 16.7 ms, draw calls <= 1000 with 4 drones on screen [13]. 8. At 8 m and pitch -10 to 60 deg, every foot is in frame and >= 12 px tall at 1080p; the drone wind-up reads in grayscale [10]. 9. Valley (GDD 9.1): every cliff sample >= 30 m and >= 60 deg; no build leaves the valley floor; only the Strider reaches the ledge pocket and only the Crawler the talus pocket [9.1]. | Scenarios: `walk_flat`, `gait_course`, `build_contrast`, `workshop_edit`, `drone_fight`, `loop_full`, `map_bounds`, `perf_4_drones`. Test: `test_valley_geometry.gd`. Screenshots: `gait_course__midstride`, `gait_course__pitch_low`, `gait_course__pitch_high`, `build_contrast__a_vs_b`, `workshop_edit__stats`, `drone_fight__windup`, `drone_fight__windup_gray`, `loop_full__hud` | planned |
| M1 | Vertical slice | Defined after the M0 review: uneven leg builds, blueprints (2-3 per zone), 2nd zone and terrain gate, enemy walker sentinel, 5 legs and 5 top parts, footstep audio, final toon shading [9, 14] | tbd | planned |
| M2 | Content | 3 zones, all parts, gamepad, menu, save/load [14] | tbd | planned |

## M0 order
- T00 (lead) first.
- Then T01, T02 and T05 in parallel. T03 (which owns its own test course) and T04 start after T01 and T02
  merge.
- **Gate:** after T03 and T04, the lead puts T04's rig into `gait_course` (with `WalkerBody.yaw_source` for the
  fallback) and adds the `gait_course__pitch_low` / `__pitch_high` shots. Then run `gait_course` and
  `build_contrast` plus a playtest-critic pass, and Klas
  plays the tank controls (fallback: body turns to camera yaw). If risk 1, 2 or 3 from GDD section 16 fails, stop and redesign before content work.
- After the gate: T06, T07, T08 and T09 (max 3 devs at once). Then T11. T12 integrates last, including the HUD.
- Cut first if scope slips: the armor plate, then the compass. The ink outline is already moved to M1.

## Tasks
Status: ready, in-progress, review-passed, done.

| Id | Title | Owned paths | Tier | Status | Branch |
|---|---|---|---|---|---|
| T00 | Input map (GDD section 6 names: turn_*, strafe_*, interact on F) + collision layers in project.godot (lead) | project.godot, test/unit/test_input_map.gd | 2 | done | main |
| T01 | WalkerBuild data, part catalog, stat formulas, validity | scripts/walker/walker_build.gd, scripts/walker/part_catalog.gd, test/unit/test_walker_build.gd | 2 | done | worktree-agent-a21795ac19081cafb, merged ada5280 |
| T02 | TwoBoneIK + GaitSolver (pure) | scripts/walker/two_bone_ik.gd, scripts/walker/gait_solver.gd, test/unit/test_two_bone_ik.gd, test/unit/test_gait_solver.gd | 2 | done | worktree-agent-ab4347227a88ecff3, merged 6c723ee |
| T03 | Walker body controller + greybox leg rig | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/test/gait_course.gd, scenes/walker/, scenes/test/gait_course.tscn, test/unit/test_walker_body.gd, test/scenarios/walk_flat.json, test/scenarios/gait_course.json, test/scenarios/build_contrast.json | 3 | in-progress | worktree-agent-ad532fa106554226e |
| T04 | Orbit camera rig (8 m, lag 0.10 s, zoom, aim, spring-arm collision) | scripts/camera/, scenes/camera/, test/unit/test_orbit_camera.gd, test/integration/test_orbit_camera_rig.gd, test/scenarios/camera_orbit.json | 3 | done | worktree-agent-a71d1078987d3e4d0, merged a3954ea |
| T05 | Greybox valley map (GDD 9.1): cliff bounds, wash, workshop bench, ledge + talus pockets, node and drone-site markers | scenes/world/, scripts/world/, assets/world/, test/integration/test_valley_geometry.gd, test/scenarios/valley_overview.json | 3 | done | worktree-agent-a919dedea3b3d2cd4, merged 3207acb |
| T06 | Pulse cannon + projectiles (top socket part) | scripts/weapons/, scenes/weapons/, test/unit/test_weapon.gd | 3 | | |
| T07 | Drone enemy: state machine, telegraph, leash | scripts/enemies/, scenes/enemies/, test/unit/test_drone_brain.gd, test/scenarios/drone_fight.json | 3 | | |
| T08 | Salvage economy, scrap nodes, wreck cache, repair on bank, recall | scripts/economy/, scenes/pickups/, test/unit/test_economy.gd | 3 | | |
| T09 | Workshop scene + build UI | scenes/workshop/, ui/workshop/, scripts/workshop/, test/scenarios/workshop_edit.json | 3 | | |
| T11 | Toon ramp + palette materials, dust puff + contact decal (outline moved to M1) | shaders/, assets/materials/ | 3 | | |
| T12 | Integration: main flow, death/respawn, field HUD, loop + perf scenarios | scenes/main.tscn, scripts/main.gd, ui/hud/, test/scenarios/loop_full.json, test/scenarios/map_bounds.json, test/scenarios/perf_4_drones.json | 3 | | |

## Notes for packets not yet written (from the T01-T05 reviews, 2026-10-09)
- Gate (lead): give the camera an un-bobbed anchor (its 0.1 s lag only half-filters the 2.8 Hz body bob). Judge
  `start_pitch` facing down-valley (the critic suggests 12-15 deg). With a fixed 1.5 m `target_offset` the Crawler's
  camera sits 0.47 m off the ground at pitch -10; consider a per-build offset.
- Lead follow-ups from the T03 review: set the 4-leg gait_factor in GDD 8.1 and walker_build.gd from T03's
  measured quad speed; TwoBoneIK.solve allocates a Solution per leg per tick (T02 code), so reuse one if the
  perf budget needs it. Pending design: the game-designer proposes arched-knee proportions; Klas approves first.
- T03: a 4-5 leg wave with one stuck leg stands still until the player steers off (the hovering leg holds the
  only airborne slot; accepted, judge it at the gate). Turning tripods can make a leg wait about 2.5 step
  durations. Check stop/start at top speed on a tripod with real 0.25 s acceleration: the fake walker dragged a
  planted foot to 1.28 x reach. `gait_course` should also run a 4-leg build into a blocked foot.
- T06: the crosshair and any HUD Control at screen centre use `mouse_filter = IGNORE`, so they never swallow mouse look.
- T06/T07: the walker's movement collider is a wide cylinder (about 4 m across on the Strider). Hits use a
  chassis-sized hurtbox instead, so shots between the legs miss (M0 criterion 5).
- T07: the ledge-guard drone site sits in the west wall's shadow strip; check the fight reads there.
- T08: pocket pickups at least 0.5 m tall or with a vertical beam (the talus scrap sits behind a 4.1 m lip).
- T09: a vertical home landmark on the bench, at least 20 m tall (toward_home has nothing to steer to).
- T11: harden the wash (threshold the vertex-colour weight into a flat band), soft smoke with fog back on, sage
  sky top; `assets/world/ground_streak.tres` is unused and can go.
  In grayscale the orange foot tops sit only 0.08 luma below the floor (0.61 vs 0.69); give the contact decal a dark value.
- T12: `%WashPath` starts at (2, 8) in front of the workshop; `perf_4_drones` should also measure a ring-2 view
  looking up-valley.
