import Foundation

/// Compone il prompt finale a partire dalle scelte dell'utente.
/// Logica pura (nessuna dipendenza da SwiftUI/AppKit) così da poter essere verificata dai test.
struct Composer {
    static let targets = ["DeepSeek", "ChatGPT", "Claude", "Gemini", "Grok", "Mistral", "Llama / locale", "Altra AI"]

    static func make(_ request: String, target: String, model: String, detail: String, format: String, context: String) -> String {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = cleanModel.isEmpty ? target : "\(target) — \(cleanModel)"
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = cleanContext.isEmpty ? "" : "\n\nCONTESTO E VINCOLI DELL’UTENTE\n\(cleanContext)"
        return """
        OBIETTIVO
        Soddisfa la richiesta riportata qui sotto, rispettandone scopo e vincoli.

        RICHIESTA
        \(request.trimmingCharacters(in: .whitespacesAndNewlines))\(extra)

        CRITERI DI ESECUZIONE
        - Non inventare dati, fonti, accessi, prove eseguite o risultati.
        - Se manca un’informazione indispensabile, chiedi un chiarimento mirato; per dettagli non essenziali, dichiara un’ipotesi ragionevole e procedi.
        - Se il compito richiede informazioni aggiornate, verificale con gli strumenti disponibili e cita le fonti; se non puoi verificarle, dichiaralo.
        - Separa fatti verificati, ipotesi e proposte quando pertinente.
        - Verifica che il risultato rispetti la richiesta prima di consegnarlo.

        RISULTATO ATTESO
        Lingua: italiano, salvo diversa richiesta.
        Formato: \(format).
        \(depth(for: detail))
        \(structure(for: target))

        Adatta l’esecuzione alle capacità effettivamente disponibili in \(destination), senza presumere strumenti o accessi esterni.
        """
    }

    /// Livello di approfondimento richiesto, in base al dettaglio scelto.
    private static func depth(for detail: String) -> String {
        switch detail {
        case "Sintetico":
            return "Rispondi in modo conciso, mantenendo i dettagli necessari per usare il risultato."
        case "Dettagliato":
            return "Fornisci un risultato completo e organizzato. Esplicita ipotesi, passaggi operativi e criteri di verifica pertinenti, evitando ripetizioni."
        default:
            return "Bilancia completezza e sintesi: sviluppa i punti utili e ometti le digressioni."
        }
    }

    /// Indicazioni di struttura specifiche per il target; per gli altri vale la frase generica.
    private static func structure(for target: String) -> String {
        switch target {
        case "Claude":
            return "Distingui chiaramente istruzioni, materiale di riferimento e risultato."
        case "Gemini":
            return "Se sono presenti allegati, collega le conclusioni ai relativi contenuti senza presumere di aver visto file non disponibili."
        case "DeepSeek":
            return "Consegna il risultato finale con una breve motivazione delle scelte rilevanti e controlli verificabili."
        default:
            return "Organizza la risposta in sezioni solo quando rendono il risultato più leggibile."
        }
    }
}
