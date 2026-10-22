shader_type canvas_item;

uniform sampler2D previous_frame : source_color;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

// Clear ivory linework and muted foliage, with no glow or animated lighting.
vec4 ink_color(vec3 paper) {
	float ink = 1.0 - dot(paper, vec3(0.299, 0.587, 0.114));
	float foliage = clamp((paper.g - paper.r) * 5.0, 0.0, 1.0);
	vec3 color = mix(vec3(0.96, 0.89, 0.72), vec3(0.62, 0.85, 0.66), foliage);
	float alpha = smoothstep(0.035, 0.75, ink) * 0.70;
	return vec4(color * alpha, alpha);
}

void fragment() {
	vec4 before = ink_color(texture(previous_frame, UV).rgb);
	vec4 after = ink_color(texture(TEXTURE, UV).rgb);
	vec4 blended = mix(before, after, smoothstep(0.0, 1.0, fade));
	// Blend premultiplied ink so overlapping lines never become more opaque.
	COLOR = vec4(blended.rgb / max(blended.a, 0.00001), blended.a);
}
