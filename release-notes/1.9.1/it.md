# Versione %VERSION% (Build %BUILD%)

### Batteria

- La pagina batteria mostra una ripartizione del flusso di energia (display integrato, uscita USB/accessori e sistema) e una barra opzionale dell'energia in tempo reale. L'uscita accessori viene letta dai rail della porta SMC quando disponibile.
- Nuova impostazione «Ripristina limite dopo l'annullamento» per Ricarica fino al massimo, con stati più chiari quando macOS avvia da sé l'override temporaneo.
- I colori dell'icona batteria possono seguire colori di stato personalizzati, con scelta separata per l'indicatore di connessione (fulmine, spina o percentuale).
- Modalità «divisa» opzionale per l'anello della batteria: quando il gap superiore mostra fulmine, spina o percentuale, l'arco sinistro indica 0–50% e il destro 50–100%, così 40–60% non viene più nascosto. Disattivata per impostazione predefinita; vale per barra dei menu e Dock.

### Alimentazione

- Lo slot centrale può mostrare la potenza totale in tempo reale invece della sorgente di connessione.
- Anche i Mac senza batteria integrata possono mostrare la potenza e aprire i dettagli della batteria.

### Display

- Controllo della luminosità: i display esterni usano DDC diretto, quelli integrati sono pilotati con DisplayServices.

### Icona centrale

- La sorgente dello slot centrale è ora un unico selettore «Icona centrale»: rete, dispositivo Bluetooth, sorgente di ingresso corrente, percentuale batteria o potenza. I due interruttori di errore di rete sono uniti in uno che vale per tutte le sorgenti, l'interruttore Bluetooth «sostituisci icona di rete» non funzionante è stato rimosso e i valori salvati vengono migrati automaticamente.
- Corretta l'icona centrale che non era centrata verticalmente.

### Guida

- Guida introduttiva migliorata.

### Audio

- I dispositivi di input/output possono essere riordinati, nascosti e limitati nel numero.
- Il feedback del volume con la rotella è configurabile a parte; ricliccando la modalità di ascolto selezionata si disattiva.

### Pannello

- Il pannello di stato usa uno stile senza angoli né tacca, coerente con il pannello della barra dei menu di macOS, aggiunge un menu «altro» in basso e adatta meglio dimensioni e layout con Liquid Glass.

### Correzioni

- Le informazioni Wi‑Fi restano visibili senza autorizzazione Posizione.
