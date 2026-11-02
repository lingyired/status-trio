# Versione %VERSION% (Build %BUILD%)

### Batteria

- Modalità «divisa» opzionale per l'anello della batteria: quando il gap superiore mostra fulmine, spina o percentuale, l'arco sinistro indica 0–50% e il destro 50–100%, così 40–60% non viene più nascosto. Disattivata per impostazione predefinita; vale per barra dei menu e Dock.
- I colori dell'icona batteria possono seguire colori di stato personalizzati, con scelta separata per l'indicatore di connessione (fulmine, spina o percentuale). Barra dei menu e Dock condividono la stessa scena.
- La pagina batteria mostra una ripartizione del flusso di energia (display integrato, uscita USB/accessori e sistema) e una barra opzionale dell'energia in tempo reale. L'uscita accessori viene letta dai rail della porta SMC quando disponibile.
- Nuova impostazione «Ripristina limite dopo l'annullamento» per Ricarica fino al massimo, con stati più chiari quando macOS avvia da sé l'override temporaneo.

### Alimentazione

- Lo slot centrale può mostrare la potenza totale in tempo reale invece della sorgente di connessione; i Mac senza batteria integrata sono pienamente supportati.

### Display

- Controllo della luminosità: i display esterni usano DDC diretto, quelli integrati sono pilotati con DisplayServices, quindi BetterDisplay non serve più per lo schermo interno.
- Nel diagramma di flusso l'altezza di ogni scheda è proporzionale alla sua quota, con qualsiasi numero di rami.

### Audio

- I dispositivi di input/output possono essere riordinati, nascosti e limitati nel numero. Un solo dispositivo con modalità di ascolto mantiene i pulsanti di riduzione del rumore anche nascondendo le altre uscite.
- Il feedback del volume con la rotella è configurabile a parte; ricliccando la modalità di ascolto selezionata si disattiva.

### Pannello

- Il pannello di stato usa uno stile senza angoli né tacca, aggiunge un menu «altro» in basso e adatta meglio dimensioni e layout con Liquid Glass. Nell'ordine predefinito «Luminosità display» è sotto «Ingresso audio».

### Correzioni

- Riavviare durante Ricarica fino al massimo mantiene il limite di ripristino calcolato all'inizio invece di tornare al 100%.
- Chiudere il pannello libera il campionamento della barra energia; l'icona campiona ogni 2 s solo mentre mostra energia.
- Attivando/disattivando la barra energia a pannello aperto si usa subito il nuovo valore.
- Una ripartizione di energia batteria verificata non viene più scartata allo scollegamento.
- Il collegamento a caldo di un display aggiorna l'elenco luminosità e scarta la connessione DDC obsoleta.
- Una scrittura DDC non confermata mostra «non disponibile» invece di perdere cursore e spiegazione.
- Le informazioni Wi‑Fi restano visibili senza autorizzazione Posizione.
