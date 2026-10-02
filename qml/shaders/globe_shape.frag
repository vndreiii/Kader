#version 440
// uv spans [-1, 1] across the shape (a unit circle for dots, |v| for lines);
// w is the half extent in device pixels, giving a 1-device-pixel soft edge.
layout(location = 0) in vec2 uv;
layout(location = 1) in float w;
layout(location = 2) in vec4 color;

layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

void main() {
    float a = clamp((1.0 - length(uv)) * w, 0.0, 1.0);
    fragColor = color * a; // premultiplied
}
