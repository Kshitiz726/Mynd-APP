#version 460 core
#include <flutter/runtime_effect.glsl>

// Mynd's face, generated rather than filmed.
//
// This replaces a 519 KB video that had to be decoded every frame, and it
// fixes the loop problem by not having a loop: the motion is driven by four
// sine fields whose periods share no common multiple you would notice, so it
// never arrives back where it started and there is no seam to hide.
//
// The colours are uniforms, not pixels, so the orb is brand-coloured by
// definition - change OmColors and this changes with it, in both themes.

precision highp float;

uniform vec2 uSize;
uniform float uTime;
uniform vec3 uPrimary;
uniform vec3 uAccent;
uniform vec3 uFlow;

out vec4 fragColor;

// A cheap smooth field. Three sines at unrelated frequencies read as organic
// motion for a fraction of the cost of sampling real noise.
float field(vec2 p, float t) {
    return sin(p.x * 1.7 + t)
         + sin(p.y * 2.3 - t * 0.83) * 0.7
         + sin((p.x + p.y) * 1.31 + t * 0.61) * 0.6;
}

void main() {
    vec2 uv = (FlutterFragCoord().xy / uSize) * 2.0 - 1.0;
    float r = length(uv);
    float t = uTime;

    // Domain warping, twice. Warping the coordinates before sampling is what
    // turns concentric ripples into something that folds and curls like liquid.
    vec2 p = uv * 1.55;
    p += 0.42 * vec2(field(p + vec2(0.0, 1.7), t * 0.50),
                     field(p.yx + vec2(3.1, 0.0), t * 0.41));
    p += 0.26 * vec2(field(p * 1.9 + vec2(1.3, 0.0), t * 0.29),
                     field(p.yx * 1.7 + vec2(0.0, 2.4), t * 0.35));

    float a = field(p, t * 0.23) * 0.44 + 0.5;
    float b = field(p * 0.7 + 2.0, -t * 0.17) * 0.44 + 0.5;

    // A four-stop ramp, dark to light: near-black brand purple, into primary,
    // into brand blue, with coral on the crests and a pale bloom on the very
    // brightest.
    //
    // Primary and flow sit close together in hue, so ramping only between
    // those two gave a flat blue ball. The depth has to come from a tone
    // darker than either of them - the same near-black the painted fallback
    // orb has always ended on.
    vec3 deep = mix(uPrimary, vec3(0.086, 0.047, 0.180), 0.74);

    vec3 col = mix(deep, uPrimary, smoothstep(0.02, 0.52, a));
    col = mix(col, uFlow, smoothstep(0.38, 0.92, a) * 0.85);
    col = mix(col, uAccent, smoothstep(0.54, 1.0, b) * 0.72);
    col = mix(col, vec3(1.0), smoothstep(0.80, 1.0, b) * 0.22);

    // Shading, so it reads as a sphere rather than a flat disc: lit from the
    // top-left, falling away to the lower right.
    float lambert = clamp(0.5 - dot(normalize(vec2(0.62, 0.72)), uv) * 0.55, 0.0, 1.0);
    col *= 0.66 + 0.62 * lambert;

    // The wet highlight. Small, tight, and offset - it is what makes the
    // surface look like it has a skin.
    float spec = smoothstep(0.40, 0.0, length(uv - vec2(-0.36, -0.40)));
    col += vec3(1.0) * spec * 0.30;

    // Feathered, never clipped. A hard circular edge hangs a visible disc on
    // the page and the blob stops floating.
    float alpha = smoothstep(1.0, 0.68, r);

    // Flutter composites premultiplied.
    fragColor = vec4(col * alpha, alpha);
}
