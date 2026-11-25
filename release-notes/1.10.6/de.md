# Version %VERSION% (Build %BUILD%)

## Fehlerbehebungen

- Falsche Fehlermeldung „Status für ‚Wachhalten bei geschlossenem Deckel‘ kann nicht gelesen werden“ (Code DS-R4) auf Macs behoben, auf denen diese Funktion nie aktiviert wurde. macOS listet die Einstellung erst nach der ersten Verwendung, daher behandelt die App ein fehlender Wert jetzt als „aus“ statt als Lesefehler.
- Der Schalter „Wachhalten bei geschlossenem Deckel“ zeigt auf diesen Macs nun den korrekten Ausgangszustand und funktioniert beim ersten Klick, ohne manuell `sudo pmset -a disablesleep` auszuführen.
