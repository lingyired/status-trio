# Versión %VERSION% (Compilación %BUILD%)

### Novedades

- Control del modo de bajo consumo: un interruptor opcional en los detalles de la batería activa o desactiva el modo de bajo consumo sin abrir Ajustes del Sistema. Requiere una aprobación única en Ajustes del Sistema › General › Ítems de inicio de sesión, en «Permitir en segundo plano»; el asistente que registra no hace nada más, solo se ejecuta mientras la app lo usa y se cierra solo cuando está inactivo. La indicación de aprobación permanece bajo el control y toda la fila abre los ítems de inicio de sesión.
- Nivel de anillo lleno: elige el nivel de carga al que el anillo de batería se considera lleno (50%–100%, 100% por defecto). Útil en un Mac cuyo límite de carga mantiene la batería por debajo del 100%; «Usar el límite de carga» lee el valor del sistema. La barra de menús y el Dock siguen juntos.
- IP local: un ajuste opcional de Red que muestra la dirección privada de LAN de este Mac en la segunda línea de la fila de red, antes de los detalles de Wi-Fi. Desactivado por defecto.
- Compartir Internet: las páginas de detalles de Wi-Fi y de cable pueden abrir directamente el panel «Compartir», donde se activa Compartir Internet. La app solo abre el panel; no activa ni desactiva la compartición por su cuenta.

### Correcciones

- Señal Wi-Fi: se puentean las lecturas no válidas intermitentes de CoreWLAN, así el icono conectado ya no se atenúa ni muestra 0 barras.
- Iconos de dispositivos Bluetooth: el icono ahora se dibuja solo según la clase que declara el propio dispositivo (device_minorType), así que conectar o desconectar ya no lo cambia. Si un fabricante declara mal la clase —por ejemplo, un teclado que se anuncia como ratón—, el icono sigue esa declaración y la app ya no la corrige.
- Icono de la barra de menús: la parte monocroma vuelve a colorearse en vivo mientras se arrastra un espacio.
- Alineación de iconos: los SF Symbols se centran por su tinta visible y no por su caja de diseño, así el icono de Wi-Fi ya no queda descentrado en el anillo.
- Audio: se eliminó la fila duplicada de resumen de salida de audio.

### Notas

- Mientras se arrastra un cambio de espacio, solo un icono totalmente monocromo sigue al espacio de destino; los elementos con color de estado (batería baja, modo de bajo consumo, corriente conectada, Bluetooth) se actualizan al confirmarse el cambio.
