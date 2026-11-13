# Version %VERSION% (Build %BUILD%)

### Panel & Bluetooth-Audio

- AirPods unterstützen jetzt „Spatialize Stereo“ und „Conversation Awareness“.
- Umschalten des Hör-Modus für Redmi-/Xiaomi-Ohrhörer hinzugefügt.
- Behoben: Ohrhörer zeigten nach dem Zurücklegen ins Case noch etwa zwei Minuten „Verbunden“ an.
- Behoben: Ein einzelner Klick auf das Status-Symbol hat das Panel aktualisiert statt geschlossen — im normalen Modus, im reinen Menüleisten-Modus und beim Klick auf den Rand des Symbols (#224).
- Geschmeidigere Lautstärke per Scrollrad: aktualisiert bei jedem Ereignis, mit kurzem Easing im Regler, und jeder Schritt ist 1/16, passend zu den System-Lautstärketasten.

### Batterie & Energie

- Verbleibende Laufzeit wird jetzt im Status-Panel und in den Details angezeigt, die Details zeigen außerdem die Batterietemperatur (#298).
- „Maximale Kapazität“ nutzt jetzt den System-Gesundheitsprozentsatz wie macOS (#317) und fällt bei nicht lesbarem Zustand auf Systeminformationen zurück.
- Die Energieaufschlüsselung teilt USB-Ausgabe nach Port auf und benennt jedes Zubehör; behoben: Verlust der gesamten USB-Ausgabe bei 300-W-Grenze des Ladeports sowie fehlende interne Displayleistung bei manchen Modellen.
- Macs ohne Batterie zeigen jetzt einen vollen Ring, die obere Anzeige lässt sich zwischen Blitz und Stecker umschalten (#310); der volle Ring gilt nur am Netzteil (#318).
- „Jetzt voll laden“ entspricht dem nativen Verhalten, die zusätzliche „Ladelimit wiederherstellen“-Oberfläche ist entfernt.
- Bei Display-Schlaf pausieren Energie-Sampling und Bluetooth-Scan in der Nähe und werden beim Aufwachen fortgesetzt — spart Energie (#300).
- Das Segmented-Control für den Energiemodus nutzt jetzt einen halbtransparenten Hintergrund passend zu Liquid Glass.

### Symbole & Darstellung

- Option hinzugefügt, beim Laden und Verbinden Schwarz-Weiß-Symbole zu verwenden (#309).
- Die obere Batterieanzeige lässt sich jetzt je Nutzungszustand (Akku / Laden usw.) getrennt konfigurieren (#315).
- Behoben: Das obere Ringelement in der Menüleiste war versetzt und driftete (#30).
- Behoben: Das Dock-Ladeanimations-Symbol schrumpfte auf 1x-Displays auf die halbe Größe (#303).

### Displays & Helligkeit

- In den Helligkeitseinstellungen lässt sich ein BetterDisplay-Display manuell wählen; ist die Helligkeit nicht verfügbar, wird ein manuelles Umschalten vorgeschlagen (#313).
- Behoben: Helligkeit war nicht verfügbar, wenn die Identität eines externen Displays unklar war (jetzt Rückfall auf das einzige externe Display).

### Netzwerk & Eingabequelle

- Schalter „Vor dem Ausschalten von Wi-Fi bestätigen“ hinzugefügt (#305).
- Die Pinyin-Eingabequellen-Anzeige unterscheidet vereinfachtes und traditionelles Pinyin; die 简/繁-Markierung ist jetzt optional und kann 中 anzeigen.

### Sonstiges

- Behoben: Die Liste der Ausgabegeräte verschwand, wenn das Lesen der Lautstärke fehlschlug (#296).
