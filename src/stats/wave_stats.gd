class_name WaveStats
extends RefCounted
## A pure record of one wave's combat, produced by CombatTracker and rendered by
## RecapView. Each gun card is a Dictionary {item, name, damage, shots, hits, kills};
## dps/accuracy are derived (kept out of the card so they can't drift).

var wave := 0
var duration := 0.0                   # seconds of active combat
var damage_dealt := 0.0
var damage_taken := 0.0
var souls_earned := 0
var kills_by_type: Dictionary = {}    # type name -> count, e.g. {"Imp": 30}
var guns: Array = []                  # Array of gun-card dicts


## Damage-per-second for a gun card (0 when the wave had no measured duration).
func dps(card: Dictionary) -> float:
	if duration <= 0.0:
		return 0.0
	return float(card.get("damage", 0.0)) / duration


## Hit fraction for a gun card (0 when it fired nothing).
func accuracy(card: Dictionary) -> float:
	var shots := int(card.get("shots", 0))
	if shots <= 0:
		return 0.0
	return float(card.get("hits", 0)) / float(shots)


## The highest-damage gun card ({} when no guns fired). Returned by reference so the
## view can flag it with is_same().
func mvp() -> Dictionary:
	var best: Dictionary = {}
	var best_dmg := -1.0
	for c in guns:
		var d := float(c.get("damage", 0.0))
		if d > best_dmg:
			best_dmg = d
			best = c
	return best


## Total kills across all enemy types.
func total_kills() -> int:
	var n := 0
	for k in kills_by_type:
		n += int(kills_by_type[k])
	return n
