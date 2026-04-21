import Foundation

struct ChatNavigationRequest: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let deepAnalysisFocus: String?
    let shouldOfferDeepAnalysis: Bool
    let startNewChat: Bool
}

@Observable final class ChatNavigationManager {
    static let shared = ChatNavigationManager()

    var pendingRequest: ChatNavigationRequest?

    private init() {}

    func openChat(
        prompt: String,
        deepAnalysisFocus: String? = nil,
        shouldOfferDeepAnalysis: Bool = false,
        startNewChat: Bool = false
    ) {
        pendingRequest = ChatNavigationRequest(
            prompt: prompt,
            deepAnalysisFocus: deepAnalysisFocus,
            shouldOfferDeepAnalysis: shouldOfferDeepAnalysis,
            startNewChat: startNewChat
        )
    }

    func consume(_ request: ChatNavigationRequest) {
        guard pendingRequest == request else { return }
        pendingRequest = nil
    }
}
