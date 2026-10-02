import Foundation

@main struct ComposerTests {
    static func main() throws {
        // La richiesta viene ripulita dagli spazi e inserita nella sezione RICHIESTA.
        let base = Composer.make("  Riassumi il documento  ", target: "ChatGPT", model: "", detail: "Bilanciato", format: "Elenco puntato", context: "")
        precondition(base.contains("RICHIESTA\nRiassumi il documento\n"))
        precondition(!base.contains("  Riassumi"))
        precondition(base.contains("Formato: Elenco puntato."))

        // Senza modello la destinazione è il solo target; con modello si aggiunge " — modello".
        precondition(base.contains("capacità effettivamente disponibili in ChatGPT,"))
        let withModel = Composer.make("x", target: "Claude", model: "  claude-3.5-sonnet  ", detail: "Bilanciato", format: "Testo", context: "")
        precondition(withModel.contains("capacità effettivamente disponibili in Claude — claude-3.5-sonnet,"))

        // I tre livelli di dettaglio producono frasi distinte.
        let sintetico = Composer.make("x", target: "ChatGPT", model: "", detail: "Sintetico", format: "Testo", context: "")
        let bilanciato = Composer.make("x", target: "ChatGPT", model: "", detail: "Bilanciato", format: "Testo", context: "")
        let dettagliato = Composer.make("x", target: "ChatGPT", model: "", detail: "Dettagliato", format: "Testo", context: "")
        precondition(sintetico.contains("Rispondi in modo conciso"))
        precondition(bilanciato.contains("Bilancia completezza e sintesi"))
        precondition(dettagliato.contains("Fornisci un risultato completo e organizzato"))
        precondition(sintetico != bilanciato && bilanciato != dettagliato && sintetico != dettagliato)

        // La struttura cambia in base al target; i target non speciali usano la frase generica.
        precondition(Composer.make("x", target: "Claude", model: "", detail: "Bilanciato", format: "Testo", context: "").contains("Distingui chiaramente istruzioni"))
        precondition(Composer.make("x", target: "Gemini", model: "", detail: "Bilanciato", format: "Testo", context: "").contains("Se sono presenti allegati"))
        precondition(Composer.make("x", target: "DeepSeek", model: "", detail: "Bilanciato", format: "Testo", context: "").contains("Consegna il risultato finale"))
        for target in ["ChatGPT", "Grok", "Mistral", "Llama / locale", "Altra AI"] {
            precondition(Composer.make("x", target: target, model: "", detail: "Bilanciato", format: "Testo", context: "").contains("Organizza la risposta in sezioni"))
        }

        // Il contesto vuoto non aggiunge sezioni; quello valorizzato compare ripulito.
        precondition(!base.contains("CONTESTO E VINCOLI"))
        let withContext = Composer.make("x", target: "ChatGPT", model: "", detail: "Bilanciato", format: "Testo", context: "  Pubblico tecnico  ")
        precondition(withContext.contains("CONTESTO E VINCOLI DELL’UTENTE\nPubblico tecnico"))
        precondition(!withContext.contains("  Pubblico tecnico"))

        // Il catalogo dei target resta quello atteso dall'interfaccia.
        precondition(Composer.targets.first == "DeepSeek" && Composer.targets.count == 8)

        print("PASS: composizione del prompt (richiesta ripulita, destinazione con/senza modello, tre livelli di dettaglio, struttura per target, contesto opzionale, catalogo target). Nessuna chiamata di rete.")
    }
}
