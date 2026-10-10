# walkers - playtest build

## Run it
Unzip anywhere and run `walkers.exe`. Windows SmartScreen may warn about an unknown app: click
"More info", then "Run anyway". F11 switches to exclusive fullscreen (smoothest picture), F9 shows frame times.

## Keys
| Key | What it does |
|---|---|
| W / S | walk forward / back along the body's facing |
| A / D | turn the body |
| Q / E | strafe sideways |
| Mouse | move the camera; the screen centre dot is where you aim |
| LMB (hold) | fire every gun whose ring is live (orange) |
| RMB (hold) | zoom in for fine aim (no longer slows the turn) |
| Mouse wheel | camera distance |
| F | enter the workshop (within 4 m of the bench); hold 3 s anywhere to recall home |
| Workshop: LMB / RMB / Tab | place a part / remove a part / leave |
| Esc | pause |

## What changed since the last build (walkers-playtest-20261010-1224)
- **Aim follows the mouse.** Every gun swings toward the dot by itself, as fast as its weight allows. The 40 kg
  pulse cannon takes about half a second for a quarter turn; turning the body toward the target with A/D gets it
  there about a third faster.
- **One ring per gun.** Each ring shows where that gun's shot goes right now, so it trails the dot while the gun
  swings. A gray dashed ring means that gun cannot reach the dot from its mount (aim at your own feet to see it);
  it stays silent until the dot is back in reach.
- **Dust.** Each foot plant kicks up soft, sandy dust that settles over most of a second instead of a white blob.
  Its size follows the walker's weight per leg, so a heavy, short-legged build kicks up more than a light,
  long-legged one.

## Try in the first 5 minutes
1. Walk out with the Scout. Watch the feet: does the dust read as dust?
2. Find a drone. Keep the dot on it and fire; then try turning into it with A/D while the gun swings.
3. Look down at your own feet and fire: the ring should go gray and the gun stay silent.
4. Walk while aiming at the ground just ahead of your feet: does a ring flicker between orange and gray?
5. In the workshop, make the walker heavier per leg (remove a leg pair, or add a second cannon; the exit tells you
   if the build is too heavy to leave) and walk it again: is its dust bigger?

## Questions for you
- Does the dust read as dust, and does a heavier foot kick up more?
- Did you turn the body in fights, and did it help? Were the fights too easy?
- Is the cannon's half-second swing right, or should small guns feel near-instant?
- Anything about the rings that confused you (the dot, gray rings, the edge arrow)?
