# Adding weapons & enemies

A complete catalog of every property a weapon and an enemy carry today, and a
file-by-file checklist of what to add to register a new one. Reflects the code as
of 2026-06-27 (only the **Pistol** weapon and the **Imp** enemy exist, so most
systems are written generically but a handful of spots are still hardcoded to
those two — flagged as **⚠ hardcoded** below).

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

An enemy is **one script** (`imp.gd`) plus shared services. Everything that targets
or counts enemies keys on the group string **`Imp.GROUP` = `"imps"`** — a new
enemy must join it (or you must generalize targeting).

| Service | File | Responsibility |
|---|---|---|
| Animation | `src/enemies/imp_anim.gdshader` | Vertex walk/attack/death + glowing eyes (no skeleton) |
| Spawner | `src/enemies/wave_spawner.gd` | Drips waves, scales stats, ⚠ hardcodes `ImpScript.new()` |
| Spawn FX | `src/fx/portal.gd` | Summoning circle; freezes the monster via `emerge()` |
| Death FX | `src/fx/gore.gd` + `gib.gd` | Gib chunks + directional blood decals |
| Combat numbers | `src/fx/damage_number.gd` | Flying damage numbers (free via `take_damage`) |
| Loot | `src/loot/xp_orb_field.gd` | Connects to `died(world_pos, xp_value)` |
| Shadow | `src/fx/blob_shadow.gd` | Available but **unused** today |

### 2a. All enemy properties (`imp.gd`)

**Identity / model:**
- `class_name`, `extends Node3D`, `GROUP = "imps"`, `add_to_group(GROUP)` in `_ready`.
- `MODEL` = `res://models/imp_opt.glb` (+ baked textures). `_fit_model()` auto-scales to `IMP_HEIGHT` (1.3) and sits the base on the ground; `MODEL_YAW` (PI) faces it forward (−Z).
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

**Combat stats:**

| Property | Const → per-wave | Notes |
|---|---|---|
| HP | `BASE_HP` 3.0 → `max_hp` | spawner adds `HP_PER_WAVE` 3.0/wave × power mult |
| Attack damage | `BASE_ATTACK_DAMAGE` 1.0 → `attack_damage` | spawner adds `ATTACK_DMG_PER_WAVE` 1.0/wave |
| Attack range | `ATTACK_RANGE` = 1.4 | plays the jab + melee hit |
| Attack cooldown | `ATTACK_COOLDOWN` = 0.8 | seconds between hits |
| Attack blend | `ATTACK_SMOOTH` = 6.0 | ease into/out of the attack pose |
| XP value | `BASE_XP` 1.0 → `xp_value` | spawner adds `XP_PER_WAVE` 1.0/wave; emitted on death |
| Knockback | `KNOCKBACK` 6.5 / `KNOCKBACK_DAMP` 14.0 | shove along the bolt on a non-lethal hit |
| Hit slow | `HIT_SLOW_TIME` 0.45 / `HIT_SLOW_FACTOR` 0.45 | brief slow after a hit |
| Hit flash | `HIT_FLASH_TIME` 0.12 / `DEATH_FLASH` 0.22 | white pulse via shader `hit` uniform |
| Death | `DEATH_TIME` 0.4 | corpse crumple + sink (shader `death`) |

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

**Death FX** (`gore.gd`): `GIB_COUNT` 8 / `HIT_GIB_COUNT` 3, `GIB_CONE`, blood textures (`blood_direct_*`, `blood_spot_*`), `BLOOD_TINT`, `BLOOD_HOLD`/`BLOOD_FADE`, `BLOOD_MAX` 600 cap. Driven by the killing projectile's blood count + travel dir.

**Audio:** none. ⚠ Enemies have **no spawn/attack/death SFX** today — only the weapon-side `ImpactSfx` thud when a bolt connects. Adding enemy sound is greenfield.

### 2b. Checklist — register a new enemy

Fastest path (a melee chaser variant): copy `imp.gd`, tune consts, register in the spawner.

