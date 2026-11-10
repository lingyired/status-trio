# Versión %VERSION% (Compilación %BUILD%)

### Batería

- Se ha añadido el flujo de energía de la batería con estimaciones de la entrada del cargador, la energía que entra en la batería y la energía del sistema. La entrada del cargador está desactivada de forma predeterminada; las otras dos lecturas están activadas.
- Se ha añadido una lista opcional del impacto energético de la CPU con hasta cinco apps a partir de muestras recientes. Si los contadores de energía no están disponibles, usa la actividad de la CPU y permite un intervalo de muestreo de 10–60 segundos.
- En Macs compatibles con chip Apple y macOS 26.4 o posterior, Cargar hasta el máximo y Cancelar carga hasta el máximo están disponibles y se activan de forma predeterminada cuando la función es compatible.

### Pantallas externas

- Se ha añadido un método de control de volumen mediante BetterDisplay para pantallas externas o salidas de audio cuyo volumen no puede controlar macOS directamente. Permite asociar la pantalla de forma automática o manual y muestra los estados de conexión y error.
- Se sigue dando prioridad al volumen nativo que admite escritura, el modo Standard/DDC puede restaurarse en cualquier momento y Status Trio no inicia ni modifica BetterDisplay cuando no está disponible.

### Estabilidad e interfaz

- Se ha mejorado la gestión de eventos de Wi-Fi agrupando las llamadas de CoreWLAN de alta frecuencia y limitando la frecuencia de recuperación en estados anómalos, lo que reduce el riesgo de que una tormenta de eventos amplifique la presión sobre la CPU y la memoria.
- El panel de estado ahora conserva la página de detalles actual al volver a abrirlo en lugar de regresar a la página principal.
- Se han mejorado el diseño y la navegación de los detalles de la batería, el área pulsable del engranaje y la actualización de la energía en tiempo real.
- Se ha mejorado la composición de la capa de color y la imagen de plantilla en la barra de menús. Las pantallas sin foco ahora se atenúan correctamente y se mantiene el cambio de color del sistema al cambiar de Space.

### Notas importantes

- Cargar hasta el máximo usa una interfaz privada de PowerUI y solo está disponible en Macs con chip Apple y macOS 26.4 o posterior. No se garantiza su comportamiento entre distintas versiones de macOS.
- Tras completar la carga o volver a conectar el adaptador de corriente, el límite de carga puede seguir en 100 %. Status Trio no lo restaura automáticamente; usa Cancelar carga hasta el máximo o restaura el límite en Ajustes del Sistema.
- La lista del impacto energético de la CPU no representa el consumo total de energía de una app ni es una copia de la lista “Uso importante de energía” de macOS.
- El control de volumen mediante BetterDisplay requiere que BetterDisplay esté en ejecución. El volumen de la pantalla y el comportamiento DDC siguen dependiendo del hardware y la conexión.
