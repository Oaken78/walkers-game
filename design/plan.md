# walkers - production plan

Edited only by the lead, on `main`. Packets live in `design/tasks/<id>.md` (see `docs/task-template.md`).
Source of truth for numbers: `design/gdd.md` (section refs in brackets).

## Milestones
| Id | Name | Acceptance criteria (measurable) | Proof (scenarios / screenshots) | Status |
|---|---|---|---|---|
| M0 | Playable loop | 1. Scout walks at 4.5 m/s +/- 0.1, reaching it in 0.25 s +/- 0.05 [5]. 2. Planted foot drift <= 2 cm per step and airborne legs (swinging or hanging) never above the gait limit over 20 s on the 30 deg bumpy course and through the climb lane; while any leg hangs, the centre of mass stays inside the planted feet's polygon by >= 0.1 x mean reach; on the bumps no leg hangs or reaches up [5, 8.2]. 3. Strider A vs Crawler B: (A - B) / A >= 40 % in top speed and in climb height measured on the ledges lane (expected 1.44 vs 0.54 m, 0.625), with neither stat clamped, and B's DPS x HP >= 1.8x A's [4, 8.1]. 4. Workshop: place and remove a part, see the stat delta, exit is blocked with a reason while the build is invalid [8.6]. 5. Drone telegraphs >= 0.6 s before every shot, dies in 3 hits and holds still for 0.9 s of each 1.5 s cycle; a strafing Scout takes <= 40 % of the damage an idle Scout takes; weapon yaw equals the body heading within 0.1 deg on every tick, and with a drone on the heading the shot lands within 0.5 deg of the camera aim point; every M0 reference build brings its heading onto a drone 90 deg off in <= 1.0 s, and a no-lead tracker hits >= 80 % of shots fired during holds and kills within two holds with the Scout and with the Crawler [5, 8.3, 8.4, 16]. 6. Full loop: collect scrap, bank (full repair), buy a part, socket it, die, wreck cache dropped, reclaim it, with no scrap duplicated. The first purchase happens on expedition 1-2, and the Strider reaches the 1.2 m ledge pocket by reaching and hauling, while the Scout's front legs paw at the face and it cannot climb it [7, 8.2, 8.5, 9]. 7. Tier 3 green: 0 log errors, frame p95 <= 16.7 ms, draw calls <= 1000 with 4 drones on screen [13]. 8. At 8 m and pitch -10 to 60 deg every foot is in frame and >= 12 px tall at 1080p (the -20 to -10 aim-up range is exempt); the drone wind-up reads in grayscale; the camera dot and weapon reticle read in grayscale, and the edge chevron shows whenever the reticle is off screen [6, 10, 12]. 9. Valley (GDD 9.1): every cliff sample >= 30 m and >= 60 deg; no build leaves the valley floor (max climb 1.44 m); only the Strider reaches the 1.2 m ledge pocket and only the Crawler the talus pocket; every build that climbs into a pocket climbs back down out of it [9.1, 8.2]. | Scenarios: `walk_flat`, `gait_course`, `build_contrast`, `workshop_edit`, `drone_fight`, `loop_full`, `map_bounds`, `perf_4_drones`. Test: `test_valley_geometry.gd`. Screenshots: `gait_course__midstride`, `gait_course__pitch_low`, `gait_course__pitch_high`, `build_contrast__a_vs_b`, `workshop_edit__stats`, `drone_fight__windup`, `drone_fight__windup_gray`, `drone_fight__reticle_offset`, `drone_fight__aim_up`, `loop_full__hud` | planned |
| M1 | Vertical slice | Defined after the M0 review: uneven leg builds, blueprints (2-3 per zone), 2nd zone and terrain gate, enemy walker sentinel, 5 legs and 5 top parts, footstep audio, final toon shading, a flatter chassis so the arched knees peak above it [9, 14] | tbd | planned |
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
- Cut first if scope slips: the armor plate, then the compass. The ink outline is already moved to M1.

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
| T06 | Pulse cannon, projectiles and the aim model (dot + world reticle, aim-up pitch -20), damage contract, risk 8 and 9 spikes | scripts/weapons/, scenes/weapons/, scripts/combat/, ui/aim/, scripts/test/aim_range.gd, scenes/test/aim_range.tscn, test/scenarios/aim_range.json, test/unit/test_weapon.gd, test/unit/test_aim_math.gd, test/unit/test_combat.gd, scripts/camera/orbit_camera.gd (pitch_min only), test/unit/test_orbit_camera.gd | 3 | in-progress | feat/walkers-pulse-cannon |
| T07 | Drone enemy: state machine, telegraph, leash | scripts/enemies/, scenes/enemies/, test/unit/test_drone_brain.gd, test/scenarios/drone_fight.json | 3 | | |
| T08 | Salvage economy, scrap nodes, wreck cache, bank (emits `banked` for the repair), recall hold | scripts/economy/, scenes/pickups/, test/unit/test_economy.gd, scripts/test/economy_course.gd, scenes/test/economy_course.tscn, test/scenarios/economy_loop.json | 3 | done | feat/walkers-economy, merged d094bc9 |
| T09 | Workshop scene + build UI (inventory, mirrored leg pairs, stat deltas, exit reason); starts after T08 merges (Economy.spend) | scenes/workshop/, ui/workshop/, scripts/workshop/, test/unit/test_workshop.gd, test/scenarios/workshop_edit.json | 3 | in-progress | art/walkers-workshop |
| T11 | Toon ramp + palette materials, dust puff + contact decal (outline moved to M1) | shaders/, assets/materials/ | 3 | | |
| T14 | Gate rig: orbit camera on the test course (un-bobbed anchor), steer-mode toggle, free play, pitch_low/high shots with foot boxes | scripts/test/gait_course.gd, scenes/test/gait_course.tscn, test/scenarios/gait_course.json, test/scenarios/gait_rig.json, scripts/camera/orbit_camera.gd, test/unit/test_orbit_camera.gd, scripts/walker/walker_body.gd (anchor only) | 3 | done | art/walkers-gate-rig, merged c7bc5e8 |
| T15 | Descent camera: pitch floor (slope behind - 5 deg) on steep ground, gait_camera scenario | scripts/camera/orbit_camera.gd, test/unit/test_orbit_camera.gd, test/scenarios/gait_camera.json | 3 | done | art/walkers-descent-camera, merged 6376f87 |
| T17 | View stutter: smooth camera and walker at any refresh rate, F9 frame-time readout (Klas, playtest of 1a777b6) | scripts/camera/, scenes/camera/, test/unit/test_orbit_camera.gd, test/scenarios/camera_smooth.json, autoload/dev_harness.gd (readout only) | 3 | done | fix/walkers-view-stutter, merged 38ba789 |
| T16 | Climbing: reach and haul (climb 0.9 x reach, hanging legs, step-down mirror, ledge pocket 1.2 m), gait_climb scenario | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/walker/walker_build.gd, test/unit/test_walker_build.gd, scripts/test/gait_course.gd, scenes/test/gait_course.tscn, scripts/test/valley_pockets.gd, scenes/test/valley_pockets.tscn, scripts/world/valley_layout.gd (LEDGE_RISE), test/integration/test_valley_geometry.gd, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, test/scenarios/ (gait_climb new, gait_*, walk_flat, build_contrast, valley_pockets) | 3 | in-progress | feat/walkers-climbing |
| T13 | Walker controller hardening (T03 review follow-ups): face-height wall test, slide along faces, stall and cost limits, tilt smoothing, spawn resolve, valley pocket scenario | scripts/walker/walker_body.gd, scripts/walker/walker_leg.gd, scripts/walker/walker_telemetry.gd, scripts/test/gait_course.gd, scenes/test/gait_course.tscn, test/unit/test_walker_body.gd, test/integration/test_walker_rig.gd, test/scenarios/gait_slopes.json, test/scenarios/gait_talus.json, test/scenarios/walk_flat.json, test/scenarios/gait_course.json, test/scenarios/build_contrast.json, test/scenarios/gait_rig.json, new test/scenarios/gait_*.json, scripts/test/valley_pockets.gd, test/scenarios/valley_pockets.json | 3 | done | fix/walkers-walker-hardening, merged eff475a |
| T12 | Integration: main flow, death/respawn, field HUD, loop + perf scenarios | scenes/main.tscn, scripts/main.gd, ui/hud/, test/scenarios/loop_full.json, test/scenarios/map_bounds.json, test/scenarios/perf_4_drones.json | 3 | | |

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
- T06: the camera dot, the weapon reticle and any HUD Control at screen centre use `mouse_filter = IGNORE`, so they
  never swallow mouse look. Aim model (gate, written 2026-10-09): GDD 6, 8.3 (convergence point Q, world-relative
  elevation -10..45, even firing phases), 12 (dot, reticle, merge pip, dashed at a limit, edge chevron) and risk 9.
  The camera's pitch minimum moves -10 -> -20 (aim-up range, spring arm shortens against the ground): a change in
  scripts/camera/ that T06 owns; the risk 9 spike is a shot at pitch -20 at a target 12 m out and 6 m up.
- T07: drones orbit at <= 6 m/s and hold still to shoot (brake within 0.1 s, hold 0.9 s, resume over 0.3 s; wind-ups
  in one encounter >= 0.4 s apart; bolt aimed at the chassis with no lead; GDD 8.4). `drone_fight` carries the risk 8
  spike as GDD 16 states it (no-lead tracker, >= 80 % of hold shots, kill within two holds; criterion 5). Keep T07
  lean (Klas, 2026-10-09: not much effort on the drone design now): build GDD 8.4 as written, no new design rounds.
- T06/T07: the walker's movement collider is the chassis box plus a 0.06 m sphere per hip (T03 round 5). Hits use a
  chassis-sized hurtbox too, so shots between the legs miss (M0 criterion 5).
- Walker API (after T16 merges, one small task owning walker_body.gd): the read-only hooks T06 and T09 ask for (top-socket and
  leg-socket transforms, a flag to skip drawing cannons, a switch that stops field input on the workshop stand).
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
