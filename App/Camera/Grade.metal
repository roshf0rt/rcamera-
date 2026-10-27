#include <metal_stdlib>
using namespace metal;

// One-pass grade, after Lampa's Ironstone shaders: read the camera pixel, sharpen and fringe it, apply
// the manual regulators, apply the preset LUT, add halation and bloom from a blurred highlight mask,
// add film grain. The formulas are mirrored in CameraCore/FilmMath.swift and CameraCore/ToneMath.swift,
// where they are tested.

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
    // Crossfade from the previous preset's LUT: 1 = all previous, 0 = all current.
    int hasPreviousLUT;
    float previousLutScale;
    float previousLutOffset;
    float previousMix;
    // Manual regulators, applied before the LUT. Neutral values change nothing.
    float exposure;
    float temp;
    float tint;
    float contrast;
    float shadows;
    float midpoint;
    float highlights;
    float fade;
    float shoulderKnee;   // 1 = no roll-off
    float saturation;     // already multiplied by (1 - 0.6 * mute)
    float hueCos;
    float hueSin;
    int hasHue;
    float filmStrength;   // how much of the graded colour shows over the regulated one
    float bloom;
    float sharpness;      // negative softens
    float fringe;         // chromatic aberration, 0...4
};

constant float3 kLuma = float3(0.299, 0.587, 0.114);
constant float3 kHalationTint = float3(1.0, 0.39, 0.1);

constexpr sampler linearClamp(coord::normalized, address::clamp_to_edge, filter::linear);
constexpr sampler linearRepeat(coord::normalized, address::repeat, filter::linear);

static uint2 sourcePoint(uint2 gid, constant GradeParams &p) {
    uint x = p.mirror != 0 ? uint(p.width - 1) - gid.x : gid.x;
    return uint2(uint(p.originX) + x, uint(p.originY) + gid.y);
}

/// A point inside the crop, offset by `d` and clamped to the crop's edges.
static uint2 offsetPoint(uint2 gid, int2 d, constant GradeParams &p) {
    int x = clamp(int(gid.x) + d.x, 0, p.width - 1);
    int y = clamp(int(gid.y) + d.y, 0, p.height - 1);
    return uint2(uint(x), uint(y));
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

/// The camera pixel at `gid` after sharpness and chromatic aberration.
static float3 readFiltered(texture2d<float, access::read> luma,
                           texture2d<float, access::read> chroma,
                           uint2 gid,
                           constant GradeParams &p) {
    float3 c = readSource(luma, chroma, sourcePoint(gid, p), p);
    if (p.sharpness != 0.0) {
        float3 around = readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(1, 0), p), p), p)
                      + readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(-1, 0), p), p), p)
                      + readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(0, 1), p), p), p)
                      + readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(0, -1), p), p), p);
        c = saturate(c + p.sharpness * (c - around * 0.25));
    }
    if (p.fringe > 0.0) {
        // Red spreads outwards and blue inwards, more towards the corners.
        float2 centred = (float2(gid) + 0.5) / float2(float(p.width), float(p.height)) - 0.5;
        int2 shift = int2(round(centred * p.fringe * 4.0));
        float red = readSource(luma, chroma, sourcePoint(offsetPoint(gid, shift, p), p), p).r;
        float blue = readSource(luma, chroma, sourcePoint(offsetPoint(gid, -shift, p), p), p).b;
        c = float3(red, c.g, blue);
    }
    return c;
}

static float toneRegion(float x, constant GradeParams &p) {
    float inverse = 1.0 - x;
    return x + 0.15 * (p.shadows * inverse * inverse + p.midpoint * 4.0 * x * inverse + p.highlights * x * x);
}

static float shoulder(float x, float knee) {
    if (knee >= 1.0 || x <= knee) {
        return x;
    }
    float span = 1.0 - knee;
    return knee + span * (1.0 - exp(-(x - knee) / span));
}

