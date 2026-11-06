# Versión %VERSION% (compilación %BUILD%)

### Batería y energía

- Los detalles de la batería ahora incluyen la capacidad máxima del sistema, el estado de la batería, el tiempo de actividad del sistema y el estado del modo de alto rendimiento.
- Cuando «Carga optimizada de la batería» pausa la carga con un límite del 100 %, ahora se puede usar «Cargar al máximo ahora»; si no está disponible, las páginas de detalles y Ajustes explican por qué (#292, #280).

### Brillo y pantallas

- Las pantallas externas incorporan un backend de brillo «Automático»: usa BetterDisplay mientras se ejecuta y, si no, DDC directo.
- Los cambios de brillo de la pantalla integrada desde teclas, Centro de control o Ajustes ahora se reflejan de inmediato en el panel (#286).
- Mientras el panel está abierto, los ajustes de brillo de las pantallas externas también se reflejan pronto en el panel.
- Corregido el tirón al arrastrar el brillo DDC y la identificación correcta de pantallas externas (#284, #285).

### Wi-Fi y red

- La fila resumen de los servicios VPN del sistema ahora tiene un interruptor de energía; las conexiones TUN de Clash Verge ya no se muestran como «VPN», sino correctamente como «TUN» (con el nombre del cliente cuando es Clash Verge), y esa fila permanece de solo lectura sin interruptor (#272).

### Fuente de entrada

- El indicador de fuente de entrada ABC ahora muestra a/A según las mayúsculas y minúsculas (#279).

### Bluetooth

- Mejorado el problema de dispositivos fantasma de Bluetooth (#248).
- Añadido color personalizado para el icono de Bluetooth (#275).

### Panel y ajustes

- Mejorada la coincidencia entre el hover y el área pulsable de la fila de ajustes de batería (#281).
- Refinada la apariencia de las esquinas del diagrama de flujo de energía (#282).
- El intervalo de actualización de estado ahora se ajusta por separado para «Con batería / Conectado a la corriente» (#255).

### Rendimiento y estabilidad

- Reducida la frecuencia de actualización en segundo plano y el uso de recursos, bajando el consumo y mejorando la estabilidad (#294).
- Corregido que la lista de dispositivos de salida no se actualizaba tras cambiar de dispositivo de audio (#293).
