#include <metal_stdlib>
using namespace metal;

// One-pass grade, after Lampa's Ironstone shaders: read the camera pixel, apply the preset LUT,
// add halation from a blurred highlight mask, add film grain. The formulas are mirrored in
// CameraCore/FilmMath.swift, where they are tested.

// Must match `GradeParams` in MetalGrader.swift: scalars only, so both sides lay it out the same way.
struct GradeParams {
    int originX;
    int originY;
    int width;
    int height;
    int mirror;
    int inputKind;      // 0 = BGRA, 1 = 10-bit video-range BT.2020 Y'CbCr (Apple Log)
    int chromaShiftX;
    int chromaShiftY;
    int hasLUT;
    float lutScale;
    float lutOffset;
    float grain;
    float grainOffsetX;
    float grainOffsetY;
    float grainScale;
    float halation;
};

constant float3 kLuma = float3(0.299, 0.587, 0.114);
constant float3 kHalationTint = float3(1.0, 0.39, 0.1);

constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler linearRepeat(coord::normalized, address::repeat, filter::linear);

static uint2 sourcePoint(uint2 gid, constant GradeParams &p) {
    uint x = p.mirror != 0 ? uint(p.width - 1) - gid.x : gid.x;
    return uint2(uint(p.originX) + x, uint(p.originY) + gid.y);
}

static float3 readSource(texture2d<float, access::read> luma,
                         texture2d<float, access::read> chroma,
                         uint2 point,
                         constant GradeParams &p) {
    if (p.inputKind == 0) {
        return luma.read(point).rgb;
    }
    // 10-bit codes sit in the top bits of 16-bit samples, so unorm * 65535 / 64 is the code.
    const float toCode = 65535.0 / 64.0;
    float y = luma.read(point).r * toCode;
    float2 c = chroma.read(uint2(point.x >> uint(p.chromaShiftX), point.y >> uint(p.chromaShiftY))).rg * toCode;
    float Y = (y - 64.0) / 876.0;
    float Cb = (c.x - 512.0) / 896.0;
    float Cr = (c.y - 512.0) / 896.0;
    return saturate(float3(Y + 1.4746 * Cr, Y - 0.16455 * Cb - 0.57135 * Cr, Y + 1.8814 * Cb));
}

static float3 applyLUT(float3 color, texture3d<float> lut, constant GradeParams &p) {
    if (p.hasLUT == 0) {
        return color;
    }
    float3 coordinate = saturate(color) * p.lutScale + p.lutOffset;
    return lut.sample(linearClamp, coordinate).rgb;
}

/// Highlight mask at reduced size. Each thread samples the graded color at the middle of its block.
kernel void halationMask(texture2d<float, access::read> luma [[texture(0)]],
                         texture2d<float, access::read> chroma [[texture(1)]],
                         texture3d<float> lut [[texture(2)]],
                         texture2d<float, access::write> mask [[texture(3)]],
                         constant GradeParams &p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    uint maskWidth = mask.get_width();
    uint maskHeight = mask.get_height();
    if (gid.x >= maskWidth || gid.y >= maskHeight) {
        return;
    }
    uint2 outputPoint = uint2(min(uint((float(gid.x) + 0.5) * float(p.width) / float(maskWidth)), uint(p.width - 1)),
                              min(uint((float(gid.y) + 0.5) * float(p.height) / float(maskHeight)), uint(p.height - 1)));
    float3 color = applyLUT(readSource(luma, chroma, sourcePoint(outputPoint, p), p), lut, p);
    float t = saturate((dot(color, kLuma) - 0.55) / 0.45);
    float k = saturate(7.5 * t);
    float m = k * k * (3.0 - 2.0 * k) * t * t;
    mask.write(float4(m, m, m, 1.0), gid);
}

kernel void grade(texture2d<float, access::read> luma [[texture(0)]],
                  texture2d<float, access::read> chroma [[texture(1)]],
                  texture3d<float> lut [[texture(2)]],
                  texture2d<float> glow [[texture(3)]],
                  texture2d<float> grain [[texture(4)]],
                  texture2d<float, access::write> destination [[texture(5)]],
                  constant GradeParams &p [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(p.width) || gid.y >= uint(p.height)) {
        return;
    }
    float3 color = applyLUT(readSource(luma, chroma, sourcePoint(gid, p), p), lut, p);

    if (p.halation > 0.0) {
        float2 uv = (float2(gid) + 0.5) / float2(float(p.width), float(p.height));
        float m = glow.sample(linearClamp, uv).r;
        float amount = p.halation * saturate(0.77 - dot(color, kLuma)) * m;
        color = saturate(color * (1.0 - amount) + amount * kHalationTint);
    }

    if (p.grain > 0.0) {
        float2 size = float2(float(grain.get_width()), float(grain.get_height())) * p.grainScale;
        float2 uv = (float2(gid) + float2(p.grainOffsetX, p.grainOffsetY)) / size;
        float noise = grain.sample(linearRepeat, uv).r - 0.5;
        float y = dot(color, kLuma);
        float weight = y > 0.5 ? 1.12 - y : y + 0.18;
        color = saturate(color + p.grain * weight * noise);
    }

    destination.write(float4(color, 1.0), gid);
}
