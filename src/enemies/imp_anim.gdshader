shader_type spatial;
render_mode cull_disabled;
// Vertex-animated imp (no skeleton). The walk is faked from vertex height `h`
// (0 = feet, 1 = top), so different bands of the body move differently:
//   - legs (low h) stride fore/aft along face_dir, left/right in anti-phase;
//   - hips vs shoulders counter-rotate about the vertical (the strongest "walking" tell);
//   - the body bobs and squashes at each footfall;
//   - the whole body leans into the run (top tips toward face_dir).
// `attack` eases the walk out and plays a forward jab; `death` crumples the corpse.
// Per-imp `phase` keeps the swarm out of lockstep. imp.gd supplies face_dir and the
// mesh-local foot/height (local_min_y / local_height) so `h` is correct for any model.
// Fragment is a cheap albedo-only pass (fine for tiny top-down fodder).

uniform sampler2D albedo_tex : source_color, hint_default_white;
uniform vec3 tint = vec3(1.0);      // white when a texture is set; BODY_COLOR fallback when not
uniform float phase = 0.0;
uniform float walk_freq = 8.0;

// Walk shaping (all scale-independent — strides/bob are fractions of model height).
uniform float stride = 0.18;        // fore/aft leg swing
uniform float twist = 0.22;         // hip/shoulder counter-rotation (radians)
uniform float lean_run = 0.16;      // forward lean into the run (radians-ish)
uniform float bob = 0.08;           // vertical bob across a step
uniform float squash = 0.10;        // footfall squash/stretch

uniform float attack = 0.0;         // set per-imp by imp.gd
uniform float jab_freq = 9.0;
uniform float jab_reach = 0.35;     // forward lunge distance at full attack (model units)
uniform vec3 face_dir = vec3(0.0, 0.0, -1.0);   // node-forward in mesh-local space (imp.gd sets it)

uniform float local_min_y = 0.0;    // mesh-local foot height (imp.gd sets per mesh)
uniform float local_height = 1.0;   // mesh-local model height (imp.gd sets per mesh)

uniform float hit = 0.0;            // brief white hurt-flash on a non-killing hit (imp.gd pulses it)

uniform float death = 0.0;          // 0 alive .. 1 collapsed (the corpse tweens it on death)
uniform float death_squash = 0.85;  // how flat the body crumples
uniform float death_splay = 0.5;    // how much it spreads as it collapses

void vertex() {
	float dead = clamp(death, 0.0, 1.0);
	float live = 1.0 - dead;
	float idle = (1.0 - clamp(attack, 0.0, 1.0)) * live;   // walk only when not attacking/dying

	vec3 fdir = normalize(face_dir);
	vec3 side = normalize(cross(vec3(0.0, 1.0, 0.0), fdir));
	float yy = VERTEX.y - local_min_y;                     // height above the feet
	float h = clamp(yy / max(local_height, 0.0001), 0.0, 1.0);

	float t = TIME * walk_freq + phase;
	float s = sin(t);
	float lr = sign(dot(VERTEX, side) + 0.00001);          // -1 left limb, +1 right limb

	// 1) Leg stride: the lower body swings fore/aft, left & right in anti-phase.
	float leg = smoothstep(0.55, 0.05, h);
	VERTEX += fdir * (s * lr) * stride * local_height * leg * idle;

	// 2) Hip/shoulder counter-rotation about the vertical axis — the big walking cue.
	float ang = s * twist * (h - 0.5) * idle;
	float c = cos(ang);
	float sn = sin(ang);
	vec2 xz = mat2(vec2(c, -sn), vec2(sn, c)) * vec2(VERTEX.x, VERTEX.z);
	VERTEX.x = xz.x;
	VERTEX.z = xz.y;

	// 3) Bob across the step + squash/widen at each footfall (abs(s) peaks mid-step).
	float lift = abs(s);
	VERTEX.y += (lift - 0.4) * bob * local_height * idle;
	float sq = (0.5 - lift) * squash * idle;               // >0 near footfall
	VERTEX.y *= (1.0 - sq);
	VERTEX.xz *= (1.0 + sq * 0.5);

	// 4) Forward lean into the run (top tips toward face_dir, proportional to height).
	VERTEX += fdir * (lean_run * idle) * yy;

	// Attack: repeated forward jabs while `attack` is up (cut off while dying).
	float jab = attack * live * (0.5 - 0.5 * cos(TIME * jab_freq + phase));
	VERTEX += fdir * jab * jab_reach;

	// Death: crumple flat and splay outward (the corpse node also sinks it — see imp.gd).
	VERTEX.y *= (1.0 - death_squash * dead);
	VERTEX.xz *= (1.0 + death_splay * dead);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;
	EMISSION = vec3(1.0, 0.92, 0.85) * clamp(hit, 0.0, 1.0) * 1.2;   // white pop when hit
}
