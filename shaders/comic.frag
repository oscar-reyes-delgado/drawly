// Comic / cel look. uA.x colour levels, uA.y outline 0..100, uA.z dot screen 0..100.
#include "common.glsl"

float lumaAt(vec2 p) {
  vec4 c = src(p);
  return luma(c.rgb) + (1.0 - c.a);
}

void main() {
  vec2 p = fragPx();
  vec4 c = src(p);
  vec3 rgb = unpremul(c);
  float levels = max(2.0, uA.x);
  vec3 post = floor(rgb * levels + 0.5) / levels;

  float d = max(1.0, uScale);
  float tl = lumaAt(p + vec2(-d, -d));
  float t = lumaAt(p + vec2(0.0, -d));
  float tr = lumaAt(p + vec2(d, -d));
  float l = lumaAt(p + vec2(-d, 0.0));
  float r = lumaAt(p + vec2(d, 0.0));
  float bl = lumaAt(p + vec2(-d, d));
  float b = lumaAt(p + vec2(0.0, d));
  float br = lumaAt(p + vec2(d, d));
  float gx = -tl - 2.0 * l - bl + tr + 2.0 * r + br;
  float gy = -tl - 2.0 * t - tr + bl + 2.0 * b + br;
  float g = sqrt(gx * gx + gy * gy);
  float edge = smoothstep(0.25, 0.6, g) * (uA.y / 100.0);

  // ben-day dots in the shadows
  vec2 q = docPos() / 6.0;
  vec2 rq = vec2(q.x * 0.7071 + q.y * 0.7071, -q.x * 0.7071 + q.y * 0.7071);
  float dist = length(fract(rq) - 0.5);
  float shade = clamp(1.0 - luma(post) * 1.4, 0.0, 1.0);
  float dots = (1.0 - smoothstep(shade * 0.6 - 0.05, shade * 0.6 + 0.05, dist)) * (uA.z / 100.0);
  post *= 1.0 - dots * 0.45;

  vec3 o = mix(post, vec3(0.0), edge);
  float a = max(c.a, edge);
  fragColor = vec4(o * a, a);
}
