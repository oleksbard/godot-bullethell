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

uniform float attack = 0.0;         // set per-imp by imp.gd (0 idle .. 1 attacking)
uniform float lunge_rate = 1.8;     // lunges per second while attacking
uniform float lunge_reach = 0.45;   // forward strike distance at full lunge (model-height units)
uniform vec3 face_dir = vec3(0.0, 0.0, -1.0);   // node-forward in mesh-local space (imp.gd sets it)

uniform float local_min_y = 0.0;    // mesh-local foot height (imp.gd sets per mesh)
uniform float local_height = 1.0;   // mesh-local model height (imp.gd sets per mesh)

uniform float hit = 0.0;            // brief white hurt-flash on a non-killing hit (imp.gd pulses it)

uniform float death = 0.0;          // 0 alive .. 1 collapsed (the corpse tweens it on death)
uniform float death_squash = 0.85;  // how flat the body crumples
uniform float death_splay = 0.5;    // how much it spreads as it collapses

// Glowing eyes: emission painted onto the body surface near two socket points (object
// space), so it rides every deform and needs no extra geometry. imp.gd sets eye_pos from
// the mesh AABB; the second eye is this one mirrored across x = 0. Fades out as it dies.
uniform vec3  eye_pos = vec3(0.14, 0.63, 0.30);   // one socket, mesh-local (imp.gd overrides)
uniform float eye_radius = 0.10;
uniform float eye_softness = 0.05;
uniform vec3  eye_emission : source_color = vec3(1.0, 0.6, 0.15);
uniform float eye_energy = 3.0;     // > glow_hdr_threshold so the eyes bloom

varying vec3 v_obj;                  // original (pre-deform) object position, for the eye mask

void vertex() {
	v_obj = VERTEX;                  // capture before deforms move it -> glow stays on the same surface patch
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

	// Attack: a coiled lunge, not a rigid slide. Each cycle: windup (pull back + crouch),
	// a fast snap where the upper body whips forward over planted feet (it pitches down at
	// the player, like a bite), then recovery. `phase` desyncs the swarm so it isn't a chorus.
	float aw = clamp(attack, 0.0, 1.0) * live;
	float u = fract(TIME * lunge_rate + phase * 0.159);    // 0..1 per lunge
	float windup  = smoothstep(0.0, 0.40, u);
	float fired   = smoothstep(0.40, 0.55, u);             // fast strike between windup and recovery
	float recover = smoothstep(0.55, 1.0, u);
	float thrust = -0.35 * windup * (1.0 - fired)          // coil back...
	             +  1.0  * fired  * (1.0 - recover);        // ...then snap forward and decay out
	float upper = smoothstep(0.05, 0.85, h);               // feet plant, torso/head whip the most
	VERTEX += fdir * thrust * lunge_reach * (0.35 + 0.65 * upper) * aw;
	VERTEX.y += (-0.08 * windup * (1.0 - fired) + 0.06 * fired * (1.0 - recover)) * local_height * aw;

	// Death: crumple flat and splay outward (the corpse node also sinks it — see imp.gd).
	VERTEX.y *= (1.0 - death_squash * dead);
	VERTEX.xz *= (1.0 + death_splay * dead);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	ROUGHNESS = 0.85;
	METALLIC = 0.0;

	// Glowing eyes: light up surface near either socket (mirror across x=0), fading on death.
	float dl = distance(v_obj, eye_pos);
	float dr = distance(v_obj, vec3(-eye_pos.x, eye_pos.y, eye_pos.z));
	float glow = 1.0 - smoothstep(eye_radius - eye_softness, eye_radius, min(dl, dr));
	glow *= 1.0 - clamp(death, 0.0, 1.0);
	ALBEDO = mix(ALBEDO, eye_emission, glow);                        // lit core, not only bloom

	EMISSION = vec3(1.0, 0.92, 0.85) * clamp(hit, 0.0, 1.0) * 1.2;   // white pop when hit
	EMISSION += eye_emission * eye_energy * glow;                    // demon eyes
}
