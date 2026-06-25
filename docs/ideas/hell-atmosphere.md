# Hell atmosphere — deferred ideas (full-fat visuals)

Iteration 1 ships a **styled-but-cheap** hell island (charred basalt palette,
warm low key light, ember-glow rocks). These are the bigger-effort atmosphere
ideas to layer in later, roughly cheapest → most expensive.

## Lighting & post
- Pulsing/flickering ember ambient (subtle noise on the key-light energy/colour).
- Stronger volumetric/height fog: red-black haze pooling in the low rings so the
  island edge dissolves into the void.
- Heat-haze refraction shimmer near lava/ember sources (screen-space distortion).
- Bloom tuned per-emissive so lava reads as molten, not just bright.

## Terrain
- Lava cracks: emissive vein network across the crust (procedural noise mask in a
  shader, animated flow).
- Lava rivers/pools: flowing emissive surface (scrolling noise UVs) with cooled
  black-rock rims.
- Cooling-crust gradient: black at the surface, glowing down in the cracks.
- Jagged spires / obsidian shards scattered as set dressing.

## Particles & VFX
- Rising ember particles (GPUParticles, additive) drifting up off the island.
- Smoke/ash plumes from vents; falling ash/cinders in the air.
- Ground scorch decals where things burn or die.

## Sky / void
- A distant burning horizon or hellish skybox instead of flat near-black.
- Floating debris/rock chunks orbiting in the void around the island.
- Occasional distant fire flashes / heat lightning.

## Audio (later)
- Low rumble bed, crackling-fire loops, distant roars.

## Note
Atmosphere VFX compete with demon rendering for frame time. Prefer baked/shader
effects over many particle nodes — keep the data-driven swarm budget in mind
(see `docs/guidelines/performance.md`).
