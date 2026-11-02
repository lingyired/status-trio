# Version %VERSION% (Build %BUILD%)

### Batterie

- Optionaler „Split"-Modus für den Batteriering: Zeigt die obere Lücke Blitz, Stecker oder Prozent, liest der linke Bogen 0–50 % und der rechte 50–100 %, sodass 40–60 % nicht mehr verdeckt wird. Standardmäßig aus; gilt für Menüleiste und Dock.
- Batterie-Symbolfarben können benutzerdefinierten Statusfarben folgen, mit eigener Wahl für die Verbindungsanzeige (Blitz, Stecker oder Prozent). Menüleiste und Dock teilen eine Szene.
- Die Batteriedetails zeigen eine Leistungsfluss-Aufteilung (internes Display, USB-/Zubehörausgang und System) sowie eine optionale Live-Leistungsleiste. Zubehörausgang wird, wo verfügbar, aus den SMC-Port-Rails gelesen.
- Neue Einstellung „Limit nach Abbruch wiederherstellen" für „Jetzt voll laden", mit klareren Zuständen, wenn macOS die temporäre Überschreibung selbst startet.

### Energie

- Der Mittelfeld-Slot kann statt einer Verbindungsquelle die Live-Leistung des gesamten Macs anzeigen; Macs ohne internen Akku werden voll unterstützt.

### Displays

- Helligkeitsregelung für Displays: externe über direktes DDC, interne direkt über DisplayServices – BetterDisplay ist für interne Bildschirme nicht mehr nötig.
- Im Leistungsflussdiagramm richtet sich die Kartenhöhe jedes Zweigs nach seinem Anteil, unabhängig von der Anzahl der Zweige.

### Audio

- Ein-/Ausgabegeräte lassen sich sortieren, ausblenden und in der Anzahl begrenzen. Ein einzelnes gerät mit Hör-Modus behält seine Rauschsteuerung, auch wenn andere Ausgaben ausgeblendet sind.
- Die Lautstärkerückmeldung beim Scrollen ist separat einstellbar; erneutes Klicken auf den gewählten Hör-Modus schaltet ihn aus.

### Panel

- Das Statuspanel hat einen eckigen, zahnlosen Stil, ein „Mehr"-Menü unten und passt Größe und Layout unter Liquid Glass besser an. In der Standardreihenfolge steht „Displayhelligkeit" unter „Audioeingang".

### Korrekturen

- Ein Neustart während „Jetzt voll laden" behält das ursprünglich ermittelte Wiederherstellungslimit statt auf 100 % zurückzufallen.
- Das Schließen des Statuspanels gibt die Leistungsleisten-Abtastung frei; das Symbol tastet nur alle 2 Sekunden ab, solange es Leistung zeigt.
- Das Umschalten der Leistungsleiste bei offenem Panel nutzt sofort den neuen Wert.
- Eine bestätigte Akku-Leistungsaufteilung wird beim Abstecken nicht mehr verworfen.
- Hot-Plug eines Displays aktualisiert die Helligkeitsliste und verwirft die veraltete DDC-Verbindung.
- Ein unbestätigter DDC-Helligkeitsschreibvorgang zeigt „nicht verfügbar", statt Regler und Erklärung zu verlieren.
- Wi-Fi-Verbindungsinfos werden auch ohne Standortberechtigung angezeigt.
