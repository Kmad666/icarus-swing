// Screen pass on the low-res game image: 15-bit colour (5 bits per channel)
// with a 4x4 ordered dither, like the PS1's framebuffer.
shader_type canvas_item;

uniform float levels = 31.0;
uniform float dither_strength = 1.0;

const float bayer[16] = float[16](
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	ivec2 p = ivec2(floor(UV * vec2(textureSize(TEXTURE, 0)))) % 4;
	float d = (bayer[p.y * 4 + p.x] / 16.0 - 0.5) * dither_strength;
	c.rgb = floor(c.rgb * levels + d + 0.5) / levels;
	COLOR = vec4(c.rgb, 1.0);
}
