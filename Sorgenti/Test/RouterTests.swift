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
        print("PASS: request, no-reasoning text mode, credential/model validation, string and multipart responses, truncation, 8 HTTP errors, malformed content and model filtering. No network calls.")
    }
}
