class_name PlayerStats
extends Node
## Minimal player stat holder the HUD binds to. take_damage() is called by the marine
## on imp hits; add_xp() is called (via marine.gain_xp) when a dropped XP orb is collected.
## Both emit signals the HUD listens to.

signal health_changed(health: float, max_health: float)
signal xp_changed(total_xp: float)        # monotonic lifetime XP; the HUD animates the bar from it
signal leveled_up(level: int)             # authoritative level event (the HUD fires the flourish/modal when its bar fills)
signal souls_changed(souls: int)          # banked soul count changed (HUD + level-up menu show it)
signal damaged(amount: float)             # damage the player took this hit (CombatTracker tallies it)

var max_health := 60.0
var health := 60.0
var level := 1
var xp := 0.0
var xp_to_next := 16.0                     # = xp_for(1); first level-up cost (Brotato curve)
var total_xp := 0.0                       # never decreases; lets the HUD animate across level boundaries
var souls := 0                            # currency banked from collected soul-motes; spent in the level-up shop
var total_souls := 0                      # never decreases; lifetime souls collected (drives the shop reroll base)
var rarity_bonus := 0.0                   # "Increased Rarity" / Luck: flattens the shop's level-roll curve upward (0 for now; future upgrade)


# Called by the marine when an imp lands a melee hit.
func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)
	damaged.emit(amount)


# Called (via marine.gain_health) when a health vial is picked up. Restores up to `amount`
# HP (clamped to max) and returns the HP actually restored — 0 when already full, which lets
# the vial know to stay on the map instead of being wasted.
func heal(amount: float) -> float:
	var before := health
	health = clampf(health + amount, 0.0, max_health)
	if health != before:
		health_changed.emit(health, max_health)
	return health - before


# Called (via marine.gain_xp) when a dropped XP orb is collected. Updates the
# authoritative level/xp at once; the HUD lags the bar behind via animation and
# only shows the level-up flourish/modal when the bar reaches 100% (see hud.gd).
func add_xp(amount: float) -> void:
	xp += amount
	total_xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = xp_for(level)
		leveled_up.emit(level)
	xp_changed.emit(total_xp)


## Bank souls from collected soul-motes (one per mote). Spent in the level-up shop.
func add_souls(amount: int = 1) -> void:
	souls += amount
	total_souls += amount
	souls_changed.emit(souls)


## Spend `amount` souls if affordable; returns whether the purchase went through.
func spend_souls(amount: int) -> bool:
	if amount > souls:
		return false
	souls -= amount
	souls_changed.emit(souls)
	return true


## XP needed to clear `lvl` -> lvl+1. Brotato's quadratic curve: (level + 3)^2
## (16, 25, 36, 49, ...), so each level costs progressively more. Brotato counts
## its first level-up from level 0; we start the marine at level 1, so xp_for(1)=16
## is the first level-up — the same 16/25/36 ramp, just offset by one in numbering.
func xp_for(lvl: int) -> float:
	return float((lvl + 3) * (lvl + 3))
