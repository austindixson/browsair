import Foundation

struct CDPRequest: Encodable {
    let id: Int
    let method: String
    let params: [String: AnyCodable]?
    let sessionId: String?

    init(id: Int, method: String, params: [String: Any]? = nil, sessionId: String? = nil) {
        self.id = id
        self.method = method
        self.params = params.map { $0.mapValues { AnyCodable($0) } }
        self.sessionId = sessionId
    }

    enum CodingKeys: String, CodingKey {
        case id, method, params, sessionId
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
    }
}

struct CDPResponse: Decodable {
    let id: Int?
    let method: String?
    let sessionId: String?
    let result: AnyCodable?
    let error: CDPErrorBody?
    let params: AnyCodable?
}

struct CDPErrorBody: Decodable, Error, LocalizedError {
    let code: Int?
    let message: String?

    var errorDescription: String? { message ?? "CDP error \(code ?? -1)" }
}

struct ObscuraVersionInfo: Decodable {
    let webSocketDebuggerUrl: String
    let browser: String?
    let protocolVersion: String?
    let userAgent: String?

    enum CodingKeys: String, CodingKey {
        case webSocketDebuggerUrl
        case browser = "Browser"
        case protocolVersion = "ProtocolVersion"
        case userAgent = "User-Agent"
    }
}

/// Type-erased JSON value for CDP params/results.
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: encoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    var dictionaryValue: [String: Any]? { value as? [String: Any] }
    var stringValue: String? { value as? String }
    var intValue: Int? { value as? Int }
    var boolValue: Bool? { value as? Bool }
}
