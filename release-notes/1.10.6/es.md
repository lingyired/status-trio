# Versión %VERSION% (Compilación %BUILD%)

## Correcciones

- Se corrigió un error falso de «no se puede leer el estado de mantener despierto con la tapa cerrada» (código DS-R4) en Macs que nunca habían activado esta función. macOS solo muestra el ajuste tras usarlo una vez, así que ahora la app lo trata como desactivado en lugar de un fallo de lectura.
- El interruptor de mantener despierto con la tapa cerrada ahora muestra el estado inicial correcto y funciona al primer clic en esos Macs, sin ejecutar `sudo pmset -a disablesleep` manualmente.