- [ ] **New script** `src/enemies/<enemy>.gd` — `extends Node3D`; `add_to_group("imps")` (so guns, off-screen indicators, and the spawner's alive-count find it) **or** introduce a new group and generalize the targeting set (`WeaponRing._assign_targets`, `Projectile._first_hit`, `Marine._refresh_targets`/`_nearest_on_side`, `offscreen_indicators.gd`).
- [ ] **Required interface** so existing systems work unchanged:
  - `var player`, `var obstacles`, `var max_hp/hp`, `var attack_damage`, `var xp_value`.
  - `signal died(world_pos: Vector3, xp_value: float)` — loot listens.
  - `func emerge(duration)` — portal freeze.
  - `func take_damage(amount, blood_spatters := 3, hit_dir := Vector3.ZERO)` — projectiles call this.
  - per-frame: chase + `_separation()` + `_clamp_to_island()` + `obstacles.resolve(pos, BODY_RADIUS, IslandShape.surface_height(x, z))`.
- [ ] **Model** — add `models/<enemy>.glb` (+ textures, import). Set `MODEL`, `IMP_HEIGHT`-equiv, `MODEL_YAW`; reuse `_fit_model`/`_merged_aabb`.
- [ ] **Animation** — reuse `imp_anim.gdshader` (set `face_dir`, `local_min_y/height`, `eye_pos`, `phase`) or author a new shader for a different gait. Wire `attack`/`hit`/`death` uniforms.
- [ ] **Stats** — set the full block above (speed, HP, XP, attack dmg/range/cooldown, body radius, separation, knockback, flash/slow, death time, eye colour, `BODY_COLOR`).
- [ ] **Spawner** (`wave_spawner.gd`) — `_spawn_one()` hardcodes `ImpScript.new()` (⚠). Use the dormant `_variant_for(pf)` hook: gate the new enemy by `_power_factor` (e.g. `pf > 1.4 → brute`, `pf > 2.0 → fast`) and instance it there, handing it `player`, `obstacles`, scaled `max_hp`/`attack_damage`/`xp_value`, then `emerge()` + a `Portal`. Add per-wave scaling consts if its curve differs.
- [ ] **Spawn FX (optional)** — reuse `Portal` as-is, or pass a per-enemy portal colour/size.
- [ ] **Death FX** — works via `Gore` for free; set `BODY_COLOR` for its blood/gib tint. Override gib size/count if desired.
- [ ] **Loot** — automatic: `xp_orb_field.on_imp_spawned` connects to `died`. Confirm `spawner.imp_spawned.emit(enemy)` fires for the new enemy.
- [ ] **Audio (optional, greenfield)** — add an enemy SFX class (mirror `ImpactSfx`: pooled players, clip set) for spawn/attack/death, and a clip set under `sound/`. Trigger from `emerge()`/attack/`die()`.
- [ ] **Shadow (optional)** — `add_child(BlobShadow.make(BODY_RADIUS))` to ground it.
- [ ] **Test** — `test/suites/enemies_suite.gd`: add the new enemy to the spawn/scaling tests; assert it joins the targeted group and emits `died` with its `xp_value`.

### 2c. ⚠ Imp-hardcoded spots to generalize
`wave_spawner.gd:_spawn_one()` (instances `ImpScript` directly; `_variant_for` is the intended seam) · everything that targets `Imp.GROUP = "imps"` (`weapon_ring`, `projectile`, `marine`, `offscreen_indicators`) — fine if the new enemy joins `"imps"`, otherwise generalize the group set · no enemy-side audio exists yet.

---

## Quick reference — minimum to ship one of each

**New weapon (bolt-firing gun kind):** `Kind` + shape + 4 tooltip arms + stat scaling in `inventory_item.gd`; `equipped_*` in `inventory.gd`; stat/model wiring in `weapon_ring.gd`; icon in `grid_view.gd` (+ `add-item-art`). Reuse `Gun`, `Projectile`, `ShotSfx`.

**New enemy (melee chaser):** one `src/enemies/<enemy>.gd` joining `"imps"` with the required interface + stat block + model + (reused) anim shader; register in `wave_spawner.gd:_variant_for()`. Reuse `Portal`, `Gore`, loot. Add SFX only if you want enemy sound (none exists yet).
