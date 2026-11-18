// Simulated CMYK print preview: ink limit, dot gain and paper / ink tint.
#include "common.glsl"

void main() {
  vec4 c = src(fragPx());
  vec3 rgb = unpremul(c);
  float k = 1.0 - max(rgb.r, max(rgb.g, rgb.b));
  vec3 cmy = (1.0 - rgb - k) / max(1.0 - k, 0.0001);
  // dot gain
  cmy = pow(cmy, vec3(0.86));
  k = pow(k, 0.9);
  // total ink limit 300%
  float total = cmy.x + cmy.y + cmy.z + k;
  float s = min(1.0, 3.0 / max(total, 0.0001));
  cmy *= s;
  // inks are not perfectly pure
  vec3 o = vec3(1.0);
  o *= mix(vec3(1.0), vec3(0.0, 0.62, 0.89), cmy.x);
  o *= mix(vec3(1.0), vec3(0.89, 0.0, 0.50), cmy.y);
  o *= mix(vec3(1.0), vec3(1.0, 0.93, 0.0), cmy.z);
  o *= mix(vec3(1.0), vec3(0.11, 0.10, 0.10), k);
  // paper white
  o *= vec3(0.985, 0.98, 0.955);
  fragColor = vec4(o * c.a, c.a);
}
