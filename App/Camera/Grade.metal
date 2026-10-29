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
    int inputKind;      // 0 = RGBA (8-bit, or half float with values above 1), 1 = 10-bit video-range BT.2020 Y'CbCr (Apple Log)
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
    float shadowLift;     // dynamic range above HIGH
    float crush;          // dynamic range below HIGH
    float saturation;     // already multiplied by (1 - 0.6 * mute)
    float hueCos;
    float hueSin;
    int hasHue;
    float filmStrength;   // how much of the graded colour shows over the regulated one
    float bloom;
    float sharpness;      // negative softens
    float fringe;         // chromatic aberration, 0...4
    // Live portrait: background from the depth map replaced by the blurred bokeh texture.
    int hasPortrait;
    int depthRotated;     // 1 when the depth map is already portrait like the frames
    int sourceWidth;
    int sourceHeight;
    float depthFocus;     // the subject's disparity
    float swirl;
    float lensVignette;
    float bokehBoost;     // how much highlights swell into bokeh balls
    // The lens's bokeh, mirrored in CameraCore/LensKernel.swift: aperture blades, cat's eye, ovality, rim.
    int blades;           // 0 for a round opening
    float catsEye;
    float ovality;
    float rim;
    float rimWidth;
    float fringing;       // red and blue rims of the bokeh drift apart
    float bokehRadius;    // blur radius in pixels of the small bokeh texture
    // Viewfinder aids, never set for recordings or photos. Mirrored in CameraCore/ExposureAssist.swift.
    int assist;           // 1 zebra, 2 false colour, 4 focus peaking, 8 waveform counts (luma)
    int stripePhase;      // moves the zebra stripes from frame to frame
    float zebraLevel;
    float peakThreshold;  // focus peaking: Laplacian of the camera's luma above this lights up
    int waveColumns;
    int waveLevels;
    int waveStepX;        // every waveStepX-th pixel of every waveStepY-th row is counted
    int waveStepY;
    int waveTurn;         // DeviceOrientation.quarterTurns: the columns run across the picture as it is held
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
        c = max(c + p.sharpness * (c - around * 0.25), 0.0);
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

/// `DynamicRangeCurve.apply`: lift the shadows, roll everything above the knee (headroom included)
/// softly under white, or bend towards an S-curve.
static float dynamicRange(float x, constant GradeParams &p) {
    float t = saturate(x);
    float inverse = 1.0 - t;
    x += p.shadowLift * t * inverse * inverse * inverse;
    if (p.shoulderKnee < 1.0 && x > p.shoulderKnee) {
        float span = 1.0 - p.shoulderKnee;
        x = p.shoulderKnee + span * (1.0 - exp(-(x - p.shoulderKnee) / span));
    }
    if (p.crush > 0.0) {
        float u = saturate(x);
        x += p.crush * (u * u * (3.0 - 2.0 * u) - x);
    }
    return x;
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
    c = float3(dynamicRange(c.r, p), dynamicRange(c.g, p), dynamicRange(c.b, p));
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

/// NaN and infinity test on the bits, which fast math cannot optimise away.
static inline bool finiteValue(float x) {
    return (as_type<uint>(x) & 0x7f800000u) != 0x7f800000u;
}

/// 0 on the subject, 1 on the background, from the depth map, for the crop pixel `outputPoint`.
/// Holes in the depth map count as the subject, so they stay sharp instead of going black.
static float portraitMask(texture2d<float> depth, uint2 outputPoint, constant GradeParams &p) {
    float2 sp = (float2(sourcePoint(outputPoint, p)) + 0.5) / float2(float(p.sourceWidth), float(p.sourceHeight));
    float2 duv = p.depthRotated != 0 ? sp : float2(sp.y, 1.0 - sp.x);
    float d = depth.sample(linearClamp, duv).r;
    if (!finiteValue(d)) {
        d = p.depthFocus;
    }
    float mask = saturate((p.depthFocus * 0.85 - d) / max(p.depthFocus * 0.3, 0.0001));
    return finiteValue(mask) ? mask : 0.0;
}

/// The graded picture at reduced size with its highlights swollen into bokeh balls, and the background
/// mask in alpha. `lensBokeh` blurs it into the portrait background.
kernel void bokehSource(texture2d<float, access::read> luma [[texture(0)]],
                        texture2d<float, access::read> chroma [[texture(1)]],
                        texture3d<float> lut [[texture(2)]],
                        texture2d<float, access::write> small [[texture(3)]],
                        texture2d<float> depth [[texture(4)]],
                        constant GradeParams &p [[buffer(0)]],
                        uint2 gid [[thread_position_in_grid]]) {
    uint w = small.get_width();
    uint h = small.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    uint2 outputPoint = uint2(min(uint((float(gid.x) + 0.5) * float(p.width) / float(w)), uint(p.width - 1)),
                              min(uint((float(gid.y) + 0.5) * float(p.height) / float(h)), uint(p.height - 1)));
    float3 c = gradeColor(readSource(luma, chroma, sourcePoint(outputPoint, p), p), lut, p);
    float y = dot(c, kLuma);
    c += c * p.bokehBoost * smoothstep(0.55, 1.0, y) * 2.5;
    small.write(float4(c, portraitMask(depth, outputPoint, p)), gid);
}

/// For saved photos: the photo at reduced size with highlights swollen, and the mask in alpha.
kernel void packPortrait(texture2d<float, access::read> colour [[texture(0)]],
                         texture2d<float, access::read> mask [[texture(1)]],
                         texture2d<float, access::write> small [[texture(2)]],
                         constant GradeParams &p [[buffer(0)]],
                         uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= small.get_width() || gid.y >= small.get_height()) {
        return;
    }
    float3 c = max(colour.read(gid).rgb, 0.0);
    float y = dot(c, kLuma);
    c += c * p.bokehBoost * smoothstep(0.55, 1.0, y) * 2.5;
    small.write(float4(c, saturate(mask.read(gid).r)), gid);
}

