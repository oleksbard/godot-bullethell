shader_type spatial;
render_mode cull_disabled;
// Untextured molten material for the TitleMesh. The lava heat is baked per-vertex
// into COLOR by src/lib/title_mesh.gd; here we just emit it (× energy for HDR bloom)
// over a dark charred-iron albedo that shows through the cooler valleys. No textures.

uniform vec3 char_color : source_color = vec3(0.06, 0.05, 0.05);
uniform float emission_energy = 1.15;

void fragment() {
	ALBEDO = char_color;
	METALLIC = 0.35;
	ROUGHNESS = 0.6;
	EMISSION = COLOR.rgb * emission_energy;
}
