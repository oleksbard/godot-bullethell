# CLAUDE.md

Guidance for Claude Code (and humans) working in this repository. This file is
the **hub**: what the project is, how to run it, and the load-bearing rules —
detail lives in the linked guideline docs under [`docs/guidelines/`](docs/guidelines/).

## What this is

A **Godot 4.7** (Forward+) **3D top-down arena survival shooter**: a marine on a
hell island floating in the void fights **auto-spawned waves of demons**, the
marine **auto-fires** its equipped weapons, and you collect loot between waves —
**Doom × Brotato × loot-game**. Camera is **top-down orthographic**; movement is
**WASD**. The world (island, rocks) is **procedural** beveled-box geometry; the
**marine is an imported rigged glb** (`models/marine_01.glb`) animated from code.
The sibling `../godot-prototype` is the source of these conventions and the
reused `src/lib/` utilities.

**Status:** marine (WASD) on the hell island. It holds two pistols, one per hand;
each whole arm swings (with a little lag) to aim at the nearest imp on *its* half
(right hand → right side, left → left side, so the arms never cross), with the gun
fixed in the hand so it never twists on its own. A hand with no imp on its side
rests down. The body only turns *while moving*, toward the midpoint between its two
targets, so it stays centred with the arms splayed evenly; WASD strafes/backpedals
and the legs reverse their swing when moving backward. Guns 3–12 (if equipped)
float around it and self-aim at the i-th closest, as before. Guns auto-fire
bolts at the closest imps; imps spawn in doubling waves (15 → 30 → …), dying into
gib chunks + blood decals; off-screen imps are flagged on the screen border. Next
up: real gun/imp models, player health/damage. Specs: `docs/superpowers/specs/`.

## Commands

```sh
./play.sh    # run the game (auto-detects Godot; GODOT=/path overrides)
./edit.sh    # open in the editor

# Headless validation — load the project, run N frames, surface script errors:
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path . --quit-after 120

# Headless test suite (exit 0 = all pass; CI-friendly). See docs/guidelines/testing.md:
./test/run_tests.sh
```

The scripts auto-detect the engine (first match wins: `~/Downloads/Godot.app`,
`/Applications/Godot.app`, `~/Applications/Godot.app`, then `godot4`/`godot` on
PATH). Override with `GODOT=/path/to/godot`. `play.sh` runs the windowed game and
does not forward flags — for headless validation use the binary line above.

**Always run the headless validation after editing `.gd` files** — it catches
parse errors and `_ready` runtime errors without opening a window.

## Architecture direction (load-bearing)

It's a swarm shooter, so the decision that will matter most (iteration 2+):
**don't spawn one node per demon-bullet, and don't lean on one heavy node per
demon at scale.** Keep swarm state in flat arrays, step it in one loop, and
render via **`MultiMesh` / `MultiMeshInstance3D`** (or `RenderingServer`
directly); broad-phase collision with a uniform grid or cheap radius math. A few
distinct elite enemies can be real nodes; the *swarm* is data. (The examples in
[performance.md](docs/guidelines/performance.md) are written in 2D terms —
`MultiMeshInstance2D` — but the principle is identical in 3D.)

> Language note: C# is faster at raw compute, but the bottleneck here is
> node/draw-call count, not the script language. This project is GDScript for
> tighter engine integration and faster iteration.

## Conventions (load-bearing summary)

Full rules in [`docs/guidelines/`](docs/guidelines/); the essentials:

- **Style** — `snake_case` members/functions, `PascalCase` types, `CONSTANT_CASE`
  constants, `_` prefix for private; **static typing** everywhere; follow the
  member order (signals → enums → constants → exports → vars → `@onready` →
  methods). See [code-quality.md](docs/guidelines/code-quality.md).
- **Structure** — group by feature under `src/`; one responsibility per script;
  stateless helpers live in `src/lib/` utility classes, **not** in the
  composition root. See [project-structure.md](docs/guidelines/project-structure.md).
- **Reuse / decoupling** — depend on `class_name` utilities (reached via a
  `preload()` const), not on sibling node scripts; communicate **down** via
  method calls and **up** via signals; never reach across the tree with
  hard-coded `get_node` paths. See [reusability.md](docs/guidelines/reusability.md).
- **Performance** — MultiMesh for the swarm, pool fast-churn objects, no per-frame
  allocations or `get_node` in loops, `_physics_process` only for physics.
  See [performance.md](docs/guidelines/performance.md).
- **Testing** — a zero-dependency headless runner (`./test/run_tests.sh`); test
  pure deterministic logic (coastline/pattern math, RNG ranges, pool invariants).
  See [testing.md](docs/guidelines/testing.md).

## Layout

```
main.tscn                  # composition-root scene -> src/world/main.gd
src/
  world/   main.gd          # composition root: env, light, island, marine, waves, weapons, UI, camera
           hell_island.gd   # procedural charred-basalt island (IslandShape + ColorUtil)
  marine/  marine.gd        # WASD move + face-nearest-imp; per-arm aim at own imp; marine_01.glb, code walk, hand grips
  enemies/ imp.gd           # "weak imp" placeholder enemy (group "imps"); drifts toward player
           wave_spawner.gd  # scatters a wave of imps across the island (wave 1 = 15)
  weapons/ gun.gd           # small pistol; self-aims when floating (held guns aimed by the ring), fires bolts, muzzle flash
           weapon_ring.gd   # first 2 pistols fixed in the hands (marine aims via the arm), rest float; gun i targets i-th closest imp
  fx/      projectile.gd    # homing bolt; one-shot kills its target imp
           gib.gd           # a flying chunk of a blown-up imp (ballistic, settles, fades)
           gore.gd          # spawns the gib burst + blood decals on death
  ui/      offscreen_indicators.gd  # screen-border arrows pointing at off-screen imps
  audio/   shot_sfx.gd      # plays a random pistol clip per shot (pooled players)
           impact_sfx.gd    # softer random thud when a bolt hits an imp (pooled; via Projectile.hit_enemy)
  lib/     mesh_factory.gd  color_util.gd  island_shape.gd   # reused from ../godot-prototype
models/    marine_01.glb    # imported rigged marine (Mixamo-style bones, no baked anims)
sound/     pistol_01..05.mp3  impact_01..03.mp3  # shot + hit samples (random per event)
test/      run_tests.gd     # headless test runner (+ run_tests.sh)
docs/      guidelines/  ideas/hell-atmosphere.md  superpowers/specs/
```

Cross-script references load via `preload()` consts (robust on a cold clone / CI
— a bare `class_name` reference needs the editor's global class cache, which a
fresh `--path` run hasn't built). Features communicate call-down / signal-up;
the composition root is the only place that knows them all.
