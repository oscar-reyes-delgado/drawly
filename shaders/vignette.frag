// Vignette. uA.x amount -100..100, uA.y size, uA.z softness. uB = document rect.
#include "common.glsl"

void main() {
  vec4 c = src(fragPx());
  vec2 center = uB.xy + uB.zw * 0.5;
  vec2 d = (docPos() - center) / (uB.zw * 0.5);
  float dist = length(d) / 1.4142;
  float inner = 1.0 - uA.y / 100.0;
  float soft = max(0.01, uA.z / 100.0);
  float v = smoothstep(inner * 0.9, inner * 0.9 + soft, dist);
  float amt = uA.x / 100.0;
  vec3 rgb = unpremul(c);
  vec3 dark = rgb * (1.0 - v * max(amt, 0.0));
  vec3 lite = mix(dark, vec3(1.0), v * max(-amt, 0.0));
  fragColor = vec4(lite * c.a, c.a);
}
