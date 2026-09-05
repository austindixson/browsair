import Foundation

enum InspectScript {
    static func make(request: InspectRequest) throws -> String {
        guard let selectorData = try? JSONSerialization.data(withJSONObject: [request.selector]),
              let encoded = String(data: selectorData, encoding: .utf8),
              let selector = encoded.dropFirst().dropLast().description.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw AgentProtocolError.invalidInspect
        }
        // The selector is JSON-encoded before insertion. Bounds are constants from validated input.
        return """
        (() => {
          const root = document.querySelector(\(selector));
          const maxDepth = \(request.maxDepth), maxNodes = \(request.maxNodes), includeText = \(request.includeText);
          let count = 0, truncated = false;
          const clean = value => value.replace(/\\s+/g, ' ').trim().slice(0, 2000);
          const visit = (element, depth) => {
            if (!element || count >= maxNodes) { truncated = true; return null; }
            count++;
            const children = [];
            if (depth < maxDepth) for (const child of element.children) {
              const node = visit(child, depth + 1); if (node) children.push(node);
              if (count >= maxNodes) break;
            } else if (element.children.length) truncated = true;
            return {tag: element.tagName.toLowerCase(), id: element.id || null, classes: Array.from(element.classList).slice(0, 32), text: includeText ? clean(element.childNodes.length ? Array.from(element.childNodes).filter(n => n.nodeType === Node.TEXT_NODE).map(n => n.textContent || '').join(' ') : '') : null, children};
          };
          return {url: location.href, title: document.title || '', nodes: root ? [visit(root, 0)].filter(Boolean) : [], truncated};
        })()
        """
    }
}
