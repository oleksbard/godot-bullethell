# Adding weapons & enemies

A complete catalog of every property a weapon and an enemy carry today, and a
file-by-file checklist of what to add to register a new one. Reflects the code as
of 2026-06-29 (only the **Pistol** weapon exists; two enemies exist — **Imp** and
**Zombie** — sharing the `Enemy` base. A handful of weapon spots are still hardcoded
to Pistol — flagged as **⚠ hardcoded** below).

---

## Part 1 — Weapons

A weapon is **two objects** plus shared services:

| Object | File | Responsibility |
|---|---|---|
| `InventoryItem` | `src/inventory/inventory_item.gd` | The grid item: shape, level, stats, descriptions, power, price |
| `Gun` (3D node) | `src/weapons/gun.gd` | Floating/held model that aims, fires, reloads, muzzle-flashes |
| `Projectile` | `src/fx/projectile.gd` | The bolt the gun spawns (shared by all guns today) |
| `ShotSfx` / `ImpactSfx` | `src/audio/` | Fire + hit sounds (shared by all guns today) |
| `WeaponRing` | `src/weapons/weapon_ring.gd` | Turns equipped items into Gun nodes and wires their stats |
| `GridView` / `ItemTooltip` | `src/ui/` | Inventory icon + hover stat card |

### 1a. All weapon properties

**Combat stats** — base values in `Gun` (`gun.gd`), level-scaled in `InventoryItem`:

| Property | Const / method | Where | Notes |
|---|---|---|---|
| Damage per bolt | `Gun.DAMAGE` = 5.0 → `InventoryItem.damage_value()` | gun.gd:15 / item:113 | `+DMG_PER_LEVEL` (0.4) per level |
| Fire interval (s) | `Gun.FIRE_INTERVAL` = 1.7 → `fire_interval_value()` | gun.gd:14 / item:118 | `-FIRE_SPEEDUP_PER_LEVEL` (0.05)/lvl, floor `FIRE_INTERVAL_MIN` 0.6 |
| Magazine size | `Gun.MAG_SIZE` = 7 / `InventoryItem.MAGAZINE` = 7 | gun.gd:16 / item:29 | bolts before a reload |
| Reload time (s) | `Gun.RELOAD_TIME` = 2.0 → `reload_time_value()` | gun.gd:17 / item:130 | `-RELOAD_SPEEDUP_PER_LEVEL` (0.07)/lvl, floor `RELOAD_MIN` 0.8 |
| Targeting range | `WeaponRing.MAX_RANGE` = 12.0 | ring:29 | shared by all guns; tooltip shows a display-only "Range" |
| Turn speed | `Gun.TURN_SPEED` = 18.0 | gun.gd:13 | how fast a floating gun yaws to aim |
| Power score | `InventoryItem.power()` / `POWER_BASE` = 10 | item:135 | DPS-normalized; sums into `loadout_power()` → wave scaling |

**Projectile stats** (`projectile.gd`) — shared by every gun today:

| Property | Const | Notes |
|---|---|---|
| Speed | `SPEED` = 38.25 | straight bolt, no homing |
| Hit radius | `HIT_DIST` = 0.7 | swept hit along travel |
| Lifetime | `LIFETIME` = 2.0 | |
| Aim height | `AIM_HEIGHT` = 0.6 | aims at imp mass, not feet |
| Blood per kill | `BLOOD_MIN`/`BLOOD_MAX` = 1/4 | rolled per hit, passed to `Gore` |
| Visual | `_build()` | sphere mesh, emissive tracer (`emission_energy` 6 → blooms) |

**Visuals / model** (`gun.gd`):
- `_build_body()` — procedural beveled-box slide + barrel + grip (`BODY_COLOR`).
- `BARREL_TIP` = (0, 0.02, −0.34) — muzzle origin for flash + bolt spawn.
- Muzzle flash: `FLASH_ENERGY` 6, `FLASH_DECAY` 40, `FLASH_SIZE` 0.55, shared radial sprite texture, `OmniLight3D` + additive billboard.
- Reload look: `RELOAD_COLOR`, `RELOAD_ALPHA_MIN` (gun tints red and fills opaque as it reloads).
- Held vs floating: `held` flag; held guns are aimed by the marine's arm, floating guns self-aim and get a `TurretMount` strut (`turret_mount.gd`).

