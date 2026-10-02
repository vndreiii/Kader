#version 440
// Antialiased shape batch of the globe (land dots, borders, city markers).
layout(location = 0) in vec4 vertexCoord;
layout(location = 1) in vec2 vertexUv;
layout(location = 2) in float vertexW;
layout(location = 3) in vec4 vertexColor;

layout(location = 0) out vec2 uv;
layout(location = 1) out float w;
layout(location = 2) out vec4 color;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
};

out gl_PerVertex { vec4 gl_Position; };

void main() {
    uv = vertexUv;
    w = vertexW;
    color = vertexColor * qt_Opacity;
    gl_Position = qt_Matrix * vertexCoord;
}
