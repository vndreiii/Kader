#version 440

// Direct port of cobe's (https://github.com/shuding/cobe) globe.frag.glslx —
// a fullscreen raymarched sphere with a procedural Fibonacci-lattice dot field.
// No 3D mesh: the "globe" is entirely fragment-shader math over a flat quad.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 uResolution;
    vec2 offset;
    vec2 rotation;      // (phi, theta)
    float dots;
    float scale;
    vec3 baseColor;
    vec3 glowColor;
    vec4 renderParams;  // (dotsBrightness, diffuse, dark, opacity)
    float mapBaseBrightness;
};

layout(binding = 1) uniform sampler2D uTexture;

const float sqrt5 = 2.236068;
const float PI = 3.141593;
const float kTau = 6.283185;
const float kPhi = 1.618034;
const float r = 0.8;

float byDots;

mat3 rotate(float theta, float phi) {
    float cx = cos(theta);
    float cy = cos(phi);
    float sx = sin(theta);
    float sy = sin(phi);
    return mat3(
        cy, sy * sx, -sy * cx,
        0.0, cx, sx,
        sy, cy * -sx, cy * cx
    );
}

vec3 nearestFibonacciLattice(vec3 p, out float m) {
    p = p.xzy;

    float k = max(2.0, floor(log2(sqrt5 * dots * PI * (1.0 - p.z * p.z)) * 0.72021));

    vec2 f = floor(pow(kPhi, k) / sqrt5 * vec2(1.0, kPhi) + 0.5);
    vec2 br1 = fract((f + 1.0) * (kPhi - 1.0)) * kTau - 3.883222;
    vec2 br2 = -2.0 * f;
    vec2 sp = vec2(atan(p.y, p.x), p.z - 1.0);
    vec2 c = floor(vec2(br2.y * sp.x - br1.y * (sp.y * dots + 1.0), -br2.x * sp.x + br1.x * (sp.y * dots + 1.0)) / (br1.x * br2.y - br2.x * br1.y));

    float mindist = PI;
    vec3 minip = vec3(0.0);
    for (float s = 0.0; s < 4.0; s += 1.0) {
        vec2 o = vec2(mod(s, 2.0), floor(s * 0.5));
        float idx = dot(f, c + o);
        if (idx > dots) continue;

        float a = idx;
        float b = 0.0;
        if (a >= 16384.0) { a -= 16384.0; b += 0.868872; }
        if (a >= 8192.0)  { a -= 8192.0;  b += 0.934436; }
        if (a >= 4096.0)  { a -= 4096.0;  b += 0.467218; }
        if (a >= 2048.0)  { a -= 2048.0;  b += 0.733609; }
        if (a >= 1024.0)  { a -= 1024.0;  b += 0.866804; }
        if (a >= 512.0)   { a -= 512.0;   b += 0.433402; }
        if (a >= 256.0)   { a -= 256.0;   b += 0.216701; }
        if (a >= 128.0)   { a -= 128.0;   b += 0.108351; }
        if (a >= 64.0)    { a -= 64.0;    b += 0.554175; }
        if (a >= 32.0)    { a -= 32.0;    b += 0.777088; }
        if (a >= 16.0)    { a -= 16.0;    b += 0.888544; }
        if (a >= 8.0)     { a -= 8.0;     b += 0.944272; }
        if (a >= 4.0)     { a -= 4.0;     b += 0.472136; }
        if (a >= 2.0)     { a -= 2.0;     b += 0.236068; }
        if (a >= 1.0)     { a -= 1.0;     b += 0.618034; }

        float theta = fract(b) * kTau;

        float cosphi = 1.0 - 2.0 * idx * byDots;
        float sinphi = sqrt(max(0.0, 1.0 - cosphi * cosphi));
        vec3 samp = vec3(cos(theta) * sinphi, sin(theta) * sinphi, cosphi);

        float dist = length(p - samp);

        if (dist < mindist) {
            mindist = dist;
            minip = samp;
        }
    }

    m = mindist;
    return minip.xzy;
}

void main() {
    byDots = 1.0 / dots;

    vec2 invResolution = 1.0 / uResolution;

    vec2 fragCoord = qt_TexCoord0 * uResolution;
    vec2 uv = ((fragCoord * invResolution) * 2.0 - 1.0) / scale - offset * vec2(1.0, -1.0) * invResolution;
    uv.x *= uResolution.x * invResolution.y;

    float l = dot(uv, uv);
    float glowFactor = 0.0;

    vec4 color = vec4(0.0);

    if (l <= r * r) {
        float dis;
        vec3 p = normalize(vec3(uv, sqrt(max(0.0, r * r - l))));
        mat3 rot = rotate(rotation.y, rotation.x);
        float dotNL = p.z;

        vec3 gP = nearestFibonacciLattice(p * rot, dis);

        float gPhi = asin(clamp(gP.y, -1.0, 1.0));
        float cosPhi = cos(gPhi);
        float gTheta = cosPhi > 0.0001 ? acos(clamp(-gP.x / cosPhi, -1.0, 1.0)) : 0.0;
        if (gP.z < 0.0) gTheta = -gTheta;

        // U: exact port of cobe's longitude term (globe.frag.glslx:113), wrapped via
        // fract() since it can go negative — cobe relies on the sampler's default
        // GL_REPEAT for this, which fract() replicates without depending on QML's
        // ShaderEffectSource.wrapMode matching GL semantics.
        // V: derived directly against assets/globe-world-mask.png's actual pixel
        // layout (row 0 = north pole, standard equirect) — verified by placing a
        // known real-world coordinate on the raw PNG and confirming it lands on
        // land at the right coastline. gPhi is latitude in radians, so
        // V = 0.5 - gPhi/PI (not + — that swaps north/south).
        float mapColor = max(texture(uTexture, vec2(fract((gTheta * 0.5) / PI), 0.5 - (gPhi / PI))).x, mapBaseBrightness);

        float samp = mapColor
            * smoothstep(0.008, 0.0, dis)
            * pow(dotNL, renderParams.y)
            * renderParams.x;
        vec4 layer = vec4(baseColor
            * (mix((1.0 - samp) * pow(dotNL, 0.4), samp, renderParams.z) + 0.1)
            + pow(1.0 - dotNL, 4.0) * glowColor
        , 1.0);

        color += layer * (1.0 + renderParams.w) * 0.5;

        glowFactor = (1.0 - l) * (1.0 - l) * smoothstep(0.0, 1.0, 0.2 / (l - r * r));
    } else {
        float outD = sqrt(0.2 / (l - r * r));
        glowFactor = smoothstep(0.5, 1.0, outD / (outD + 1.0));
    }

    fragColor = (color + vec4(glowFactor * glowColor, glowFactor)) * qt_Opacity;
}
