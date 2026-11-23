# Versione %VERSION% (build %BUILD%)

### Monitor di sistema

- Il pannello di stato ora monitora CPU, GPU, memoria, rete, disco e velocità della ventola; fai clic per aprire la pagina di dettaglio corrispondente.
- Colori personalizzati per le metriche di CPU, GPU, memoria, rete, disco e velocità della ventola.
- Personalizza l'intervallo di aggiornamento e l'intervallo della cronologia.
- Il monitor di sistema campiona su richiesta: legge le metriche solo mentre sono visualizzate e la cronologia in background è disattivata per impostazione predefinita, riducendo il carico.

### Icona della barra dei menu e anello

- Nuove origini dati del monitor di sistema per l'anello esterno, con layout ad anello singolo e doppio anello sinistra/destra. Gli archi possono usare utilizzo CPU, temperatura CPU, utilizzo GPU, temperatura GPU, utilizzo memoria, temperatura batteria, livello batteria, velocità ventola, velocità di download/upload, volume e segnale Wi-Fi.
- L'arco del livello batteria segue i colori di sistema; un nuovo ruolo colore «Scarica (non alimentato)» consente di personalizzare separatamente i colori di carica, basso, alte prestazioni, critico e scarica (#357).
- Nuova modalità AirPods per l'indicatore superiore: i doppi anelli possono mostrare la batteria degli auricolari sinistro e destro (anche uno solo) e, se disconnessi, tornano alla batteria del Mac o a un anello personalizzato.
- L'indicatore inferiore supporta un'origine dati personalizzata: volume, segnale Wi-Fi o livello batteria (o nascosto).

### Pannello e interazione

- Passa il cursore sull'icona della barra dei menu per aprire il pannello; fai clic per fissarlo (#355).
- I dettagli ora si aprono in un pannello laterale accanto al pannello di stato, con un passaggio più fluido.
- Aggiunta la scheda del monitor hardware.
- Rifiniti i cursori numerici (volume e luminosità) con un aspetto più vicino a macOS 26+ e un movimento più fluido; supportano lo scorrimento orizzontale del trackpad (#351).
- Le icone Wi-Fi e Bluetooth sono colorate in base allo stato di connessione (#352).
- Il pulsante «Carica al massimo ora» ha un riflesso liquid glass al passaggio del cursore.
- Rimossi i grassetti nel pannello di stato; valori e unità usano un font monospaziato.

### Mantieni attivo e sospensione

- Aggiunti «Mantieni schermo acceso» e «Nessuna sospensione a coperchio chiuso», ciascuno con durata personalizzabile (#295).

### Luminosità

- Nuovo interruttore «Usa luminosità combinata BetterDisplay» (#344).

### Batteria e audio

- Corretti il testo e la riga di carica di mantenimento al 100%.
- Corretto il silenziamento a volume esattamente zero e il ripristino del solo silenziamento automatico.
- Corretta la stima «tempo alla carica completa» per rispettare il limite di carica di macOS (#349).

### Altre correzioni

- La cronologia dei dettagli del monitor è ora isolata per tipo di metrica.
- Migliorati il campionamento in background e la stabilità delle pipe dei processi, con meno scatti e interferenze.
- Corretto lo sfarfallio dell'altezza della riga della modalità di ascolto AirPods all'apertura del pannello (#354).
