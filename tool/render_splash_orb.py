"""Render shaders/fluid_orb.frag offline, at t=0, to a transparent PNG.

The Android splash icon has to be a bitmap - no Dart has run yet, so the real
shader cannot draw it. Rather than hand-draw an approximation, this is a
straight port of the GLSL, so the still the system paints and the first frame
the shader paints are the same image.

t = 0 is not arbitrary: FluidOrb's clock starts at 0, so this *is* frame one.

Re-run whenever the shader or the brand palette changes, or the still and the
live orb will drift apart and the hand-off will show:

    pip install numpy
    python tool/render_splash_orb.py \
        android/app/src/main/res/drawable-nodpi/splash_orb.png
"""

import struct
import zlib

import numpy as np

W = H = 512
T = 0.0

# Android masks the splash icon to a circle inside its own canvas, so an orb
# drawn edge to edge loses its rim to the mask. Occupying the middle ~70% keeps
# the whole sphere, including the contact shading that makes it read as round.
FILL = 0.70

# OmColors.light - must match lib/core/theme/app_colors.dart.
PRIMARY = np.array([0x6B, 0x70, 0xC9]) / 255.0
ACCENT = np.array([0xF0, 0xA4, 0x79]) / 255.0
FLOW = np.array([0x5C, 0x8A, 0xD0]) / 255.0


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


def mix(a, b, t):
    return a + (b - a) * t


def field(px, py, t):
    return (np.sin(px * 1.7 + t)
            + np.sin(py * 2.3 - t * 0.83) * 0.7
            + np.sin((px + py) * 1.31 + t * 0.61) * 0.6)


ix, iy = np.meshgrid(np.arange(W), np.arange(H))
# Pixel centres, matching FlutterFragCoord.
ux = (((ix + 0.5) / W) * 2.0 - 1.0) / FILL
uy = (((iy + 0.5) / H) * 2.0 - 1.0) / FILL

r = np.sqrt(ux * ux + uy * uy)
z = np.sqrt(np.maximum(0.0, 1.0 - r * r))

# Project onto the sphere before sampling.
denom = 0.45 + 0.78 * z
sx, sy = ux / denom, uy / denom

px, py = sx * 1.55, sy * 1.55

nx = px + 0.42 * field(px + 0.0, py + 1.7, T * 0.50)
ny = py + 0.42 * field(py + 3.1, px + 0.0, T * 0.41)
px, py = nx, ny

nx = px + 0.24 * field(px * 1.9 + 1.3, py * 1.9 + 0.0, T * 0.29)
ny = py + 0.24 * field(py * 1.7 + 0.0, px * 1.7 + 2.4, T * 0.35)
px, py = nx, ny

nx = px + 0.09 * field(px * 4.3 + 2.7, py * 4.3 + 0.0, T * 0.22)
ny = py + 0.09 * field(py * 3.9 + 0.0, px * 3.9 + 5.2, T * 0.18)
px, py = nx, ny

a = field(px, py, T * 0.23) * 0.44 + 0.5
b = field(px * 0.7 + 2.0, py * 0.7 + 2.0, -T * 0.17) * 0.44 + 0.5

deep = mix(PRIMARY, np.array([0.086, 0.047, 0.180]), 0.46)

col = np.zeros((H, W, 3))
col[:] = deep
col = mix(col, PRIMARY, smoothstep(0.06, 0.46, a)[..., None])
col = mix(col, FLOW, (smoothstep(0.42, 0.86, a) * 0.80)[..., None])
col = mix(col, ACCENT, (smoothstep(0.60, 0.98, b) * 0.70)[..., None])

ridge = np.abs(np.sin(a * 8.0 + b * 3.0)) ** 5.0
col = col + mix(ACCENT, np.ones(3), 0.55) * (ridge * 0.12 * (0.35 + 0.65 * z))[..., None]

light = np.array([-0.45, -0.55, 0.70])
light = light / np.linalg.norm(light)

ndotl = np.clip(ux * light[0] + uy * light[1] + z * light[2], 0.0, 1.0)
col = col * (0.62 + 0.58 * ndotl)[..., None]

hx, hy, hz = ux, uy, z + 0.75
hlen = np.sqrt(hx * hx + hy * hy + hz * hz)
spec = np.clip((hx * light[0] + hy * light[1] + hz * light[2]) / hlen, 0.0, 1.0) ** 16.0
col = col + spec[..., None] * 0.26

col = col * (1.0 - 0.22 * smoothstep(0.72, 1.0, r))[..., None]
col = col + mix(FLOW, np.ones(3), 0.45) * ((1.0 - z) ** 4.5 * 0.08)[..., None]

luma = col[..., 0] * 0.213 + col[..., 1] * 0.715 + col[..., 2] * 0.072
col = mix(col, np.repeat(luma[..., None], 3, axis=2), 0.24)
col = mix(col, np.ones(3), 0.10)

pxs = 1.0 / min(W, H)
alpha = 1.0 - smoothstep(1.0 - pxs * 6.0, 1.0, r)

rgba = np.zeros((H, W, 4), dtype=np.uint8)
rgba[..., :3] = np.clip(col, 0.0, 1.0) * 255.0 + 0.5
rgba[..., 3] = np.clip(alpha, 0.0, 1.0) * 255.0 + 0.5

raw = b"".join(b"\x00" + rgba[y].tobytes() for y in range(H))


def chunk(tag, data):
    return (struct.pack(">I", len(data)) + tag + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))


png = (b"\x89PNG\r\n\x1a\n"
       + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
       + chunk(b"IDAT", zlib.compress(raw, 9))
       + chunk(b"IEND", b""))

import sys
open(sys.argv[1], "wb").write(png)
print(f"wrote {sys.argv[1]}  {W}x{H}  {len(png) // 1024} KB")
