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
        req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": [["role":"system", "content":system], ["role":"user", "content":draft]], "max_tokens": 3500, "stream": false])
        return req
    }
    static func parse(_ data: Data, status: Int) throws -> RouterResult {
        guard status == 200 else {
            let messages = [400:"Richiesta non accettata. Verifica il modello selezionato.", 401:"Chiave OpenRouter non valida o revocata.", 402:"Credito OpenRouter insufficiente per questa richiesta.", 403:"Accesso negato: verifica permessi e impostazioni dell’account OpenRouter.", 404:"Modello non disponibile. Aggiorna il catalogo o cambia modello.", 429:"Limite di richieste raggiunto. Riprova più tardi.", 502:"Il fornitore del modello non è disponibile. Riprova più tardi.", 503:"Nessun fornitore disponibile per il modello selezionato."]
            throw failure(messages[status] ?? "OpenRouter ha restituito un errore HTTP \(status).")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw failure("Risposta OpenRouter non valida.") }
        guard json["error"] == nil else { throw failure("OpenRouter ha segnalato un errore di generazione. Verifica modello, credito e disponibilità del fornitore.") }
        guard let choices = json["choices"] as? [[String:Any]], let first = choices.first, let message = first["message"] as? [String:Any], let content = message["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw failure("Il modello non ha restituito testo utilizzabile. Prova un altro modello o ripeti la richiesta.") }
        if first["finish_reason"] as? String == "error" { throw failure("La generazione è terminata con un errore del fornitore.") }
        return RouterResult(text: content, truncated: first["finish_reason"] as? String == "length", tokens: (json["usage"] as? [String:Any])?["total_tokens"] as? Int)
    }
    static func catalog(_ data: Data) throws -> [RouterModel] {
        struct Response: Decodable { let data: [RouterModel] }
        return try JSONDecoder().decode(Response.self, from: data).data.filter { $0.architecture?.output_modalities?.contains("text") ?? true }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