/// The scene twisted about the centre, more towards the corners: the swirl of Helios- and Petzval-style lenses.
static float2 lensTwirl(float2 uv, float aspect, float swirl) {
    float2 c = (uv - 0.5) * float2(aspect, 1.0);
    float a = swirl * 1.2 * dot(c, c);
    float s = sin(a);
    float k = cos(a);
    float2 turned = float2(c.x * k - c.y * s, c.x * s + c.y * k);
    return turned / float2(aspect, 1.0) + 0.5;
}

constant int kBokehTaps = 96;

/// The portrait background: every pixel gathers 96 samples laid out the way the lens draws a point of light.
/// Blades make polygons, the rim a bright ring with a hollow centre or a soft fade, the cat's eye clips the
/// bokeh towards the edges, ovality stretches it, swirl twists it. Samples on the subject count for little,
/// so the subject does not bleed into the background. Mirrors `LensKernel.tap`.
kernel void lensBokeh(texture2d<float> source [[texture(0)]],
                      texture2d<float, access::write> result [[texture(1)]],
                      constant GradeParams &p [[buffer(0)]],
                      uint2 gid [[thread_position_in_grid]]) {
    uint w = result.get_width();
    uint h = result.get_height();
    if (gid.x >= w || gid.y >= h) {
        return;
    }
    float2 size = float2(float(w), float(h));
    float aspect = size.x / size.y;
    float2 uv = (float2(gid) + 0.5) / size;
    float4 here = source.sample(linearClamp, uv);
    if (here.a < 0.02) {
        result.write(float4(here.rgb, 1.0), gid);
        return;
    }

    float2 centred = (uv - 0.5) * float2(aspect, 1.0);
    float distanceFromCentre = length(centred);
    float edge = saturate(distanceFromCentre / 0.55);
    float2 radial = distanceFromCentre > 0.0001 ? centred / distanceFromCentre : float2(0.0, 1.0);
    float2 tangent = float2(-radial.y, radial.x);
    // Near the subject's edge the blur starts small, so the outline does not halo.
    float radius = p.bokehRadius * mix(0.3, 1.0, smoothstep(0.0, 0.7, here.a)) * (1.0 + 0.45 * p.swirl * edge * edge);

    float catsShift = p.catsEye * pow(edge, 1.5) * 0.9;
    float stretch = 1.0 + 0.7 * p.swirl * edge;
    float ovalScale = max(0.3, 1.0 + 0.9 * p.ovality);
    float2 oval = float2(rsqrt(ovalScale), sqrt(ovalScale));
    float bladeCount = float(max(p.blades, 3));
    float sector = 6.2831853 / bladeCount;
    float polygonFill = sqrt(3.1415927 / (0.5 * bladeCount * sin(sector)));
    float fringe = 0.12 * p.fringing;
    // A different turn of the pattern at every pixel hides its structure.
    float rotation = fract(52.9829189 * fract(dot(float2(gid), float2(0.06711056, 0.00583715)))) * 6.2831853;

    float3 sum = float3(0.0);
    float total = 0.0;
    for (int i = 0; i < kBokehTaps; i++) {
        float rho = sqrt((float(i) + 0.5) / float(kBokehTaps));
        float theta = float(i) * 2.3999632 + rotation;
        float2 u = rho * float2(cos(theta), sin(theta));

        float weight;
        if (p.rim >= 0.0) {
            weight = 1.0 + (0.25 + 3.0 * smoothstep(1.0 - p.rimWidth, 1.0, rho) - 1.0) * p.rim;
        } else {
            weight = 1.0 + (exp(-2.5 * rho * rho) - 1.0) * -p.rim;
        }
        if (p.blades >= 3) {
            float angle = atan2(u.y, u.x);
            float inSector = angle - sector * floor(angle / sector) - 0.5 * sector;
            float k = cos(0.5 * sector) / cos(inSector);
            u *= k * polygonFill;
            weight *= k * k;
        }
        if (catsShift > 0.01) {
            float2 halfShift = radial * (catsShift * 0.5);
            if (length(u - halfShift) > 1.0 || length(u + halfShift) > 1.0) {
                continue;
            }
        }
        if (stretch != 1.0) {
            u = radial * dot(u, radial) + tangent * (dot(u, tangent) * stretch);
        }
        u *= oval;

        float2 offset = u * radius / size;
        float4 s = source.sample(linearClamp, lensTwirl(uv + offset, aspect, p.swirl));
        float3 c = s.rgb;
        if (fringe > 0.01) {
            // Red from a little further out and blue from a little further in: rims fringed like a real lens.
            c.r = source.sample(linearClamp, lensTwirl(uv + offset * (1.0 + fringe), aspect, p.swirl)).r;
            c.b = source.sample(linearClamp, lensTwirl(uv + offset * (1.0 - fringe), aspect, p.swirl)).b;
        }
        float w8 = weight * (s.a + 0.02);
        sum += c * w8;
        total += w8;
    }
    float3 colour = total > 0.0001 ? sum / total : here.rgb;
    result.write(float4(max(colour, 0.0), 1.0), gid);
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

/// `ExposureAssist.falseColor`: exposure bands in colour, everything else in grey.
static float3 falseColor(float y) {
    if (y < 0.025) return float3(0.55, 0.1, 0.85);
    if (y < 0.10) return float3(0.1, 0.35, 1.0);
    if (y >= 0.42 && y < 0.50) return float3(0.2, 0.85, 0.3);
    if (y >= 0.60 && y < 0.68) return float3(1.0, 0.55, 0.7);
    if (y >= 0.985) return float3(1.0, 0.15, 0.1);
    if (y >= 0.93) return float3(1.0, 0.9, 0.1);
    return float3(y * 0.85);
}

/// How sharp the camera's picture is at `gid`: the Laplacian of its luma, larger on in-focus edges.
static float focusEdge(texture2d<float, access::read> luma,
                       texture2d<float, access::read> chroma,
                       uint2 gid,
                       constant GradeParams &p) {
    float centre = dot(readSource(luma, chroma, sourcePoint(gid, p), p), kLuma);
    float around = dot(readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(1, 0), p), p), p), kLuma)
                 + dot(readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(-1, 0), p), p), p), kLuma)
                 + dot(readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(0, 1), p), p), p), kLuma)
                 + dot(readSource(luma, chroma, sourcePoint(offsetPoint(gid, int2(0, -1), p), p), p), kLuma);
    return abs(4.0 * centre - around);
}

