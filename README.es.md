<p align="center">
  <img src="screenshots/status-trio-dock-state-strip-symmetric.png" width="1000" alt="Ocho estados del icono de Status Trio en el Dock con fondos oscuros y claros dispuestos de forma simétrica, incluidos estados de Wi-Fi, audio por Bluetooth, batería, puntos y arco">
</p>

<p align="center">
  <img src="Support/AppIcon.png" width="112" alt="Icono de la app Status Trio">
</p>

<h1 align="center">Status Trio</h1>

<p align="center">
  <a href="https://trendshift.io/repositories/234371?utm_source=trendshift-badge&utm_medium=badge&utm_campaign=badge-trendshift-234371" target="_blank" rel="noopener noreferrer"><img src="https://trendshift.io/api/badge/trendshift/repositories/234371/daily?language=Swift" alt="lingyired/status-trio | Trendshift" width="250" height="55"/></a>
</p>

<p align="center"><strong>Tres señales del sistema. Un solo icono de estado nativo de macOS: en la barra de menús o en el Dock.</strong></p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/badge/Download%20for%20macOS-Universal%20%C2%B7%20macOS%2013%20target-000000?logo=apple&logoColor=white&style=for-the-badge" alt="Descargar para macOS — versión universal, macOS 13 como objetivo de implementación (validación de Ventura pendiente)"></a>
</p>

<p align="center">
  ¿Quieres verlo en acción primero? Abre <a href="https://statustrio.lingai.net/">statustrio.lingai.net</a> para simular todos los estados del icono en el navegador.
</p>

<p align="center">
  <a href="https://github.com/lingyired/status-trio/releases/latest"><img src="https://img.shields.io/github/v/release/lingyired/status-trio?label=release&color=blue" alt="Última versión"></a>
  <a href="https://github.com/lingyired/status-trio/actions/workflows/release.yml"><img src="https://github.com/lingyired/status-trio/actions/workflows/release.yml/badge.svg" alt="Estado del flujo de trabajo Build and Release macOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/lingyired/status-trio?label=license" alt="Licencia: Apache-2.0"></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-13%20target%20%28validation%20pending%29-blue?logo=apple&logoColor=white" alt="Compatible con macOS 13 como objetivo de implementación (validación de Ventura pendiente)">
  <img src="https://img.shields.io/badge/Universal-Apple%20Silicon%20%7C%20Intel-lightgrey" alt="Binario universal para Apple Silicon e Intel">
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <strong>Español</strong> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.pt-BR.md">Português (Brasil)</a> ·
  <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="screenshots/menu-bar-wifi.jpg" width="1000" alt="Icono de Status Trio en la barra de menús mostrando el glifo de Wi-Fi mientras hay conexión Wi-Fi, con su panel emergente de estado abierto">
</p>

Status Trio es una app de estado nativa de macOS que combina Wi-Fi, batería y volumen en un único icono compacto y configurable, que se muestra en la barra de menús, en el Dock o en ambos. Su panel emergente va más allá del icono: un panel de Wi-Fi para las redes cercanas y los detalles del enlace, un panel de Bluetooth para los dispositivos emparejados, una página de Detalles de la batería y los dispositivos de audio que están reproduciendo. Está inspirada en el icono combinado de la barra de estado del iPhone Duo para Wi-Fi, batería y datos móviles, adaptado al Mac con el volumen en lugar de los datos móviles.

> Status Trio es un proyecto independiente y no está afiliado a Apple.

## Aspectos destacados

