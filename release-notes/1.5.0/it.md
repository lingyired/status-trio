# Versione %VERSION% (build %BUILD%)

### Miglioramenti

- Migliorata la coerenza degli aggiornamenti del pannello di stato, mantenendo invariati controlli, layout e navigazione.
- Il pannello di stato viene mostrato in modo più affidabile quando cambiano dispositivo, rete o audio.

### Privacy

- Aggiunte statistiche di utilizzo facoltative. Nelle nuove installazioni l’opzione è attiva di default, ma non viene inviato alcun heartbeat prima di completare la guida o scegliere Personalizza. Dopo un aggiornamento, la funzione resta disattivata finché non viene attivata nelle Impostazioni.
- L’heartbeat contiene un ID di installazione casuale, le versioni dell’app e di macOS, le lingue del sistema e dell’app e la posizione dell’icona. Consulta [privacy e analisi](https://github.com/lingyired/status-trio/blob/main/docs/privacy-telemetry.md).
- L’app non include SDK di analisi di terze parti.
