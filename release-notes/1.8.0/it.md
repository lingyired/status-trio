# Versione %VERSION% (Compilazione %BUILD%)

### Batteria

- È stato aggiunto il flusso di energia della batteria con stime dell’ingresso del caricatore, dell’energia inviata alla batteria e dell’energia di sistema. L’ingresso del caricatore è disattivato per impostazione predefinita; le altre due letture sono attive.
- È stato aggiunto un elenco opzionale dell’impatto energetico della CPU con un massimo di cinque app basato sui campioni recenti. Se i contatori energetici non sono disponibili, usa l’attività della CPU e supporta un intervallo di campionamento di 10–60 secondi.
- Sui Mac compatibili con chip Apple e macOS 26.4 o versioni successive, Carica fino al massimo e Annulla carica fino al massimo sono disponibili e attivi per impostazione predefinita quando la funzione è supportata.

### Display esterni

- È stato aggiunto un metodo di controllo del volume tramite BetterDisplay per display esterni o uscite audio il cui volume non può essere controllato direttamente da macOS. Supporta l’associazione automatica o manuale del display e mostra gli stati di connessione ed errore.
- Il volume nativo scrivibile rimane preferito, la modalità Standard/DDC può essere ripristinata in qualsiasi momento e Status Trio non avvia né modifica BetterDisplay quando non è disponibile.

### Stabilità e interfaccia

- La gestione degli eventi Wi-Fi è stata migliorata raggruppando le chiamate CoreWLAN ad alta frequenza e limitando la frequenza di ripristino negli stati anomali, riducendo il rischio che una tempesta di eventi amplifichi il carico su CPU e memoria.
- Il pannello di stato ora mantiene la pagina dei dettagli corrente quando viene riaperto invece di tornare alla pagina principale.
- Sono stati migliorati il layout dei dettagli della batteria, la navigazione, l’area cliccabile dell’ingranaggio e l’aggiornamento della potenza in tempo reale.
- È stata migliorata la composizione del livello colorato e dell’immagine modello nella barra dei menu. I display senza focus ora si attenuano correttamente mantenendo la ricolorazione di sistema quando si cambia Space.

### Note importanti

- Carica fino al massimo usa un’interfaccia PowerUI privata ed è disponibile solo sui Mac con chip Apple e macOS 26.4 o versioni successive. Il comportamento non è garantito tra le versioni di macOS.
- Dopo il completamento della carica o il ricollegamento dell’alimentatore, il limite di carica può rimanere al 100%. Status Trio non lo ripristina automaticamente; usa Annulla carica fino al massimo o ripristina il limite nelle Impostazioni di Sistema.
- L’elenco dell’impatto energetico della CPU non rappresenta il consumo energetico totale di un’app e non è una copia dell’elenco macOS “Uso significativo di energia”.
- Il controllo del volume tramite BetterDisplay richiede che BetterDisplay sia in esecuzione. Il volume del display e il comportamento DDC dipendono comunque dall’hardware e dalla connessione.
