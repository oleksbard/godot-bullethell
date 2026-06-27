shader_type canvas_item;
// Full-screen hell post stack, drawn by a ColorRect on a CanvasLayer *below* the UI
// (see screen_grade.gd), so it processes the rendered 3D scene only — the HUD draws
// after, untouched. Runs as ONE pass (no integer CanvasLayer slot exists between the
// grade at layer 0 and the UI at layer 1), in this order:
//   0.  Ember heat-haze — warp the lookup near hot (warm+bright) pixels; heat rises  (#5)
//   1.  Sharpen         — 4-tap unsharp mask (1px)                                (grade)
//   2.  Clarity         — 8-tap midtone unsharp (~2px), the headline grade op     (grade)
//   3.  Saturation      — luma-preserving chroma scale                            (grade)
//   3b. Contrast        — soft S-curve: darks deeper, brights hotter              (#1b)
//   4.  Cel posterize   — quantise luma into flat bands, keep hue                 (#1)
//   4b. Cel specular    — lift the brightest luma into a flat hot plateau         (#2b)
//   5.  Edges           — Sobel -> dark ink (both sides) + bright rim (lit side)   (#1/#3)
//   6.  Halftone        — dot screen that fills the shadows (comic shading)        (#2)
// Every effect has a strength uniform; set it to 0 to disable that effect cleanly.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

const vec3 SPEC_COLOR = vec3(1.0, 0.95, 0.85);   // warm-white toon highlight plateau
const vec3 RIM_COLOR  = vec3(1.0, 0.92, 0.78);   // ember-tinted lit-edge rim

// --- video grade (ported defaults) ---
uniform float sharpness  : hint_range(0.0, 3.0)  = 1.0;
uniform float clarity    : hint_range(-1.0, 1.0) = 1.0;
uniform float saturation : hint_range(0.0, 3.0)  = 1.12;

// --- #1 cel / comic ---
uniform float posterize_bands   : hint_range(1.0, 16.0) = 4.0;   // luma bands (fewer = chunkier)
uniform float posterize_amount  : hint_range(0.0, 1.0)  = 0.7;   // blend toward banded (0 = off)
uniform float outline_strength  : hint_range(0.0, 2.0)  = 0.8;   // ink-edge darkening (0 = off)
uniform float outline_threshold : hint_range(0.0, 1.0)  = 0.15;  // edge sensitivity

// --- #1b contrast / #2b cel specular / #3 rim highlight ---
uniform float contrast       : hint_range(0.0, 1.0)  = 0.35;  // S-curve punch (0 = off)
uniform float spec_threshold : hint_range(0.0, 1.0)  = 0.8;   // luma where the gloss plateau starts
uniform float spec_softness  : hint_range(0.01, 0.5) = 0.12;  // plateau edge softness
uniform float spec_strength  : hint_range(0.0, 1.0)  = 0.6;   // push toward the hot highlight (0 = off)
uniform float rim_strength   : hint_range(0.0, 1.0)  = 0.5;   // bright edge on the lit side (0 = off)
uniform float rim_threshold  : hint_range(0.0, 0.5)  = 0.08;  // how much brighter the lit side must be

// --- #2 halftone (dots in shadows) ---
uniform float halftone_strength : hint_range(0.0, 1.0)  = 0.35;  // 0 = off
uniform float halftone_scale    : hint_range(2.0, 16.0) = 6.0;   // dot cell size, px

