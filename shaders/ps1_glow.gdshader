// PS1-style glow that ignores fog, so lantern flames stay visible far away.
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;   // cuts through the fog

uniform vec4 albedo : source_color = vec4(1.0);
uniform vec2 snap_res = vec2(200.0, 112.0);

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	clip.xy = floor(clip.xy / clip.w * snap_res + 0.5) / snap_res * clip.w;
	POSITION = clip;
}

void fragment() {
	ALBEDO = albedo.rgb;
}
