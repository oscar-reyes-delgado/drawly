// Directional blur. uA.x angle (deg), uA.y distance (doc px).
#include "common.glsl"

void main() {
  float a = radians(uA.x);
  vec2 dir = vec2(cos(a), sin(a)) * uA.y * uScale;
  vec2 p = fragPx();
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 33; i++) {
    float t = float(i) / 32.0 - 0.5;
    acc += srcDecal(p + dir * t);
  }
  fragColor = acc / 33.0;
}