- **Un icono, tres señales** — la batería, el Wi-Fi y el volumen comparten un solo icono en la barra de menús, en el Dock o en ambos, y un dispositivo Bluetooth que está reproduciendo puede ocupar la posición central con su propio símbolo.
- **Bluetooth** — el indicador de volumen se vuelve azul mientras se reproduce. El panel muestra los dispositivos emparejados que puedes tocar para conectarlos o desconectarlos, muestra los niveles de batería de forma predeterminada y permanece desactivado hasta que lo actives.
- **Batería** — porcentaje, carga o conexión a la corriente, tiempo para la carga completa y un color cuando está baja. Abre la fila para ver la potencia del adaptador, el voltaje, la corriente, el número de ciclos y el modo de bajo consumo.
- **Wi-Fi** — la red a la que estás conectado y la intensidad de la señal. Ábrelo para ver las redes cercanas, consultar los detalles del enlace o desactivar el Wi-Fi. Cambiar de red se hace en el panel de Wi-Fi de Ajustes del Sistema.
- **Volumen** — nivel, silencio y dispositivo de salida, dibujado como puntos o como un arco. Desplázate por todo el panel o solo por el control, y elige en qué dirección sube el volumen.
- **Hazlo tuyo** — tamaño del icono, escala de los símbolos, grosor del anillo, colores de estado y qué secciones muestra el panel emergente, en el orden que quieras.
- **Barra de menús, Dock o ambos** — y el icono del Dock puede seguir el estilo del sistema o mantenerse oscuro o claro.
- **Nativo en macOS** — el clic izquierdo abre el panel emergente, el clic derecho abre el menú, y una guía de primer inicio explica cada parte del icono. Ethernet, un punto de acceso personal o Compartir Internet pueden mantener el glifo de Wi-Fi si lo prefieres.
- **Siempre al día** — el estado proviene de eventos del sistema, con un sondeo lento como respaldo, y Sparkle actualiza la app mediante un canal firmado.
- **También incluye** — doce idiomas y la opción de abrir al iniciar sesión.

## Instalación

Instala desde el Cask oficial de Homebrew:

```bash
brew install --cask status-trio
```

Para actualizar una instalación de Homebrew:

```bash
brew upgrade --cask status-trio
```