kernel void grade(texture2d<float, access::read> luma [[texture(0)]],
                  texture2d<float, access::read> chroma [[texture(1)]],
                  texture3d<float> lut [[texture(2)]],
                  texture2d<float> glow [[texture(3)]],
                  texture2d<float> grain [[texture(4)]],
                  texture2d<float, access::write> destination [[texture(5)]],
                  texture3d<float> previousLUT [[texture(6)]],
                  texture2d<float> depth [[texture(7)]],
                  texture2d<float> bokeh [[texture(8)]],
                  constant GradeParams &p [[buffer(0)]],
                  device atomic_uint *wave [[buffer(1)]],
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

    if (p.hasPortrait != 0) {
        float mask = portraitMask(depth, gid, p);
        float3 background = bokeh.sample(linearClamp, uv).rgb;
        if (finiteValue(background.r) && finiteValue(background.g) && finiteValue(background.b)) {
            color = mix(color, saturate(background), mask);
        }
        float2 centred = uv - 0.5;
        color *= 1.0 - p.lensVignette * 0.9 * smoothstep(0.3, 0.95, length(centred) * 1.414);
    }

    // The waveform counts the graded picture before halation and grain, so film noise does not smear the
    // trace. Mirrored in CameraCore/ExposureAssist.swift (Waveform.measure, Waveform.column).
    if ((p.assist & 8) != 0 && gid.x % uint(p.waveStepX) == 0 && gid.y % uint(p.waveStepY) == 0) {
        float across = p.waveTurn == 1 ? uv.y : (p.waveTurn == -1 ? 1.0 - uv.y : uv.x);
        uint column = min(uint(across * float(p.waveColumns)), uint(p.waveColumns - 1));
        uint level = min(uint(saturate(dot(color, kLuma)) * float(p.waveLevels)), uint(p.waveLevels - 1));
        atomic_fetch_add_explicit(&wave[column * uint(p.waveLevels) + level], 1u, memory_order_relaxed);
    }

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

    if (p.assist != 0) {
        float y = dot(color, kLuma);
        if ((p.assist & 2) != 0) {
            color = falseColor(y);
        }
        if ((p.assist & 1) != 0 && y >= p.zebraLevel && ((int(gid.x) + int(gid.y) + p.stripePhase) / 8) % 2 == 0) {
            color = mix(color, float3(0.0), 0.75);
        }
        if ((p.assist & 4) != 0) {
            float edge = focusEdge(luma, chroma, gid, p);
            float k = smoothstep(p.peakThreshold, p.peakThreshold * 2.0, edge);
            color = mix(color, float3(1.0, 0.18, 0.12), k);
        }
    }

    destination.write(float4(color, 1.0), gid);
}
