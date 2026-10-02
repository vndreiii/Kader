#version 440
layout(location = 0) in vec4 vertexCoord;
layout(location = 0) out vec2 pos;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 center;
    float radius;
    float dpr;
    vec4 ocean;
    vec4 edge;
    vec4 glow;
    float glowWidth;
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    pos = vertexCoord.xy;
    gl_Position = qt_Matrix * vertexCoord;
}
