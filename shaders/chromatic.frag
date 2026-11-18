// Chromatic aberration. uA.x amount (doc px), uA.y radial(1) / horizontal(0). uB = document rect.
#include "common.glsl"

void main() {
  vec2 p = fragPx();
  vec2 center = uB.xy + uB.zw * 0.5;
  vec2 d = (docPos() - center) / (max(uB.z, uB.w) * 0.5);
  vec2 radial = d * uA.x * uScale;
  vec2 horiz = vec2(uA.x * uScale, 0.0);
  vec2 off = mix(horiz, radial, step(0.5, uA.y));
  vec4 cr = srcDecal(p + off);
  vec4 cg = srcDecal(p);
  vec4 cb = srcDecal(p - off);
  float a = max(cg.a, max(cr.a, cb.a));
  fragColor = vec4(cr.r, cg.g, cb.b, a);
}
