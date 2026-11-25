# Versión %VERSION% (Compilación %BUILD%)

## Novedades

- El indicador inferior ahora incluye la opción «Presión de memoria», para ver de un vistazo el uso actual de memoria.
- Los detalles del disco ahora muestran todos los volúmenes montados (internos y externos) con su velocidad de lectura/escritura individual; el porcentaje superior puede incluir opcionalmente SSD externos.
- Los cuatro anillos del monitor de hardware ahora pueden dividir el progreso hacia ambos lados, de modo que el porcentaje superior ya no tapa el anillo.
- La página de detalles del hardware incluye un botón «Abrir Monitor de Actividad» para ver rápidamente qué consume recursos.
- La lista de alto uso / alto consumo ahora permite fijar una fila y forzar su cierre (incluidos sus procesos secundarios); las tarjetas muestran una cuenta atrás de actualización y el elemento desaparece en cuanto se cierra.

## Correcciones

- Se corrigió la temperatura de GPU del M3 Air que no se podía leer y se evitó contar dos veces la misma zona.
- Se optimizó el cálculo de la temperatura de CPU para M5 / M6.
- Se añadió la identificación del A18 Pro; los chips no reconocidos ahora muestran «no disponible» en lugar de una temperatura errónea.
- Se corrigió un caso en el que algunos modelos seguían mostrando 0,00 W de consumo de pantalla sin una lectura real.
- El consumo de pantalla ahora se oculta cuando no hay una lectura real, en lugar de mostrar una estimación; ya no quedan valores antiguos con la pantalla apagada o la tapa cerrada.
- El consumo de 0 W de pantalla y USB ya no se muestra como consumo real.
- Se corrigió el fallo de la primera lectura del ajuste de tapa en arranque en frío; ahora se reintenta automáticamente.
- Se corrigió un tiempo de espera falso en el que la app se rendía antes que el servicio en segundo plano; los mensajes de error ahora incluyen un código para el diagnóstico.
- Cuando no hay dispositivo de audio disponible se oculta el control de volumen y se muestra el aviso «No hay dispositivos disponibles».
- Se mejoraron algunos textos en inglés y las líneas largas para que ya no se corten.
