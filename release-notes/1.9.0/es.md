# Versión %VERSION% (Compilación %BUILD%)

### Batería

- Modo «dividido» opcional para el anillo de batería: cuando el hueco superior muestra rayo, enchufe o porcentaje, el arco izquierdo lee 0–50 % y el derecho 50–100 %, así 40–60 % deja de ocultarse. Desactivado por defecto; se aplica a la barra de menús y al Dock.
- Los colores del icono de batería pueden seguir colores de estado personalizados, con elección aparte del indicador de conexión (rayo, enchufe o porcentaje). La barra de menús y el Dock comparten una escena.
- Los detalles de batería muestran un desglose del flujo de energía (pantalla integrada, salida USB/accesorios y sistema) y una barra opcional de energía en vivo. La salida de accesorios se lee de los raíles del puerto SMC cuando está disponible.
- Nueva opción «Restaurar límite tras cancelar» para Cargar hasta el máximo, con estados más claros cuando macOS inicia la anulación temporal.

### Energía

- La ranura central puede mostrar la energía total en vivo en lugar de la fuente de conexión, y los Mac sin batería integrada son totalmente compatibles.

### Pantallas

- Control de brillo de pantalla: las externas usan DDC directo y las integradas se controlan con DisplayServices, por lo que BetterDisplay ya no es necesario para pantallas integradas.
- En el diagrama de flujo, la altura de cada tarjeta es proporcional a su cuota, con cualquier número de ramas.

### Audio

- Los dispositivos de entrada y salida se pueden reordenar, ocultar y limitar en número. Un único dispositivo con modo de escucha conserva sus botones de control de ruido aunque se oculten otras salidas.
- La respuesta de volumen con la rueda se configura por separado y volver a pulsar el modo de escucha seleccionado lo desactiva.

### Panel

- El panel de estado usa un estilo sin esquinas ni muesca, añade un menú «más» inferior y adapta mejor tamaño y diseño con Liquid Glass. En el orden predeterminado, «Brillo de pantalla» está bajo «Entrada de audio».

### Correcciones

- Reiniciar durante Cargar hasta el máximo conserva el límite de restauración derivado al inicio en vez de volver al 100 %.
- Cerrar el panel de estado libera el muestreo de la barra de energía; el icono solo muestrea cada 2 s mientras muestra energía.
- Alternar la barra de energía con el panel abierto usa el nuevo valor de inmediato.
- Un desglose de energía de batería verificado ya no se descarta al desenchufar el Mac.
- Conectar en caliente una pantalla actualiza la lista de brillo y descarta la conexión DDC obsoleta.
- Una escritura DDC sin confirmar muestra «no disponible» en lugar de perder el control y la explicación.
- La información de Wi-Fi se sigue mostrando sin permiso de Ubicación.
