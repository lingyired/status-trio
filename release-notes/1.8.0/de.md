# Version %VERSION% (Build %BUILD%)

### Batterie

- Der Batterieleistungsfluss zeigt jetzt geschätzte Werte für die Eingangsleistung des Ladegeräts, die in die Batterie fließende Leistung und die Systemleistung. Die Ladegerät-Eingangsleistung ist standardmäßig ausgeschaltet; die anderen beiden Werte sind standardmäßig eingeschaltet.
- Eine optionale Liste zur Auswirkung der CPU-Energie zeigt anhand aktueller Messwerte bis zu fünf Apps. Sind Energiewerte nicht verfügbar, wird auf die CPU-Aktivität zurückgegriffen; das Messintervall kann zwischen 10 und 60 Sekunden liegen.
- Auf unterstützten Macs mit Apple Chip und macOS 26.4 oder neuer stehen „Jetzt vollständig laden“ und „Vollständiges Laden abbrechen“ zur Verfügung und sind bei vorhandener Unterstützung standardmäßig aktiviert.

### Externe Displays

- Für externe Displays oder Audioausgaben, deren Lautstärke macOS nicht direkt steuern kann, wurde eine Lautstärkesteuerung über BetterDisplay hinzugefügt. Displays lassen sich automatisch oder manuell zuordnen; Verbindungs- und Fehlerzustände werden angezeigt.
- Die native beschreibbare Lautstärkesteuerung bleibt bevorzugt, der Standard-/DDC-Modus kann jederzeit wiederhergestellt werden, und Status Trio startet BetterDisplay nicht und ändert dessen Einstellungen nicht, wenn es nicht verfügbar ist.

### Stabilität und Oberfläche

- Die Wi-Fi-Ereignisverarbeitung wurde verbessert: Hochfrequente CoreWLAN-Callbacks werden zusammengefasst und Wiederherstellungen in abnormalen Zuständen begrenzt, wodurch das Risiko sinkt, dass Ereignisstürme CPU- und Speicherlast verstärken.
- Beim erneuten Öffnen behält das Statusfenster jetzt die aktuelle Detailseite bei, statt zur Hauptseite zurückzukehren.
- Layout und Navigation der Batteriedetails, die Klickfläche des Zahnrads und die Aktualisierung der Live-Leistung wurden verbessert.
- Die Komposition aus farbiger Ebene und Vorlagenbild in der Menüleiste wurde verbessert. Nicht fokussierte Displays werden jetzt korrekt abgedunkelt, während die systemseitige Neueinfärbung beim Wechsel von Spaces erhalten bleibt.

### Wichtige Hinweise

- „Jetzt vollständig laden“ verwendet eine private PowerUI-Schnittstelle und ist nur auf Macs mit Apple Chip und macOS 26.4 oder neuer verfügbar. Das Verhalten ist nicht über alle macOS-Versionen hinweg garantiert.
- Nach Abschluss des Ladevorgangs oder erneutem Anschließen des Netzteils kann das Ladelimit bei 100 % bleiben. Status Trio stellt es nicht automatisch wieder her; verwende „Vollständiges Laden abbrechen“ oder stelle das Limit in den Systemeinstellungen wieder her.
- Die Liste zur CPU-Energieauswirkung zeigt nicht den gesamten Energieverbrauch einer App und ist keine Kopie der macOS-Liste „Hohe Energieverwendung“.
- Die Lautstärkesteuerung über BetterDisplay erfordert, dass BetterDisplay läuft. Displaylautstärke und DDC-Verhalten hängen weiterhin von Hardware und Verbindung ab.
