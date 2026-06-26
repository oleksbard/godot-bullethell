class_name PlayerStats
extends Node
## Minimal player stat holder the HUD binds to. take_damage() is called by the marine
## on imp hits; add_xp() is called (via marine.gain_xp) when a dropped XP orb is collected.
## Both emit signals the HUD listens to.

signal health_changed(health: float, max_health: float)
signal xp_changed(total_xp: float)        # monotonic lifetime XP; the HUD animates the bar from it
signal leveled_up(level: int)             # authoritative level event (the HUD fires the flourish/modal when its bar fills)
signal souls_changed(souls: int)          # banked soul count changed (HUD + level-up menu show it)

var max_health := 60.0
var health := 60.0
var level := 1
var xp := 0.0
var xp_to_next := 10.0
var total_xp := 0.0                       # never decreases; lets the HUD animate across level boundaries
var souls := 0                            # currency banked from collected soul-motes; spent on upgrades later


# Called by the marine when an imp lands a melee hit.
func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)


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


## Bank souls from collected soul-motes (one per mote). Spent on upgrades later.
func add_souls(amount: int = 1) -> void:
	souls += amount
	souls_changed.emit(souls)


## XP needed to clear `lvl` -> lvl+1. Simple linear ramp; tune later.
func xp_for(lvl: int) -> float:
	return 10.0 + float(lvl - 1) * 5.0
