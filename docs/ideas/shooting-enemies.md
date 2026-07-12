# Shooting (ranged) enemies

**Why:** the two existing enemies (fast imp 1pt, slow tank zombie 2pt) are both
melee — they close to `attack_range` and jab, so the player can stand still and
let auto-fire clear the horde. A **ranged demon** that hangs back and lobs
projectiles at the marine (60 HP, already has `take_damage` + overhead bar)
forces movement and dodging. It plugs in as a minimal `enemy.gd` subclass plus a
reused `projectile.gd` variant that calls `marine.take_damage` instead of
`enemy.take_damage`.

Doom lineage, since the imp already is a Doom imp.

## Candidates

### Revenant ⭐ (CHOSEN — IMPLEMENTED)
Tall skeletal demon with shoulder-mounted rocket pods; screeches, fires slow
dodgeable rockets. *The* canonical Doom ranged demon.
- **Read:** bony, spiky silhouette — very legible top-down.
- **Fit:** grounded, so it reuses the existing walk-shader gait. Skeleton = best
  gib gore. Complements the two melee silhouettes without duplicating them.
- **Tier:** 3-point elite; **appears from wave 1** (rare), share climbing 5%→25%
  with the wave. The 3-point cost self-limits its count so wave 1 isn't swamped.
- **Behavior:** holds at range, *not* a kite. Approaches to `stop_dist` (~9u) and
  stands/shoots within `attack_range` (~13u); fires **one slow, dodgeable bolt
  every 2.5s**. Every **2–3 shots it strafes sideways** to a new spot (orbits the
  player) so it's a moving target, not a turret. When the marine crowds it (<6u) it
  *occasionally* (rolled, 3s cooldown) darts back for ~0.7s. ~8 HP, no melee.
- **T-pose fix (the real one):** the generated model was a T-pose (armspan≈height)
  and the shader has **no skeleton**, so no gait could lower the arms — twisting the
  body just rotates outstretched arms in a horizontal circle. Fixed by **baking the
  arms down into the mesh geometry**: `tools/repose_arms.py` reads the verts, finds
  the arm band (upper body + far out along X), and rotates it down about a per-side
  shoulder pivot (normals too), writing a new `revenant_opt.glb`. Re-run it after
  regenerating/re-optimizing the model: `python3 tools/repose_arms.py in.glb out.glb [deg]`.
  A live procedural arm-droop/cast shader hack was tried first and **removed** —
  bending a rigless unknown-topology mesh per-frame mangled it; baking a one-time,
  geometry-informed pose is the reliable approach short of a real rig.
- **Gait:** `uses_melee_pose = false` (else a big `attack_range` pins the shader's
  melee `attack`≈1 and the walk gait freezes) + a heavy lumber (`twist`/`bob`/slow
  `walk_freq`) so the now-lowered arms swing as it moves. Tunable in `_configure()`.
- **Bolt:** `src/fx/enemy_bolt.gd` — a dedicated **hostile-red** bolt (vs the
  player's yellow) that damages **only the marine** (single-target check, never
  scans the `"imps"` group), so revenant fire can't harm other enemies. Aims once
  at spawn; strafe and it misses. A `_spent` guard prevents any double-hit.
- **Special — Missile Barrage** (Doom Eternal signature): granted one-at-a-time by
  `RevenantCoordinator` on a ~15s global cooldown (like the imp-leap / zombie-buff
  coordinators). ~0.6s rooted wind-up (telegraph) → a wide **fan of 5 bolts** the
  player dodges by strafing perpendicular → brief recovery.
- **Model:** `models/revenant_opt.glb`, 4,079 tris (decimated from 10,423 via
  `tools/optimize_model.sh` elite preset).

### Cacodemon
Floating spherical one-eyed maw that spits plasma.
- **Read:** big round blob — the most distinct shape from above.
- **Fit:** floats → does **not** use the leg gait; needs a bob/float instead, so
  it's the most visually different from imp/zombie. Simplest mesh.
- **Tier:** could be 2pt mid or 3pt elite.
- **Behavior:** slow drift, lobs fireballs; same kiting logic as Revenant.

### Hell-spider / Arachnotron
Spider chassis with a plasma cannon.
- **Read:** radial, wide footprint — reads well top-down.
- **Fit:** legs mean a new multi-leg gait; busiest to model.
- **Tier:** 3pt elite.
- **Behavior:** scuttles, holds range, fires plasma bursts.

## Revenant — 3D model prompt (text-to-3D: Meshy / Tripo / Rodin)

> A gaunt hellish skeletal demon warrior, "revenant" archetype, standing upright
> in a neutral A-pose. Bleached bone-white ribcage and spine exposed, sinewy
> dark-red muscle strands stretched between the bones, a fanged elongated skull
> with hollow glowing amber eye-sockets and small backswept horns. Two large
> mechanical-organic rocket launcher pods fused onto its shoulders, bristling
> with stubby missile tubes, scorched black metal veined with molten-red cracks.
> Long clawed arms, digitigrade hooved legs, hunched menacing posture. Grim
> dark-fantasy Doom-style creature, semi-stylized realism, PBR textures,
> dramatic scorched/ashen palette with red and amber emissive accents. Single
> game-ready character, clean quad topology, symmetrical.

**Technical constraints (match `imp_opt.glb` / `zombie_opt.glb`):**
- Single merged mesh, **~2,000–3,000 tris** (zombie is 2,329), no loose parts.
- **A-pose / neutral standing**, arms slightly out — animated by the
  `imp_anim.gdshader` vertex shader, so **no rig/skeleton needed**.
- Origin at the **feet**; model authored **facing forward (+Z)** — code yaws it
  180° via `model_yaw = PI`. Verify facing by motion in-engine, not by eye.
- Baked PBR / single albedo+emissive set; export **glb**, target < 300 KB.
- Emissive on eye-sockets and rocket-pod cracks so they glow in hell lighting.
- Leave a **muzzle point** near the shoulder pods — code reads its tip as the
  projectile origin (like the gun's `barrel_tip`).

## Implementation (shipped)

- `src/enemies/enemy.gd` — two behavior-preserving base seams: `_attack_player()`
  (default = instant melee; revenant overrides to fire) and `_steer_intent(to_player,
  delta)` (default = chase-to-stop_dist; revenant overrides to hold + backpedal). Plus a
  third special mirroring the buff channel: `can_special_barrage`, `begin_barrage()`,
  `_process_barrage()` (rooted wind-up→recover) calling the `_release_barrage()` hook.
- `src/fx/enemy_bolt.gd` — the player-only bolt.
- `src/enemies/revenant.gd` — the subclass (tunables, `_attack_player`, `_steer_intent`,
  `_release_barrage` fan, bone+crimson `_spawn_gore`).
- `src/enemies/revenant_coordinator.gd` — the 15s barrage grant.
- `src/enemies/wave_spawner.gd` — `REVENANT_COST 3`, `_revenant_share()` (from wave 1),
  spawn branch, and the coordinator wired in `_ready`.
- Tests in `test/suites/enemies_suite.gd`: identity, share bounds, bolt-hits-only-player,
  fires-on-cooldown, barrage-fan-count, coordinator gate.

Cacodemon / Hell-spider remain unbuilt ideas above.
