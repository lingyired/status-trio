# Version %VERSION% (Build %BUILD%)

### Batterie & Energie

- Batteriedetails zeigen jetzt die maximale Systemkapazität, den Batteriezustand und die Systemlaufzeit.
- Der Hochleistungsmodus erscheint in den Details nun immer als eigene, klare Zeile und liest seinen Zustand direkt aus pmset; unbekannte Gesundheits- und Hochleistungszustände werden ausdrücklich angezeigt.
- Wenn „Optimiertes Batterieladen" bei einem Limit von 100 % das Laden pausiert, funktioniert „Jetzt voll laden" nun: Die Anfrage wird wie von macOS üblich gesendet, und nach Abschluss wird das vorherige Ladelimit nicht wiederhergestellt (#292).
- Detail- und Einstellungsseite erklären jetzt, warum „Jetzt voll laden" nicht verfügbar oder ausgeblendet ist (#280, #292).
- Die Einstellungen erklären, dass ein Limit von 100 % das Laden wegen des optimierten Batterieladens dennoch pausieren kann (#292).

### Helligkeit & Displays

- Externe Displays erhalten ein automatisches Helligkeits-Backend: BetterDisplay, solange es läuft, sonst direktes DDC; ein ausdrücklich gewähltes Backend wird beibehalten und nie überschrieben.
- Änderungen der Helligkeit des integrierten Displays über Tasten, Kontrollzentrum oder Einstellungen werden jetzt sofort im Panel angezeigt (#286).
- Solange das Panel sichtbar ist, wird die Helligkeit externer Displays in einem begrenzten 2-Sekunden-Intervall aktualisiert, damit Tastaturänderungen das Panel zeitnah erreichen.
- Ruckeln beim Ziehen der DDC-Helligkeit behoben und externe Displays korrekt erkannt, sodass der integrierte Bildschirm nicht als externes Display angesteuert wird (#284, #285).

### WLAN & Netzwerk

- Clash-Verge-TUN-Netzschalter hinzugefügt: TUN wird über die schreibgeschützte Mihomo-API erkannt, reine Tunnel erscheinen als „TUN" statt „VPN", und der Schalterzustand bleibt synchron (#272).
- Sichtbarkeit des Netzschalters in der WLAN-Zusammenfassungszeile und den Bestätigungsumfang vor dem Ausschalten eines Netzwerks verbessert (#252).

### Eingabequelle

- Behoben, dass Großschreibung nicht beibehalten wurde, wenn Caps Lock und Umschalt gleichzeitig aktiv sind; die Anzeige zeigt jetzt korrekt a/A (#279).

### Bluetooth

- Benutzerdefinierte Farbe für das Bluetooth-Symbol hinzugefügt (#275).
- Veraltete Batteriewerte von getrennten Bluetooth-Geräten laufen jetzt ab, statt zu bleiben.

### Panel & Einstellungen

- Hover-Dekoration der Batterie-Einstellungszeile an die anklickbaren Schaltflächengrenzen angeglichen und etwas Luft hinzugefügt (#281).
- Abgerundete Karten im Energieflussdiagramm wiederhergestellt und den Überlauf des Bands maskiert (#282).
- Ursprüngliche Schieberegler-Komponente für Aktualisierungsintervalle in den Einstellungen wiederhergestellt (#255).

### Leistung & Stabilität

- Lebensdauer der Überwachungs-Threads und Abfrageintervall gestrafft, um Hintergrundlast zu senken und die Stabilität zu verbessern (#294).
- Zwischengespeicherte Ausgabegeräte werden bei Änderungen der Audiogeräte-Topologie aktualisiert (#293).
- Leistungs- und Stabilitätsprobleme bei Symbolen, Panel, Einstellungen und Überwachung behoben.
