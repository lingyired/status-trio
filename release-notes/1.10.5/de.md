# Version %VERSION% (Build %BUILD%)

## Neue Funktionen

- Der untere Indikator bietet jetzt die Option „Speicherdruck“, damit sich die aktuelle Speicherauslastung auf einen Blick ablesen lässt.
- Die Datenträgerdetails listen jetzt alle eingebundenen Volumes (intern und extern) mit Lese-/Schreibgeschwindigkeit je Volume auf; der obere Prozentwert kann optional externe SSDs einschließen.
- Die vier Ringe der Hardwareüberwachung können den Fortschritt jetzt nach beiden Seiten aufteilen, sodass der obere Prozentwert den Ring nicht mehr verdeckt.
- Die Hardware-Detailseite hat jetzt eine Schaltfläche „Aktivitätsanzeige öffnen“, um schnell zu sehen, was Ressourcen belegt.
- Die Liste mit hoher Auslastung / hohem Energieverbrauch unterstützt jetzt das Fixieren einer Zeile und das sofortige Beenden (einschließlich der untergeordneten Prozesse); die Karten zeigen einen Aktualisierungs-Countdown und der Eintrag verschwindet nach dem Beenden sofort.

## Fehlerbehebungen

- Die nicht lesbare GPU-Temperatur des M3 Air wurde behoben; derselbe Bereich wird nicht mehr doppelt gezählt.
- Die Berechnung der CPU-Temperatur für M5 / M6 wurde optimiert.
- A18-Pro-Erkennung hinzugefügt; nicht erkannte Chips zeigen jetzt „nicht verfügbar“ statt einer falschen Temperatur.
- Ein Fall wurde behoben, in dem einige Modelle ohne echten Messwert weiterhin 0,00 W Displayleistung anzeigten.
- Die Displayleistung wird jetzt ausgeblendet, wenn kein echter Messwert vorliegt, statt einen Schätzwert zu zeigen; bei ausgeschaltetem Bildschirm oder geschlossenem Deckel bleiben keine alten Werte stehen.
- 0 W Display- und USB-Leistung werden nicht mehr als echte Leistung dargestellt.
- Behoben, dass der erste Lesevorgang der Deckel-Einstellung beim Kaltstart fehlschlug; er wird jetzt automatisch wiederholt.
- Ein falsches Timeout wurde behoben, bei dem die App vor dem Hintergrunddienst aufgab; Fehlermeldungen enthalten jetzt einen Fehlercode zur Fehlersuche.
- Bei fehlendem Audiogerät wird der Lautstärkeregler ausgeblendet und stattdessen ein Hinweis „Keine Geräte verfügbar“ angezeigt.
- Einige englische Texte und lange Zeilen wurden überarbeitet, sodass sie nicht mehr abgeschnitten werden.
