shader_type canvas_item;
// Screen-space "video filter" grade, ported from the delivery-game web build
// (src/postGrade.ts). Three tuned ops, applied in order to the rendered frame:
//   1. Sharpen    — 4-tap N/S/E/W unsharp mask (1px)
//   2. Clarity    — wider 8-tap unsharp mask (~2px) gated to midtones (the headline op)
//   3. Saturation — luma-preserving chroma scale
// Drawn by a full-screen ColorRect on a CanvasLayer *below* the UI (see screen_grade.gd),
// so it grades the 3D scene only — the HUD draws after, ungraded. That matches the web
// build, where this pass runs on the rendered scene and the DOM UI sits on top.
//
// Web port notes: GLSL texture2D() -> texture(), gl_FragColor -> COLOR, and the web
// uResolution texel (1/res) is the built-in SCREEN_PIXEL_SIZE here.
// Vignette / split-tone / grain from the web version are omitted — they default OFF
// there. ponytail: add them back as extra uniforms + branches if a fuller grade is wanted.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

// delivery-game DEFAULT_GRADE_PARAMS (the tuned "video filter" look).
uniform float sharpness  : hint_range(0.0, 3.0)  = 1.0;
uniform float clarity    : hint_range(-1.0, 1.0) = 1.0;
uniform float saturation : hint_range(0.0, 3.0)  = 1.35;

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 texel = SCREEN_PIXEL_SIZE;                       // 1.0 / viewport size, in screen UV
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;

	// 1) Sharpen — 4-tap unsharp mask (N/S/E/W, 1px).
	if (sharpness > 0.0) {
		vec3 n = texture(screen_texture, SCREEN_UV + vec2(0.0,  texel.y)).rgb;
		vec3 s = texture(screen_texture, SCREEN_UV + vec2(0.0, -texel.y)).rgb;
		vec3 e = texture(screen_texture, SCREEN_UV + vec2( texel.x, 0.0)).rgb;
		vec3 w = texture(screen_texture, SCREEN_UV + vec2(-texel.x, 0.0)).rgb;
		vec3 avg = (n + s + e + w) * 0.25;
		c = c + sharpness * (c - avg);
	}

	// 2) Clarity — wider ~2px unsharp mask weighted toward midtones, so highlights and
	//    shadows don't gain extra contrast. 8-tap ring around the center.
	if (abs(clarity) > 0.0001) {
		vec2 r = texel * 2.0;
		vec3 sum = vec3(0.0);
		sum += texture(screen_texture, SCREEN_UV + vec2( r.x,  0.0)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2(-r.x,  0.0)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2( 0.0,  r.y)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2( 0.0, -r.y)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2( r.x,  r.y)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2(-r.x,  r.y)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2( r.x, -r.y)).rgb;
		sum += texture(screen_texture, SCREEN_UV + vec2(-r.x, -r.y)).rgb;
		vec3 avg2 = sum * 0.125;
		float L = luma(c);
		float midtone = 1.0 - abs(L - 0.5) * 2.0;
		c = c + clarity * midtone * (c - avg2);
	}

	// 3) Saturation — preserve luma, scale chroma around it.
	if (abs(saturation - 1.0) > 0.0001) {
		float L = luma(c);
		c = mix(vec3(L), c, saturation);
	}

	COLOR = vec4(c, 1.0);
}
