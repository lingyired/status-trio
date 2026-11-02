# Versione %VERSION% (Build %BUILD%)

### Batteria

- La pagina batteria mostra una ripartizione del flusso di energia (display integrato, uscita USB/accessori e sistema) e una barra opzionale dell'energia in tempo reale. L'uscita accessori viene letta dai rail della porta SMC quando disponibile.
- Nuova impostazione «Ripristina limite dopo l'annullamento» per Ricarica fino al massimo, con stati più chiari quando macOS avvia da sé l'override temporaneo.
- I colori dell'icona batteria possono seguire colori di stato personalizzati, con scelta separata per l'indicatore di connessione (fulmine, spina o percentuale).
- Modalità «divisa» opzionale per l'anello della batteria: quando il gap superiore mostra fulmine, spina o percentuale, l'arco sinistro indica 0–50% e il destro 50–100%, così 40–60% non viene più nascosto. Disattivata per impostazione predefinita; vale per barra dei menu e Dock.

### Alimentazione

- Lo slot centrale può mostrare la potenza totale in tempo reale invece della sorgente di connessione; i Mac senza batteria integrata sono pienamente supportati.

### Display

- Controllo della luminosità: i display esterni usano DDC diretto, quelli integrati sono pilotati con DisplayServices.

### Icona centrale

- La sorgente dello slot centrale è ora un unico selettore «Icona centrale»: rete, dispositivo Bluetooth, sorgente di ingresso corrente, percentuale batteria o potenza. I due interruttori di errore di rete sono uniti in uno che vale per tutte le sorgenti, l'interruttore Bluetooth «sostituisci icona di rete» non funzionante è stato rimosso e i valori salvati vengono migrati automaticamente.
- Le sorgenti dell'icona centrale sono ora riquadri immagine che mostrano il rendering reale. Un'unica «Dimensione icona centrale» controlla Wi‑Fi, Bluetooth, sorgente di ingresso e numeri, e le opzioni di stile dell'icona di rete sono state spostate in quella pagina.
- L'anteprima mostra lo stato di carica, il contenuto centrale è ora centrato verticalmente sull'anello della batteria e il testo è leggermente più piccolo dei simboli.

### Guida

- Guida rinnovata: la finestra adotta l'altezza della pagina più alta e non cambia più dimensione tra i passi; le anteprime condividono una superficie, le didascalie indicano arco superiore, icona centrale e punti inferiori, sono stati aggiunti esempi dello slot centrale (percentuale, potenza, sorgente di ingresso) e il blocco del consenso è più compatto.

### Impostazioni

- Tutti i menu a comparsa delle Impostazioni usano una larghezza comune e non cambiano più con le opzioni o l'elenco dei dispositivi, mantenendo l'aspetto nativo.

### Audio

- I dispositivi di input/output possono essere riordinati, nascosti e limitati nel numero.
- Il feedback del volume con la rotella è configurabile a parte; ricliccando la modalità di ascolto selezionata si disattiva.

### Pannello

- Il pannello di stato usa uno stile senza angoli né tacca, aggiunge un menu «altro» in basso e adatta meglio dimensioni e layout con Liquid Glass.

### Correzioni

- Le informazioni Wi‑Fi restano visibili senza autorizzazione Posizione.
