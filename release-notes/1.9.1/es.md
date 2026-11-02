# Versión %VERSION% (Compilación %BUILD%)

### Batería

- Los detalles de batería muestran un desglose del flujo de energía (pantalla integrada, salida USB/accesorios y sistema) y una barra opcional de energía en vivo. La salida de accesorios se lee de los raíles del puerto SMC cuando está disponible.
- Nueva opción «Restaurar límite tras cancelar» para Cargar hasta el máximo, con estados más claros cuando macOS inicia la anulación temporal.
- Los colores del icono de batería pueden seguir colores de estado personalizados, con elección aparte del indicador de conexión (rayo, enchufe o porcentaje).
- Modo «dividido» opcional para el anillo de batería: cuando el hueco superior muestra rayo, enchufe o porcentaje, el arco izquierdo lee 0–50 % y el derecho 50–100 %, así 40–60 % deja de ocultarse. Desactivado por defecto; se aplica a la barra de menús y al Dock.

### Energía

- La ranura central puede mostrar la energía total en vivo en lugar de la fuente de conexión, y los Mac sin batería integrada son totalmente compatibles.

### Pantallas

- Control de brillo de pantalla: las externas usan DDC directo y las integradas se controlan con DisplayServices.

### Icono central

- La fuente del espacio central ahora es un único selector «Icono central»: red, dispositivo Bluetooth, fuente de entrada actual, porcentaje de batería o energía. Los dos interruptores de error de red se han unido en uno que afecta a todas las fuentes, el interruptor de Bluetooth «reemplazar icono de red» que no funcionaba se ha eliminado y los valores guardados se migran automáticamente.
- Las fuentes del icono central ahora son mosaicos de imagen que previsualizan el resultado real. Un único «Tamaño del icono central» controla Wi‑Fi, Bluetooth, fuente de entrada y números, y las opciones de estilo del icono de red se movieron a esa página.
- La vista previa muestra el estado de carga, el contenido central queda centrado verticalmente en el anillo de batería y el texto es algo más pequeño que los símbolos.

### Guía

- Guía renovada: la ventana adopta la altura de la página más alta y ya no cambia de tamaño entre pasos; las vistas previas comparten una superficie, las leyendas nombran el arco superior, el icono central y los puntos inferiores, se añaden ejemplos del espacio central (porcentaje, energía, fuente de entrada) y el bloque de consentimiento es más compacto.

### Ajustes

- Todos los menús emergentes de Ajustes usan un ancho común y ya no cambian de ancho con sus opciones o la lista de dispositivos, manteniendo el aspecto nativo.

### Audio

- Los dispositivos de entrada y salida se pueden reordenar, ocultar y limitar en número.
- La respuesta de volumen con la rueda se configura por separado y volver a pulsar el modo de escucha seleccionado lo desactiva.

### Panel

- El panel de estado usa un estilo sin esquinas ni muesca, añade un menú «más» inferior y adapta mejor tamaño y diseño con Liquid Glass.

### Correcciones

- La información de Wi-Fi se sigue mostrando sin permiso de Ubicación.
