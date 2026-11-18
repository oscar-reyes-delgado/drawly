// Unsharp mask. uA.x amount (%), uA.y radius (doc px).
#include "common.glsl"

void main() {
  vec2 p = fragPx();
  float r = max(0.5, uA.y * uScale);
  vec4 c = src(p);
  vec4 blur = c * 4.0;
  blur += (src(p + vec2(r, 0.0)) + src(p - vec2(r, 0.0)) + src(p + vec2(0.0, r)) + src(p - vec2(0.0, r))) * 2.0;
  blur += src(p + vec2(r, r)) + src(p + vec2(-r, r)) + src(p + vec2(r, -r)) + src(p + vec2(-r, -r));
  blur /= 16.0;
  vec4 o = c + (c - blur) * (uA.x / 100.0);
  float a = clamp(c.a, 0.0, 1.0);
  fragColor = vec4(clamp(o.rgb, 0.0, a), a);
}
