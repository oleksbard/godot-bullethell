# Code quality (GDScript)

Rules for readable, consistent GDScript in a small–medium project. Based on the
official [GDScript style guide](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html).

## Naming

| Kind | Convention | Example |
| --- | --- | --- |
| Files / scripts | `snake_case.gd` | `grass_field.gd` |
| Classes (`class_name`, nodes, scenes) | `PascalCase` | `class_name GrassField` |
| Functions & variables | `snake_case` | `func plant_field()`, `var blade_count` |
| Private members (intended-internal) | leading `_` | `var _clock`, `func _settle()` |
| Constants & enum values | `CONSTANT_CASE` | `const MAX_LEAN`, `WIND_FREQ` |
| Signals | `snake_case`, past tense | `signal grass_mowed(count)` |

Virtual/engine callbacks keep their `_` (`_ready`, `_process`). Don't prefix a
member with `_` unless it's genuinely private — `_` is a contract, not decoration.

## Static typing — required

Type every variable, parameter, and return. It catches errors at parse time,
documents intent, and speeds up GDScript.

```gdscript
# Good
func island_radius(angle: float) -> float: ...
var _blades: Array[Node3D] = []

# Avoid
func island_radius(angle): ...
var blades = []
```

Use inference (`:=`) when the right-hand type is obvious; use an explicit type
when it isn't, or for empty collections (`var items: Array[Foo] = []`).

## Member order

One class = one file. Declare members in this order (matches the style guide):

1. `@tool` / `class_name` / `extends` / `## docstring`
2. signals
3. enums
4. constants
5. `@export` variables
6. public variables
7. private variables (`_`)
8. `@onready` variables
9. `_init`, `_ready`, other virtuals
10. public methods
11. private methods (`_`)

## Functions

- **One job per function.** If you can't name it without "and", split it.
- Keep them short; extract a private helper rather than nesting 3+ levels.
- Prefer early `return` over deep `if` nesting.
- No magic numbers in bodies — promote to a named `const` or `@export`.

## Comments

- Comment **why**, not what. The code says what.
- Use `##` docstrings on scripts and non-obvious public functions (they show in
  the editor).
- Delete commented-out code; git remembers it.

## Constants vs exports

- Tuning values a designer might touch → `@export` (visible in the inspector,
  per-instance). Internal invariants → `const`.
- Group related constants with a blank-line section and a one-line comment
  (e.g. `# --- Bending ---`).

## In this project

- We already type most code and group tuning constants at the top of each script
  — keep that up.
- Add `class_name` to every script during the refactor so types are first-class
  and cross-references stop going through `preload("res://Main.gd")`.
- Magic literals still live in mesh/builder code (offsets, sizes); the refactor
  promotes the load-bearing ones to named constants.
