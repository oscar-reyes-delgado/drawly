// Lookup-table colour mapping. uA.x: 0 = per channel, 1 = luminance indexed.
#include "common.glsl"

uniform sampler2D uLut;

void main() {
  vec4 c = src(fragPx());
  vec3 rgb = clamp(unpremul(c), 0.0, 1.0);
  vec3 perCh = vec3(
    texture(uLut, vec2((rgb.r * 255.0 + 0.5) / 256.0, 0.5)).r,
    texture(uLut, vec2((rgb.g * 255.0 + 0.5) / 256.0, 0.5)).g,
    texture(uLut, vec2((rgb.b * 255.0 + 0.5) / 256.0, 0.5)).b);
  float l = luma(rgb);
  vec3 byLuma = texture(uLut, vec2((l * 255.0 + 0.5) / 256.0, 0.5)).rgb;
  vec3 o = mix(perCh, byLuma, step(0.5, uA.x));
  fragColor = vec4(o * c.a, c.a);
}
