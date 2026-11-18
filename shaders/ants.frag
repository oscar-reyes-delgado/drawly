// Marching ants: outlines the 50% contour of a selection mask.
// Uniforms: uSize (px), uPhase, uStripe.
#include <flutter/runtime_effect.glsl>

precision highp float;

uniform vec2 uSize;
uniform float uPhase;
uniform float uStripe;
uniform sampler2D uMask;

out vec4 fragColor;

float m(vec2 px) {
  vec2 uv = px / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  float inside = step(0.0, uv.x) * step(uv.x, 1.0) * step(0.0, uv.y) * step(uv.y, 1.0);
  return step(0.5, texture(uMask, clamp(uv, 0.0, 1.0)).a) * inside;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float c = m(p);
  float n = m(p + vec2(1.0, 0.0)) + m(p - vec2(1.0, 0.0)) + m(p + vec2(0.0, 1.0)) + m(p - vec2(0.0, 1.0));
  float edge = step(0.5, abs(n - c * 4.0)) * c + step(0.5, n) * (1.0 - c) * 0.0;
  float stripe = step(0.5, fract((p.x + p.y + uPhase) / uStripe));
  vec3 col = vec3(stripe);
  fragColor = vec4(col * edge, edge);
}
