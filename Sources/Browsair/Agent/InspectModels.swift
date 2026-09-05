import Foundation

struct InspectRequest: Equatable {
    static let maximumDepth = 8
    static let maximumNodes = 500
    static let maximumSelectorLength = 256
    let selector: String
    let maxDepth: Int
    let maxNodes: Int
    let includeText: Bool

    static func decode(json: String) throws -> InspectRequest {
        guard json.utf8.count <= 20_000 else { throw AgentProtocolError.inputTooLarge }
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["command"] as? String == "inspect",
              let selector = object["selector"] as? String, !selector.isEmpty, selector.utf8.count <= maximumSelectorLength,
              !selector.contains(";") && !selector.contains("{") && !selector.contains("}") else { throw AgentProtocolError.invalidInspect }
        let depth = min(max(object["maxDepth"] as? Int ?? 4, 1), maximumDepth)
        let nodes = min(max(object["maxNodes"] as? Int ?? 100, 1), maximumNodes)
        return InspectRequest(selector: selector, maxDepth: depth, maxNodes: nodes, includeText: object["includeText"] as? Bool ?? true)
    }
}

struct InspectNode: Codable, Equatable {
    let tag: String
    let id: String?
    let classes: [String]
    let text: String?
    let children: [InspectNode]
}

struct InspectSnapshot: Codable, Equatable {
    let url: String
    let title: String
    let nodes: [InspectNode]
    let truncated: Bool

    static func decode(json: String) throws -> InspectSnapshot {
        guard let data = json.data(using: .utf8) else { throw AgentProtocolError.invalidJSON }
        return try JSONDecoder().decode(InspectSnapshot.self, from: data)
    }
}
