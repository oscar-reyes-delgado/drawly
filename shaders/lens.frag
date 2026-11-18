// Barrel / pincushion distortion. uA.x amount -100..100, uA.y zoom (%). uB = document rect.
#include "common.glsl"

void main() {
  vec2 center = uB.xy + uB.zw * 0.5;
  float halfDiag = length(uB.zw) * 0.5;
  vec2 d = (docPos() - center) / halfDiag;
  float k = uA.x / 100.0 * 0.6;
  float r2 = dot(d, d);
  vec2 q = d * (1.0 + k * r2) / (1.0 + k) * (100.0 / max(1.0, uA.y));
  vec2 doc = center + q * halfDiag;
  fragColor = srcDecal((doc - uOrigin) * uScale);
}
