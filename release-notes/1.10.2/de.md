# Version %VERSION% (Build %BUILD%)

### Systemmonitor

- Das Statusfenster überwacht jetzt CPU, GPU, Arbeitsspeicher, Netzwerk, Festplatte und Lüfterdrehzahl; ein Klick öffnet die jeweilige Detailseite.
- Eigene Farben für die Messwerte CPU, GPU, Arbeitsspeicher, Netzwerk, Festplatte und Lüfterdrehzahl.
- Aktualisierungsintervall und Zeitraum des Verlaufs lassen sich anpassen.
- Der Systemmonitor tastet nur bei Bedarf ab: Messwerte werden nur gelesen, solange sie angezeigt werden, und der Hintergrundverlauf ist standardmäßig aus, was die Hintergrundlast senkt.

### Menüleisten-Symbol & Ring

- Neue Systemmonitor-Datenquellen für den äußeren Ring, mit Einzelring- und linkem/rechtem Doppelring-Layout. Ringbögen können CPU-Auslastung, CPU-Temperatur, GPU-Auslastung, GPU-Temperatur, Speicherauslastung, Batterietemperatur, Batteriestand, Lüfterdrehzahl, Download- und Upload-Geschwindigkeit, Lautstärke und Wi-Fi-Signal nutzen.
- Der Batteriestand-Bogen des Rings folgt den Systembatteriefarben; eine neue Farbrolle „Entladen (nicht am Strom)“ erlaubt getrennte Farben für Laden, Niedrig, Hohe Leistung, Kritisch und Entladen (#357).
- Neuer AirPods-Modus für die obere Anzeige: Die Doppelringe können den Akkustand des linken und rechten Ohrhörers zeigen (auch einseitig) und fallen bei Trennung auf die Mac-Batterie oder einen eigenen Ring zurück.
- Die untere Anzeige unterstützt eine eigene Datenquelle: Lautstärke, Wi-Fi-Signal oder Batteriestand (oder ausgeblendet).

### Fenster & Interaktion

- Beim Überfahren des Menüleistensymbols erscheint das Fenster; ein Klick heftet es an (#355).
- Details öffnen sich jetzt in einem Seitenfenster neben dem Statusfenster, mit flüssigerem Wechsel.
- Neue Hardware-Monitor-Karte.
- Die Zahlenschieber (Lautstärke, Helligkeit) wurden näher an macOS 26+ gestaltet und laufen flüssiger; sie reagieren auf horizontales Trackpad-Wischen (#351).
- Wi-Fi- und Bluetooth-Symbole werden nach Verbindungsstatus eingefärbt (#352).
- Die Schaltfläche „Jetzt voll laden“ erhielt einen Liquid-Glass-Schimmer beim Überfahren.
- Fette Schrift im Statusfenster entfernt; Werte und Einheiten nutzen eine Festbreitenschrift.

### Wachhalten & Ruhezustand

- „Bildschirm anlassen“ und „Ruhezustand bei geschlossenem Deckel aus“ hinzugefügt, jeweils mit eigener Dauer (#295).

### Helligkeit

- Neuer Schalter „BetterDisplay-Kombinationshelligkeit verwenden“ (#344).

### Batterie & Audio

- Text und Zeile zum Erhaltungsladen bei 100 % korrigiert.
- Stummschaltung bei genau null Lautstärke und Wiederherstellung nur der automatischen Stummschaltung korrigiert.
- Die Schätzung „Zeit bis voll“ berücksichtigt nun das macOS-Ladelimit (#349).

### Weitere Korrekturen

- Der Verlauf der Monitor-Details ist nun je Messwertart getrennt.
- Hintergrundabtastung und Prozess-Pipe-Stabilität verbessert, weniger Stocken und Übersprechen im Fenster.
- Flackern der Zeilenhöhe des AirPods-Hörmodus beim Öffnen des Fensters behoben (#354).
