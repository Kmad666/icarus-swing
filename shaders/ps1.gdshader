// PS1-style lit surface: per-vertex lighting, wobbly snapped vertices,
// affine (non-perspective-correct) texture warping, nearest-filtered textures.
// Textures are mapped from world position, so boxes of any size tile cleanly.
shader_type spatial;
render_mode vertex_lighting, specular_disabled, diffuse_lambert;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform bool use_tex = false;
uniform float tile = 2.0;            // world metres per texture repeat
uniform vec2 snap_res = vec2(200.0, 112.0);  // lower = wobblier
uniform vec3 emission : source_color = vec3(0.0);

varying vec3 aff_uv;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wn = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
	vec2 uv = wn.y > 0.6 ? wp.xz : (wn.x > wn.z ? vec2(wp.z, -wp.y) : vec2(wp.x, -wp.y));
	uv /= tile;
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy = floor(clip.xy / clip.w * snap_res + 0.5) / snap_res * clip.w;
	POSITION = clip;
	aff_uv = vec3(uv * clip.w, clip.w);
}

void fragment() {
	vec4 c = albedo;
	if (use_tex) {
		c *= texture(tex, aff_uv.xy / aff_uv.z);
	}
	ALBEDO = c.rgb;
	EMISSION = emission;
}
