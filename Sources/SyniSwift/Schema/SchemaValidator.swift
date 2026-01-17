import Foundation

/// Validates engine outputs against JSON schemas and provides grammar constraints.
final class SchemaValidator: @unchecked Sendable {
    private let schemasPath: URL?
    private let grammarsPath: URL?
    private var schemas: [String: JSONSchema] = [:]
    private var grammars: [String: Grammar] = [:]
    private let lock = NSLock()

    init(schemasPath: URL?, grammarsPath: URL? = nil) {
        self.schemasPath = schemasPath
        self.grammarsPath = grammarsPath
    }

    // MARK: - Loading

    func loadSchemas() throws {
        lock.lock()
        defer { lock.unlock() }

        if let path = schemasPath {
            try loadSchemasFromPath(path)
        } else {
            loadBuiltInSchemas()
        }
    }

    func loadGrammars() throws {
        lock.lock()
        defer { lock.unlock() }

        // Grammars are typically co-located with schemas
        if let path = grammarsPath ?? schemasPath {
            try loadGrammarsFromPath(path)
        } else {
            loadBuiltInGrammars()
        }
    }

    // MARK: - Retrieval

    func getSchema(id: String) throws -> JSONSchema {
        lock.lock()
        defer { lock.unlock() }

        guard let schema = schemas[id] else {
            throw SyniError.schemaNotFound(id)
        }
        return schema
    }

    func getGrammar(id: String) throws -> Grammar {
        lock.lock()
        defer { lock.unlock() }

        guard let grammar = grammars[id] else {
            throw SyniError.grammarNotFound(id)
        }
        return grammar
    }

    // MARK: - Validation

    /// Validates raw engine output against a schema.
    /// - Returns: The validated JSON dictionary.
    /// - Throws: `SyniError.schemaValidationFailed` if validation fails.
    func validate(output: EngineOutput, schema: JSONSchema) throws -> [String: Any] {
        guard let jsonString = output.text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonString) as? [String: Any] else {
            // Attempt to repair/extract JSON
            if let repaired = attemptJSONRepair(output.text),
               let repairedJSON = try? JSONSerialization.jsonObject(with: repaired) as? [String: Any] {
                return try validateAgainstSchema(repairedJSON, schema: schema)
            }
            throw SyniError.schemaValidationFailed(details: "Output is not valid JSON")
        }

