// Zoom / spin blur. uA.x amount 0..100, uA.yz centre (%), uA.w spin(1) or zoom(0).
// uB = document rect (x, y, w, h).
#include "common.glsl"

void main() {
  vec2 center = (uB.xy + uB.zw * uA.yz / 100.0 - uOrigin) * uScale;
  vec2 p = fragPx();
  vec2 d = p - center;
  float amt = uA.x / 100.0;
  vec4 acc = vec4(0.0);
  for (int i = 0; i < 33; i++) {
    float t = float(i) / 32.0;
    // zoom
    vec2 zp = center + d * (1.0 - amt * 0.5 * t);
    // spin
    float ang = (t - 0.5) * amt * 0.6;
    float cs = cos(ang);
    float sn = sin(ang);
    vec2 sp = center + vec2(d.x * cs - d.y * sn, d.x * sn + d.y * cs);
    acc += srcDecal(mix(zp, sp, step(0.5, uA.w)));
  }
  fragColor = acc / 33.0;
}
