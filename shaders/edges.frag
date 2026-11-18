// Sobel based effects. uA.x strength (%), uA.y mode (0 edges, 1 pencil sketch, 2 emboss), uA.z angle.
#include "common.glsl"

float lumaAt(vec2 p) {
  vec4 c = src(p);
  return luma(c.rgb);
}

void main() {
  vec2 p = fragPx();
  vec4 c = src(p);
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
  float k = uA.x / 100.0;
  float g = clamp(sqrt(gx * gx + gy * gy) * k, 0.0, 1.0);

  vec3 edges = vec3(g);
  float grain = 0.9 + 0.1 * vnoise(docPos() * 0.8);
  vec3 sketch = vec3(clamp(1.0 - g * 1.3, 0.0, 1.0) * grain);
  float ang = radians(uA.z);
  float e = clamp(0.5 + (gx * cos(ang) + gy * sin(ang)) * k * 0.5, 0.0, 1.0);
  vec3 emboss = vec3(e);

  vec3 o = mix(edges, sketch, step(0.5, uA.y));
  o = mix(o, emboss, step(1.5, uA.y));
  fragColor = vec4(o * c.a, c.a);
}
