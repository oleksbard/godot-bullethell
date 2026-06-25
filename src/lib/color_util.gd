extends RefCounted
## Stateless colour helpers. Reference via `const ColorUtil := preload(...)`.

## Per-instance HSL + (caller-applied) roughness variance — the delivery-game
## convention: ~±0.04 hue, ±0.06 sat, ±0.08 value so adjacent surfaces differ.
static func vary(c: Color, rng: RandomNumberGenerator) -> Color:
	var h := fposmod(c.h + rng.randf_range(-0.04, 0.04), 1.0)
	var s := clampf(c.s + rng.randf_range(-0.06, 0.06), 0.0, 1.0)
	var v := clampf(c.v + rng.randf_range(-0.08, 0.08), 0.0, 1.0)
	return Color.from_hsv(h, s, v, c.a)