**Item / inventory metadata** (`inventory_item.gd`):
- `Kind` enum (⚠ `{ PISTOL }`), `ItemType` enum (`GUN | ARTIFACT | OTHER`).
- Shape: `<KIND>_CELLS` (e.g. `PISTOL_CELLS`) — occupied grid cells; `rot` rotates them.
- Level/rarity: `item_level`, `MAX_ITEM_LEVEL` 8, `rarity()` bands, `roll_level()` curve.
- Economy: `BASE_PRICE` 10, `PRICE_EXP` 1.5, `buy_price()`, `SELL_FRACTION` 0.65, `sell_price()`.

**Descriptions / UI text** (`inventory_item.gd`, read by `ItemTooltip`):
- `display_name()` (⚠ match on `kind`) — header name.
- `tags()` (⚠ match on `kind`) — header pills, e.g. `["Projectile", "Gun"]`.
- `stats()` (⚠ match on `kind`) — ordered `[label, value]` rows; zero/false rows auto-hide (so unimplemented stats like Piercing/Ricochet/Knockback can sit at 0).
- `flavor()` (⚠ match on `kind`) — flavour sentence.
- `rarity()` colour comes from `ItemTooltip.RARITY_COLORS`.

**Icon art** (`grid_view.gd`):
- `ITEM_TEXTURE_PATHS = {0: "res://art/items/pistol.png"}` (⚠ keyed by `Kind` int).
- `PISTOL_COLOR` placeholder block drawn when no icon file exists (⚠ `color_for()` returns it for everything today).
- Use the **`add-item-art`** skill to generate/fit/import the icon.

**Audio** (`weapon_ring.gd` wires it):
- `ShotSfx` (`shot_sfx.gd`) — `CLIPS` = pistol_01..05 + per-clip `CLIP_PEAKS_DB` loudness trims. One instance plays for **every** gun fire (⚠ not per-weapon).
- `ImpactSfx` (`impact_sfx.gd`) — `CLIPS` = impact_01..03, played on `Projectile.hit_enemy`.

### 1b. Checklist — register a new weapon

Reusing the existing `Gun`/`Projectile` (a new *gun kind* that still fires bolts):

- [ ] **`inventory_item.gd`** — add to `Kind` enum; add `<KIND>_CELLS`; add a `static func <kind>()` factory; extend the `match kind` arms in `display_name()`, `tags()`, `stats()`, `flavor()`; if its scaling differs, add per-kind stat methods/consts (today `damage_value()` etc. read `GunScript.DAMAGE`/`FIRE_INTERVAL` directly — generalize to per-kind base stats).
- [ ] **`inventory.gd`** — `equipped_pistols()` filters `Kind.PISTOL` (⚠). Either rename/generalize to `equipped_guns()` (return all `ItemType.GUN`) or add a parallel query; make sure `loadout_power()` and `WeaponRing` consume it. Optionally seat one in `build()` for the starting loadout.
- [ ] **`weapon_ring.gd`** — `_rebuild()` reads `equipped_pistols()` and sets `g.damage/fire_interval/mag_size/reload_time` (⚠ pistol-specific). Generalize so each equipped gun maps to the right Gun visuals + stats. If the new weapon has a distinct **model**, branch the `GunScript.new()` instantiation on kind.
- [ ] **`grid_view.gd`** — add `ITEM_TEXTURE_PATHS[<kind>] = "res://art/items/<name>.png"` and a placeholder colour in `color_for()`. Generate the icon with the `add-item-art` skill.
- [ ] **Audio** — if it should sound different, add a clip set + an SFX class (or parameterize `ShotSfx` with a per-weapon `CLIPS`), and pick it in `WeaponRing._on_gun_fired`.
- [ ] **Shop (optional)** — `level_up_menu.gd` rolls `InventoryItemScript.rolled_pistol(...)`; add a `rolled_<kind>()` and include it in the shop roll.
- [ ] **Held grip (optional)** — if hand-held and oddly shaped, tune `Marine.GRIP_ROLL`/`GRIP_YAW` and `WeaponRing.HELD_SEAT`/`HELD_LIFT`.
- [ ] **Test** — `test/suites/weapons_suite.gd`: assert the new item's `stats()`/`power()`/`damage_value()` and that `equipped_*` picks it up.

