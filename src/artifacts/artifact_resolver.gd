class_name ArtifactResolver
extends RefCounted
## Pure resolution of a backpack layout into per-gun modifiers. Two passes:
##   1. effective magnitude per artifact (stacking + Resonator amplification)
##   2. per gun: gather reaching-ADJACENT + all GLOBAL artifact effects, multiply in.
## No tree access -> fully unit-testable. EXPANSION items are ignored. Reference via preload.

const GunModsScript := preload("res://src/weapons/gun_mods.gd")
const WeaponCatalogScript := preload("res://src/weapons/weapon_catalog.gd")
const WeaponDefScript := preload("res://src/weapons/weapon_def.gd")


## Returns { gun InventoryItem : GunMods }. Every gun gets a GunMods (identity if unbuffed).
static func resolve(backpack) -> Dictionary:
	return resolve_full(backpack)["mods"]


## Full resolution for the UI. Returns:
##   "mods":        { gun : GunMods }          — the per-gun multipliers (== resolve())
##   "by_gun":      { gun : [artifact, ...] }  — which artifacts buff each gun
##   "by_artifact": { artifact : [gun, ...] }  — which guns each artifact reaches
## Only stat artifacts (Rune/Furnace/...) appear as sources; amps/conduits buff indirectly.
static func resolve_full(backpack) -> Dictionary:
	var guns: Array = []
	var artifacts: Array = []
	for it in backpack.items_in_reading_order():
		if it.item_type == WeaponDefScript.ItemType.ARTIFACT:
			artifacts.append(it)
		elif it.item_type == WeaponDefScript.ItemType.GUN:
			guns.append(it)

	# Pass 1: each artifact's resolved gun-stat multiplier (stacking + Resonator).
	var resolved: Dictionary = {}     # artifact -> {"stat","mul"} or {} (amp/conduit)
	for a in artifacts:
		resolved[a] = _resolved_effect(a, backpack)

	# Pass 2: apply to guns, recording the source artifacts both directions.
	var mods: Dictionary = {}
	var by_gun: Dictionary = {}
	var by_artifact: Dictionary = {}
	for a in artifacts:
		by_artifact[a] = []
	for g in guns:
		var gm := GunModsScript.new()
		var sources: Array = []
		for a in artifacts:
			var r: Dictionary = resolved[a]
			if r.is_empty():
				continue
			var scope: int = _def_of(a).effect.get("scope", -1)
			var applies := false
			if scope == WeaponDefScript.Scope.GLOBAL:
				applies = true
			elif scope == WeaponDefScript.Scope.ADJACENT:
				applies = _reaches(a, g, backpack)
			if applies:
				_apply(gm, r)
				sources.append(a)
				by_artifact[a].append(g)
		mods[g] = gm
		by_gun[g] = sources
	return {"mods": mods, "by_gun": by_gun, "by_artifact": by_artifact}


static func _def_of(item) -> WeaponDefScript:
	return WeaponCatalogScript.get_def(item.kind)


## Resolve one artifact into {"stat","mul"} (or {} for amps/conduits/non-stat). Folds in
## per-neighbour stacking and Resonator amplification of the bonus.
static func _resolved_effect(a, backpack) -> Dictionary:
	var e: Dictionary = _def_of(a).effect
	if not e.has("stat"):
		return {}
	var bonus := 0.0                     # signed bonus over 1.0 (e.g. +0.4 for x1.4, -0.4 for x0.6)
	if e.has("mul"):
		bonus = float(e["mul"]) - 1.0
	elif e.has("mul_per"):
		var count := _stack_count(a, String(e.get("per", "")), backpack)
		bonus = minf(float(e.get("cap", 1.0e9)), float(e["mul_per"]) * float(count))
	for other in backpack.adjacent_items(a):
		if other.item_type == WeaponDefScript.ItemType.ARTIFACT and _def_of(other).is_amplifier():
			bonus *= float(_def_of(other).effect.get("mul", 1.0))
	return {"stat": String(e["stat"]), "mul": 1.0 + bonus}


static func _stack_count(a, per: String, backpack) -> int:
	var n := 0
	for other in backpack.adjacent_items(a):
		if per == "adjacent_gun" and other.item_type == WeaponDefScript.ItemType.GUN:
			n += 1
		elif per == "adjacent_artifact" and other.item_type == WeaponDefScript.ItemType.ARTIFACT:
			n += 1
	return n


## Does artifact `a` reach gun `g` — directly adjacent, or through a chain of Conduits?
static func _reaches(a, g, backpack) -> bool:
	if backpack.adjacent_items(a).has(g):
		return true
	var visited: Dictionary = {}
	var frontier: Array = []
	for n in backpack.adjacent_items(a):
		if _is_conduit(n):
			visited[n] = true
			frontier.append(n)
	while not frontier.is_empty():
		var c = frontier.pop_back()
		for n in backpack.adjacent_items(c):
			if n == g:
				return true
			if _is_conduit(n) and not visited.has(n):
				visited[n] = true
				frontier.append(n)
	return false


static func _is_conduit(item) -> bool:
	return item.item_type == WeaponDefScript.ItemType.ARTIFACT and _def_of(item).is_conduit()


static func _apply(mods, r: Dictionary) -> void:
	var m: float = r["mul"]
	match r["stat"]:
		"damage": mods.damage_mul *= m
		"fire_rate": mods.fire_rate_mul *= m
		"reload": mods.reload_mul *= m
