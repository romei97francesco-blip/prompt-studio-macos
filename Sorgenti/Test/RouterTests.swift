import Foundation
@main struct Tests {
    static func main() throws {
        let req = try OpenRouter.request(key: " test-key ", model: " vendor/model ", system: "system", draft: "richiesta")
        precondition(req.url?.absoluteString == "https://openrouter.ai/api/v1/chat/completions")
        precondition(req.value(forHTTPHeaderField:"Authorization") == "Bearer test-key")
        let body = try JSONSerialization.jsonObject(with: req.httpBody!) as! [String:Any]
        precondition(body["model"] as? String == "vendor/model")
        precondition(body["thinking"] == nil)
        precondition(body["stream"] as? Bool == false)
        for pair in [("", "vendor/model"), ("test-key", " ")] {
            do { _ = try OpenRouter.request(key: pair.0, model: pair.1, system: "", draft: ""); fatalError("Missing validation") } catch {}
        }
        let valid = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Il prompt"}}],"usage":{"total_tokens":25}}"#.utf8)
        let result = try OpenRouter.parse(valid, status:200)
        precondition(result.text == "Il prompt" && !result.truncated && result.tokens == 25)
        let truncated = Data(#"{"choices":[{"finish_reason":"length","message":{"content":"Parziale"}}]}"#.utf8)
        let cut = try OpenRouter.parse(truncated, status:200)
        precondition(cut.truncated)
        for status in [400,401,402,403,404,429,502,503] {
            do { _ = try OpenRouter.parse(valid, status: status); fatalError("HTTP error ignored") } catch {}
        }
        for raw in [#"{"error":{"message":"private provider error"}}"#, #"{"choices":[]}"#, #"{"choices":[{"message":{"content":" "}}]}"#] {
            do { _ = try OpenRouter.parse(Data(raw.utf8), status:200); fatalError("Invalid content accepted") } catch {}
        }
        let catalog = Data(#"{"data":[{"id":"v/image","name":"Image","architecture":{"output_modalities":["image"]}},{"id":"v/text","name":"Text","architecture":{"output_modalities":["text"]}}]}"#.utf8)
        let models = try OpenRouter.catalog(catalog)
        precondition(models.count == 1 && models[0].id == "v/text")
        print("PASS: request, credential/model validation, response, truncation, 8 HTTP errors, malformed content and model filtering. No network calls.")
    }
}