Adding a **new firing behaviour** (not a bolt — e.g. beam, shotgun spread, homing):

- [ ] **New `Projectile` variant** (or params on `Projectile`: speed, lifetime, `HIT_DIST`, blood range, pierce/ricochet, homing) under `src/fx/`.
- [ ] **`Gun`** — `_fire()` emits `fired(origin, target, damage)`; `WeaponRing._on_gun_fired` spawns `ProjectileScript`. To vary per weapon, have the Gun carry its projectile type (or map kind→projectile in the ring). For multi-pellet, emit/spawn N with spread.
- [ ] Wire `Piercing`/`Ricochet`/`Knockback` (currently display-only 0s in `stats()`) into the projectile + `Imp._react_to_hit`.

### 1c. ⚠ Pistol-hardcoded spots to generalize
`inventory_item.gd` (Kind matches + stat methods reading `GunScript` consts) · `inventory.gd:equipped_pistols()` · `weapon_ring.gd:_rebuild()` stat wiring · `grid_view.gd` icon/colour maps · `shot_sfx.gd` (one shared pistol clip set) · `level_up_menu.gd:rolled_pistol`.

---

## Part 2 — Enemies

Two enemies exist — **Imp** and **Zombie** — both subclassing the shared `Enemy`
base (`src/enemies/enemy.gd`). Everything that targets or counts enemies keys on
the group string **`Enemy.GROUP` = `"imps"`** — both types join it, and so must
any new enemy (or you must generalize targeting).

| Service | File | Responsibility |
|---|---|---|
| **Base AI** | `src/enemies/enemy.gd` | Shared chaser logic: movement, separation, island-clamp, knockback, hit-flash, emerge, melee, death/gore, model build + shader wiring |
| Animation | `src/enemies/imp_anim.gdshader` | Vertex walk/attack/death + glowing eyes (no skeleton); reused by both enemy types |
| Spawner | `src/enemies/wave_spawner.gd` | Point-budget drip: imp = 1 pt, zombie = 2 pts; zombie share gated/capped by `_zombie_share(wave)`, zombies from wave 2 |
| Spawn FX | `src/fx/portal.gd` | Summoning circle; freezes the monster via `emerge()` |
| Death FX | `src/fx/gore.gd` + `gib.gd` | Gib chunks + directional blood decals; accepts optional `blood_tints`/`gib_colors` lists (zombie uses red+green) |
| Combat numbers | `src/fx/damage_number.gd` | Flying damage numbers (free via `take_damage`) |
| Loot | `src/loot/xp_orb_field.gd` | Connects to `died(world_pos, xp_value)` |
| Shadow | `src/fx/blob_shadow.gd` | Available but **unused** today |

### 2a. All enemy properties

**Base class (`enemy.gd`) + subclasses (`imp.gd`, `zombie.gd`):**

Shared logic lives in `Enemy` (`src/enemies/enemy.gd`). Subclasses override three hooks:
- `_configure()` — set instance vars (`speed`, `model_height`, `eye_color`, gait knobs, etc.). Called before `_ready` populates the node. Do **not** touch spawner-set combat numbers (`max_hp`, `attack_damage`, `xp_value`) here.
- `_model_scene() -> PackedScene` — return the preloaded GLB for this enemy.
- `_spawn_gore(blood_spatters, hit_dir)` — override to change the death FX palette (default = imp red via `Gore.spawn_death`).

Per-wave scaling consts (`BASE_HP`, `BASE_ATTACK_DAMAGE`, `BASE_XP`) live on the **subclass** as `const`, so the spawner can read them without instantiating. `ENEMY_NAME` is a `const String` returned by `enemy_type()`.

**Identity / model:**
- `class_name Enemy`, `extends Node3D`, `const GROUP := "imps"`, `add_to_group(GROUP)` in `_ready`.
- Imp: `MODEL` = `res://models/imp_opt.glb`, `model_height` 1.3 (base default). Zombie: `MODEL` = `res://models/zombie_opt.glb`, `model_height` 1.8.
- `_fit_model()` auto-scales to `model_height` and sits the base on the ground; `model_yaw` (PI) faces it forward (−Z).
- Casts no real shadow (`cast_shadow = OFF`); `BlobShadow.make(r)` is available if you want a grounding disc.

