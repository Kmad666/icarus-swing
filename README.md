# Icarus Swing

A third-person grapple-hook swinging game in **Godot 4.7** — point, click, swing, fly. Inspired by Verlet Swing. All art is placeholder shapes for now.

**Play in your browser:** https://kmad666.github.io/icarus-swing/

## Goal
**Right now the game loads a flat test field** with grapple targets scattered in the air, for tuning the physics. The lava course below is still in the code (`_build_level()` in `scripts/main.gd`).

Swing across the lava sea through three sections and reach the golden beacon on the summit tower. Grab the cyan rings for bonus points, beat your best time.

1. **Pillar Slalom** — T-shaped columns with arms hanging over the path
2. **Beam Run** — overhead bars at alternating heights
3. **Moons** — floating spheres, then reel yourself up to the gold block above the summit

Green platforms are checkpoints. Falling into the lava sends you back to the last one.

## Controls
| Input | Action |
|---|---|
| Mouse | Orbit camera / turn |
| Hold **Left Click** | Fire grapple & swing (crosshair turns green when in range, 70 m) |
| Release Left Click | Let go, keep momentum (gravity is off while hooked) |
| **WASD** | Walk / air-steer / pump your swing |
| **Space** | Jump; while hooked, hold to reel in |
| Space / Right Click / Shift / E / Wheel Up | Reel in |
| Q / Ctrl / Wheel Down | Reel out |
| **1 / 2 / 3** | Switch physics preset (also in the pause menu) |
| **R** | Restart run |
| Esc | Pause |

Tip: grab things *above and ahead* of you. A rope on a wall just swings you into the wall.

## Physics presets
Pick one in the pause menu (Esc) or press 1/2/3 any time. Your choice is saved.

1. **Float** — no gravity while hooked; you drift on your momentum and the rope just limits how far you go.
2. **Light Arc** — 25% gravity while hooked, for slow, gentle pendulum swings.
3. **Bungee** — the rope pulls you toward the hook like a stretchy band, with 60% gravity. Fast and slingy.

## How the rope works
`scripts/player.gd` treats the rope as a Verlet distance constraint: each physics tick it predicts where gravity and momentum would carry you, and if that's past the rope length it projects the point back onto the rope's sphere and derives velocity from the correction. You get real pendulum swings, and reeling in pumps speed.

## Project layout
- `scripts/main.gd` — builds the course, HUD, checkpoints, rings, goal, timer
- `scripts/player.gd` — first-person controller + grapple
- `.github/workflows/deploy.yml` — every push to `main` exports for web and publishes to GitHub Pages (`gh-pages` branch)

## Setup note
After the first push, in the repo go to **Settings → Pages** and set the source to **Deploy from a branch → `gh-pages` / root**.
