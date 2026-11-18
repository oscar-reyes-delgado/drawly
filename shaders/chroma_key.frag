// Chroma key. uB.rgb key colour, uA.x tolerance, uA.y softness, uA.z despill (all 0..100).
#include "common.glsl"

vec2 chroma(vec3 c) {
  return vec2(-0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b, 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b);
}

void main() {
  vec4 c = src(fragPx());
  vec3 rgb = unpremul(c);
  vec3 key = uB.rgb;
  float dist = distance(chroma(rgb), chroma(key));
  float tol = uA.x / 100.0 * 0.5;
  float soft = max(0.001, uA.y / 100.0 * 0.3);
  float keep = smoothstep(tol, tol + soft, dist);

  // despill: pull the key's dominant channel back to the others
  float kmax = max(key.r, max(key.g, key.b));
  vec3 dom = vec3(step(kmax - 0.0001, key.r), step(kmax - 0.0001, key.g), step(kmax - 0.0001, key.b));
  dom /= max(1.0, dom.r + dom.g + dom.b);
  float domV = dot(rgb, dom);
  float others = (rgb.r + rgb.g + rgb.b - domV) * 0.5;
  float excess = max(0.0, domV - others);
  rgb -= dom * excess * (uA.z / 100.0);

  float a = c.a * keep;
  fragColor = vec4(clamp(rgb, 0.0, 1.0) * a, a);
}
