import Foundation
@main struct Tests {
    static func main() throws {
        let req = try OpenRouter.request(key: " test-key ", model: " vendor/model ", system: "system", draft: "richiesta")
        precondition(req.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        precondition(req.value(forHTTPHeaderField:"Authorization") == "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String:Any]
        precondition(body["model"] as? String == "vendor/model")
        precondition(body["max_completion_tokens"] as? Int == 3500)
        precondition(body["max_tokens"] == nil)
        precondition(body["reasoning_effort"] as? String == "none")
        precondition(body["modalities"] as? [String] == ["text"])
        precondition(body["stream"] as? Bool == false)
        precondition(body["stream_options"] == nil)
        for pair in [("", "vendor/model"), ("test-key", " ")] {
            do { _ = try OpenRouter.request(key: pair.0, model: pair.1, system: "", draft: ""); fatalError("Missing validation") } catch {}
        }
        let valid = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Il prompt"}}],"usage":{"total_tokens":25}}"#.utf8)
        let result = try OpenRouter.parse(valid, status:200)
        precondition(result.text == "Il prompt" && !result.truncated && result.tokens == 25)
        let multipart = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":[{"type":"text","text":"Prima riga"},{"type":"text","text":"Seconda riga"}]}}]}"#.utf8)
        let multipartResult = try OpenRouter.parse(multipart, status:200)
        precondition(multipartResult.text == "Prima riga\nSeconda riga")
        let truncated = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"Parziale"}}]}"#.utf8)
        let cut = try OpenRouter.parse(truncated, status:200)
        precondition(cut.truncated)
        for status in [400,401,402,403,404,429,502,503] {
            do { _ = try OpenRouter.parse(valid, status: status); fatalError("HTTP error ignored") } catch {}
        }
        for raw in [#"{"error":{"message":"private provider error"}}"#, #"{"choices":[]}"#, #"{"choices":[{"message":{"content":" "}}]}"#, #"{"choices":[{"finish_reason":"length","message":{"content":null,"reasoning":"budget usato"}}]}"#] {
            do { _ = try OpenRouter.parse(Data(raw.utf8), status:200); fatalError("Invalid content accepted") } catch {}
        }
        let catalog = Data(#"{"data":[{"id":"v/image","name":"Image","architecture":{"output_modalities":["image"]}},{"id":"v/text","name":"Text","architecture":{"output_modalities":["text"]}}]}"#.utf8)
        let models = try OpenRouter.catalog(catalog)
        precondition(models.count == 1 && models[0].id == "v/text")

        // Richiesta in streaming: attiva stream e include_usage.
        let streamRequest = try OpenRouter.request(key: "k", model: "m", system: "s", draft: "d", stream: true)
        let streamBody = try JSONSerialization.jsonObject(with: streamRequest.httpBody!) as! [String:Any]
        precondition(streamBody["stream"] as? Bool == true)
        precondition((streamBody["stream_options"] as? [String:Bool])?["include_usage"] == true)

        // Analisi degli eventi SSE.
        precondition(OpenRouter.streamEvent(from: "") == nil)
        precondition(OpenRouter.streamEvent(from: ": OPENROUTER PROCESSING") == nil)
        precondition(OpenRouter.streamEvent(from: "data: ") == nil)
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{"content":"Ciao"}}]}"#) == .delta("Ciao", reason: nil))
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{"content":" mondo"}}]}"#) == .delta(" mondo", reason: nil))
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{"content":""}}]}"#) == nil)
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{"content":" "}}]}"#) == .delta(" ", reason: nil))
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{"content":"\n"}}]}"#) == .delta("\n", reason: nil))
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#) == .finished(reason: "stop", tokens: nil))
        precondition(OpenRouter.streamEvent(from: #"data: {"choices":[],"usage":{"total_tokens":42}}"#) == .finished(reason: nil, tokens: 42))
        precondition(OpenRouter.streamEvent(from: "data: [DONE]") == .finished(reason: nil, tokens: nil))
        precondition(OpenRouter.streamEvent(from: "data: non-json") == nil)
        if case .failure(let message)? = OpenRouter.streamEvent(from: #"data: {"error":{"message":"boom"}}"#) {
            precondition(message.contains("boom"))
        } else { fatalError("Streaming error ignored") }

        // Classificazione degli errori ritentabili e attesa crescente.
        for status in [408, 409, 425, 429, 500, 502, 503, 504, 522, 524] { precondition(OpenRouter.isRetryable(status: status)) }
        for status in [400, 401, 402, 403, 404] { precondition(!OpenRouter.isRetryable(status: status)) }
        precondition(OpenRouter.isRetryable(URLError(.timedOut)))
        precondition(OpenRouter.isRetryable(URLError(.notConnectedToInternet)))
        precondition(OpenRouter.isRetryable(URLError(.networkConnectionLost)))
        precondition(!OpenRouter.isRetryable(URLError(.cancelled)))
        precondition(!OpenRouter.isRetryable(OpenRouter.failure("errore non ritentabile")))
        precondition(OpenRouter.isRetryable(OpenRouter.failure("errore ritentabile", retryable: true)))
        precondition(OpenRouter.retryDelay(attempt: 1) == 1)
        precondition(OpenRouter.retryDelay(attempt: 2) == 2)
        precondition(OpenRouter.retryDelay(attempt: 3) == 4)
        precondition(OpenRouter.retryDelay(attempt: 9) == 8)

        // Messaggi di rete comprensibili.
        precondition(OpenRouter.message(for: URLError(.notConnectedToInternet)).contains("Internet"))
        precondition(OpenRouter.message(for: URLError(.timedOut)).contains("tempo massimo"))
        precondition(OpenRouter.message(for: OpenRouter.failure("messaggio diretto")) == "messaggio diretto")

        // Trascrizione realistica di uno stream OpenRouter, riga per riga.
        let transcript = [
            ": OPENROUTER PROCESSING",
            "",
            #"data: {"choices":[{"delta":{"role":"assistant","content":""}}]}"#,
            #"data: {"choices":[{"delta":{"content":"OBIETTIVO"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" "}}]}"#,
            #"data: {"choices":[{"delta":{"content":"chiaro"}}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            #"data: {"choices":[],"usage":{"total_tokens":123}}"#,
            "data: [DONE]"
        ]
        var assembled = ""
        var finalReason: String?
        var finalTokens: Int?
        for line in transcript {
            guard let event = OpenRouter.streamEvent(from: line) else { continue }
            switch event {
            case .delta(let chunk, _): assembled += chunk
            case .finished(let reason, let tokens):
                if let reason { finalReason = reason }
                if let tokens { finalTokens = tokens }
            case .failure(let message): fatalError("Errore inatteso nello stream: \(message)")
            }
        }
        precondition(assembled == "OBIETTIVO chiaro")
        precondition(finalReason == "stop")
        precondition(finalTokens == 123)

        // Alcuni fornitori accorpano l'ultimo contenuto e finish_reason nella stessa riga:
        // il motivo di fine non deve andare perso, altrimenti il troncamento passa inosservato.
        let combined = [
            #"data: {"choices":[{"delta":{"content":"Parziale"},"finish_reason":"length"}]}"#,
            "data: [DONE]"
        ]
        var combinedText = ""
        var combinedReason: String?
        for line in combined {
            guard let event = OpenRouter.streamEvent(from: line) else { continue }
            if case .delta(let chunk, let reason) = event {
                combinedText += chunk
                if let reason { combinedReason = reason }
            }
        }
        precondition(combinedText == "Parziale")
        precondition(combinedReason == "length")

        // Cache su disco del catalogo: andata e ritorno, scadenza, file assente.
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("promptstudio-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let cacheFile = OpenRouter.cacheFile(in: tempDir)!
        precondition(OpenRouter.loadCachedCatalog(from: cacheFile) == nil)
        OpenRouter.saveCachedCatalog(catalog, to: cacheFile)
        let cached = OpenRouter.loadCachedCatalog(from: cacheFile)
        precondition(cached?.count == 1 && cached?[0].id == "v/text")
        precondition(OpenRouter.loadCachedCatalog(from: cacheFile, maxAge: -1) == nil)

        print("PASS: request, no-reasoning text mode, credential/model validation, string and multipart responses, truncation, 8 HTTP errors, malformed content, model filtering, streaming request, SSE events (including combined finish_reason), retry classification, backoff and network messages. No network calls.")
    }
}
