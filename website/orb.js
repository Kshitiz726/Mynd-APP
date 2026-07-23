/* ===========================================================================
   Mynd's orb, on the web.
   ---------------------------------------------------------------------------
   This is not a CSS impression of the orb. It is shaders/fluid_orb.frag from the
   Flutter app, ported to WebGL with the same uniforms and the same maths, so the
   site renders the identical object: the same domain warping, the same sphere
   normal, the same four-stop ramp, the same final desaturate-and-lift.

   Two deliberate differences, both forced by the platform:
     - GLSL ES 1.00 instead of #version 460 (WebGL1, for reach), so `out
       fragColor` becomes gl_FragColor and FlutterFragCoord() becomes
       gl_FragCoord.
     - gl_FragCoord counts y upward where Flutter counts it downward, so y is
       flipped when building uv. Without that the light would come from the
       lower left and the orb would read upside down.
   ======================================================================== */

const FRAG = `
precision highp float;

uniform vec2  uSize;
uniform float uTime;
uniform vec3  uPrimary;
uniform vec3  uAccent;
uniform vec3  uFlow;

// A cheap smooth field. Three sines at unrelated frequencies read as organic
// motion for a fraction of the cost of sampling real noise.
float field(vec2 p, float t) {
  return sin(p.x * 1.7 + t)
       + sin(p.y * 2.3 - t * 0.83) * 0.7
       + sin((p.x + p.y) * 1.31 + t * 0.61) * 0.6;
}

void main() {
  // y flipped so the lighting matches Flutter's top-left origin.
  vec2 frag = vec2(gl_FragCoord.x, uSize.y - gl_FragCoord.y);
  vec2 uv = (frag / uSize) * 2.0 - 1.0;
  float r = length(uv);
  float t = uTime;

  // Reconstruct the sphere's surface normal from the disc, so the detail sits
  // ON a ball instead of being printed across a circle.
  float z = sqrt(max(0.0, 1.0 - r * r));
  vec3 n = vec3(uv, z);

  // Project onto the sphere before sampling - detail compresses towards the
  // rim the way it does on anything spherical.
  vec2 sph = uv / (0.45 + 0.78 * z);

  // Domain warping, three octaves. The third is where the fine detail lives.
  vec2 p = sph * 1.55;
  p += 0.42 * vec2(field(p + vec2(0.0, 1.7), t * 0.50),
                   field(p.yx + vec2(3.1, 0.0), t * 0.41));
  p += 0.24 * vec2(field(p * 1.9 + vec2(1.3, 0.0), t * 0.29),
                   field(p.yx * 1.7 + vec2(0.0, 2.4), t * 0.35));
  p += 0.09 * vec2(field(p * 4.3 + vec2(2.7, 0.0), t * 0.22),
                   field(p.yx * 3.9 + vec2(0.0, 5.2), t * 0.18));

  float a = field(p, t * 0.23) * 0.44 + 0.5;
  float b = field(p * 0.7 + 2.0, -t * 0.17) * 0.44 + 0.5;

  // Four-stop ramp, dark to light. Only a little darker than primary - taking
  // it to black gave an orb with more contrast than the rest of the page.
  vec3 deep = mix(uPrimary, vec3(0.086, 0.047, 0.180), 0.46);

  vec3 col = mix(deep, uPrimary, smoothstep(0.06, 0.46, a));
  col = mix(col, uFlow,   smoothstep(0.42, 0.86, a) * 0.80);
  col = mix(col, uAccent, smoothstep(0.60, 0.98, b) * 0.70);

  // Filaments along the folds, fading towards the rim.
  float ridge = pow(abs(sin(a * 8.0 + b * 3.0)), 5.0);
  col += mix(uAccent, vec3(1.0), 0.55) * ridge * 0.12 * (0.35 + 0.65 * z);

  // Diffuse, lit from the upper left, with a shallow falloff because the page
  // it sits on has no hard shadows anywhere.
  vec3 light = normalize(vec3(-0.45, -0.55, 0.70));
  col *= 0.62 + 0.58 * clamp(dot(light, n), 0.0, 1.0);

  // The wet highlight: a sheen on a surface, not a dot stuck on top of one.
  float spec = pow(clamp(dot(light, normalize(n + vec3(0.0, 0.0, 0.75))), 0.0, 1.0), 16.0);
  col += vec3(1.0) * spec * 0.26;

  // Contact shading where the sphere turns away from every light in the room.
  col *= 1.0 - 0.22 * smoothstep(0.72, 1.0, r);
  col += mix(uFlow, vec3(1.0), 0.45) * pow(1.0 - z, 4.5) * 0.08;

  // Settle it into the interface: keep the form, drop the vividness.
  float luma = dot(col, vec3(0.213, 0.715, 0.072));
  col = mix(col, vec3(luma), 0.24);
  col = mix(col, vec3(1.0), 0.10);

  // Soft enough to sit in the page, tight enough to keep a silhouette.
  float px = 1.0 / min(uSize.x, uSize.y);
  float alpha = 1.0 - smoothstep(1.0 - px * 6.0, 1.0, r);

  gl_FragColor = vec4(col * alpha, alpha);   // premultiplied, as Flutter does
}
`;