**Movement / AI stats:**

| Property | Const | Notes |
|---|---|---|
| Move speed | `SPEED` = 2.3 | drift toward player |
| Body radius | `BODY_RADIUS` = 0.4 | vs columns/lava in `ObstacleField.resolve` |
| Stop distance | `STOP_DIST` = 0.8 | don't climb onto the player |
| Separation | `SEP_RADIUS` 1.2 / `SEP_WEIGHT` 1.6 | swarm spread (O(n²) today) |
| Edge margin | `EDGE_MARGIN` = 0.6 | keep inside the coastline |
| Terrain | samples `IslandShape.surface_height` each frame | walks the hills (added 2026-06-27) |

**Combat stats (imp / zombie):**

| Property | Imp base | Zombie base | Per-wave | Notes |
|---|---|---|---|---|
| HP | `BASE_HP` 3.0 | `BASE_HP` 30.0 | `+HP_PER_WAVE` 2.0/wave × power mult | spawner sets `max_hp` |
| Attack damage | `BASE_ATTACK_DAMAGE` 1.0 | `BASE_ATTACK_DAMAGE` 2.0 | `+ATTACK_DMG_PER_WAVE` 0.5/wave | |
| Attack range | `attack_range` 1.4 | `attack_range` 1.7 | — | plays the jab + melee hit |
| Attack cooldown | `attack_cooldown` 0.8 | `attack_cooldown` 1.2 | — | seconds between hits |
| Attack blend | `attack_smooth` 6.0 | (same) | — | ease into/out of the attack pose |
| XP value | `BASE_XP` 1.0 | `BASE_XP` 2.0 | `+XP_PER_WAVE` 1.0/wave | emitted on death |
| Knockback | `knockback` 6.5 / `knockback_damp` 14.0 | (same) | — | shove along the bolt on a non-lethal hit |
| Hit slow | `hit_slow_time` 0.45 / `hit_slow_factor` 0.45 | (same) | — | brief slow after a hit |
| Hit flash | `hit_flash_time` 0.12 / `death_flash` 0.22 | (same) | — | white pulse via shader `hit` uniform |
| Death | `death_time` 0.4 | (same) | — | corpse crumple + sink (shader `death`) |

**Spawn lifecycle:**
- `emerge(duration)` — freezes + scales up from `EMERGE_SCALE_FROM` (0.2) while the portal is open (`EMERGE_TIME` 1.0 in the spawner). Killable while emerging.
- Death: `die(blood_spatters, hit_dir)` → `Gore.spawn_death(...)` + detached corpse + `died.emit()`; `remove_from_group`.

**Visuals / animation** (`imp_anim.gdshader`, per-mesh `ShaderMaterial`):
- Walk shaping uniforms: `stride`, `twist`, `lean_run`, `bob`, `squash`, `walk_freq`, per-imp `phase`.
- Attack uniforms: `attack`, `lunge_rate`, `lunge_reach`.
- Required from script: `face_dir`, `local_min_y`, `local_height` (so `h` = foot→crown is right for any model).
- Death: `death`, `death_squash`, `death_splay`. Hurt: `hit`.
- Eyes: `eye_pos` (from mesh AABB via `EYE_*_FRAC`), `eye_radius`, `eye_softness`, `eye_emission` (`EYE_COLOR`), `eye_energy` (`EYE_ENERGY` 3 → blooms). Mirrored across x=0 for the second eye.
- `BODY_COLOR` (0.45,0.08,0.08) = blood/gib tint + albedo fallback when the model has no texture.

**Death FX** (`gore.gd`): `GIB_COUNT` 8 / `HIT_GIB_COUNT` 3, `GIB_CONE`, blood textures (`blood_direct_*`, `blood_spot_*`), `BLOOD_TINT`, `BLOOD_HOLD`/`BLOOD_FADE`, `BLOOD_MAX` 600 cap. Driven by the killing projectile's blood count + travel dir. Pass optional `blood_tints`/`gib_colors` lists to `Gore.spawn_death` for a custom palette (the Zombie uses `[BLOOD_TINT, GORE_TOXIC_GREEN]` / `[red, green]`); the Imp path uses empty-list defaults (unchanged).

