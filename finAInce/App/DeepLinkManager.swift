import Foundation

// MARK: - Deep Links

enum DeepLink: Equatable {
    case home
    case transactions
    case transactionsCategory(id: String)
    case chat
    case search
    case profile
    case settings
    case transaction(id: String)
    case category(id: String)
    case goal(id: String)
    case project(id: String)
    case account(id: String)
    case analysis
    case monthComparison
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

        if let staticLink = staticDeepLink(for: host ?? pathComponents.first?.lowercased()) {
            return staticLink
        }

        if host == "transactions",
           pathComponents.count >= 2,
           pathComponents[0].lowercased() == "category" {
            let id = pathComponents[1]
            guard !id.isEmpty else { return nil }
            return .transactionsCategory(id: id)
        }

        if let host, ["transaction", "category", "goal", "project", "account"].contains(host) {
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
        case "project": return .project(id: id)
        case "account": return .account(id: id)
        default: return nil
        }
    }

    private static func staticDeepLink(for kind: String?) -> DeepLink? {
        switch kind {
        case "home":
            return .home
        case "transactions":
            return .transactions
        case "chat":
            return .chat
        case "search":
            return .search
        case "profile":
            return .profile
        case "settings":
            return .settings
        case "analysis":
            return .analysis
        case "month-comparison", "monthcomparison":
            return .monthComparison
        default:
            return nil
        }
    }
}
