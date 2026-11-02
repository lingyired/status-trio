# Version %VERSION% (Build %BUILD%)

### Batterie

- Die Batteriedetails zeigen eine Leistungsfluss-Aufteilung (internes Display, USB-/Zubehörausgang und System) sowie eine optionale Live-Leistungsleiste. Zubehörausgang wird, wo verfügbar, aus den SMC-Port-Rails gelesen.
- Neue Einstellung „Limit nach Abbruch wiederherstellen" für „Jetzt voll laden", mit klareren Zuständen, wenn macOS die temporäre Überschreibung selbst startet.
- Batterie-Symbolfarben können benutzerdefinierten Statusfarben folgen, mit eigener Wahl für die Verbindungsanzeige (Blitz, Stecker oder Prozent).
- Optionaler „Split"-Modus für den Batteriering: Zeigt die obere Lücke Blitz, Stecker oder Prozent, liest der linke Bogen 0–50 % und der rechte 50–100 %, sodass 40–60 % nicht mehr verdeckt wird. Standardmäßig aus; gilt für Menüleiste und Dock.

### Energie

- Der Mittelfeld-Slot kann statt einer Verbindungsquelle die Live-Leistung des gesamten Macs anzeigen; Macs ohne internen Akku werden voll unterstützt.

### Displays

- Helligkeitsregelung für Displays: externe über direktes DDC, interne direkt über DisplayServices.

### Mittleres Symbol

- Die Quelle des Mittelfelds ist jetzt ein gemeinsamer „Mittleres Symbol"-Selektor: Netzwerk, Bluetooth-Gerät, aktuelle Eingabequelle, Batterieprozentsatz oder Leistung. Die beiden Netzwerkfehler-Schalter sind zu einem zusammengeführt, der für alle Quellen gilt; der wirkungslose Bluetooth-Schalter „Netzwerksymbol ersetzen" entfällt, alte Werte werden automatisch übernommen.
- Das mittlere Symbol war nicht vertikal zentriert; das ist behoben.

### Anleitung

- Die Einführung wurde überarbeitet.

### Audio

- Ein-/Ausgabegeräte lassen sich sortieren, ausblenden und in der Anzahl begrenzen.
- Die Lautstärkerückmeldung beim Scrollen ist separat einstellbar; erneutes Klicken auf den gewählten Hör-Modus schaltet ihn aus.

### Panel

- Das Statuspanel hat einen eckigen, zahnlosen Stil passend zum macOS-Menüleisten-Panel, ein „Mehr"-Menü unten und passt Größe und Layout unter Liquid Glass besser an.

### Korrekturen

- Wi-Fi-Verbindungsinfos werden auch ohne Standortberechtigung angezeigt.
