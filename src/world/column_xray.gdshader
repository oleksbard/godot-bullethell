shader_type spatial;
render_mode cull_disabled;
// Charred-rock column that stays FULLY OPAQUE (no alpha — so it can never read as
// translucent), and instead dissolves a soft, cyan-rimmed window where the marine
// is hidden behind it, via a dithered discard. Only the part of the column nearer
// the camera than the marine, and only when the marine is actually close to THIS
// column, opens — so distant columns stay solid.

uniform vec3 player_world;                       // marine torso, fed by Main each frame
uniform vec3 column_origin;                      // this column's world position (per instance)
uniform float near_dist = 5.0;                   // only open within this distance of the marine
uniform vec3 albedo : source_color = vec3(0.16, 0.11, 0.11);
uniform float rough = 0.9;
uniform float cut_radius = 0.17;                 // screen-space radius (fraction of viewport height)
uniform vec3 rim_color : source_color = vec3(0.25, 0.85, 1.0);
uniform float rim_energy = 1.7;

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = rough;
	METALLIC = 0.0;

	// Project the player to screen UV (NDC y is up, SCREEN_UV y is down -> flip).
	vec4 pclip = PROJECTION_MATRIX * VIEW_MATRIX * vec4(player_world, 1.0);
	vec2 puv = pclip.xy / pclip.w * 0.5 + 0.5;
	puv.y = 1.0 - puv.y;

	// Aspect-correct so the window is a circle, not an ellipse.
	vec2 d = SCREEN_UV - puv;
	d.x *= VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	float dist = length(d);

	// Gate 1: only fragments nearer the camera than the player (view -Z forward, so
	// a larger/less-negative view z is nearer). VERTEX is the view-space position.
	float pz = (VIEW_MATRIX * vec4(player_world, 1.0)).z;
	float gate = step(pz, VERTEX.z);

	// Gate 2: only when the marine is actually close to THIS column in world space.
	float wd = length(player_world.xz - column_origin.xz);
	gate *= 1.0 - smoothstep(near_dist * 0.7, near_dist, wd);

	float cut = smoothstep(cut_radius, cut_radius * 0.45, dist) * gate;

	// Dithered dissolve (interleaved-gradient noise) — keeps the material opaque and
	// depth-correct while letting the marine show through. Discard grows toward the
	// centre, where the column nearly vanishes.
	float ign = fract(52.9829189 * fract(dot(FRAGCOORD.xy, vec2(0.06711056, 0.00583715))));
	if (cut > ign) {
		discard;
	}

	// Sweet glowing rim hugging the edge of the window.
	float rim = clamp(smoothstep(cut_radius * 1.22, cut_radius, dist)
		- smoothstep(cut_radius, cut_radius * 0.6, dist), 0.0, 1.0) * gate;
	EMISSION = rim_color * rim * rim_energy;
}
