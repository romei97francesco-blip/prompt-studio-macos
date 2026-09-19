import Foundation

struct RouterModel: Decodable, Identifiable {
    let id: String
    let name: String
    let architecture: Architecture?
    struct Architecture: Decodable { let output_modalities: [String]? }
}
struct RouterResult { let text: String; let truncated: Bool; let tokens: Int? }
enum OpenRouter {
    static func failure(_ text: String) -> NSError {
        NSError(domain: "PromptStudio.OpenRouter", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
    }
    static func request(key: String, model: String, system: String, draft: String) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw failure("Inserisci la chiave API OpenRouter nelle impostazioni.") }
        guard !model.isEmpty else { throw failure("Scegli il modello generatore nelle impostazioni OpenRouter.") }
        var req = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Prompt Studio", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role":"system", "content":system], ["role":"user", "content":draft]],
            "max_completion_tokens": 3500,
            "reasoning_effort": "none",
            "modalities": ["text"],
            "stream": false
        ])
        return req
    }
    private static func text(from content: Any?) -> String? {
        if let content = content as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : content
        }
        guard let parts = content as? [[String:Any]] else { return nil }
        let combined = parts.compactMap { part -> String? in
            if let text = part["text"] as? String { return text }
            if let text = part["content"] as? String { return text }
            return nil
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }
    static func parse(_ data: Data, status: Int) throws -> RouterResult {
        guard status == 200 else {
            let messages = [400:"Richiesta non accettata. Verifica il modello selezionato.", 401:"Chiave OpenRouter non valida o revocata.", 402:"Credito OpenRouter insufficiente per questa richiesta.", 403:"Accesso negato: verifica permessi e impostazioni dell’account OpenRouter.", 404:"Modello non disponibile. Aggiorna il catalogo o cambia modello.", 429:"Limite di richieste raggiunto. Riprova più tardi.", 502:"Il fornitore del modello non è disponibile. Riprova più tardi.", 503:"Nessun fornitore disponibile per il modello selezionato."]
            throw failure(messages[status] ?? "OpenRouter ha restituito un errore HTTP \(status).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw failure("Risposta OpenRouter non valida.") }
        guard json["error"] == nil else { throw failure("OpenRouter ha segnalato un errore di generazione. Verifica modello, credito e disponibilità del fornitore.") }
        guard let choices = json["choices"] as? [[String:Any]], let first = choices.first, let message = first["message"] as? [String:Any] else { throw failure("La risposta di OpenRouter non contiene un risultato utilizzabile.") }
        let finishReason = first["finish_reason"] as? String
        if finishReason == "error" { throw failure("La generazione è terminata con un errore del fornitore. Riprova o cambia modello.") }
        guard let content = text(from: message["content"]) else {
            if finishReason == "length" {
                throw failure("Il modello ha esaurito il limite di output prima di scrivere il prompt. Riduci la richiesta o riprova.")
            }
            throw failure("Il modello non ha restituito testo. Riprova; se il problema continua, cambia modello generatore.")
        }
        return RouterResult(text: content, truncated: finishReason == "length", tokens: (json["usage"] as? [String:Any])?["total_tokens"] as? Int)
    }
    static func catalog(_ data: Data) throws -> [RouterModel] {
        struct Response: Decodable { let data: [RouterModel] }
        return try JSONDecoder().decode(Response.self, from: data).data.filter { $0.architecture?.output_modalities?.contains("text") ?? true }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
