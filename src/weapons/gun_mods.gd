class_name GunMods
extends RefCounted
## Resolved per-gun modifiers from equipped artifacts (Phase 1: stat multipliers only).
## The WeaponRing reads these when building a gun. Behaviour/conditional fields arrive later.

var damage_mul := 1.0       # multiplies the gun's damage
var fire_rate_mul := 1.0    # >1 = faster: fire_interval is DIVIDED by this
var reload_mul := 1.0       # <1 = faster: reload_time is MULTIPLIED by this
