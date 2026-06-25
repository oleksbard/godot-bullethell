# Performance

Pragmatic performance rules for a small–medium project. Don't pre-optimize —
but don't write code the docs explicitly warn against. Based on the
[optimization](https://docs.godotengine.org/en/stable/tutorials/performance/index.html)
and best-practice docs.

## Draw calls: instance, don't spawn thousands of nodes

Each node is a separate draw submission. For **many identical visuals**
(bullets, enemies, particles, debris) use **`MultiMesh`** /
`MultiMeshInstance2D` — thousands of instances in a single draw call, set
per-instance transforms/colors via `set_instance_transform_2d()` /
`set_instance_color()`. For the lowest-overhead path, talk to `RenderingServer`
and `PhysicsServer2D` directly and skip nodes entirely.

> This is the headline win for a bullet hell: **do not spawn one `Area2D`/`Node`
> per bullet.** Keep bullet state in flat arrays (pos/vel) updated in one loop,
> draw them via a single `MultiMeshInstance2D`, and do collision with cheap math
> or direct server queries. 10k nodes will choke; 10k array entries won't.

## The per-frame budget

`_process` / `_physics_process` run every frame for every node. In them:

- **No allocations in hot loops** where avoidable — reuse buffers; creating a
  few `Vector3`/`Quaternion` is fine, building arrays/dictionaries per frame for
  thousands of items is not.
- **No `get_node()` / string lookups in loops** — cache refs in `@onready` or
  `@export` once.
- **Throttle expensive work.** Run it every N frames:
  ```gdscript
  if Engine.get_physics_frames() % 4 == 0:
      _expensive()
  ```
- **Skip idle work.** If a subsystem has nothing to do (no items in a list,
  player far away), early-`return` before the loop.

## `_process` vs `_physics_process`

- `_physics_process(delta)` — fixed timestep; use for physics bodies, movement
  with collision, anything that must be frame-rate-independent and deterministic.
- `_process(delta)` — once per rendered frame; use for visuals, cameras,
  cosmetic animation.
- Disable processing you don't need: `set_process(false)` /
  `set_physics_process(false)`.

## Pooling

For objects created/destroyed rapidly (projectiles, pop effects), reuse a pool
instead of `new()`/`queue_free()` each time. For one-shot bursts, a single
reused emitter (`CPUParticles3D`/`GPUParticles3D` with `restart()`) beats
spawning nodes — we already do this for grass clippings.

## Materials & shading

- Share material resources; don't build a new `StandardMaterial3D` per instance
  when a small pool of variants (or MultiMesh instance colors) gives the same
  variety.
- Forward+ post (glow/SSAO) has a fixed screen-space cost — fine here, but keep
  emissive/transparent overdraw modest.

## Measure before chasing

Use the **Profiler** and **Monitor** (Debugger panel) and the on-screen FPS
before optimizing. Frame time and draw-call count are the numbers that matter;
optimize the top item, re-measure.

## In this project

- **Bullets / enemy fire → data + MultiMesh**, never one node per projectile.
  A single update loop over flat `PackedVector2Array`s (position, velocity),
  drawn by one `MultiMeshInstance2D`. This is the load-bearing decision for the
  whole genre — the language (GDScript vs C#) matters far less than this.
- **Pool** everything created/destroyed rapidly (bullets, hit sparks, pickups):
  reuse a fixed array of slots, mark active/inactive — no `new()`/`queue_free()`
  in the hot path.
- Collision: broad-phase with a uniform grid or cheap radius math against the
  player; reserve real physics bodies for the few things that need them.
- Keep the player and a handful of distinct enemies as real nodes — node count
  is negligible there; only the *swarm* goes data-driven.
