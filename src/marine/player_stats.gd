class_name PlayerStats
extends Node
## Minimal player stat holder the HUD binds to. take_damage() is called by the marine
## on imp hits; add_xp() is called (via marine.gain_xp) when a dropped XP orb is collected.
## Both emit signals the HUD listens to.

signal health_changed(health: float, max_health: float)
signal xp_changed(xp: float, xp_to_next: float)
signal leveled_up(level: int)

var max_health := 60.0
var health := 60.0
var level := 1
var xp := 0.0
var xp_to_next := 10.0


# Called by the marine when an imp lands a melee hit.
func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)


# Called (via marine.gain_xp) when a dropped XP orb is collected.
func add_xp(amount: float) -> void:
	xp += amount
	while xp >= xp_to_next:
		xp -= xp_to_next
		level += 1
		xp_to_next = _xp_for(level)
		leveled_up.emit(level)
	xp_changed.emit(xp, xp_to_next)


## XP needed to clear `lvl` -> lvl+1. Simple linear ramp; tune later.
static func _xp_for(lvl: int) -> float:
	return 10.0 + float(lvl - 1) * 5.0
