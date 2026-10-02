import Foundation

/// Compone il prompt finale a partire dalle scelte dell'utente.
/// Logica pura (nessuna dipendenza da SwiftUI/AppKit) così da poter essere verificata dai test.
struct Composer {
    static let targets = ["DeepSeek", "ChatGPT", "Claude", "Gemini", "Grok", "Mistral", "Llama / locale", "Altra AI"]

    static func make(_ request: String, target: String, model: String, detail: String, format: String, context: String) -> String {
        let cleanModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let destination = cleanModel.isEmpty ? target : "\(target) — \(cleanModel)"
        let depth = detail == "Sintetico" ? "Rispondi in modo conciso, mantenendo i dettagli necessari per usare il risultato." : detail == "Dettagliato" ? "Fornisci un risultato completo e organizzato. Esplicita ipotesi, passaggi operativi e criteri di verifica pertinenti, evitando ripetizioni." : "Bilancia completezza e sintesi: sviluppa i punti utili e ometti le digressioni."
        let cleanContext = context.trimmingCharacters(in: .whitespacesAndNewlines)
        let extra = cleanContext.isEmpty ? "" : "\n\nCONTESTO E VINCOLI DELL’UTENTE\n\(cleanContext)"
        let structure = target == "Claude" ? "Distingui chiaramente istruzioni, materiale di riferimento e risultato." : target == "Gemini" ? "Se sono presenti allegati, collega le conclusioni ai relativi contenuti senza presumere di aver visto file non disponibili." : target == "DeepSeek" ? "Consegna il risultato finale con una breve motivazione delle scelte rilevanti e controlli verificabili." : "Organizza la risposta in sezioni solo quando rendono il risultato più leggibile."
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
        \(depth)
        \(structure)

        Adatta l’esecuzione alle capacità effettivamente disponibili in \(destination), senza presumere strumenti o accessi esterni.
        """
    }
}
