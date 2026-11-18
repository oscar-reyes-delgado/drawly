// Shared header for Drawly filter shaders.
//
// Uniform layout (floats):
//   0-1   uSize    size of the source image in pixels (local coords)
//   2-3   uOrigin  document coordinate of the image's top-left pixel
//   4     uScale   image pixels per document pixel
//   5-8   uA       filter parameters 0..3
//   9-12  uB       filter parameters 4..7 / key colour / document rect
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform vec2 uOrigin;
uniform float uScale;
uniform vec4 uA;
uniform vec4 uB;
uniform sampler2D uImage;

out vec4 fragColor;

vec2 fragPx() { return FlutterFragCoord().xy; }

vec2 flipY(vec2 uv) {
#ifdef IMPELLER_TARGET_OPENGLES
  return vec2(uv.x, 1.0 - uv.y);
#else
  return uv;
#endif
}

// Sample the source at a pixel position (premultiplied colour).
vec4 src(vec2 px) { return texture(uImage, flipY(px / uSize)); }

// Like src() but transparent outside the image.
vec4 srcDecal(vec2 px) {
  vec2 uv = px / uSize;
  float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  return texture(uImage, flipY(clamp(uv, 0.0, 1.0))) * inside;
}

// Document-space position of the current fragment.
vec2 docPos() { return uOrigin + fragPx() / uScale; }

vec3 unpremul(vec4 c) { return c.a > 0.0001 ? c.rgb / c.a : vec3(0.0); }

float luma(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float hash21(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  float a = hash21(i);
  float b = hash21(i + vec2(1.0, 0.0));
  float c = hash21(i + vec2(0.0, 1.0));
  float d = hash21(i + vec2(1.0, 1.0));
  return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}