        return try validateAgainstSchema(json, schema: schema)
    }

    /// Creates a safe fallback JSON for when validation fails completely.
    func createFallbackJSON(for schemaId: String) -> [String: Any] {
        // Return a minimal valid JSON based on schema
        lock.lock()
        let schema = schemas[schemaId]
        lock.unlock()

        return schema?.fallbackValue ?? ["error": true, "message": "Generation failed"]
    }

    // MARK: - Private Loading

    private func loadSchemasFromPath(_ path: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents where fileURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: fileURL),
                  let schema = try? JSONDecoder().decode(JSONSchema.self, from: data) else {
                continue
            }
            schemas[schema.id] = schema
        }
    }

    private func loadGrammarsFromPath(_ path: URL) throws {
        let fileManager = FileManager.default
        let contents = try fileManager.contentsOfDirectory(
            at: path,
            includingPropertiesForKeys: nil
        )

        for fileURL in contents where fileURL.pathExtension == "gbnf" || fileURL.lastPathComponent.contains("grammar") {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }
            let id = fileURL.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: ".grammar", with: "")
            grammars[id] = Grammar(id: id, content: content)
        }
    }

    private func loadBuiltInSchemas() {
        // Keyboard schema
        let keyboardSchema = JSONSchema(
            id: "keyboard.v1",
            properties: [
                "suggestion": .init(type: .string, required: true),
                "confidence": .init(type: .number, required: false)
            ],
            fallbackValue: ["suggestion": "", "confidence": 0.0]
        )

        // Life coach schema
        let lifeCoachSchema = JSONSchema(
            id: "life.coach.v1",
            properties: [
                "response": .init(type: .string, required: true),
                "followUpQuestions": .init(type: .array, required: false),
                "sentiment": .init(type: .string, required: false)
            ],
            fallbackValue: [
                "response": "I'm here to help. Could you tell me more?",
                "followUpQuestions": [],
                "sentiment": "neutral"
            ]
        )

        schemas[keyboardSchema.id] = keyboardSchema
        schemas[lifeCoachSchema.id] = lifeCoachSchema
    }

    private func loadBuiltInGrammars() {
        // Simple JSON grammar for keyboard
        let keyboardGrammar = Grammar(
            id: "keyboard.v1",
            content: """
            root ::= "{" ws "\"suggestion\"" ws ":" ws string ws ("," ws "\"confidence\"" ws ":" ws number ws)? "}"
            string ::= "\"" [^"\\\\]* "\""
            number ::= [0-9]+ ("." [0-9]+)?
            ws ::= [ \\t\\n]*
            """
        )

        // Life coach grammar
        let lifeCoachGrammar = Grammar(
            id: "life.coach.v1",
            content: """
            root ::= "{" ws "\"response\"" ws ":" ws string ws ("," ws "\"followUpQuestions\"" ws ":" ws array)? ws ("," ws "\"sentiment\"" ws ":" ws string)? ws "}"
            string ::= "\"" [^"\\\\]* "\""
            array ::= "[" ws (string ws ("," ws string ws)*)? "]"
            ws ::= [ \\t\\n]*
            """
        )

        grammars[keyboardGrammar.id] = keyboardGrammar
        grammars[lifeCoachGrammar.id] = lifeCoachGrammar
    }

    // MARK: - Validation Helpers

    private func validateAgainstSchema(_ json: [String: Any], schema: JSONSchema) throws -> [String: Any] {
        // Check required properties
        for (key, property) in schema.properties where property.required {
            guard json[key] != nil else {
                throw SyniError.schemaValidationFailed(details: "Missing required property: \(key)")
            }
        }

        // Type validation
        for (key, value) in json {
            if let property = schema.properties[key] {
                try validateType(value: value, expectedType: property.type, key: key)
            }
        }

        return json
    }

    private func validateType(value: Any, expectedType: JSONType, key: String) throws {
        switch expectedType {
        case .string:
            guard value is String else {
                throw SyniError.schemaValidationFailed(details: "Property '\(key)' expected string")
            }
        case .number:
            guard value is Double || value is Int || value is Float else {
                throw SyniError.schemaValidationFailed(details: "Property '\(key)' expected number")
            }
        case .boolean:
            guard value is Bool else {
                throw SyniError.schemaValidationFailed(details: "Property '\(key)' expected boolean")
            }
        case .array:
            guard value is [Any] else {
                throw SyniError.schemaValidationFailed(details: "Property '\(key)' expected array")
            }
        case .object:
            guard value is [String: Any] else {
                throw SyniError.schemaValidationFailed(details: "Property '\(key)' expected object")
            }
        }
    }

    private func attemptJSONRepair(_ text: String) -> Data? {
        // Try to extract JSON from text that might have extra content
        let patterns = [
            "\\{[^{}]*\\}",  // Simple object
            "\\{.*\\}"       // Nested object (greedy)
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
               let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
               let range = Range(match.range, in: text) {
                let jsonString = String(text[range])
                if let data = jsonString.data(using: .utf8),
                   (try? JSONSerialization.jsonObject(with: data)) != nil {
                    return data
                }
            }
        }

        return nil
    }
}

// MARK: - Schema Types

/// A JSON schema definition.
struct JSONSchema: Codable, Sendable {
    let id: String
    let properties: [String: SchemaProperty]
    let fallbackValue: [String: Any]

    enum CodingKeys: String, CodingKey {
        case id, properties
    }

    init(id: String, properties: [String: SchemaProperty], fallbackValue: [String: Any]) {
        self.id = id
        self.properties = properties
        self.fallbackValue = fallbackValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        properties = try container.decode([String: SchemaProperty].self, forKey: .properties)
        fallbackValue = [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(properties, forKey: .properties)
    }
}

/// A property in a JSON schema.
struct SchemaProperty: Codable, Sendable {
    let type: JSONType
    let required: Bool

    init(type: JSONType, required: Bool) {
        self.type = type
        self.required = required
    }
}

/// JSON value types.
enum JSONType: String, Codable, Sendable {
    case string
    case number
    case boolean
    case array
    case object
}

/// A grammar definition for constrained decoding.
struct Grammar: Sendable {
    let id: String
    let content: String
}
