# Versión %VERSION% (compilación %BUILD%)

### Novedades

- Ahora es compatible con macOS 13.
- Se añadieron estadísticas de uso opcionales. Están desactivadas por defecto; debes activarlas tú mismo.
- Batería de dispositivos Apple: permite leer la batería de un Apple Watch emparejado a través de un iPhone conectado y muestra los dispositivos Apple de confianza como filas unificadas en la lista Bluetooth. También añade la actualización de la batería en segundo plano con un intervalo configurable. La batería solo se lee en los dispositivos seleccionados visibles en el panel.
- Ahora puedes personalizar el icono de audio Bluetooth.

### Mejoras

- Se optimizó la lógica de actualización del icono y del panel de estado.

### Correcciones

- Representación de iconos: se corrigieron la fidelidad de los mapas de bits en caché, el cambio de tamaño con animación estable, el color del latido del rayo de carga y la alineación de la barra de menús y el Dock.
- La primera actualización de Bluetooth ya no abre Ajustes por error.

### Privacidad

- Explica las estadísticas de uso opcionales, qué contiene un heartbeat y que no se incluye ningún SDK de análisis de terceros. Consulta [privacidad y análisis](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md) para obtener todos los detalles.
