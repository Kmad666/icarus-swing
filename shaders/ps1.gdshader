// PS1-style lit surface: per-vertex lighting, wobbly snapped vertices,
// affine (non-perspective-correct) texture warping, nearest-filtered textures.
// Textures are mapped from world position by default, so boxes of any size
// tile cleanly; `use_uv` switches to the mesh's own UVs (the heroine's face).
shader_type spatial;
render_mode vertex_lighting, specular_disabled, diffuse_lambert;

uniform vec4 albedo : source_color = vec4(1.0);
uniform sampler2D tex : source_color, filter_nearest, repeat_enable;
uniform bool use_tex = false;
uniform bool use_uv = false;         // mesh UVs instead of world-mapped
uniform float tile = 2.0;            // world metres per texture repeat
uniform vec2 snap_res = vec2(320.0, 180.0);  // lower = wobblier
uniform vec3 emission : source_color = vec3(0.0);
uniform float self_glow = 0.0;       // glow in the surface's own colour, keeps characters readable at night
uniform bool glow_mask = false;      // texels with alpha < 1 glow (the eyes)
uniform float glow_strength = 1.5;

varying vec3 aff_uv;

void vertex() {
	vec2 uv;
	if (use_uv) {
		uv = UV;
	} else {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		vec3 wn = abs(normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz));
		uv = wn.y > 0.6 ? wp.xz : (wn.x > wn.z ? vec2(wp.z, -wp.y) : vec2(wp.x, -wp.y));
		uv /= tile;
	}
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy = floor(clip.xy / clip.w * snap_res + 0.5) / snap_res * clip.w;
	POSITION = clip;
	aff_uv = vec3(uv * clip.w, clip.w);
}

void fragment() {
	vec4 c = albedo;
	float glow = self_glow;
	if (use_tex) {
		vec4 t = texture(tex, aff_uv.xy / aff_uv.z);
		c.rgb *= t.rgb;
		if (glow_mask) {
			glow += (1.0 - t.a) * glow_strength;
		}
	}
	ALBEDO = c.rgb;
	EMISSION = emission + c.rgb * glow;
}
