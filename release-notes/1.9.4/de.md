# Version %VERSION% (Build %BUILD%)

### Batterie & Energie

- Batteriedetails zeigen jetzt die maximale Systemkapazität, den Batteriezustand, die Systemlaufzeit und den Status des Hochleistungsmodus.
- Wenn „Optimiertes Batterieladen" bei einem Limit von 100 % das Laden pausiert, kann jetzt „Jetzt voll laden" verwendet werden; ist es nicht verfügbar, erklären Detail- und Einstellungsseite den Grund (#292, #280).

### Helligkeit & Displays

- Externe Displays erhalten ein „Automatisches" Helligkeits-Backend: BetterDisplay, solange es läuft, sonst direktes DDC.
- Änderungen der Helligkeit des integrierten Displays über Tasten, Kontrollzentrum oder Einstellungen werden jetzt sofort im Panel angezeigt (#286).
- Solange das Panel geöffnet ist, werden Helligkeitsanpassungen externer Displays ebenfalls zeitnah im Panel angezeigt.
- Ruckeln beim Ziehen der DDC-Helligkeit behoben und externe Displays korrekt erkannt (#284, #285).

### WLAN & Netzwerk

- Die Zusammenfassungszeile für System-VPN-Dienste hat jetzt einen Netzschalter; Clash-Verge-TUN-Verbindungen werden nicht mehr als „VPN", sondern korrekt als „TUN" angezeigt (bei Clash Verge mit Clientnamen), und diese Zeile bleibt schreibgeschützt ohne Schalter (#272).

### Eingabequelle

- Die ABC-Eingabequellenanzeige zeigt jetzt je nach Groß-/Kleinschreibung a/A (#279).

### Bluetooth

- Das Geistergeräte-Problem bei Bluetooth-Geräten wurde verbessert (#248).
- Benutzerdefinierte Farbe für das Bluetooth-Symbol hinzugefügt (#275).

### Panel & Einstellungen

- Hover- und Klickbereich der Batterie-Einstellungszeile besser abgestimmt (#281).
- Ecken-Darstellung des Energieflussdiagramms verfeinert (#282).
- Das Aktualisierungsintervall lässt sich jetzt getrennt für „Im Akkubetrieb / Am Netzteil" einstellen (#255).

### Leistung & Stabilität

- Hintergrund-Aktualisierungsrate und Ressourcenverbrauch reduziert, um Stromverbrauch zu senken und die Stabilität zu verbessern (#294).
- Behoben, dass die Ausgabegeräteliste nach dem Wechsel von Audiogeräten nicht aktualisiert wurde (#293).
