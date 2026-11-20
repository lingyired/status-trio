# Versión %VERSION% (compilación %BUILD%)

### Monitor del sistema

- El panel de estado ahora supervisa CPU, GPU, memoria, red, disco y velocidad del ventilador; haz clic para abrir la página de detalles correspondiente.
- Colores personalizados para las métricas de CPU, GPU, memoria, red, disco y velocidad del ventilador.
- Personaliza el intervalo de actualización y el rango del historial.
- El monitor del sistema muestrea a demanda: solo lee las métricas mientras se muestran y el historial en segundo plano está desactivado de forma predeterminada, lo que reduce la carga.

### Icono de la barra de menús y anillo

- Nuevas fuentes de datos del monitor del sistema para el anillo exterior, con diseño de anillo único y doble anillo izquierdo/derecho. Los arcos pueden usar uso de CPU, temperatura de CPU, uso de GPU, temperatura de GPU, uso de memoria, temperatura de la batería, nivel de batería, velocidad del ventilador, velocidad de descarga/subida, volumen y señal Wi-Fi.
- El arco del nivel de batería sigue los colores del sistema; un nuevo rol de color «Descarga (sin corriente)» permite personalizar por separado los colores de carga, bajo, alto rendimiento, crítico y descarga (#357).
- Nuevo modo AirPods para el indicador superior: los anillos dobles pueden mostrar la batería de los auriculares izquierdo y derecho (también uno solo) y, al desconectarse, vuelven a la batería del Mac o a un anillo personalizado.
- El indicador inferior admite una fuente de datos personalizada: volumen, señal Wi-Fi o nivel de batería (u oculto).

### Panel e interacción

- Pasa el cursor sobre el icono de la barra de menús para mostrar el panel; haz clic para fijarlo (#355).
- Los detalles se abren ahora en un panel lateral junto al panel de estado, con un cambio más fluido.
- Nueva tarjeta de monitor de hardware.
- Se refinaron los controles deslizantes numéricos (volumen y brillo) con un aspecto más cercano a macOS 26+ y un movimiento más fluido; admiten deslizamiento horizontal en el trackpad (#351).
- Los iconos de Wi-Fi y Bluetooth se tiñen según el estado de conexión (#352).
- El botón «Cargar al máximo ahora» incorpora un brillo liquid glass al pasar el cursor.
- Se quitó la negrita del panel de estado; los valores y unidades usan una fuente monoespaciada.

### Mantener activo y reposo

- Se añadieron «Mantener pantalla encendida» y «Sin reposo con tapa cerrada», cada uno con duración personalizable (#295).

### Brillo

- Nuevo interruptor «Usar brillo combinado de BetterDisplay» (#344).

### Batería y audio

- Se corrigió el texto y la fila de carga de mantenimiento al 100 %.
- Se corrigió el silencio con volumen exactamente cero y la restauración del silencio automático.
- Se corrigió la estimación de «tiempo hasta carga completa» para respetar el límite de carga de macOS (#349).

### Otras correcciones

- El historial de detalles del monitor ahora se aísla por tipo de métrica.
- Se mejoró el muestreo en segundo plano y la estabilidad de las tuberías de procesos, con menos tirones e interferencias.
- Se corrigió el parpadeo de altura de la fila del modo de escucha de AirPods al abrir el panel (#354).