/// The manual regulators, in the order `ToneMath.regulate` runs them.
static float3 regulate(float3 c, constant GradeParams &p) {
    c *= p.exposure;
    c.r += 0.06 * p.temp + 0.02 * p.tint;
    c.g -= 0.04 * p.tint;
    c.b += -0.06 * p.temp + 0.02 * p.tint;
    c = float3(toneRegion(c.r, p), toneRegion(c.g, p), toneRegion(c.b, p));
    c = (c - 0.5) * p.contrast + 0.5;
    c = c * (1.0 - 0.25 * p.fade) + 0.12 * p.fade;
    c = float3(shoulder(c.r, p.shoulderKnee), shoulder(c.g, p.shoulderKnee), shoulder(c.b, p.shoulderKnee));
    float y = dot(c, kLuma);
    c = y + (c - y) * p.saturation;
    if (p.hasHue != 0) {
        float Y = dot(c, float3(0.299, 0.587, 0.114));
        float I = dot(c, float3(0.596, -0.274, -0.322));
        float Q = dot(c, float3(0.211, -0.523, 0.312));
        float rotatedI = I * p.hueCos - Q * p.hueSin;
        float rotatedQ = I * p.hueSin + Q * p.hueCos;
        c = float3(Y + 0.956 * rotatedI + 0.621 * rotatedQ,
                   Y - 0.272 * rotatedI - 0.647 * rotatedQ,
                   Y - 1.106 * rotatedI + 1.703 * rotatedQ);
    }
    return saturate(c);
}

static float3 applyLUT(float3 color, texture3d<float> lut, constant GradeParams &p) {
    if (p.hasLUT == 0) {
        return color;
    }
    float3 coordinate = saturate(color) * p.lutScale + p.lutOffset;
    return lut.sample(linearClamp, coordinate).rgb;
}

/// Regulators, then the LUT, blended by film strength.
static float3 gradeColor(float3 source, texture3d<float> lut, constant GradeParams &p) {
    float3 regulated = regulate(source, p);
    float3 graded = applyLUT(regulated, lut, p);
    return mix(regulated, graded, p.filmStrength);
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
    float3 color = gradeColor(readSource(luma, chroma, sourcePoint(outputPoint, p), p), lut, p);
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
                  texture3d<float> previousLUT [[texture(6)]],
                  constant GradeParams &p [[buffer(0)]],
                  uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= uint(p.width) || gid.y >= uint(p.height)) {
        return;
    }
    float3 source = readFiltered(luma, chroma, gid, p);
    float3 color = gradeColor(source, lut, p);
    if (p.previousMix > 0.0) {
        float3 previous = regulate(source, p);
        if (p.hasPreviousLUT != 0) {
            float3 coordinate = saturate(previous) * p.previousLutScale + p.previousLutOffset;
            previous = previousLUT.sample(linearClamp, coordinate).rgb;
        }
        color = mix(color, previous, p.previousMix);
    }

    float2 uv = (float2(gid) + 0.5) / float2(float(p.width), float(p.height));
    if (p.halation > 0.0) {
        float m = glow.sample(linearClamp, uv).r;
        float amount = p.halation * saturate(0.77 - dot(color, kLuma)) * m;
        color = saturate(color * (1.0 - amount) + amount * kHalationTint);
    }

    if (p.bloom > 0.0) {
        // Screen-style glow from the same highlight mask, so bright areas bleed a little.
        float g = glow.sample(linearClamp, uv).r;
        color = saturate(color + p.bloom * 0.35 * g * (1.0 - color));
    }

    if (p.grain > 0.0) {
        float2 size = float2(float(grain.get_width()), float(grain.get_height())) * p.grainScale;
        float2 grainUV = (float2(gid) + float2(p.grainOffsetX, p.grainOffsetY)) / size;
        float noise = grain.sample(linearRepeat, grainUV).r - 0.5;
        float y = dot(color, kLuma);
        float weight = y > 0.5 ? 1.12 - y : y + 0.18;
        color = saturate(color + p.grain * weight * noise);
    }

    destination.write(float4(color, 1.0), gid);
}
