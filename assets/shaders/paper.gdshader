// Battlefield background: old paper (#efe3c8 from docs/ART_STYLE.md) with a light texture —
// soft blotches, fine grain and slightly darker edges. Drawn in code: no picture to download.
shader_type canvas_item;

uniform vec4 paper : source_color = vec4(0.937, 0.890, 0.784, 1.0);
uniform vec4 stain : source_color = vec4(0.80, 0.70, 0.52, 1.0);

varying vec2 local_position;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	local_position = VERTEX;
}

void fragment() {
	vec2 p = local_position;
	float blotches = noise(p / 90.0) * 0.6 + noise(p / 31.0) * 0.4;
	float fibres = noise(p * vec2(0.9, 0.18));
	float grain = hash(floor(p));
	vec2 edge = min(UV, 1.0 - UV);
	float vignette = 1.0 - smoothstep(0.0, 0.12, min(edge.x, edge.y));
	float darken = blotches * 0.10 + fibres * 0.03 + grain * 0.03 + vignette * 0.22;
	COLOR = vec4(mix(paper.rgb, stain.rgb, darken), 1.0);
}
