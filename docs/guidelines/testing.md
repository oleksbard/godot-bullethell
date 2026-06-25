# Testing

This project uses a **zero-dependency headless test runner** for its
deterministic core, with [gdUnit4](https://github.com/MikeSchulze/gdUnit4) noted
as the upgrade path when richer node/integration testing is needed.

## Why a custom runner (not gdUnit4 yet)

gdUnit4 is excellent but it's a heavy editor addon whose version tracks the Godot
release; on a brand-new Godot (4.7) that's a compatibility gamble, and it adds a
plugin + global-class-cache dependency. For a small prototype whose valuable
tests are **pure, deterministic logic**, a ~80-line runner that needs nothing but
the Godot binary is more robust and CI-friendly. Adopt gdUnit4 when you need its
`scene_runner` (simulated input over frames), mocking, or fluent assertions.

## What to test (and what not to)

Test the **stable, pure, deterministic** parts — easy to get subtly wrong, hard
to eyeball:

- **Shape / math** — `IslandShape.radius()` is bounded and periodic; `ring_vertex`
  lands where expected.
- **Generators / RNG ranges** — `ColorUtil.vary()` stays in `[0,1]` and is
  deterministic for a fixed seed.
- **Geometry builders** — `MeshFactory.beveled_box()` vertex count + AABB.
- **Gameplay invariants** — the player clamps inside the coastline; a swing
  cuts grass and increments the count (signal fires).

**Don't** test rendering or "does it look good" — that stays a manual check in
the window. Always pass a **seeded** `RandomNumberGenerator` for determinism.

## The runner

[`test/run_tests.gd`](../../test/run_tests.gd) extends `SceneTree` and runs as a
standalone main loop. It calls the extracted lib statics directly and exits `0`
on success / `1` on any failure.

```gdscript
extends SceneTree
const IslandShape := preload("res://src/lib/island_shape.gd")

func _initialize() -> void:
    _check(IslandShape.radius(0.5) == IslandShape.radius(0.5 + TAU), "periodic")
    quit(1 if _failed > 0 else 0)
```

**Pure logic** runs synchronously, no scene needed. **Node behavior** (anything
using `global_position`, e.g. `GrassField.on_swing`) requires the node in the
tree: `get_root().add_child(node)` then `await process_frame` so `_ready()` fires
— and any node it reads (`player`) must be in the tree too.

## Running

```sh
./test/run_tests.sh                      # auto-detects Godot
GODOT=/path/to/godot ./test/run_tests.sh # explicit binary (CI)
```

The script exits non-zero on failure, so it drops straight into CI. Keep the
suite fast (it builds a full grass field in well under a second).

## Adding a test

1. Add a `_test_*()` method in `run_tests.gd`, set `_suite`, and use `_ok(cond, msg)`.
2. Call it from `_initialize()` (prefix with `await` if it touches the tree).
3. Free any nodes you create so the run stays leak-clean.

When the suite outgrows this (you want simulated input, mocks, parameterized
cases), install `addons/gdUnit4/`, enable the plugin, and move suites to
`*_test.gd` extending `GdUnitTestSuite` — the pure-logic tests port almost
verbatim, and `scene_runner` unlocks input-driven integration tests.
