# Drawly

Estudio de dibujo y animación 2D, libre y de código abierto, hecho con Flutter para escritorio, móvil y web.

## Funciones

- **Dibujo:** pinceles con presión, borrador, difuminar, cubo de pintura, degradados, formas (incluidos globos de cómic), texto, selecciones y licuar.
- **Capas:** trama, vector, texto, grupos, capas de ajuste, instancias y partículas; máscaras, modos de fusión, efectos (sombra, resplandor, trazo) y emparentado.
- **Animación:** línea de tiempo con exposiciones y fotogramas clave, intermedios vectoriales, cámara, audio WAV con forma de onda, cinemática inversa, huesos que deforman el dibujo, seguimiento de movimiento y física con rebote.
- **Archivos:** formato propio `.drawly`; importa imágenes, SVG, OpenRaster y paletas (GPL, HEX, PAL, ACO, ASE); exporta PNG, JPG, WebP, BMP, TIFF, TGA, GIF, APNG, secuencias, hojas de sprites con su JSON, SVG, ORA, PSD, Lottie y listas de edición EDL / XML de Final Cut Pro 7.
- **Idiomas:** español, inglés, portugués y francés.

## Compilar

Requisitos: [Flutter](https://docs.flutter.dev/get-started/install) estable.

```sh
flutter pub get
flutter run                     # en el dispositivo o escritorio conectado
flutter build windows --release # o macos, linux, apk, web
```

Pruebas y análisis:

```sh
flutter analyze
flutter test
```

## Licencia

Copyright (C) 2026 Oscar Reyes

Drawly es software libre: puedes redistribuirlo y/o modificarlo bajo los términos de la Licencia Pública General de GNU publicada por la Free Software Foundation, ya sea la versión 3 de la Licencia o (a tu elección) cualquier versión posterior.

Drawly se distribuye con la esperanza de que sea útil, pero SIN NINGUNA GARANTÍA; ni siquiera la garantía implícita de COMERCIABILIDAD o IDONEIDAD PARA UN PROPÓSITO PARTICULAR. Consulta la Licencia Pública General de GNU para más detalles.

El texto completo de la licencia está en [LICENSE](LICENSE) (GPL-3.0-or-later).
