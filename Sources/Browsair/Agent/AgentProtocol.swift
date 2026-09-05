import Foundation

enum AgentProtocolError: Error { case invalidJSON, invalidCommand, invalidURL, invalidInspect, inputTooLarge }

enum AgentCommand: Equatable {
    case getState, navigate(url: String), reload, back, forward, readPageText, inspect(request: InspectRequest)

    static func decode(json: String) throws -> AgentCommand {
        guard let data = json.data(using: .utf8), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let name = object["command"] as? String else { throw AgentProtocolError.invalidJSON }
        switch name {
        case "inspect":
            let request = try InspectRequest.decode(json: json)
            return .inspect(request: request)
        case "getState": return .getState
        case "reload": return .reload
        case "back": return .back
        case "forward": return .forward
        case "readPageText": return .readPageText
        case "navigate":
            guard let url = object["url"] as? String, let parsed = URL(string: url), ["http", "https"].contains(parsed.scheme?.lowercased()) else { throw AgentProtocolError.invalidURL }
            return .navigate(url: url)
        default: throw AgentProtocolError.invalidCommand
        }
    }
}

struct AgentState: Codable, Equatable { let url: String; let title: String; let isLoading: Bool }
private struct AgentSuccess: Codable { let ok: Bool; let state: AgentState }
private struct AgentFailure: Codable { let ok: Bool; let error: String }
private struct AgentPageTextSuccess: Encodable {
    let ok: Bool
    let state: AgentState
    let result: TextResult
    struct TextResult: Encodable { let text: String }
}
private struct AgentInspectSuccess: Encodable {
    let ok: Bool
    let state: AgentState
    let result: InspectSnapshot
}

enum AgentResponse: Equatable {
    case ok(AgentState)
    case pageText(state: AgentState, text: String)
    case inspect(state: AgentState, snapshot: InspectSnapshot)
    case error(String)

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch self {
        case .ok(let state):
            return try encoder.encode(AgentSuccess(ok: true, state: state))
        case .pageText(let state, let text):
            return try encoder.encode(AgentPageTextSuccess(ok: true, state: state, result: .init(text: text)))
        case .inspect(let state, let snapshot):
            return try encoder.encode(AgentInspectSuccess(ok: true, state: state, result: snapshot))
        case .error(let message):
            return try encoder.encode(AgentFailure(ok: false, error: message))
        }
    }
}
