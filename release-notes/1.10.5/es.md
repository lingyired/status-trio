# Versión %VERSION% (compilación %BUILD%)

## Sensores y temperaturas

- La temperatura GPU del M3 Air (Mac15,12) vuelve a funcionar: los sensores Tf ilegibles se sustituyen por los Tg verificados y se agrupan en seis pares para no contar dos veces una misma zona física.
- En M5 y M6 las sondas de un mismo núcleo de CPU se agrupan; varias sondas ya no aumentan el número de núcleos ni el promedio.
- Se añade la identificación del A18 Pro. Los chips desconocidos no toman las claves de temperatura de otra generación; muestran sin lectura en lugar de un número plausible pero incorrecto.

## Consumo de pantalla

- Corregido el Issue #374: un M3 Air sin PDBR y con PBLR fijo en 0 ya no muestra una rama de pantalla de 0,00 W.
- Si no hay una vía de retroiluminación medida utilizable, el consumo de pantalla puede recurrir a una estimación de AppleARMBacklight. Los 6 V son una suposición, no una medición; el valor se marca con ≈ y el residual del sistema como estimado.
- Las ramas de pantalla y USB de 0 W se ocultan.

## Monitorización y rendimiento

- Las capacidades de los sensores se sondean una vez y se almacenan en caché; las claves inexistentes se reintentan con retroceso.
- Sin nuevos temporizadores, helper ni accesos privilegiados. La captura de temperatura y retroiluminación sigue deteniéndose al cerrar el panel.