O descarga el último `StatusTrio-*.dmg` de [GitHub Releases](https://github.com/lingyired/status-trio/releases/latest), ábrelo y arrastra `Status Trio.app` a `/Applications`.

La versión oficial está firmada con Developer ID y notarizada por Apple. Ábrela normalmente tras instalarla; no hace falta eliminar atributos de cuarentena. Las actualizaciones integradas usan Sparkle y verificación de firmas EdDSA.

## Controles de entrada y audio

- **Icono de entrada**: muestra el método de entrada actual en el centro del icono de la barra de menús y del Dock. Elígelo en **Ajustes › Red**; selecciona una fuente habilitada en el panel para cambiar a ella.
- **Atajo global**: configura un atajo en **Ajustes › General** para abrir o cerrar el panel desde otra app. No hay ninguno asignado por defecto.
- **Controles Bluetooth**: activa o desactiva Bluetooth, conecta o desconecta dispositivos y cambia el modo de escucha de AirPods y HUAWEI FreeBuds compatibles. Las filas opcionales de batería de dispositivos Apple se configuran en los ajustes de Bluetooth; dependen del dispositivo y la conexión.
- **Entrada y salida de audio**: elige altavoces o micrófonos y ajusta sus niveles. Controla altavoces de monitores externos compatibles mediante DDC; la compatibilidad depende del hardware y la conexión.
- **Carga y apariencia**: efectos de carga en la barra de menús y el Dock. En macOS 26 o posterior, el icono de Finder y Launchpad también sigue la apariencia clara u oscura del sistema.

## Novedades en main (sin publicar)

Estas funciones están en el código de `main`, pero no en la versión pública actual de GitHub / Homebrew, **1.7.5**:

- **Flujo de potencia e impacto energético de CPU**: estimaciones de entrada del cargador, carga de batería y potencia del sistema. Una lista opcional ordena hasta cinco apps por energía de CPU, o actividad de CPU si faltan contadores. No representa el consumo total ni replica la lista de macOS. Activarla inicia un muestreo periódico en segundo plano; desactivarla lo detiene. [Detalles](docs/battery-power-flow.md).
- **Cargar completamente ahora y cancelar**: opción desactivada por defecto para Mac con chip Apple compatibles y macOS 26.4 o posterior. Usa una interfaz privada de PowerUI para anular el límite. **El límite puede seguir al 100% tras cargar o reconectar la corriente; no se restaura automáticamente.** Usa la cancelación para solicitar restaurarlo, o compruébalo y restáuralo en Ajustes del Sistema. El comportamiento depende de macOS. [Comportamiento y pruebas](docs/charge-to-full-now-poc.md).

## Audio por Bluetooth

Mientras se reproduce audio por Bluetooth, dos interruptores en **Ajustes › Bluetooth** permiten que el glifo central pase a ser el símbolo propio de ese dispositivo —los AirPods, los auriculares, los altavoces y otros dispositivos aportan el suyo— y que los puntos o el arco del volumen se vuelvan azules. Ambos están desactivados de forma predeterminada. **Dar prioridad a los errores de red**, activado de forma predeterminada, mantiene el icono de red mientras la propia conexión tiene problemas:

<p align="center">
  <img src="screenshots/menu-bar-airpods.jpg" width="1000" alt="Icono de Status Trio en la barra de menús mostrando el glifo de AirPods mientras hay AirPods conectados, con su panel emergente de estado abierto">
</p>

La fila de Bluetooth del panel emergente informa del estado en vivo: los nombres de los dispositivos conectados y, en el caso de los AirPods, la batería del izquierdo, del derecho y del estuche. El panel de Bluetooth muestra los dispositivos emparejados y su estado de conexión: toca un dispositivo para conectarlo y uno conectado para desconectarlo —los teclados, ratones, trackpads y gamepads piden primero confirmación en la propia fila—. El panel está desactivado de forma predeterminada, se activa en **Ajustes › Panel de estado** y solicita permiso de Bluetooth la primera vez que se usa. **Ajustes › Bluetooth** también controla si se leen los niveles de batería, lista los dispositivos emparejados para que puedas arrastrarlos y colocarlos en el orden que quieras, además de elegir cuántos aparecen, y ajusta la escala del icono de Bluetooth del 100 % al 180 %.

## Icono del Dock

El mismo icono en vivo puede residir en el Dock en lugar de la barra de menús, o en ambos lugares a la vez:

<p align="center">
  <img src="screenshots/status-trio-dock-dark-1440x810.jpg" width="880" alt="Icono en vivo de Status Trio en el Dock con apariencia oscura">
  <br>
  <sub>Icono del Dock en apariencia oscura</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-1440x810.jpg" width="880" alt="Icono en vivo de Status Trio en el Dock con apariencia clara">
  <br>
  <sub>Icono del Dock en apariencia clara</sub>
</p>

<p align="center">
  <img src="screenshots/status-trio-dock-light-bt-1440x810.jpg" width="880" alt="Status Trio en el Dock con el panel de Bluetooth visible, apariencia clara">
  <br>
  <sub>Vista previa del panel de Bluetooth</sub>
</p>

El icono del Dock dibuja el mismo icono combinado que la barra de menús, así que, con la sustitución por audio Bluetooth activada, el glifo del dispositivo también ocupa el centro ahí. Su fondo puede seguir el estilo de iconos del sistema o fijarse a un tono concreto:

<p align="center">
  <img src="screenshots/status-trio-dock-icons.png" width="880" alt="Icono de Status Trio en el Dock con fondos oscuro, claro y transparente, en dos filas: el estado de Wi-Fi y el audio Bluetooth sustituyendo al icono de Wi-Fi con puntos de volumen azules">
</p>

## Estados del icono

Todos los estados que puede mostrar el icono combinado, dibujados por el propio renderizador de la app —los indicadores de batería arriba, el Wi-Fi (o el dispositivo de audio Bluetooth que puede sustituirlo, cuando esa opción está activada) en el centro, y los puntos o el arco del volumen abajo, que se vuelven azules mientras un dispositivo Bluetooth está reproduciendo—:

<p align="center">
  <img src="screenshots/status-trio-icon-states.png" width="880" alt="Estados del icono de Status Trio: carga, conectado a la corriente, porcentaje, batería baja y Modo de bajo consumo arriba; señal de Wi-Fi, punto de acceso personal, temporal, compartida y por cable en el centro; audio Bluetooth sustituyendo al icono de Wi-Fi, Wi-Fi conservado durante un error de red, y puntos de volumen azules y arco debajo de eso; estilos de puntos de volumen y arco para cada nivel abajo del todo">
</p>

Los mismos estados representados para una barra de menús oscura:

<p align="center">
  <img src="screenshots/status-trio-icon-states-dark.png" width="880" alt="Los mismos estados del icono de Status Trio en apariencia oscura: glifos blancos sobre fondos oscuros, carga en verde, batería baja en rojo y acentos amarillos del modo de bajo consumo, además del azul más brillante que la app usa para el audio Bluetooth en una barra de menús oscura">
</p>

## Requisitos

- macOS 13 como objetivo de implementación (validación de Ventura pendiente) para ejecutar la app
- Cadena de herramientas de Swift 6 con el SDK de macOS 26 (Xcode 26 o posterior) para compilarla. Compilar contra un
  SDK anterior produce de forma silenciosa la apariencia del panel emergente previa a Tahoe, por lo que
  `scripts/build-app.sh` falla cuando el SDK es anterior a 26.

## Ejecutar desde el código fuente

```bash
git clone https://github.com/lingyired/status-trio.git
cd status-trio
swift run StatusTrio
```

## Compilar una app local

Compila un paquete de app firmado de forma ad-hoc y ejecútalo:

```bash
bash scripts/build-app.sh release
```

El paquete se crea en `dist/StatusTrio.app`. Para compilar sin cerrar ni abrir una instancia existente, ejecuta:

```bash
bash scripts/build-app.sh release no-open
```

El paquete firmado de forma ad-hoc está pensado para uso personal local. Gatekeeper puede rechazarlo si el paquete se transfiere con metadatos de cuarentena.

## Uso

- **Clic izquierdo** en el icono de la barra de menús o en el icono del Dock para abrir el panel emergente de estado.
- **Clic derecho** en cualquiera de los dos iconos para abrir el menú nativo, que incluye la versión y la opción de salir.
- Selecciona la fila de Wi-Fi o la de batería del panel emergente para abrir su página: las redes cercanas y los detalles del enlace, o los Detalles de la batería. La fila de Bluetooth lista sus dispositivos emparejados en el propio panel —toca uno para conectarlo o desconectarlo— con un control Expandir cuando no quepan todos.
- Abre **Ajustes** para elegir dónde se muestra el icono (barra de menús, Dock o ambos) y para cambiar su tamaño, los colores, el grosor del anillo, las secciones del panel y su orden, el comportamiento de ajuste con el desplazamiento, el idioma, la búsqueda de actualizaciones y abrir al iniciar sesión.
- Vuelve a abrir la guía **Conoce tu icono** en cualquier momento desde **Ajustes › Icono de la app › Abrir guía**.
- Activa el nombre de la red Wi-Fi actual cuando se te solicite; macOS pide acceso a la ubicación para este detalle opcional.

## Limitaciones conocidas

Dos límites que macOS y este proyecto trazan deliberadamente. Ambos se explican en [Limitaciones conocidas](docs/known-limitations.md).

- **Cambiar de red se hace en Ajustes del Sistema.** Elegir una red en el panel emergente abre el panel de Wi-Fi; Status Trio nunca lee ni guarda las contraseñas de Wi-Fi, porque macOS no ofrece ninguna API pública para conectarse con una contraseña guardada y todas las alternativas acaban con la app guardándolas.
- **El control del límite de carga depende de la versión.** La versión 1.7.5 remite a Ajustes del Sistema. La opción de `main` usa una interfaz privada y requiere cancelar explícitamente para solicitar la restauración. [Detalles](docs/charge-to-full-now-poc.md). El modo de bajo consumo usa un [helper privilegiado opcional](docs/privileged-helper.md) independiente.

## Idiomas

Status Trio sigue el idioma preferido de macOS de forma predeterminada e incluye English, 简体中文, 繁體中文, 日本語, 한국어, Español, Français, Deutsch, Italiano, Português (Brasil), Русский y العربية.

## Privacidad

Status Trio lee el estado del sistema localmente. Las estadísticas anónimas solo se envían al servicio propio si las activas; están desactivadas al actualizar y se consultan durante la bienvenida de nuevas instalaciones. Incluyen un ID aleatorio, versiones de la app y macOS, idioma y ubicación del icono, sin nombres, cuentas, detalles de red ni identificadores de hardware. Consulta [telemetría y privacidad](docs/privacy-telemetry.md). No lee ni guarda contraseñas Wi-Fi ni pide acceso al Llavero. La ubicación es opcional para el nombre y los detalles de Wi-Fi; Bluetooth se solicita al activar su panel. En `main`, el control opcional de carga completa usa una interfaz privada de PowerUI solo al habilitarlo; sus límites se explican antes.

## Desarrollo

Ejecuta la suite de pruebas:

```bash
bash scripts/verify-local.sh quick BatteryMonitorTests
bash scripts/verify-local.sh docs
bash scripts/verify-local.sh full
```

Ejecuta un filtro de XCTest concreto mediante el script auxiliar:

```bash
bash scripts/test.sh BatteryMonitorTests
```

Para compilar una app de worktree junto a la instalación principal:

```bash
bash scripts/build-worktree.sh release
```

El script auxiliar deriva un identificador de paquete y un nombre visible de desarrollo a partir de la rama actual. Ambos valores se pueden sobrescribir:

```bash
BUNDLE_ID=com.lingsmbp.StatusTrio.dev.settings-redesign \
APP_NAME="Status Trio (Settings Redesign)" \
bash scripts/build-worktree.sh release
```

El bloqueo de instancia única está limitado por el identificador de paquete, por lo que las compilaciones con identificadores distintos pueden ejecutarse al mismo tiempo.

## Base técnica

- Swift 6
- SwiftUI + AppKit
- macOS 13 deployment target (Ventura runtime validation pending)
- Accesorio de barra de menús `LSUIElement` que cambia a una política de activación normal mientras se muestra el icono del Dock
- Sparkle para buscar actualizaciones

## Documentación

- [Limitaciones conocidas](docs/known-limitations.md)
- [Versiones automatizadas con GitHub Actions](docs/github-actions-release.md)
- [Especificación de diseño de Status Trio](docs/superpowers/specs/2026-09-12-status-trio-design.md)
- [SVG del icono de la barra de menús](status-menubar.svg)
- [Demostración del icono basada en datos](status-menubar-demo.html)

## Licencia

Copyright 2026 lingyired.

Con licencia Apache License, Version 2.0. Consulta [LICENSE](LICENSE) y [NOTICE](NOTICE).

## Autor

Creado y mantenido por [lingyired](https://github.com/lingyired).<br>
Sitio web: [https://statustrio.lingai.net/](https://statustrio.lingai.net/)

## Star History

<a href="https://www.star-history.com/?repos=lingyired%2Fstatus-trio&type=date&legend=top-left">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&theme=dark&legend=top-left" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
   <img alt="Star History Chart" src="https://api.star-history.com/chart?repos=lingyired/status-trio&type=date&legend=top-left" />
 </picture>
</a>
