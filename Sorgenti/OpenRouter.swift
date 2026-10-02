import Foundation

struct RouterModel: Decodable, Identifiable {
    let id: String
    let name: String
    let architecture: Architecture?
    struct Architecture: Decodable { let output_modalities: [String]? }
}

struct RouterResult { let text: String; let truncated: Bool; let tokens: Int? }

struct OpenRouterError: LocalizedError {
    let message: String
    let retryable: Bool
    var errorDescription: String? { message }
}

enum OpenRouter {
    static let endpoint = URL(string: "https://openrouter.ai/api/v1/chat/completions")!

    /// Limite di token di output inviato a OpenRouter.
    /// 3500 è un compromesso prudente: lascia spazio a prompt lunghi e strutturati
    /// senza esporre a costi imprevisti sui modelli a consumo. È configurabile
    /// tramite il parametro `maxOutputTokens` di `request`.
    static let defaultMaxOutputTokens = 3500

    static func failure(_ text: String, retryable: Bool = false) -> OpenRouterError {
        OpenRouterError(message: text, retryable: retryable)
    }

    static func request(key: String, model: String, system: String, draft: String, stream: Bool = false, maxOutputTokens: Int = OpenRouter.defaultMaxOutputTokens) throws -> URLRequest {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw failure("Inserisci la chiave API OpenRouter nelle impostazioni.") }
        guard !model.isEmpty else { throw failure("Scegli il modello generatore nelle impostazioni OpenRouter.") }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Prompt Studio", forHTTPHeaderField: "X-Title")
        var body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": system], ["role": "user", "content": draft]],
            "max_completion_tokens": maxOutputTokens,
            "reasoning_effort": "none",
            "modalities": ["text"],
            "stream": stream
        ]
        if stream { body["stream_options"] = ["include_usage": true] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return req
    }

    private static func text(from content: Any?) -> String? {
        if let content = content as? String {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : content
        }
        guard let parts = content as? [[String: Any]] else { return nil }
        let combined = parts.compactMap { part -> String? in
            if let text = part["text"] as? String { return text }
            if let text = part["content"] as? String { return text }
            return nil
        }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? nil : combined
    }

    private static func deltaText(from content: Any?) -> String? {
        if let content = content as? String { return content.isEmpty ? nil : content }
        guard let parts = content as? [[String: Any]] else { return nil }
        let combined = parts.compactMap { part -> String? in
            if let text = part["text"] as? String { return text }
            if let text = part["content"] as? String { return text }
            return nil
        }.joined()
        return combined.isEmpty ? nil : combined
    }

    static func httpFailure(_ status: Int) -> OpenRouterError {
        let messages: [Int: String] = [
            400: "Richiesta non accettata. Verifica il modello selezionato.",
            401: "Chiave OpenRouter non valida o revocata.",
            402: "Credito OpenRouter insufficiente per questa richiesta.",
            403: "Accesso negato: verifica permessi e impostazioni dell’account OpenRouter.",
            404: "Modello non disponibile. Aggiorna il catalogo o cambia modello.",
            429: "Limite di richieste raggiunto. Riprova più tardi.",
            502: "Il fornitore del modello non è disponibile. Riprova più tardi.",
            503: "Nessun fornitore disponibile per il modello selezionato."
        ]
        return failure(messages[status] ?? "OpenRouter ha restituito un errore HTTP \(status).", retryable: isRetryable(status: status))
    }

    static func parse(_ data: Data, status: Int) throws -> RouterResult {
        guard status == 200 else { throw httpFailure(status) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw failure("Risposta OpenRouter non valida.") }
        guard json["error"] == nil else { throw failure("OpenRouter ha segnalato un errore di generazione. Verifica modello, credito e disponibilità del fornitore.") }
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first, let message = first["message"] as? [String: Any] else { throw failure("La risposta di OpenRouter non contiene un risultato utilizzabile.") }
        let finishReason = first["finish_reason"] as? String
        if finishReason == "error" { throw failure("La generazione è terminata con un errore del fornitore. Riprova o cambia modello.") }
        guard let content = text(from: message["content"]) else {
            if finishReason == "length" { throw failure("Il modello ha esaurito il limite di output prima di scrivere il prompt. Riduci la richiesta o riprova.") }
            throw failure("Il modello non ha restituito testo. Riprova; se il problema continua, cambia modello generatore.")
        }
        return RouterResult(text: content, truncated: finishReason == "length", tokens: (json["usage"] as? [String: Any])?["total_tokens"] as? Int)
    }

    enum StreamEvent: Equatable {
        case delta(String, reason: String?)
        case finished(reason: String?, tokens: Int?)
        case failure(String)
    }

    static func streamEvent(from line: String) -> StreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("data:") else { return nil }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else { return nil }
        if payload == "[DONE]" { return .finished(reason: nil, tokens: nil) }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = json["error"] as? [String: Any] {
            let detail = (error["message"] as? String) ?? "errore del fornitore"
            return .failure("OpenRouter ha segnalato un errore durante la generazione: \(detail)")
        }
        let tokens = (json["usage"] as? [String: Any])?["total_tokens"] as? Int
        guard let choices = json["choices"] as? [[String: Any]], let first = choices.first else {
            return tokens == nil ? nil : .finished(reason: nil, tokens: tokens)
        }
        let reason = first["finish_reason"] as? String
        if let delta = first["delta"] as? [String: Any], let content = deltaText(from: delta["content"]) {
            return .delta(content, reason: reason)
        }
        if reason != nil { return .finished(reason: reason, tokens: tokens) }
        return nil
    }

    static func catalog(_ data: Data) throws -> [RouterModel] {
        struct Response: Decodable { let data: [RouterModel] }
        return try JSONDecoder().decode(Response.self, from: data).data
            .filter { $0.architecture?.output_modalities?.contains("text") ?? true }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func isRetryable(status: Int) -> Bool {
        [408, 409, 425, 429, 500, 502, 503, 504, 522, 524].contains(status)
    }

    static func isRetryable(_ error: Error) -> Bool {
        if let error = error as? OpenRouterError { return error.retryable }
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .networkConnectionLost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotFindHost, .resourceUnavailable, .dataNotAllowed:
            return true
        default:
            return false
        }
    }

    static func retryDelay(attempt: Int) -> TimeInterval {
        min(8, pow(2, Double(max(0, attempt - 1))))
    }

    static func message(for error: Error) -> String {
        if let error = error as? OpenRouterError { return error.message }
        guard let urlError = error as? URLError else { return error.localizedDescription }
        switch urlError.code {
        case .notConnectedToInternet: return "Nessuna connessione a Internet. Controlla la rete e riprova."
        case .timedOut: return "La richiesta ha superato il tempo massimo. Riprova o scegli un modello più rapido."
        case .cannotFindHost, .dnsLookupFailed: return "Impossibile raggiungere OpenRouter: verifica la connessione o il DNS."
        case .networkConnectionLost: return "Connessione interrotta durante la generazione. Riprova."
        case .cancelled: return "Generazione annullata."
        default: return "Errore di rete: \(urlError.localizedDescription)"
        }
    }

    // MARK: - Catalogo su disco

    static func cacheFile(in directory: URL? = nil) -> URL? {
        let folder: URL
        if let directory {
            folder = directory
        } else {
            guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
            folder = base.appendingPathComponent("it.promptstudio.mac", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("models.json")
    }

    static func loadCachedCatalog(from file: URL? = nil, maxAge: TimeInterval = 24 * 3600) -> [RouterModel]? {
        guard let file = file ?? cacheFile(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < maxAge,
              let data = try? Data(contentsOf: file) else { return nil }
        return try? catalog(data)
    }

    static func saveCachedCatalog(_ data: Data, to file: URL? = nil) {
        guard let file = file ?? cacheFile() else { return }
        try? data.write(to: file, options: .atomic)
    }

    /// Data di salvataggio del catalogo in cache, se il file esiste.
    static func cachedCatalogDate(from file: URL? = nil) -> Date? {
        guard let file = file ?? cacheFile(),
              let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }
        return modified
    }

    /// Età del catalogo salvato in forma leggibile (es. "3 ore fa").
    /// Funzione pura: `now` è iniettabile per rendere il risultato verificabile.
    static func ageDescription(since date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "poco fa" }
        if minutes < 60 { return "\(minutes) min fa" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours) \(hours == 1 ? "ora" : "ore") fa" }
        let days = hours / 24
        return "\(days) \(days == 1 ? "giorno" : "giorni") fa"
    }
}
