//
//  LLMClient.swift
//

import Foundation

enum LLMError: Error, LocalizedError {
    case emptyKey
    case http(Int, String)
    case emptyResponse
    case parse(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:                      return "Missing OPENAI_API_KEY."
        case .http(let code, let body):      return "HTTP \(code): \(body)"
        case .emptyResponse:                 return "Empty response body."
        case .parse(let msg):                return "Parse error: \(msg)"
        }
    }
}

final class LLMClient {

    private let session: URLSession
    private let apiKey: String
    private let model: String = "gpt-4o-mini"   // easy to swap later

    init() throws {
        // BEFORE (bad): environment["<your real key>"]
        guard let k = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !k.isEmpty else {
            throw LLMError.emptyKey
        }
        self.apiKey = k
        self.session = URLSession(configuration: .default)

        // Masked key tail so you can verify which key is being used
        print("[LLM] Using key tail …\(k.suffix(6))")
    }

    /// Normalize a spoken utterance into either:
    ///  - "ghost" | "cave" | "viewpoint"
    ///  - or a short local search query, e.g. "starbucks seattle"
    func interpret(_ utterance: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        let system = """
        You normalize voice commands for a maps app.
        If the user is asking for ghost towns, caves, or viewpoints, output EXACTLY one of:
        "ghost", "cave", or "viewpoint".
        Otherwise output a short local-search query suitable for Apple Maps (e.g., "starbucks seattle").
        Output **plain text only**, no quotes, no prose.
        """

        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user",   "content": utterance]
            ]
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        print("[LLM →] \(utterance)")
        let (data, resp) = try await session.data(for: req)

        guard let http = resp as? HTTPURLResponse else { throw LLMError.emptyResponse }
        let rawText = String(data: data, encoding: .utf8) ?? ""
        guard http.statusCode == 200 else { throw LLMError.http(http.statusCode, rawText) }
        guard !data.isEmpty else { throw LLMError.emptyResponse }

        // Chat Completions usually returns choices[].message.content as a string,
        // but some gateways can return an array of content parts.
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    /// We allow either a string or an array of parts {type:"text", text:"..."}
                    let content: String

                    private struct ContentPart: Decodable {
                        let type: String?
                        let text: String?
                    }

                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)

                        // 1) Try simple string first
                        if let s = try? container.decode(String.self, forKey: .content) {
                            self.content = s
                            return
                        }

                        // 2) Try array of parts
                        if let parts = try? container.decode([ContentPart].self, forKey: .content) {
                            let texts = parts.compactMap { $0.text }
                            if !texts.isEmpty {
                                self.content = texts.joined(separator: "\n")
                                return
                            }
                        }

                        throw DecodingError.dataCorrupted(
                            DecodingError.Context(codingPath: decoder.codingPath,
                                                  debugDescription: "Unsupported message.content shape")
                        )
                    }

                    enum CodingKeys: String, CodingKey { case content }
                }
                let message: Message
            }
            let choices: [Choice]
        }

        do {
            let r = try JSONDecoder().decode(ChatResponse.self, from: data)
            let out = r.choices.first?.message.content
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !out.isEmpty else { throw LLMError.parse("empty content") }
            print("[LLM ←] \(out)")
            return out
        } catch {
            // Show raw body to help debug mismatches
            print("[LLM RAW]", rawText)
            throw LLMError.parse(error.localizedDescription)
        }
    }
}
