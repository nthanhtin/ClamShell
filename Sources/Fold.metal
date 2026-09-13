#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[ stitchable ]] half4 foldGlass(float2 position, SwiftUI::Layer layer,
                                float2 size, float progress) {
    float p = clamp(progress, 0.0, 1.0);
    if (p < 0.0001) return layer.sample(position);
    if (p > 0.9999) return half4(0.0h, 0.0h, 0.0h, 1.0h);
    float2 uv = position / size;
    float height = 1.0 - uv.y;
    float tilt = p * 1.45;
    // Project the physical panel onto a stationary image plane, anchored at its hinge.
    float perspective = 1.0 / (1.0 - 0.28 * height * sin(tilt));
    float2 projected = float2(0.5 + (uv.x - 0.5) * perspective,
                              1.0 - height * cos(tilt) * perspective);
    float radius = p * p * (3.0 + 36.0 * height) * size.y / 900.0;
    half4 color = layer.sample(clamp(projected * size, float2(0.5), size - 0.5)) * 0.2h;
    // ponytail: 16 blur taps; use a separable blur if large 4K surfaces become costly.
    for (int i = 0; i < 16; i++) {
        float phase = float(i) * 2.399963;
        float2 offset = float2(cos(phase), sin(phase)) * sqrt((float(i) + 0.5) / 16.0) * radius;
        color += layer.sample(clamp(projected * size + offset, float2(0.5), size - 0.5)) * 0.05h;
    }
    float edge = 1.0 - smoothstep(0.49, 0.52, abs(projected.x - 0.5));
    float shade = (1.0 - p * height * 0.65) * (1.0 - smoothstep(0.86, 1.0, p));
    color.rgb = color.rgb * half(edge * shade);
    color.rgb += half3(0.025, 0.035, 0.045) * half(sin(tilt) * height * (1.0 - p));
    return half4(color.rgb, 1.0h);
}
