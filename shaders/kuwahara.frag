// Kuwahara painterly filter (oil / watercolour). uA.x radius, uA.y paper 0..100.
#include "common.glsl"

void main() {
  vec2 p = fragPx();
  float rad = max(1.0, uA.x) * uScale;
  vec4 m0 = vec4(0.0);
  vec4 m1 = vec4(0.0);
  vec4 m2 = vec4(0.0);
  vec4 m3 = vec4(0.0);
  vec3 s0 = vec3(0.0);
  vec3 s1 = vec3(0.0);
  vec3 s2 = vec3(0.0);
  vec3 s3 = vec3(0.0);
  float n0 = 0.0;
  float n1 = 0.0;
  float n2 = 0.0;
  float n3 = 0.0;
  for (int j = 0; j < 9; j++) {
    for (int i = 0; i < 9; i++) {
      vec2 o = vec2(float(i) - 4.0, float(j) - 4.0) / 4.0;
      vec4 c = src(p + o * rad);
      float w0 = step(o.x, 0.0) * step(o.y, 0.0);
      float w1 = step(0.0, o.x) * step(o.y, 0.0);
      float w2 = step(o.x, 0.0) * step(0.0, o.y);
      float w3 = step(0.0, o.x) * step(0.0, o.y);
      m0 += c * w0; s0 += c.rgb * c.rgb * w0; n0 += w0;
      m1 += c * w1; s1 += c.rgb * c.rgb * w1; n1 += w1;
      m2 += c * w2; s2 += c.rgb * c.rgb * w2; n2 += w2;
      m3 += c * w3; s3 += c.rgb * c.rgb * w3; n3 += w3;
    }
  }
  m0 /= n0; m1 /= n1; m2 /= n2; m3 /= n3;
  vec3 v0 = abs(s0 / n0 - m0.rgb * m0.rgb);
  vec3 v1 = abs(s1 / n1 - m1.rgb * m1.rgb);
  vec3 v2 = abs(s2 / n2 - m2.rgb * m2.rgb);
  vec3 v3 = abs(s3 / n3 - m3.rgb * m3.rgb);
  float e0 = v0.r + v0.g + v0.b;
  float e1 = v1.r + v1.g + v1.b;
  float e2 = v2.r + v2.g + v2.b;
  float e3 = v3.r + v3.g + v3.b;
  vec4 best = m0;
  float e = e0;
  float t1 = step(e1, e);
  best = mix(best, m1, t1);
  e = mix(e, e1, t1);
  float t2 = step(e2, e);
  best = mix(best, m2, t2);
  e = mix(e, e2, t2);
  float t3 = step(e3, e);
  best = mix(best, m3, t3);
  e = mix(e, e3, t3);

  float paper = uA.y / 100.0;
  vec2 dp = docPos();
  float grain = vnoise(dp * 0.35) * 0.6 + vnoise(dp * 1.3) * 0.4;
  float pool = clamp(e * 18.0, 0.0, 1.0);
  vec3 rgb = best.rgb * (1.0 - paper * (0.16 * (grain - 0.5) + 0.22 * pool));
  fragColor = vec4(clamp(rgb, 0.0, best.a), best.a);
}
