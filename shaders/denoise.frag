// Edge-preserving (bilateral) smoothing. uA.x strength 0..100, uA.y radius.
#include "common.glsl"

void main() {
  vec2 p = fragPx();
  vec4 c = src(p);
  float sigmaR = 0.02 + uA.x / 100.0 * 0.35;
  float stepPx = max(0.5, uA.y * uScale * 0.5);
  vec4 acc = vec4(0.0);
  float wsum = 0.0;
  for (int j = 0; j < 7; j++) {
    for (int i = 0; i < 7; i++) {
      vec2 o = vec2(float(i) - 3.0, float(j) - 3.0);
      vec4 s = src(p + o * stepPx);
      vec4 d = s - c;
      float w = exp(-dot(o, o) / 9.0) * exp(-dot(d, d) / (2.0 * sigmaR * sigmaR));
      acc += s * w;
      wsum += w;
    }
  }
  fragColor = acc / max(wsum, 0.0001);
}
