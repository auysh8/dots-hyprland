#version 450

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 resolution;
    vec4 fillColor;
    vec4 mainShape;
    vec4 droplet0Shape;
    vec4 droplet1Shape;
    vec4 droplet2Shape;
    vec4 blends;
} ubuf;

// Shapes contain center.xy and size.zw.
float shapeDistance(vec2 pixel, vec4 shape)
{
    if (min(shape.z, shape.w) <= 0.001)
        return 1e5;
    float radius = min(shape.z, shape.w) * 0.5;
    vec2 edge = abs(pixel - shape.xy) - shape.zw * 0.5 + vec2(radius);
    return min(max(edge.x, edge.y), 0.0) + length(max(edge, vec2(0.0))) - radius;
}

float smoothMinimum(float first, float second, float radius)
{
    if (radius <= 0.001)
        return min(first, second);
    float influence = max(radius - abs(first - second), 0.0) / radius;
    return min(first, second) - influence * influence * radius * 0.25;
}

void main()
{
    vec2 pixel = qt_TexCoord0 * ubuf.resolution;
    float surface = shapeDistance(pixel, ubuf.mainShape);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.droplet0Shape), ubuf.blends.x);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.droplet1Shape), ubuf.blends.y);
    surface = smoothMinimum(surface, shapeDistance(pixel, ubuf.droplet2Shape), ubuf.blends.z);

    // Screen derivatives keep the edge consistent under window/fractional scaling
    float aa = max(fwidth(surface), 0.001);
    float alpha = 1.0 - smoothstep(-aa * 0.5, aa * 0.5, surface);
    fragColor = ubuf.fillColor * alpha * ubuf.qt_Opacity;
}
