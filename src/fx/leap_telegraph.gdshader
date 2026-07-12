shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

// Ground leap-charge strip: arrow chevrons that fill from the imp toward the player as it
// charges (only the charged fraction UV.x <= progress shows), pointing at the player
// (UV.x = 1). No background track, no solid fill bar — just the arrows. depth_test_disabled
// -> it draws over the terrain so hills never clip it. ALBEDO is pushed HDR (unshaded) so it
// blooms. The imp drives progress/flash each frame (see leap_telegraph.gd).

uniform float progress = 0.0;
uniform float flash = 0.0;
uniform vec3 color : source_color = vec3(1.0, 0.35, 0.08);
uniform float chevrons = 7.0;       // arrowheads along the strip
uniform float speed = 2.5;          // chevron scroll toward the target

void fragment() {
	float v = abs(UV.y - 0.5) * 2.0;                  // 0 centreline .. 1 edge
	float band = smoothstep(1.0, 0.5, v);             // soft along the width
	// Chevrons pointing toward the PLAYER (+UV.x): +skew makes the tip poke toward +x.
	float x = UV.x + v * (0.5 / chevrons);
	float saw = fract(x * chevrons - TIME * speed);
	float chev = smoothstep(0.4, 0.95, saw);
	float filled = step(UV.x, progress);              // only the charged part shows
	// Soft-fade the last arrow at the player end so scrolling chevrons flow off cleanly
	// instead of being hard-sliced by the quad edge ("cut out in the front").
	float tip = smoothstep(1.0, 1.0 - 0.5 / chevrons, UV.x);
	// Just the arrow chevrons on the charged part — no background track, no solid fill bar.
	float a = band * chev * 0.9 * filled * tip;
	a = clamp(a + flash * band, 0.0, 1.0);
	vec3 c = mix(color, vec3(1.0), flash);
	ALBEDO = c * (1.3 + flash * 3.0);                 // HDR -> blooms past glow_hdr_threshold
	ALPHA = a;
}
