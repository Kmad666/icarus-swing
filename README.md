# Icarus Swing

A third-person PS1-style grapple-hook game in **Godot 4.7** — point, click, swing, fly. Inspired by Verlet Swing. Placeholder low-poly art built in code for now.

**Play in your browser:** https://kmad666.github.io/icarus-swing/

## Where it's headed
A chibi thief heroine swinging across a fantasy medieval city at night, in a PS1 style: low-poly, low resolution, no anti-aliasing. Platforming to collect loot, solve puzzles and reach places you can't get to on foot. Grapple points are hanging lanterns: dark iron cages with a glowing flame, so they stand out in the dark.

**Right now** the game loads a small test district: a cobbled street lined with half-timbered houses, a bell tower at the far end, and about 50 lanterns on posts, wall brackets and lines strung between the rooftops.

## Controls
| Input | Action |
|---|---|
| Mouse | Orbit camera / turn |
| Hold **Left Click** | Fire grapple. **Only lanterns can be hooked.** Of the lanterns inside the circle reticle (within 70 m and not behind a wall), the nearest one brightens and is where the hook goes. You get **3 grapples in the air** (pips under the reticle); landing refills them. |
| Release Left Click | Let go; at speed you get a +15% release boost |
| **WASD** | Walk / air-steer; while hooked, push toward where the camera looks (up and down too) |
| **Space** | Jump; while hooked, hold to reel in |
| Space / Right Click / E / Wheel Up | Reel in |
| **Shift** | Dash: snaps your momentum toward where the camera looks (1.2 s cooldown) |
| Q / Ctrl / Wheel Down | Reel out |
| **1 / 2 / 3** | Switch physics preset (also in the pause menu) |
| **R** | Restart run |
| Esc | Pause |

## Physics presets
Pick one in the pause menu (Esc) or press 1/2/3 any time. Your choice is saved. **Bungee is the default.** Top speed is capped at 75 on the speedometer; dashes and release boosts can briefly push past it (up to ~97) before bleeding back down. The camera pulls back as you speed up, and an orange trail shows your arc.

1. **Float** — no gravity while hooked; you drift on your momentum and the rope just limits how far you go.
2. **Light Arc** — 25% gravity while hooked, for slow, gentle pendulum swings.
3. **Bungee** — the rope pulls you toward the hook like a stretchy band, with 60% gravity. Fast and slingy.

## How the rope works
`scripts/player.gd` treats the rope as a Verlet distance constraint: each physics tick it predicts where gravity and momentum would carry you, and if that's past the rope length it projects the point back onto the rope's sphere and derives velocity from the correction. You get real pendulum swings, and reeling in pumps speed.

## The PS1 look
- The 3D world renders at 240 lines tall into a low-res viewport and is scaled up with sharp, nearest-neighbour pixels. The HUD stays crisp on top.
- `shaders/ps1.gdshader`: per-vertex lighting, wobbly snapped vertices, warped (affine) textures, 32×32 nearest-filtered textures.
- `shaders/ps1_post.gdshader`: 15-bit colour with a 4×4 ordered dither.
- Thick blue night fog; lantern flames and halos cut through it.
- Static scenery is merged by material into a few dozen meshes to keep draw calls low on integrated graphics.

## Project layout
- `scripts/main.gd` — low-res viewport, night setting, test district builder, HUD
- `scripts/player.gd` — third-person controller, lantern targeting, grapple, physics presets
- `scripts/heroine.gd` — the heroine: round lavender-haired chibi head with glowing sleepy eyes, cone cloak, pointed ballet legs; code-driven animation (idle head-tilt, tip-toe run, jump tuck, fall, swing stance with one leg raised and bent, blinking, surprised eyes on long falls, cloak hem flutter)
- `scripts/lantern.gd` — hanging lantern: iron cage, flickering flame, light, glow halo
- `scripts/ps1.gd` — shared PS1 materials and procedural textures
- `scripts/reticle.gd` — circle reticle
- `.github/workflows/deploy.yml` — every push to `main` exports for web and publishes to GitHub Pages (`gh-pages` branch)

