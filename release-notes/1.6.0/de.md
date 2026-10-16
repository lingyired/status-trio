# Version %VERSION% (Build %BUILD%)

### Neue Funktionen

- Steuerung des Energiesparmodus: Ein optionaler Schalter in den Batteriedetails aktiviert oder deaktiviert den Energiesparmodus, ohne die Systemeinstellungen zu öffnen. Erfordert eine einmalige Freigabe unter Systemeinstellungen › Allgemein › Anmeldeobjekte im Abschnitt „Im Hintergrund zulassen“; der registrierte Helfer tut nichts anderes, läuft nur, solange die App ihn nutzt, und beendet sich im Leerlauf selbst. Der Freigabehinweis bleibt unter dem Schalter stehen, und die ganze Zeile öffnet die Anmeldeobjekte.
- Ladestand für vollen Ring: Legt fest, ab welchem Ladestand der Batteriering als voll gilt (50%–100%, Standard 100%). Nützlich auf einem Mac, dessen Ladebegrenzung die Batterie unter 100% hält; „Ladebegrenzung übernehmen“ liest den Wert aus dem System. Menüleiste und Dock folgen gemeinsam.
- Lokale IP-Adresse: Eine optionale Netzwerkeinstellung zeigt die private LAN-Adresse dieses Macs in der zweiten Zeile der Netzwerkzeile, vor den WLAN-Details. Standardmäßig aus.
- Internet teilen: Die Detailseiten von WLAN und Kabelverbindung können direkt den Bereich „Teilen“ öffnen, in dem „Internet teilen“ aktiviert wird. Die App öffnet nur den Bereich und schaltet die Freigabe nicht selbst.

### Fehlerbehebungen

- WLAN-Signal: Zwischenzeitlich ungültige CoreWLAN-Messwerte werden überbrückt, sodass das verbundene Symbol nicht mehr verblasst oder 0 Balken anzeigt.
- Bluetooth-Gerätesymbole: Das Symbol richtet sich jetzt nur nach der Klasse, die das Gerät selbst angibt (device_minorType), sodass Verbinden und Trennen es nicht mehr ändern. Gibt ein Hersteller die Klasse falsch an – etwa eine Tastatur, die sich als Maus meldet –, folgt das Symbol dieser Angabe, und die App korrigiert sie nicht mehr.
- Menüleistensymbol: Der monochrome Teil färbt sich live neu ein, während ein Space gezogen wird.
- Symbolausrichtung: SF Symbols werden an der sichtbaren Tinte statt am Layoutfeld zentriert, sodass das WLAN-Symbol nicht mehr außerhalb der Ringmitte sitzt.
- Audio: Die doppelte Zusammenfassungszeile der Audioausgabe wurde entfernt.

### Hinweise

- Während ein Space gezogen wird, folgt nur ein durchgehend monochromes Symbol dem Ziel-Space; die Elemente mit Statusfarbe (schwacher Akku, Energiesparmodus, Netzstrom, Bluetooth) aktualisieren sich erst nach dem Umschalten.
