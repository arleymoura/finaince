import Foundation

// MARK: - Deep Links

enum DeepLink: Equatable {
    case home
    case transaction(id: String)
    case category(id: String)
    case goal(id: String)
}

@Observable final class DeepLinkManager {
    static let shared = DeepLinkManager()

    var pendingDeepLink: DeepLink?

    private init() {}

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let deepLink = Self.parse(url) else { return false }
        pendingDeepLink = deepLink
        return true
    }

    func routeToHome() {
        pendingDeepLink = .home
    }

    func consume(_ deepLink: DeepLink) {
        guard pendingDeepLink == deepLink else { return }
        pendingDeepLink = nil
    }

    static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "finaince" else { return nil }

        let host = url.host?.lowercased()
        let pathComponents = url.pathComponents.filter { $0 != "/" }

        if host == "home" || pathComponents.first?.lowercased() == "home" {
            return .home
        }

        if let host, ["transaction", "category", "goal"].contains(host) {
            guard let id = pathComponents.first, !id.isEmpty else { return nil }
            return deepLink(kind: host, id: id)
        }

        guard pathComponents.count >= 2 else { return nil }
        let kind = pathComponents[0].lowercased()
        let id = pathComponents[1]
        return deepLink(kind: kind, id: id)
    }

    private static func deepLink(kind: String, id: String) -> DeepLink? {
        switch kind {
        case "transaction": return .transaction(id: id)
        case "category": return .category(id: id)
        case "goal": return .goal(id: id)
        default: return nil
        }
    }
}
