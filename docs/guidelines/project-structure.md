# Project structure

How to lay out a small–medium Godot project. Based on the
[Project organization](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)
and [scenes-as-classes](https://docs.godotengine.org/en/stable/tutorials/best_practices/what_are_godot_classes.html)
best-practice docs.

## Principle: a scene is a class

A scene is a reusable, instantiable group of nodes; its root script is its
"class body". Apply the same OO principles you'd apply to code: **single
responsibility** and **encapsulation**. Ask of every scene/script: *what does it
do, how is it used, what does it depend on?* If you can't answer crisply, the
boundary is wrong.

## Group by feature, not by type

Tiny projects can live in `res://` root. Once you have more than a handful of
scripts, group by **feature** (the thing), keeping a scene, its script, and its
local assets together — and keep cross-cutting, stateless helpers in one shared
library folder.

Recommended layout for this project:

```
res://
  project.godot
  main.tscn                 # composition root scene
  src/
    world/                  # composition root, camera, arena
      main.gd
    player/
      player.gd  (player.tscn)
    bullets/
      bullet_field.gd       # data-driven swarm, one MultiMeshInstance2D
    enemies/
      enemy.gd
    ui/
      hud.gd  (hud.tscn)
    lib/                    # stateless, reusable utilities (class_name)
      bullet_patterns.gd    # pure pattern math (rings, spirals, spreads)
      rng_util.gd           # seeded spread / jitter helpers
      grid_hash.gd          # broad-phase uniform grid for collision
  test/                     # headless runner mirroring src/lib
  docs/
    guidelines/
```

Rules:
- **`src/lib/` holds no game state.** Pure functions / `static` helpers with a
  `class_name`. Anything two features both need goes here.
- A feature folder owns its scene, script, and feature-only assets.
- The **composition root** (`main`) is the only place that knows about all
  features and wires them together. Features don't reach up to it.

## Reference shared utilities by a `preload` const

Put shared, stateless logic in `src/lib/` utility scripts and reach them via a
`preload()` const — `const MeshFactory := preload("res://src/lib/mesh_factory.gd")`
then `MeshFactory.beveled_box(...)`. This is order-independent and works on a
cold clone / CI (a *bare* `class_name` reference needs the editor's global class
cache, which a fresh `--path` run hasn't built). Use `class_name` for node types
and editor autocomplete. The anti-pattern is `preload`-ing a node/god-object
just to borrow its helpers (`const Art := preload("res://Main.gd")`).

## Autoloads (singletons): sparingly

Autoloads are global state — convenient and dangerous. Use them only for things
that are genuinely one-per-game and cross-cutting: an audio bus, a save system,
a global event bus, a run-wide score. **Do not** put feature logic in an
autoload. Stateless helpers should be `class_name` utilities, not autoloads.

## Keep non-resources out of the import scan

Put a `.gdignore` file in folders that contain files Godot shouldn't try to
import (docs, raw data, scratch). 

## `main.tscn` stays thin

The root scene is a composition point. Procedural prototypes (like this one) may
build children in code, but as a feature stabilizes, prefer extracting it into
its **own scene** so it's tweakable in the editor and instantiable/testable in
isolation — that's the scenes-as-classes payoff.
