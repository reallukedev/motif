#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

// The player's moving backgrounds, drawn as fills. Each takes the size it's drawn at and a
// phase in seconds, which `BackdropClock` keeps: it runs while the music plays and glides to
// a stop when it's paused. Every one keeps white type readable on it, whatever the cover:
// see `readable`.

namespace backdrop {

float hash(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Value noise, 0 to 1, smooth between whole numbers.
float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + float2(1, 0)), u.x),
               mix(hash(i + float2(0, 1)), hash(i + float2(1, 1)), u.x), u.y);
}

// Three octaves: broad shapes with a little detail, nothing busy.
float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    const float2x2 turn = float2x2(1.6, 1.2, -1.2, 1.6);
    for (int octave = 0; octave < 3; octave++) {
        value += amplitude * noise(p);
        p = turn * p;
        amplitude *= 0.5;
    }
    return value;
}

float2x2 rotation(float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2x2(c, -s, s, c);
}

float luma(float3 colour) {
    return dot(colour, float3(0.2126, 0.7152, 0.0722));
}

// A little richer, as Music's backgrounds are, then kept under `ceiling`: dark colours stay
// as they are and bright ones come down softly, keeping their hue, so a white cover gives
// a pale grey field that white type still reads on rather than a glare.
float3 readable(float3 colour, float richness, float ceiling) {
    float grey = luma(colour);
    colour = max(float3(0.0), mix(float3(grey), colour, richness));
    grey = luma(colour);
    if (grey > 0.0001) {
        float softened = ceiling * (1.0 - exp(-grey / ceiling));
        colour *= softened / grey;
    }
    return colour;
}

// Centred, the longer side running -0.5 to 0.5, so a square cover fills any shape.
float2 centred(float2 position, float2 size) {
    return (position - size * 0.5) / max(size.x, size.y);
}

}

// Living Cover: the cover itself, flowing. Three copies of it, softened and turning slowly
// at their own speeds, as Music's animated backgrounds are made, drift through a field that
// warps like ink in water, and blend into one another where it folds.
[[ stitchable ]] half4 livingCover(float2 position, float2 size, float time, texture2d<half> cover) {
    constexpr sampler art(address::mirrored_repeat, filter::linear);
    float2 p = backdrop::centred(position, size);
    float t = time;

    // Two warps, each through the last, drifting on their own.
    float2 q = float2(backdrop::fbm(p * 1.5 + float2(0.0, t * 0.07)),
                      backdrop::fbm(p * 1.5 + float2(5.2, 1.3) - t * 0.06));
    float2 r = float2(backdrop::fbm(p * 1.5 + 3.0 * q + float2(1.7, 9.2) + t * 0.05),
                      backdrop::fbm(p * 1.5 + 3.0 * q + float2(8.3, 2.8) - t * 0.045));
    float2 warp = (r - 0.5) * 0.6;

    float2 a = backdrop::rotation(t * 0.05) * p * 0.8 + warp;
    float2 b = backdrop::rotation(-t * 0.065 + 2.1) * (p + float2(0.14, -0.1)) * 1.2 + warp * 1.3;
    float2 c = backdrop::rotation(t * 0.035 + 4.2) * (p - float2(0.12, 0.16)) * 0.55 - warp * 0.8;
    float3 first = float3(cover.sample(art, 0.5 + a).rgb);
    float3 second = float3(cover.sample(art, 0.5 + b).rgb);
    float3 third = float3(cover.sample(art, 0.5 + c).rgb);

    float blend = smoothstep(0.3, 0.7, backdrop::fbm(p * 1.2 + q * 2.0 + t * 0.03));
    float over = smoothstep(0.35, 0.75, backdrop::fbm(p * 1.4 - r * 2.0 + 7.1 - t * 0.025));
    float3 colour = mix(mix(first, second, blend), third, over * 0.7);

    // A touch more contrast, so its colours stand apart rather than meet in grey, and a
    // little deeper toward the edges, as a room is lit from the middle.
    colour = max(float3(0.0), (colour - 0.3) * 1.15 + 0.3);
    colour *= 1.0 - 0.18 * smoothstep(0.3, 0.8, length(p));
    colour = backdrop::readable(colour, 1.6, 0.47);
    return half4(half3(colour), 1.0h);
}

