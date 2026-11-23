# Versione %VERSION% (build %BUILD%)

## Sensori e temperature

- La temperatura GPU del M3 Air (Mac15,12) funziona di nuovo: i sensori Tf non leggibili vengono sostituiti dai Tg verificati, raggruppati in sei coppie per non contare due volte la stessa zona fisica.
- Su M5 e M6 le sonde dello stesso core CPU vengono raggruppate; più sonde non aumentano più il numero di core né la media.
- Aggiunta l'identificazione di A18 Pro. I chip sconosciuti non usano più le chiavi di temperatura di un'altra generazione; mostrano nessuna lettura invece di un numero plausibile ma errato.

## Consumo del display

- Risolto l'Issue #374: un M3 Air senza PDBR e con PBLR fisso a 0 non mostra più un ramo display da 0,00 W.
- Se non è disponibile una via di retroilluminazione misurata, il ramo display viene nascosto; non viene pubblicato alcun valore stimato.
- I rami display e USB a 0 W vengono nascosti.

## Monitoraggio e prestazioni

- Le capacità dei sensori vengono sondate una volta e memorizzate; le chiavi assenti vengono ritentate con backoff.
- Nessun nuovo timer, helper o accesso privilegiato. La raccolta di temperatura e retroilluminazione si ferma ancora alla chiusura del pannello.
