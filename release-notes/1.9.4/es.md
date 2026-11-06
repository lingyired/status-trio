# Versión %VERSION% (compilación %BUILD%)

### Batería y energía

- Los detalles de la batería ahora muestran la capacidad máxima del sistema, el estado de la batería y el tiempo de actividad del sistema.
- El modo de alto rendimiento ahora aparece siempre como una fila clara y propia en los detalles, leyendo su estado desde pmset; los estados de salud y alto rendimiento desconocidos se muestran explícitamente.
- Cuando «Carga optimizada de la batería» pausa la carga con un límite del 100 %, «Cargar al máximo ahora» funciona: la solicitud se envía como lo hace macOS y, al completarse, no restaura el límite de carga anterior (#292).
- Las páginas de detalles y Ajustes ahora explican por qué «Cargar al máximo ahora» no está disponible u oculto (#280, #292).
- En Ajustes se explica que un límite del 100 % aún puede pausar la carga por la carga optimizada (#292).

### Brillo y pantallas

- Las pantallas externas incorporan un backend de brillo Automático: usa BetterDisplay mientras se ejecuta y, si no, DDC directo; un backend elegido explícitamente se recuerda y nunca se sobrescribe.
- Los cambios de brillo de la pantalla integrada desde teclas, Centro de control o Ajustes ahora se reflejan de inmediato en el panel (#286).
- Mientras el panel está visible, el brillo de las pantallas externas se actualiza a un intervalo limitado de 2 segundos para que los cambios por teclado lleguen pronto al panel.
- Corregido el tirón al arrastrar el brillo DDC y la identificación correcta de pantallas externas para no controlar la pantalla integrada como externa (#284, #285).

### Wi-Fi y red

- Añadido un interruptor de energía para Clash Verge TUN: el TUN se identifica mediante la API de solo lectura de Mihomo, los túneles simples se muestran como «TUN» en lugar de «VPN» y el estado del interruptor se mantiene sincronizado (#272).
- Mejorada la visibilidad del interruptor de energía en la fila resumen de Wi-Fi y el alcance de la confirmación antes de desactivar una red (#252).

### Fuente de entrada

- Corregido que no se mantenía la mayúscula al activar Caps Lock y Mayús a la vez; el indicador ahora muestra correctamente a/A (#279).

### Bluetooth

- Añadido color personalizado para el icono de Bluetooth (#275).
- Las lecturas de batería obsoletas de dispositivos Bluetooth desconectados ahora caducan en lugar de permanecer.

### Panel y ajustes

- Alineada la decoración al pasar el ratón de la fila de ajustes de batería con los límites del botón pulsable y añadido espacio (#281).
- Restauradas las tarjetas redondeadas del diagrama de flujo de energía y ocultado el desbordamiento de la cinta (#282).
- Restaurado el componente deslizante original para los intervalos de actualización en Ajustes (#255).

### Rendimiento y estabilidad

- Ajustados los tiempos de vida de los hilos de monitorización y la cadencia de sondeo para reducir el coste en segundo plano y mejorar la estabilidad (#294).
- Se actualizan los dispositivos de salida en caché cuando cambia la topología de dispositivos de audio (#293).
- Corregidos problemas de rendimiento y estabilidad en iconos, panel, Ajustes y monitorización.
