# Reusability & decoupling

How nodes and scripts should depend on each other. Based on
[Godot interfaces](https://docs.godotengine.org/en/stable/tutorials/best_practices/godot_interfaces.html)
and the scene-organization best practices.

## The golden rule: call down, signal up

A node may **call methods on its own children** (it owns them). A node must
**not** assume anything about its parents or siblings — it tells the outside
world things happened via **signals** and lets whoever instantiated it decide
what to do.

```gdscript
# Player owns its scythe -> calls down is fine.
_scythe_pivot.rotation_degrees.y = ...

# Player must NOT know GrassField exists. It announces:
signal swing(origin: Vector3, forward: Vector3)
# The composition root connects player.swing -> grass.on_swing.
```

This keeps each feature independently understandable and testable: `Player`
works with no grass in the scene; `GrassField` works with no player.

## Node references, fastest → slowest

From the docs, prefer cached references:

```gdscript
@export var target: Node3D          # best: set in inspector, survives moves
@onready var sword := $Sword        # great: cached once, GDScript-only
func f(): print($Sword)             # ok: cached NodePath each call
func f(): get_node("Sword")         # slow: dynamic lookup — never in a loop
```

Never hard-code absolute paths (`get_node("/root/Main/Player")`) — it shatters
the moment the tree changes and couples the node to a specific scene layout.

## Share behavior through small utility scripts

Cross-cutting, stateless logic (mesh building, colour math, shape functions)
belongs in its own focused utility script of `static` functions, referenced via
a `preload()` const:

```gdscript
const ColorUtil := preload("res://src/lib/color_util.gd")
# ...
ColorUtil.vary(c, rng)
```

The anti-pattern is `preload`-ing a **node / god-object** just to reach helpers
it happens to host today (`const Art := preload("res://Main.gd")`). Depend on a
small, named tool instead.

**`class_name` vs `preload`:** `class_name` is great for types and editor
autocomplete, but a *bare* `class_name` reference (`ColorUtil.vary(...)`) only
resolves once the editor has built the global class cache — a cold `--path` run
or CI hasn't, so it fails to load. For runtime loading in a source-run project,
prefer the `preload()` const (order-independent, portable); keep `class_name` on
node scripts for typing.

## Decoupling toolbox (pick the lightest that works)

| Need | Use |
| --- | --- |
| Parent reacts to a child event | **Signal** on the child |
| One-off "find all of a kind" | **Groups** (`add_to_group` / `get_nodes_in_group`) |
| Inject a dependency | **`@export`** a typed reference, set by the composition root |
| Shared stateless function | **`class_name` static** utility |
| Truly global, one-per-game state | **Autoload** (last resort) |

## Parameterize, don't duplicate

If two builders differ only by numbers, make one function take those numbers.
Our `make_beveled_box(size, bevel)` and `island_radius(angle)` are good shapes:
pure inputs → outputs, no hidden state, reusable and testable.

## In this project

- The composition root (`src/world/main.gd`) is the only place that knows all
  features. Wire them there: e.g. `player.fired → bullets.spawn`,
  `bullets.player_hit → game.on_hit` — call-down via methods, report-up via
  signals. A `Bullets`/enemy system must not reach up for the player; inject it
  (`@export var player: Node2D`) or pass what it needs.
- Pure math (bullet patterns, RNG spreads, grid hashing) goes in `src/lib/*`
  reached by a `preload()` const — never `preload` a node script to borrow its
  helpers.
