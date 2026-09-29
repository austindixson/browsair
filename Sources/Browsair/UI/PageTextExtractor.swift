import Foundation

/// Bounds and cleans the text extracted from a page before it is handed to the AI model.
/// Delegates to `AIContextPolicy.sanitize` so the scrub-and-bound rules live in one place.
enum PageTextExtractor {
    static let maximumCharacters = AIContextPolicy.maximumCharacters

    static func sanitize(_ raw: String) -> String {
        AIContextPolicy.sanitize(raw)
    }
}
