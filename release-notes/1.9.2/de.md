# Version %VERSION% (Build %BUILD%)

### Menüleiste

- Konfigurierbare Schnellaktionen per Rechtsklick auf das Statusobjekt: Kontextmenü anzeigen, Energiesparmodus umschalten, vollständig laden oder abbrechen, stummschalten, WLAN umschalten, aktualisieren oder die WLAN-/Bluetooth-/Batterie-/Ton-Einstellungen direkt öffnen (#209).

### Panel

- Behoben: Das Panel öffnete sich über das Dock-Symbol an der falschen Position (#229).
- Behoben: Das Panel lief über den Bildschirm hinaus (#237).
- Wählbarer Panel-Hintergrund: Liquid Glass, einfarbig oder klassisches Material (#233).
- Weniger Ruckeln beim Öffnen des Statuspanels (#232):
  - Bluetooth-Zeilen zeigen beim erneuten Öffnen sofort die zuletzt bekannten Geräte, während die Batteriestände im Hintergrund aktualisiert werden;
  - der Bluetooth-Untertitel bleibt bis zum ersten Gerätelesevorgang ausgeblendet, und die Zeilen bleiben stabil, bis die Stände vorliegen;
  - die Energieinfoleiste wird bis zum ersten Lesevorgang per Skelett reserviert, was das Aufblitzen beim Öffnen entfernt und die Einblendung verkürzt.
- Die Oberfläche der Energieinfoleiste wurde überarbeitet (#230, #238): Sie zeigt die Entladerichtung, meldet im Akkubetrieb „kein Netzteil", färbt die Entladequelle orange und die Ladeeingangs-Karte erhält eine adaptive silberne Oberfläche.
- Bei reduzierter Transparenz wird die Füllung gegen das effektive Erscheinungsbild aufgelöst (#234).
- Bei geöffnetem Panel wirkt ein einzelner Klick auf das Statusobjekt sofort (#224).

### Batterie

- Die Schaltfläche „Jetzt vollständig laden" wirkt nur noch auf die erste Ebene des Statuspanels (#231).
- Behoben: Fehler beim Abbrechen nach „Jetzt vollständig laden" (#243).

### Displays

- Verbesserte Kompatibilität der Displayhelligkeit (#202): Framebuffer werden über Eigenschaften erkannt, mit namensunabhängigem Rückfall, einschließlich als AppleCLCD2 registrierter Framebuffer.

### Korrekturen

- Verbesserter Kontrast des WLAN-Verbunden-Häkchens (#242).
