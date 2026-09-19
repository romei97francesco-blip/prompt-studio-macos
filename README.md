# Prompt Studio

![Prompt Studio](Assets/Anteprima.png)

Prompt Studio è una piccola app nativa per macOS che trasforma una richiesta informale in un prompt più chiaro e dettagliato, pronto per l'AI scelta dall'utente.

L'app distingue due ruoli:

- **AI destinataria**: il modello al quale verrà consegnato il prompt finale, per esempio DeepSeek, ChatGPT, Claude o Gemini.
- **Modello generatore**: il modello richiamato tramite OpenRouter per scrivere il prompt.

## Funzioni

- due riquadri affiancati per richiesta e prompt finale;
- profili per DeepSeek, ChatGPT, Claude, Gemini, Grok, Mistral e modelli locali;
- selezione del livello di dettaglio e del formato desiderato;
- catalogo aggiornato dei modelli OpenRouter;
- modalità locale senza API;
- copia negli appunti ed esportazione in un file di testo;
- chiave API mantenuta soltanto in memoria durante l'esecuzione.

## Requisiti

- macOS 14 o successivo;
- Mac Apple Silicon;
- una chiave [OpenRouter](https://openrouter.ai/settings/keys) per la generazione tramite AI.

## Installazione

1. Scarica `Prompt-Studio-1.1.1-macOS.zip` dalla sezione **Releases**.
2. Estrai l'archivio.
3. Sposta `Prompt Studio.app` nella cartella Applicazioni.
4. Apri l'app, entra in **Impostazioni** e inserisci la chiave OpenRouter.
5. Carica il catalogo e seleziona il modello che preparerà i prompt.

La build distribuita è firmata localmente, ma non è notarizzata da Apple. Al primo avvio macOS potrebbe chiedere di confermare l'apertura dell'app scaricata da Internet.

## Privacy e costi

La chiave OpenRouter non viene salvata su disco. Quando si preme **Genera prompt**, richiesta, contesto e istruzioni vengono inviati a OpenRouter e al fornitore del modello scelto. Il costo dipende dal modello e dalle tariffe dell'account OpenRouter. Il solo identificativo del modello selezionato viene ricordato fra gli avvii.

Leggi [PRIVACY.md](PRIVACY.md) per i dettagli.

## Compilazione

Sono richiesti Xcode e gli strumenti a riga di comando:

```bash
./Sorgenti/compila.sh
```

Lo script crea o aggiorna `Prompt Studio.app` nella radice del progetto e applica una firma locale ad hoc.

## Test

```bash
./Sorgenti/test.sh
```

I test non effettuano chiamate di rete e verificano la costruzione delle richieste, la validazione di chiave e modello, le risposte normali e troncate, gli errori HTTP e il filtro del catalogo.

## Sicurezza

Non inserire mai una chiave API nel codice, nelle segnalazioni di problemi o nelle schermate pubbliche. Per segnalazioni di sicurezza, consulta [SECURITY.md](SECURITY.md).

## Licenza

Il codice è distribuito con licenza [MIT](LICENSE).