// --- #5 ember heat-haze ---
uniform float haze_strength : hint_range(0.0, 0.02) = 0.005;     // max UV warp (0 = off)
uniform float haze_speed    : hint_range(0.0, 4.0)  = 1.6;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float scene_luma(vec2 uv) {
	return luma(texture(screen_texture, uv).rgb);
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;       // 1.0 / viewport size, in screen UV
	vec2 uv = SCREEN_UV;

	// 0) Ember heat-haze: warp the lookup near hot (warm + bright) pixels. Heat rises,
	//    so bias the wobble upward; scroll two cheap sine waves over TIME.
	vec3 probe = texture(screen_texture, uv).rgb;
	float warmth = clamp((probe.r - probe.b) * 1.5, 0.0, 1.0) * smoothstep(0.25, 0.7, luma(probe));
	if (haze_strength > 0.0 && warmth > 0.0) {
		float t = TIME * haze_speed;
		float wob = (sin(uv.y * 90.0 + t) + sin(uv.x * 70.0 - t * 1.3)) * 0.5;
		uv += vec2(wob, -abs(wob) * 1.5) * haze_strength * warmth;   // rise upward
	}

	vec3 c = texture(screen_texture, uv).rgb;

	// 1) Sharpen — 4-tap unsharp mask (N/S/E/W, 1px).
	if (sharpness > 0.0) {
		vec3 n = texture(screen_texture, uv + vec2(0.0,  texel.y)).rgb;
		vec3 s = texture(screen_texture, uv + vec2(0.0, -texel.y)).rgb;
		vec3 e = texture(screen_texture, uv + vec2( texel.x, 0.0)).rgb;
		vec3 w = texture(screen_texture, uv + vec2(-texel.x, 0.0)).rgb;
		c += sharpness * (c - (n + s + e + w) * 0.25);
	}

	// 2) Clarity — wider ~2px unsharp, weighted to midtones.
	if (abs(clarity) > 0.0001) {
		vec2 r = texel * 2.0;
		vec3 sum = vec3(0.0);
		sum += texture(screen_texture, uv + vec2( r.x,  0.0)).rgb;
		sum += texture(screen_texture, uv + vec2(-r.x,  0.0)).rgb;
		sum += texture(screen_texture, uv + vec2( 0.0,  r.y)).rgb;
		sum += texture(screen_texture, uv + vec2( 0.0, -r.y)).rgb;
		sum += texture(screen_texture, uv + vec2( r.x,  r.y)).rgb;
		sum += texture(screen_texture, uv + vec2(-r.x,  r.y)).rgb;
		sum += texture(screen_texture, uv + vec2( r.x, -r.y)).rgb;
		sum += texture(screen_texture, uv + vec2(-r.x, -r.y)).rgb;
		float L = luma(c);
		float midtone = 1.0 - abs(L - 0.5) * 2.0;
		c += clarity * midtone * (c - sum * 0.125);
	}

	// 3) Saturation — preserve luma, scale chroma around it.
	if (abs(saturation - 1.0) > 0.0001) {
		float L = luma(c);
		c = mix(vec3(L), c, saturation);
	}

	// 3b) Contrast — soft S-curve (darks deeper, brights hotter), per channel.
	if (contrast > 0.0) {
		c = mix(c, smoothstep(vec3(0.0), vec3(1.0), c), contrast);
	}

	// 4) Cel posterize — quantise luma into flat bands but keep hue (rescale by lq/L).
	if (posterize_amount > 0.0 && posterize_bands >= 1.0) {
		float L = max(luma(c), 1e-4);
		float lq = floor(L * posterize_bands + 0.5) / posterize_bands;
		c = mix(c, c * (lq / L), posterize_amount);
	}

	// 4b) Cel specular — lift the brightest luma into a flat hot plateau (toon gloss).
	if (spec_strength > 0.0) {
		float L = luma(c);
		float spec = smoothstep(spec_threshold, min(spec_threshold + spec_softness, 1.0), L);
		c = mix(c, SPEC_COLOR, spec * spec_strength);
	}

	// 5) Edges — one Sobel on scene luma (original uv so the haze warp can't smear it),
	//    used for BOTH the dark ink outline (#1) and a bright rim on the lit side (#3).
	if (outline_strength > 0.0 || rim_strength > 0.0) {
		float tl = scene_luma(SCREEN_UV + vec2(-texel.x,  texel.y));
		float ll = scene_luma(SCREEN_UV + vec2(-texel.x,  0.0));
		float bl = scene_luma(SCREEN_UV + vec2(-texel.x, -texel.y));
		float tt = scene_luma(SCREEN_UV + vec2( 0.0,     texel.y));
		float bb = scene_luma(SCREEN_UV + vec2( 0.0,    -texel.y));
		float tr = scene_luma(SCREEN_UV + vec2( texel.x,  texel.y));
		float rr = scene_luma(SCREEN_UV + vec2( texel.x,  0.0));
		float br = scene_luma(SCREEN_UV + vec2( texel.x, -texel.y));
		float gx = (tr + 2.0 * rr + br) - (tl + 2.0 * ll + bl);
		float gy = (tl + 2.0 * tt + tr) - (bl + 2.0 * bb + br);
		float edge = smoothstep(outline_threshold, outline_threshold + 0.25, sqrt(gx * gx + gy * gy));

		// Dark ink (both sides of the edge) — unchanged.
		c *= 1.0 - edge * outline_strength;

		// Bright rim — only where this pixel is the LIT side of the edge (brighter than
		// its neighbours), so silhouettes catch a hot ember-white contour.
		if (rim_strength > 0.0) {
			float side = scene_luma(SCREEN_UV) - (tl + ll + bl + tt + bb + tr + rr + br) * 0.125;
			float rim = edge * smoothstep(0.0, rim_threshold, side);
			c = mix(c, RIM_COLOR, rim * rim_strength);
		}
	}

	// 6) Halftone — axis-aligned dot grid whose dots swell as the pixel darkens, so
	//    only shadows pick up the comic dot screen; highlights stay clean.
	if (halftone_strength > 0.0) {
		float darkness = 1.0 - smoothstep(0.0, 0.55, luma(c));
		float d = length(fract(FRAGCOORD.xy / halftone_scale) - 0.5);
		float rad = sqrt(darkness) * 0.5;                       // dot area ~ darkness
		float dot_in = smoothstep(rad + 0.06, rad - 0.06, d);   // 1 inside the dot
		c *= 1.0 - dot_in * halftone_strength;
	}

	COLOR = vec4(c, 1.0);
}