**Audio:** none. ⚠ Enemies have **no spawn/attack/death SFX** today — only the weapon-side `ImpactSfx` thud when a bolt connects. Adding enemy sound is greenfield.

### 2b. Checklist — register a new enemy

Fastest path (a melee chaser variant): subclass `enemy.gd`, override the three hooks, register in the spawner.

- [ ] **New script** `src/enemies/<enemy>.gd` — `extends "res://src/enemies/enemy.gd"`. It already joins `"imps"` and implements the full required interface; you only need the three hooks below.
- [ ] **`_configure()`** — set per-enemy tunables (`speed`, `model_height`, `eye_color`, `body_color`, gait knobs, `attack_range`, `attack_cooldown`, etc.). **Do not** touch spawner-set combat numbers (`max_hp`, `attack_damage`, `xp_value`).
- [ ] **`_model_scene() -> PackedScene`** — return the preloaded GLB for this enemy.
- [ ] **`_spawn_gore(blood_spatters, hit_dir)`** (optional) — override for a custom death-FX palette; base calls `Gore.spawn_death` with `body_color`.
- [ ] **Per-wave consts** — define `const BASE_HP`, `BASE_ATTACK_DAMAGE`, `BASE_XP`, `ENEMY_NAME` on the subclass so the spawner can read them without instantiating.
- [ ] **Model** — add `models/<enemy>.glb` (+ textures, import). The base handles `_fit_model`/`_merged_aabb`; set `model_height`/`model_yaw` in `_configure()`.
- [ ] **Animation** — `imp_anim.gdshader` is wired by the base. Set gait uniforms (`walk_freq`, `stride`, `twist`, `bob`, `squash`, `lunge_rate`, `lunge_reach`) in `_configure()` for a distinct shamble/lurch.
- [ ] **Spawner** (`wave_spawner.gd`) — add the new type to `_spawn_one()` alongside the imp/zombie pick. The point-budget pattern: define a `<TYPE>_COST` const and a share/gate function (like `_zombie_share(wave)` for the zombie). Read `<TypeScript>.BASE_HP` etc. the same way. Update `_start_wave` comment if the count semantics change.
- [ ] **Spawn FX (optional)** — reuse `Portal` as-is, or pass a per-enemy portal colour/size.
- [ ] **Death FX** — works via `Gore` for free; set `body_color` + override `_spawn_gore` if you want a custom palette.
- [ ] **Loot** — automatic: `xp_orb_field.on_imp_spawned` connects to `died`. Confirm `spawner.imp_spawned.emit(enemy)` fires for the new enemy.
- [ ] **Audio (optional, greenfield)** — add an enemy SFX class (mirror `ImpactSfx`: pooled players, clip set) for spawn/attack/death, and a clip set under `sound/`. Trigger from `emerge()`/attack/`die()`.
- [ ] **Shadow (optional)** — `add_child(BlobShadow.make(body_radius))` to ground it.
- [ ] **Test** — `test/suites/enemies_suite.gd`: add the new enemy to the spawn/scaling tests; assert it joins the targeted group and emits `died` with its `xp_value`.

### 2c. Remaining hardcoded spots
Everything that targets `Enemy.GROUP = "imps"` (`weapon_ring`, `projectile`, `marine`, `offscreen_indicators`) — fine for any enemy that joins `"imps"` (both Imp and Zombie do); only generalize if you add a non-`"imps"` group. No enemy-side audio exists yet.

---

## Quick reference — minimum to ship one of each

**New weapon (bolt-firing gun kind):** `Kind` + shape + 4 tooltip arms + stat scaling in `inventory_item.gd`; `equipped_*` in `inventory.gd`; stat/model wiring in `weapon_ring.gd`; icon in `grid_view.gd` (+ `add-item-art`). Reuse `Gun`, `Projectile`, `ShotSfx`.

**New enemy (melee chaser):** `src/enemies/<enemy>.gd` extending `enemy.gd`; override `_configure()` (tunables), `_model_scene()` (GLB), `_spawn_gore()` (palette, optional); define `BASE_HP/BASE_ATTACK_DAMAGE/BASE_XP/ENEMY_NAME` consts; register in `wave_spawner.gd:_spawn_one()` (point-budget pick, like the zombie). Reuse `Portal`, `Gore`, loot. Add SFX only if you want enemy sound (none exists yet).
