# Versión %VERSION% (compilación %BUILD%)

### Mejoras

- Se mejoró la coherencia de las actualizaciones del panel de estado, conservando sus controles, diseño y navegación.
- El panel de estado se muestra de forma más fiable al cambiar el dispositivo, la red o el audio.

### Privacidad

- Se añadieron estadísticas de uso opcionales. En las instalaciones nuevas, la opción está activada por defecto, pero no se envía ningún heartbeat hasta completar la guía o elegir Personalizar. Las actualizaciones permanecen desactivadas hasta que se habiliten en Ajustes.
- El heartbeat incluye un ID de instalación aleatorio, versiones de la app y macOS, idiomas del sistema y de la app, y ubicación del icono. Consulta [privacidad y análisis](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md).
- La app no incluye ningún SDK de análisis de terceros.
