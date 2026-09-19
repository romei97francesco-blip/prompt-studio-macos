# Privacy

Prompt Studio non richiede un account proprio e non gestisce un server dell'applicazione.

## Dati conservati sul Mac

- Se l'utente attiva il salvataggio, la chiave API OpenRouter viene custodita nel Portachiavi protetto di macOS e recuperata ai successivi avvii.
- Se il salvataggio è disattivato, la chiave resta soltanto nella memoria dell'app e viene persa alla chiusura.
- La chiave salvata può essere rimossa in qualsiasi momento dalle impostazioni dell'app.
- L'identificativo del modello generatore selezionato viene salvato nelle preferenze locali di macOS.
- Richieste e prompt generati non vengono salvati automaticamente. Vengono scritti su disco soltanto quando l'utente sceglie **Esporta**.

## Dati trasmessi

In modalità OpenRouter, quando l'utente preme **Genera prompt**, vengono trasmessi:

- la richiesta inserita;
- il contesto e i vincoli facoltativi;
- l'AI destinataria, il formato e il livello di dettaglio scelti;
- le istruzioni necessarie a trasformare il testo in un prompt.

I dati vengono inviati a OpenRouter e al fornitore del modello selezionato. Il loro trattamento è regolato dalle condizioni e dalle politiche dei rispettivi servizi.

Il caricamento del catalogo usa l'endpoint pubblico dei modelli OpenRouter e non invia la chiave API né il testo della richiesta.

## Modalità locale

Disattivando **Generazione tramite OpenRouter**, il prompt viene composto sul Mac senza inviare dati a servizi esterni.
