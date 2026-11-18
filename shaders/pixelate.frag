// Mosaic. uA.x cell size (doc px).
#include "common.glsl"

void main() {
  float size = max(1.0, uA.x);
  vec2 cell = (floor(docPos() / size) + 0.5) * size;
  fragColor = src((cell - uOrigin) * uScale);
}