const VERT = `
attribute vec2 aPos;
void main() { gl_Position = vec4(aPos, 0.0, 1.0); }
`;

// OmColors, as the shader receives them (0-1 sRGB components).
const THEME = {
  light: { primary: [0x6B, 0x70, 0xC9], accent: [0xF0, 0xA4, 0x79], flow: [0x5C, 0x8A, 0xD0] },
  dark:  { primary: [0x9D, 0xA1, 0xEC], accent: [0xF2, 0xAE, 0x86], flow: [0x82, 0xA8, 0xE0] },
};
const norm = (c) => c.map((v) => v / 255);

function compile(gl, type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    console.warn('[orb] shader failed:', gl.getShaderInfoLog(s));
    return null;
  }
  return s;
}

function initOrb(canvas) {
  const gl = canvas.getContext('webgl', {
    premultipliedAlpha: true,
    alpha: true,
    antialias: true,
  });
  // No WebGL (old browser, blocked GPU): the CSS gradient underneath stays
  // visible, so the orb degrades to a still brand-coloured ball rather than a
  // hole in the page.
  if (!gl) { canvas.classList.add('orb-fallback'); return; }

  const vs = compile(gl, gl.VERTEX_SHADER, VERT);
  const fs = compile(gl, gl.FRAGMENT_SHADER, FRAG);
  if (!vs || !fs) { canvas.classList.add('orb-fallback'); return; }

  const prog = gl.createProgram();
  gl.attachShader(prog, vs);
  gl.attachShader(prog, fs);
  gl.linkProgram(prog);
  if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
    canvas.classList.add('orb-fallback');
    return;
  }
  gl.useProgram(prog);

  // One full-screen triangle strip.
  const buf = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, buf);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
  const loc = gl.getAttribLocation(prog, 'aPos');
  gl.enableVertexAttribArray(loc);
  gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);

  const uSize = gl.getUniformLocation(prog, 'uSize');
  const uTime = gl.getUniformLocation(prog, 'uTime');
  const uPrimary = gl.getUniformLocation(prog, 'uPrimary');
  const uAccent = gl.getUniformLocation(prog, 'uAccent');
  const uFlow = gl.getUniformLocation(prog, 'uFlow');

  const isDark = () => {
    const forced = document.documentElement.dataset.theme;
    if (forced === 'dark') return true;
    if (forced === 'light') return false;
    return matchMedia('(prefers-color-scheme: dark)').matches;
  };

  function resize() {
    // Cap the DPR: the orb is small and the shader is the expensive part, so
    // rendering it at 3x on a phone buys nothing you can see.
    const dpr = Math.min(devicePixelRatio || 1, 2);
    const w = Math.max(1, Math.round(canvas.clientWidth * dpr));
    const h = Math.max(1, Math.round(canvas.clientHeight * dpr));
    if (canvas.width !== w || canvas.height !== h) {
      canvas.width = w;
      canvas.height = h;
      gl.viewport(0, 0, w, h);
    }
    return [w, h];
  }

  // Only the orbs actually on screen animate.
  let visible = true;
  new IntersectionObserver(
    ([e]) => { visible = e.isIntersecting; },
    { rootMargin: '120px' }
  ).observe(canvas);

  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const start = performance.now();

  function frame(now) {
    if (visible) {
      const [w, h] = resize();
      const th = isDark() ? THEME.dark : THEME.light;
      // A held frame still looks like the orb, because a still orb is just this
      // shader with the clock stopped - exactly what FluidOrb.still does.
      gl.uniform1f(uTime, reduce ? 12.0 : (now - start) / 1000);
      gl.uniform2f(uSize, w, h);
      gl.uniform3fv(uPrimary, norm(th.primary));
      gl.uniform3fv(uAccent, norm(th.accent));
      gl.uniform3fv(uFlow, norm(th.flow));
      gl.clearColor(0, 0, 0, 0);
      gl.clear(gl.COLOR_BUFFER_BIT);
      gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
    }
    requestAnimationFrame(frame);
  }
  requestAnimationFrame(frame);
}

document.querySelectorAll('.orb canvas').forEach(initOrb);
