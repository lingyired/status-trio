# Version %VERSION% (Build %BUILD%)

## Sensoren und Temperaturen

- Die GPU-Temperatur des M3 Air (Mac15,12) funktioniert wieder: Nicht lesbare Tf-Sensoren werden durch die geprüften Tg-Sensoren ersetzt und als sechs Paare gruppiert, damit eine physische Zone nicht doppelt zählt.
- Bei M5 und M6 werden Probes derselben CPU-Kerne zusammengefasst; mehrere Probes erhöhen weder die Kernanzahl noch den Durchschnitt.
- A18 Pro wird jetzt erkannt. Unbekannte Chips übernehmen keine Temperatur-Keys einer anderen Generation und zeigen bei fehlenden Werten nichts an.

## Display-Leistung

- Issue #374 behoben: Ein M3 Air ohne PDBR und mit konstant 0 bei PBLR zeigt keinen 0,00-W-Displayzweig mehr.
- Ohne nutzbare gemessene Backlight-Schiene kann die Displayleistung auf eine AppleARMBacklight-Schätzung zurückfallen. Die 6-V-Annahme ist keine Messung; der Wert wird mit ≈ und der Systemrest als geschätzt markiert.
- Null-Watt-Zweige für Display und USB werden ausgeblendet.

## Überwachung und Leistung

- Sensorfähigkeiten werden einmal geprüft und gespeichert; fehlende Keys werden mit Backoff erneut versucht statt bei jedem Refresh.
- Keine neuen Hintergrund-Timer, Helper oder privilegierten Zugriffe. Temperatur- und Backlight-Erfassung endet weiterhin beim Schließen des Panels.
