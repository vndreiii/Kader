#version 440

// Screen-space pixel grid. The effect covers the whole image area; each
// fragment is mapped back into image space from the current zoom/pan, so no
// giant scaled quad is involved and cells line up exactly with source texels.

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 viewSize;      // size of this item in px
    vec2 imageCenter;   // on-screen centre of the image, in item px (includes pan)
    vec2 imageScreen;   // on-screen size of the whole image, in px (painted * zoom)
    vec2 imagePixels;   // source image size in texels
    float gridAlpha;
};

layout(binding = 1) uniform sampler2D sourceTexture;


void main() {
    if (gridAlpha <= 0.001) { fragColor = vec4(0.0); return; }

    vec2 p = qt_TexCoord0 * viewSize;
    vec2 rel = (p - imageCenter) / imageScreen + 0.5;     // 0..1 across the image
    if (any(lessThan(rel, vec2(0.0))) || any(greaterThanEqual(rel, vec2(1.0)))) {
        fragColor = vec4(0.0);
        return;
    }

    vec2 uv = rel * imagePixels;
    vec2 f = fract(uv);
    vec2 cell = imageScreen / imagePixels;                 // screen px per texel
    vec2 d = min(f, 1.0 - f) * cell;                       // distance to nearest edge, px
    // Two-tone hairline (dark core, light halo): reads on any colour, and the
    // look never flips between neighbouring cells like a luminance pick would.
    float e = min(d.x, d.y);                               // px from nearest cell edge
    float core = 1.0 - smoothstep(0.35, 0.9, e);
    float halo = (1.0 - smoothstep(0.9, 1.7, e)) * (1.0 - core);
    float aDark  = core * 0.42;
    float aLight = halo * 0.22;
    // The shader draws the photo itself (nearest texel) as well as the grid, so
    // the cells and the pixels they outline can never drift apart.
    vec3 base = texture(sourceTexture, (floor(uv) + 0.5) / imagePixels).rgb;
    float aLines = (aDark + aLight) * gridAlpha;
    vec3 lineRgb = (aDark * vec3(0.0) + aLight * vec3(1.0)) / max(aDark + aLight, 1e-4);
    vec3 outRgb = mix(base, lineRgb, aLines);
    fragColor = vec4(outRgb, 1.0) * qt_Opacity;
}
