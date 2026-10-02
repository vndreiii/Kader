#version 440
// Ocean sphere with soft lighting, a rim light and an outer atmosphere glow.
// Pure screen-space maths: the land itself is drawn as vector dots on top.
layout(location = 0) in vec2 pos;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 center;
    float radius;
    float dpr;
    vec4 ocean;     // straight alpha
    vec4 edge;      // ocean colour at the limb
    vec4 glow;      // atmosphere colour; alpha = strength
    float glowWidth;
};

void main() {
    vec2 d = pos - center;
    float dist = length(d);
    float inside = clamp((radius - dist) * dpr + 0.5, 0.0, 1.0);

    float rr = clamp(dist / radius, 0.0, 1.0);
    float nz = sqrt(max(0.0, 1.0 - rr * rr));
    vec3 n = vec3(d.x / radius, -d.y / radius, nz);
    float light = clamp(dot(n, normalize(vec3(-0.45, 0.55, 0.70))), 0.0, 1.0);

    vec3 sea = mix(edge.rgb, ocean.rgb, smoothstep(0.0, 0.9, nz));
    sea *= 0.82 + 0.30 * light;
    float rim = pow(1.0 - nz, 4.0) * glow.a;
    vec3 body = sea + glow.rgb * rim * 0.85;
    vec4 col = vec4(body, 1.0) * ocean.a * inside;

    // atmosphere: exponential falloff outside the limb
    float outside = max(dist - radius, 0.0);
    float halo = exp(-outside / max(glowWidth, 1.0)) * (1.0 - inside) * glow.a * 0.85;
    col += vec4(glow.rgb, 1.0) * halo;

    fragColor = col * qt_Opacity;
}
