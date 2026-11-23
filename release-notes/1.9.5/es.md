# Versión %VERSION% (compilación %BUILD%)

### Panel y audio Bluetooth

- AirPods ahora admite «Spatialize Stereo» y «Conversation Awareness».
- Se añadió el cambio de modo de escucha para auriculares Redmi / Xiaomi.
- Corregido: los auriculares seguían mostrando «Conectado» durante unos dos minutos tras devolverlos al estuche.
- Corregido: un solo clic en el icono de estado actualizaba el panel en lugar de cerrarlo, en modo normal, solo barra de menús y al hacer clic en el borde del icono (#224).
- Volumen con la rueda más fluido: se actualiza por evento con una breve animación en el control, y cada paso es 1/16 para acercarse a las teclas de volumen del sistema.

### Batería y energía

- El tiempo de uso restante ahora aparece en el panel de estado y en los detalles, que también muestran la temperatura de la batería (#298).
- «Capacidad máxima» ahora usa el porcentaje de salud del sistema para coincidir con macOS (#317), y recurre a la información del sistema si no se puede leer el estado.
- El desglose de energía divide la salida USB por puerto y nombra cada accesorio; corregida la pérdida de toda la salida USB cuando el puerto de carga alcanza el límite de 300 W, y la falta de consumo de la pantalla integrada en algunos modelos.
- Los Mac sin batería muestran un anillo lleno, el indicador superior alterna entre rayo y enchufe (#310); el anillo lleno solo se aplica con corriente (#318).
- «Cargar al 100% ahora» coincide con el comportamiento nativo y se elimina la interfaz extra de «restaurar límite».
- El muestreo de energía y el escaneo Bluetooth cercano se pausan cuando la pantalla duerme y se reanudan al despertar, ahorrando energía (#300).
- El control segmentado del modo de energía usa ahora un fondo translúcido acorde con Liquid Glass.

### Iconos y apariencia

- Se añadió una opción para usar iconos en blanco y negro durante la carga y la conexión (#309).
- El indicador superior de batería ahora puede configurarse por separado según el estado de uso (batería / carga, etc.) (#315).
- Corregido: la pieza del anillo superior de la barra de menús estaba desalineada y se desplazaba (#30).
- Corregido: el icono de animación de carga del Dock se reducía a la mitad en pantallas 1x (#303).

### Pantallas y brillo

- Los ajustes de brillo permiten elegir manualmente una pantalla de BetterDisplay y sugieren cambiarla a mano cuando el brillo no está disponible (#313).
- Corregido: el brillo no estaba disponible cuando la identidad de una pantalla externa era ambigua (ahora recurre a la única pantalla externa).

### Red y fuente de entrada

- Se añadió un interruptor «Confirmar antes de apagar el Wi-Fi» (#305).
- El indicador de fuente Pinyin distingue pinyin simplificado y tradicional; el marcador 简/繁 ahora es opcional y puede mostrar 中.

### Otros

- Corregido: la lista de dispositivos de salida desaparecía cuando fallaba la lectura del volumen (#296).
