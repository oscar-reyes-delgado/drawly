// Additive noise / film grain. uA.x amount 0..100, uA.y mono, uA.z cell size, uA.w seed.
#include "common.glsl"

void main() {
  vec4 c = src(fragPx());
  vec2 cell = floor(docPos() / max(1.0, uA.z));
  float seed = uA.w * 17.31;
  float n1 = hash21(cell + seed) - 0.5;
  float n2 = hash21(cell + seed + 71.7) - 0.5;
  float n3 = hash21(cell + seed + 133.1) - 0.5;
  vec3 n = mix(vec3(n1, n2, n3), vec3(n1), step(0.5, uA.y));
  vec3 rgb = unpremul(c) + n * (uA.x / 100.0) * 1.2;
  fragColor = vec4(clamp(rgb, 0.0, 1.0) * c.a, c.a);
}
