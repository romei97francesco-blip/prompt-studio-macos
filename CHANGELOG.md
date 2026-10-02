# Changelog

## 1.2.0 - 2026-09-20

- il prompt compare mentre viene scritto: la generazione usa lo streaming di OpenRouter invece di attendere la risposta completa;
- i guasti temporanei (limite di richieste, fornitore non disponibile, rete instabile) vengono ritentati automaticamente fino a tre volte con attesa crescente;
- i messaggi di errore di rete distinguono assenza di connessione, timeout e DNS non raggiungibile;
- il catalogo dei modelli viene salvato su disco e riproposto all'avvio, senza attese;
- la chiave viene riscritta nel Portachiavi solo quando cambia davvero;
- la versione della release è letta da `Info.plist`, unica fonte di verità;
- il pulsante di generazione diventa «Rigenera» quando esiste già un risultato, e «Svuota» azzera richiesta, contesto e risultato;
- scorciatoie da tastiera: ⌘S per esportare e ⌘⇧C per copiare il prompt;
- il modello generatore attivo è mostrato nell'intestazione ed è cliccabile per cambiarlo;
- la composizione locale del prompt è isolata in `Composer`, con test dedicati e correzione del ritaglio di modello e contesto.

## 1.1.3 - 2026-09-19

- corretta la generazione con DeepSeek V4.1 Flash e altri modelli di ragionamento;
- il budget di output viene ora riservato al prompt finale;
- aggiunto il supporto alle risposte testuali multipart di OpenRouter;
- migliorati i messaggi per risposte vuote, troncate o terminate dal fornitore.

## 1.1.2 - 2026-09-19

- la chiave OpenRouter può essere salvata e recuperata dal Portachiavi protetto di macOS;
- aggiunta l'opzione per usare la chiave soltanto durante la sessione;
- aggiunto il comando per rimuovere la chiave salvata;
- aggiunto un test isolato di persistenza nel Portachiavi.

## 1.1.1 - 2026-09-19

- aggiunta l'icona dedicata per Finder e Dock;
- completato il supporto a OpenRouter;
- aggiunto il catalogo ricercabile dei modelli;
- mantenuta la modalità locale senza API;
- migliorata la gestione degli errori e dei limiti di connessione.
