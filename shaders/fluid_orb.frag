#version 460 core
#include <flutter/runtime_effect.glsl>

// Mynd's face, generated rather than filmed.
//
// This replaces a 519 KB video that had to be decoded every frame, and it
// fixes the loop problem by not having a loop: the motion is driven by sine
// fields whose periods share no common multiple you would notice, so it never
// arrives back where it started and there is no seam to hide.
//
// The colours are uniforms, not pixels, so the orb is brand-coloured by
// definition - change OmColors and this changes with it, in both themes.
//
// Crispness is deliberate and was not free. A first version was all
// low-frequency warping with a wide edge feather, and it read as an
// out-of-focus blob: nothing in it was ever in focus because nothing in it had
// a hard edge. What fixes that is detail at three scales (the third warp
// octave), thin bright ridges where the field folds, real sphere shading off a
// reconstructed normal, and an edge that resolves in a few pixels instead of
// a third of the radius.

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

    // Reconstruct the sphere's surface normal from the disc. Shading against
    // this rather than against flat uv is what makes the detail sit *on* a
    // ball instead of being printed across a circle.
    float z = sqrt(max(0.0, 1.0 - r * r));
    vec3 n = vec3(uv, z);

    // Project onto the sphere before sampling.
    //
    // This is what makes it read as a ball rather than a disc with a picture
    // on it. Warping flat uv keeps the pattern the same size from centre to
    // rim, which is exactly what a *printed* circle looks like; dividing by
    // the normal's z stretches the coordinates as the surface turns away, so
    // the detail compresses towards the edge the way it does on anything
    // spherical. Roundness comes from this, not from sharpness.
    vec2 sph = uv / (0.45 + 0.78 * z);

    // Domain warping, three octaves. Warping the coordinates before sampling
    // is what turns concentric ripples into something that folds like liquid;
    // the third pass is small and fast and is where the fine detail lives.
    vec2 p = sph * 1.55;
    p += 0.42 * vec2(field(p + vec2(0.0, 1.7), t * 0.50),
                     field(p.yx + vec2(3.1, 0.0), t * 0.41));
    p += 0.24 * vec2(field(p * 1.9 + vec2(1.3, 0.0), t * 0.29),
                     field(p.yx * 1.7 + vec2(0.0, 2.4), t * 0.35));
    p += 0.09 * vec2(field(p * 4.3 + vec2(2.7, 0.0), t * 0.22),
                     field(p.yx * 3.9 + vec2(0.0, 5.2), t * 0.18));

    float a = field(p, t * 0.23) * 0.44 + 0.5;
    float b = field(p * 0.7 + 2.0, -t * 0.17) * 0.44 + 0.5;

    // A four-stop ramp, dark to light. Primary and flow sit close together in
    // hue, so the depth has to come from a tone darker than either of them -
    // the same near-black the painted fallback orb has always ended on.
    vec3 deep = mix(uPrimary, vec3(0.086, 0.047, 0.180), 0.74);

    vec3 col = mix(deep, uPrimary, smoothstep(0.06, 0.46, a));
    col = mix(col, uFlow, smoothstep(0.42, 0.86, a) * 0.90);
    col = mix(col, uAccent, smoothstep(0.60, 0.98, b) * 0.85);

    // Filaments along the folds, softened. At full strength these were etched
    // lines of even weight across the whole disc, which reads as engraving on
    // a flat surface; they fade towards the rim with everything else now.
    float ridge = pow(abs(sin(a * 8.0 + b * 3.0)), 5.0);
    col += mix(uAccent, vec3(1.0), 0.55) * ridge * 0.18 * (0.35 + 0.65 * z);

    // Diffuse, lit from the upper left.
    vec3 light = normalize(vec3(-0.45, -0.55, 0.70));
    col *= 0.50 + 0.80 * clamp(dot(light, n), 0.0, 1.0);

    // The wet highlight, broad enough to be a sheen on a surface rather than
    // a hard dot stuck on top of one.
    float spec = pow(clamp(dot(light, normalize(n + vec3(0.0, 0.0, 0.75))), 0.0, 1.0), 16.0);
    col += vec3(1.0) * spec * 0.38;

    // Contact shading at the very edge, where a sphere turns away from every
    // light in the room. Doing this *and* a rim light was the mistake - a
    // bright ring all the way round is how a sticker catches light, not a ball.
    col *= 1.0 - 0.32 * smoothstep(0.72, 1.0, r);
    col += mix(uFlow, vec3(1.0), 0.45) * pow(1.0 - z, 4.5) * 0.10;

    // Soft enough to sit in the page, tight enough to keep a silhouette.
    float px = 1.0 / min(uSize.x, uSize.y);
    float alpha = 1.0 - smoothstep(1.0 - px * 6.0, 1.0, r);

    // Flutter composites premultiplied.
    fragColor = vec4(col * alpha, alpha);
}
