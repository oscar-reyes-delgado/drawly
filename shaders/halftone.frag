// Halftone screen. uA.x cell size, uA.y angle (deg), uA.z colour (CMYK) on/off.
#include "common.glsl"

float dotScreen(vec2 pos, float size, float angle, float value) {
  float cs = cos(angle);
  float sn = sin(angle);
  vec2 q = vec2(pos.x * cs + pos.y * sn, -pos.x * sn + pos.y * cs) / size;
  vec2 f = fract(q) - 0.5;
  float r = sqrt(clamp(value, 0.0, 1.0)) * 0.72;
  float aa = 1.2 / (size * uScale);
  return 1.0 - smoothstep(r - aa, r + aa, length(f));
}

void main() {
  float size = max(2.0, uA.x);
  vec2 pos = docPos();
  float ang = radians(uA.y);
  // sample the cell centre so each dot is uniform
  float cs = cos(ang);
  float sn = sin(ang);
  vec2 q = vec2(pos.x * cs + pos.y * sn, -pos.x * sn + pos.y * cs) / size;
  vec2 qc = (floor(q) + 0.5) * size;
  vec2 cellDoc = vec2(qc.x * cs - qc.y * sn, qc.x * sn + qc.y * cs);
  vec4 c = src((cellDoc - uOrigin) * uScale);
  vec4 here = src(fragPx());
  vec3 rgb = unpremul(c);

  // mono
  float ink = dotScreen(pos, size, ang, 1.0 - luma(rgb));
  vec3 mono = vec3(1.0 - ink);

  // cmyk
  float k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
  vec3 cmy = (1.0 - rgb - k) / max(1.0 - k, 0.0001);
  float dc = dotScreen(pos, size, ang + 0.2618, cmy.x);
  float dm = dotScreen(pos, size, ang + 1.3090, cmy.y);
  float dy = dotScreen(pos, size, ang, cmy.z);
  float dk = dotScreen(pos, size, ang + 0.7854, k);
  vec3 col = vec3(1.0);
  col *= mix(vec3(1.0), vec3(0.0, 0.68, 0.94), dc);
  col *= mix(vec3(1.0), vec3(0.93, 0.0, 0.55), dm);
  col *= mix(vec3(1.0), vec3(1.0, 0.95, 0.0), dy);
  col *= mix(vec3(1.0), vec3(0.08), dk);

  vec3 o = mix(mono, col, step(0.5, uA.z));
  float a = max(c.a, here.a);
  fragColor = vec4(o * a, a);
}
