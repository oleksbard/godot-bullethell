# Wave scaling & spawning — design direction (iteration 2+)

How difficulty grows wave-to-wave, and how a wave's enemies arrive over time.
**Not built yet** — this is the target design. Today's reality: `imp` dies in one
hit (no HP field), one enemy type, and `wave_spawner.gd` does `_wave_count *= 2`
(15 → 30 → 60 …), which explodes by ~wave 7 and melts the CPU by ~wave 8.

## The three levers (each does a different job)

| Lever | Job | Cost | Engine fit |
|---|---|---|---|
| **More monsters** | Pressure, positioning, the swarm fantasy | Cheap | Perfect — MultiMesh is built for count |
| **More HP** | Keeps the player's damage growth meaningful (TTK) | Cheap | Yes, but dangerous on fodder |
| **More types** | Variety + forces build adaptation; run-to-run depth | Expensive (model + AI + balance) | Swarm types = data, elites = nodes |

Use all three, but **staged**: count + types drive the early ramp; HP rides on
tougher tiers, elites, and bosses — never on fodder.

### Two traps to avoid
- **Exponential count** (the current `×2`) always runs away. Count must be
  **sub-exponential** and bounded by a concurrent-alive cap.
- **HP on fodder** turns trash mobs into a chip-fest — shooting the same imp 8×
  is slower, not harder. Fodder stays ~1–2 shots **forever**.

## Drive all three from one number: a wave threat-budget

Don't tune count, HP, and types as three separate knobs — that's three balance
problems. Use a single growing **budget** spent on a roster (Brotato / RTS pattern):

- Each wave gets a points budget that grows on a gentle curve.
- Spend it buying enemies from a roster, each with a cost, e.g.:
  `imp 1 · husk 1 · zombie 3 · cyber-zombie 6 · elite 15 · miniboss 60`
- **Pricier/new types unlock** as the budget crosses thresholds.
- The roster is **data** (a table) so adding a type is one entry.

One budget number then produces *more enemies* (buys more), *a tougher mix*
(affords elites), and *more variety* (unlocks types) — less code and less tuning
than three independent knobs, and it can't double-explode.

## Chunked / streamed spawning (a wave is not one dump)

A wave's budget does **not** all spawn at once. Enemies stream in over the wave's
lifetime against a **max-alive cap**:

- **Initial chunk** spawns at wave start (fill toward the cap).
- **More spawn during the wave** as the budget is drawn down, triggered by:
  - **kills** — when alive drops below the target, spawn the next chunk to refill
    (maintains steady pressure, no lulls), and/or
  - **time** — a drip-feed on a cadence so density keeps building even if the
    player isn't killing fast.
- The **cap** (≈150–250 alive, tuned to perf) bounds what's on screen at once;
  the **budget** bounds the wave's total. Chunks move budget → field until the
  budget is spent.

**Why:** steady density (no front-loaded lag spike from dumping 200 at once, no
dead air), sustained pressure, and spawn cost spread over time instead of one hitch.

**Wave-end condition changes:** today a wave ends at `alive == 0`. With streaming
it ends when **budget fully spent AND alive == 0**, then the between-wave pause.

## HP: scale against the *player*, not the wave

Difficulty here is a **race between enemy threat and player power** (loot/levels
grow DPS). So:
- **Fodder stays ~1–2 shots.** Let its HP creep only enough that rising DPS keeps
  it at 1–2 shots — never a sponge.
- **HP lives in tougher types + elites + a periodic boss** (every 5–10 waves) that
  is a real HP wall and skill check.
- Tune so time-to-kill per tier stays in a target band as the run progresses —
  that band *is* the difficulty curve.

## Roster by role (variety only matters if they play differently)

- **Imp** — baseline rusher *(exists)*
- **Husk** — slow crawler, soaks a lane
- **Zombie** — tankier walker, the HP tier
- **Cyber-zombie** — ranged spitter, changes player spacing
- **Elite** — fast + tanky, forces target priority
- **Boss** — periodic HP/skill wall

## Architecture ties

- Swarm enemies stay **data + MultiMesh**; a handful of elites/bosses can be real
  nodes. The alive-cap protects CPU (collision/AI), not just draw calls.
- The budget/roster/cap belong in `wave_spawner.gd`; `imp.gd` (and siblings) gain
  an actual `hp` field. See `docs/guidelines/performance.md`.

## First-cut numbers (starting point, all tunable)

- Budget: start ~100, grow ~×1.18/wave (gentle geometric), or a capped linear ramp.
- Concurrent-alive cap: ~150–250 (profile and adjust).
- Refill trigger: spawn next chunk when alive < ~70% of the cap.
- Boss cadence: every 5–10 waves.
