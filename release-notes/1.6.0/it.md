# Versione %VERSION% (Build %BUILD%)

### Novità

- Controllo modalità risparmio energia: un interruttore opzionale nei dettagli della batteria attiva o disattiva la modalità risparmio energia senza aprire Impostazioni di Sistema. Richiede un'approvazione una tantum in Impostazioni di Sistema › Generali › Elementi login, in «Consenti in background»; l'helper registrato non fa altro, viene eseguito solo mentre l'app lo usa e si chiude da solo in inattività. Il suggerimento di approvazione resta sotto il controllo e l'intera riga apre gli elementi login.
- Livello anello pieno: scegli il livello di carica al quale l'anello della batteria è considerato pieno (50%–100%, predefinito 100%). Utile su un Mac il cui limite di carica tiene la batteria sotto il 100%; «Usa il limite di carica» legge il valore dal sistema. Barra dei menu e Dock procedono insieme.
- IP locale: un'impostazione opzionale di Rete mostra l'indirizzo LAN privato di questo Mac nella seconda riga della riga di rete, prima dei dettagli Wi-Fi. Disattivata per impostazione predefinita.
- Condivisione Internet: le pagine dei dettagli Wi-Fi e via cavo possono aprire direttamente il pannello «Condivisione», dove si attiva la condivisione di Internet. L'app apre solo il pannello e non attiva la condivisione da sé.

### Correzioni

- Segnale Wi-Fi: le letture non valide intermittenti di CoreWLAN vengono aggirate, così l'icona connessa non si attenua più né mostra 0 tacche.
- Icone dei dispositivi Bluetooth: l'icona ora viene disegnata solo in base alla classe dichiarata dal dispositivo stesso (device_minorType), quindi collegare o scollegare non la cambia più. Se un produttore dichiara una classe errata, per esempio una tastiera che si presenta come mouse, l'icona segue quella dichiarazione e l'app non la corregge più.
- Icona della barra dei menu: la parte monocromatica si ricolora in tempo reale mentre si trascina uno spazio.
- Allineamento delle icone: gli SF Symbols sono centrati sulla loro inchiostratura visibile e non sul riquadro di layout, così l'icona Wi-Fi non è più fuori centro nell'anello.
- Audio: rimossa la riga duplicata del riepilogo dell'uscita audio.

### Note

- Mentre si trascina un cambio di spazio, solo un'icona interamente monocromatica segue lo spazio di destinazione; gli elementi con colore di stato (batteria scarica, modalità risparmio energia, alimentazione collegata, Bluetooth) si aggiornano al termine del cambio.
