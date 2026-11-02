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
- Die Quellen des mittleren Symbols sind jetzt Bildkacheln, die die echte Darstellung zeigen. Eine gemeinsame „Größe des mittleren Symbols" steuert Wi‑Fi, Bluetooth, Eingabequelle und Zahlen; die Netzwerksymbol-Stiloptionen zogen auf dieselbe Seite.
- Die Vorschau zeigt den Ladezustand, und der mittlere Inhalt sitzt jetzt vertikal mittig am Batteriering; Text ist etwas kleiner als Symbole.

### Anleitung

- Überarbeitete Einführung: Das Fenster hat die Höhe der höchsten Seite und ändert seine Größe beim Schrittwechsel nicht mehr; Vorschauen liegen auf einer Fläche, Teile-Beschriftungen nennen oberen Bogen, mittleres Symbol und untere Punkte, neue Beispiele für das Mittelfeld (Prozent, Leistung, Eingabequelle) und ein kompakterer Zustimmungsblock.

### Einstellungen

- Alle Einstellungs-Popupmenüs nutzen eine gemeinsame Breite und springen nicht mehr mit ihren Optionen oder der Geräteliste; das native Popup-Aussehen bleibt erhalten.

### Audio

- Ein-/Ausgabegeräte lassen sich sortieren, ausblenden und in der Anzahl begrenzen.
- Die Lautstärkerückmeldung beim Scrollen ist separat einstellbar; erneutes Klicken auf den gewählten Hör-Modus schaltet ihn aus.

### Panel

- Das Statuspanel hat einen eckigen, zahnlosen Stil, ein „Mehr"-Menü unten und passt Größe und Layout unter Liquid Glass besser an.

### Korrekturen

- Wi-Fi-Verbindungsinfos werden auch ohne Standortberechtigung angezeigt.
