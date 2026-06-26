class_name PlayerStats
extends Node
## Minimal player stat holder the HUD binds to. Combat damage and on-kill XP
## aren't wired yet — these are real values; take_damage()/add_xp() are the hooks
## those systems call when they land. Until then the HUD just shows the start state.

signal health_changed(health: float, max_health: float)
signal xp_changed(xp: float, xp_to_next: float)
signal leveled_up(level: int)

var max_health := 60.0
var health := 60.0
var level := 1
var xp := 0.0
var xp_to_next := 10.0


# ponytail: stub — call from enemy-contact damage when that exists.
func take_damage(amount: float) -> void:
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)


# ponytail: stub — call on imp kill when XP drops are wired.
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