// Reeded Glass: the cover behind a pane of ribbed glass. Each reed is a lens that shows a
// narrow slice of what's behind, flipped and squeezed, with light along its crest and shade
// in the groove beside it. Behind the glass the cover drifts slowly, so the slices shift as
// if you were walking past.
[[ stitchable ]] half4 reededGlass(float2 position, float2 size, float time, float reed, texture2d<half> cover) {
    constexpr sampler art(address::mirrored_repeat, filter::linear);
    float across = position.x / reed;
    float cell = floor(across);
    float local = fract(across) - 0.5;

    // What this point of the reed sees: the slice around the reed's middle, reversed.
    float seen = (cell + 0.5 - local * 2.4) * reed;
    float2 p = backdrop::centred(float2(seen, position.y + local * local * reed * 0.6), size);

    float t = time;
    p = backdrop::rotation(sin(t * 0.045) * 0.14) * p;
    p *= 0.72 + 0.06 * sin(t * 0.06);
    p += float2(sin(t * 0.037) * 0.16, cos(t * 0.029) * 0.1);
    float3 colour = float3(cover.sample(art, 0.5 + p).rgb);

    // Light on each reed's rounded face, brightest just left of its middle; shade where two
    // reeds meet.
    float lit = (local + 0.2) / 0.16;
    float crest = exp(-lit * lit);
    float groove = smoothstep(0.34, 0.5, abs(local));
    colour = colour * (0.92 - 0.3 * groove) + 0.09 * crest;

    // Down the pane, a soft sheen that drifts with the cover.
    float sheen = 0.5 + 0.5 * sin(position.y / size.y * 3.0 + t * 0.08);
    colour += 0.025 * sheen;

    colour = backdrop::readable(colour, 1.2, 0.48);
    return half4(half3(colour), 1.0h);
}

// Aurora: curtains of light in the cover's colours over a night sky of its darkest. Each
// curtain has a bright lower hem and a long glow above it, rippling along the sky, made of
// fine vertical rays that shimmer. Their hems hang at `hem`, a part of the height, and their
// glow reaches up by `tail`: high, where the cover is, so the sky below stays dark for the
// song's name and the controls.
[[ stitchable ]] half4 aurora(float2 position, float2 size, float time, float hem, float tail, half4 first, half4 second, half4 third, half4 sky) {
    float2 uv = position / size;
    float x = position.x / max(size.x, size.y) * 1.6;
    float t = time;

    float3 night = float3(sky.rgb);
    float3 colour = mix(night * 1.25, night * 0.35, smoothstep(0.0, 1.0, uv.y));
    float3 curtains[3] = { float3(first.rgb), float3(second.rgb), float3(third.rgb) };

    for (int index = 0; index < 3; index++) {
        float i = float(index);
        float edge = hem + i * 0.085
            + 0.06 * sin(x * 2.1 + t * 0.16 + i * 2.3)
            + 0.08 * (backdrop::fbm(float2(x * 1.3 + t * 0.06 + i * 3.1, i * 1.7)) - 0.5);
        float d = uv.y - edge;
        float glow = d < 0.0 ? exp(d * tail) : exp(-d * 34.0);
        float rays = 0.3 + 0.7 * pow(backdrop::fbm(float2(x * 16.0 + i * 20.0, t * 0.12 + i)), 1.4);
        // Each curtain thins and gathers along the sky, over time.
        float presence = smoothstep(0.15, 0.75, 0.5 + 0.5 * sin(x * 1.1 - t * 0.09 + i * 1.9));
        colour += curtains[index] * glow * rays * (0.35 + 0.65 * presence) * 0.85;
    }

    colour = backdrop::readable(colour, 1.1, 0.55);
    return half4(half3(colour), 1.0h);
}

// Any picture made readable in the same way, for Artwork's blurred cover.
[[ stitchable ]] half4 readableColour(float2 position, half4 colour, float richness, float ceiling) {
    float alpha = max(float(colour.a), 0.001);
    float3 kept = backdrop::readable(float3(colour.rgb) / alpha, richness, ceiling);
    return half4(half3(kept * alpha), colour.a);
}
