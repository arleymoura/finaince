import SwiftUI
import SwiftData
import Vision
import UniformTypeIdentifiers
import LinkPresentation

struct ChatView: View {
    /// When set, the prompt is auto-sent as soon as the view appears (if AI is configured).
    /// Defaults to `nil` so the tab instance is unaffected.
    var initialPrompt: String? = nil
    var deepAnalysisFocus: String? = nil
    var shouldOfferDeepAnalysis: Bool = false

    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var goals: [Goal]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var costCenters: [CostCenter]
    @Query private var families: [Family]
    @Query private var aiSettings: [AISettings]
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @AppStorage("user.name") private var userName = "Meu Perfil"
    @AppStorage("user.adultsCount") private var adultsCount = 0
    @AppStorage("user.childrenCount") private var childrenCount = 0
    @State private var chatNavigationManager = ChatNavigationManager.shared
    @State private var importManager = SharedImportManager.shared

    // ── Chat state ──────────────────────────────────────────────────────────
    @State private var inputText         = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading         = false
    @State private var conversation: ChatConversation?
    @State private var showSetup         = false
    @State private var showAISettings    = false
    @State private var pendingDraft: TransactionDraft? = nil
    @State private var reviewState: IdentifiableNewTransactionState? = nil
    @State private var pendingDeepAnalysisOffer: DeepAnalysisOfferPayload? = nil
    @State private var pendingDeepAnalysisPrompt: DeepAnalysisSharePayload? = nil
    @State private var pendingImportStatementOffer: ImportStatementOfferPayload? = nil
    @State private var pendingDeepAnalysisOfferMessageId: UUID? = nil
    @State private var pendingDeepAnalysisPromptMessageId: UUID? = nil
    @State private var pendingImportStatementOfferMessageId: UUID? = nil
    @State private var createdTransactionByMessageId: [UUID: Transaction] = [:]
    @State private var lastCreatedMessageId: UUID? = nil
    @State private var transactionToView: Transaction? = nil
    @State private var deepLinkManager = DeepLinkManager.shared
    @FocusState private var isInputFocused: Bool
    @State private var deepAnalysisOfferShown = false
    @State private var deepAnalysisSharePayload: DeepAnalysisSharePayload? = nil
    @State private var isPreparingDeepAnalysis = false
    @State private var dailyInsight: DailyInsight?
    @State private var isDailyInsightLoading = false
    @State private var dailyInsightLoadToken = UUID()
    @State private var savingsOpportunities: [SavingsOpportunity] = []
    @State private var isSavingsOpportunitiesLoading = false
    @State private var savingsOpportunityLoadToken = UUID()
    private let regularContentMaxWidth: CGFloat = 1100

    // ── Attachment state ────────────────────────────────────────────────────
    @State private var attachedImage: UIImage?              = nil
    @State private var attachedCSVName: String?             = nil
    @State private var attachedCSVContent: String?          = nil
    @State private var showAttachMenu                       = false
    @State private var showCamera                           = false
    @State private var showPhotoLibrary                     = false
    @State private var showCSVPicker                        = false
    @State private var isProcessingAttachment               = false
    @State private var activeDeepAnalysisFocus: String? = nil
    @State private var activeShouldOfferDeepAnalysis = false

    /// Session-only cache: message.id → UIImage (not persisted to SwiftData)
    @State private var sessionImages: [UUID: UIImage] = [:]

    // ── Computed ────────────────────────────────────────────────────────────
    private var activeSettings: AISettings? { aiSettings.first(where: { $0.isConfigured }) }
    private var isConfigured: Bool { activeSettings != nil }
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }
    private var hasAttachment: Bool { attachedImage != nil || attachedCSVName != nil }
    private var chatGlassFill: Color { colorScheme == .dark ? .white.opacity(0.08) : .white.opacity(0.14) }
    private var chatGlassStrongFill: Color { colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.16) }
    private var chatGlassSoftFill: Color { colorScheme == .dark ? .white.opacity(0.07) : .white.opacity(0.12) }
    private var chatGlassBorder: Color { colorScheme == .dark ? .white.opacity(0.10) : .white.opacity(0.18) }
    private var regularHeaderTopColor: Color {
        colorScheme == .dark ? Color(red: 0.34, green: 0.25, blue: 0.72) : Color.accentColor.opacity(0.95)
    }
    private var regularHeaderBottomColor: Color {
        colorScheme == .dark ? Color(red: 0.18, green: 0.14, blue: 0.36) : Color.accentColor.opacity(0.65)
    }
    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespaces).isEmpty || hasAttachment) && !isLoading
    }

    private var suggestedQuestions: [String] {
        [
            t("ai.suggest1"),
            t("ai.suggest2"),
            t("ai.suggest3"),
            t("ai.suggest4")
        ]
    }

    private struct AnalysisHubItem: Identifiable {
        let id: String
        let icon: String
        let color: Color
        let title: String
        let subtitle: String
        let prompt: String
        let deepFocus: String
    }

    private var analysisHubItems: [AnalysisHubItem] {
        [
            AnalysisHubItem(
                id: "month",
                icon: "calendar.badge.clock",
                color: .blue,
                title: t("ai.hub.monthTitle"),
                subtitle: t("ai.hub.monthSubtitle"),
                prompt: t("ai.hub.monthPrompt"),
                deepFocus: t("ai.hub.monthTitle")
            ),
            AnalysisHubItem(
                id: "card",
                icon: "creditcard.fill",
                color: .orange,
                title: t("ai.hub.cardTitle"),
                subtitle: t("ai.hub.cardSubtitle"),
                prompt: t("ai.hub.cardPrompt"),
                deepFocus: t("ai.hub.cardTitle")
            ),
            AnalysisHubItem(
                id: "excess",
                icon: "exclamationmark.triangle.fill",
                color: .red,
                title: t("ai.hub.excessTitle"),
                subtitle: t("ai.hub.excessSubtitle"),
                prompt: t("ai.hub.excessPrompt"),
                deepFocus: t("ai.hub.excessTitle")
            ),
            AnalysisHubItem(
                id: "payments",
                icon: "bell.badge.fill",
                color: .yellow,
                title: t("ai.hub.paymentsTitle"),
                subtitle: t("ai.hub.paymentsSubtitle"),
                prompt: t("ai.hub.paymentsPrompt"),
                deepFocus: t("ai.hub.paymentsTitle")
            ),
            AnalysisHubItem(
                id: "goals",
                icon: "target",
                color: .green,
                title: t("ai.hub.goalsTitle"),
                subtitle: t("ai.hub.goalsSubtitle"),
                prompt: t("ai.hub.goalsPrompt"),
                deepFocus: t("ai.hub.goalsTitle")
            ),
            AnalysisHubItem(
                id: "education",
                icon: "book.fill",
                color: .purple,
                title: t("ai.hub.educationTitle"),
                subtitle: t("ai.hub.educationSubtitle"),
                prompt: t("ai.hub.educationPrompt"),
                deepFocus: t("ai.hub.educationTitle")
            )
        ]
    }

    private var activeProviderLabel: String {
        activeSettings?.provider.label ?? t("ai.notConfigured")
    }

    private var dailyInsightReloadKey: String {
        let latestTransaction = transactions.first?.id.uuidString ?? "none"
        let latestGoal = goals.first?.id.uuidString ?? "none"
        let latestAccount = accounts.first?.id.uuidString ?? "none"
        return "\(transactions.count)-\(goals.count)-\(accounts.count)-\(currencyCode)-\(latestTransaction)-\(latestGoal)-\(latestAccount)"
    }

    private struct QuickReplyAction: Identifiable {
        enum Kind {
            case sendText(String)
            case openDeepLink(URL)
        }

        let id: String
        let title: String
        let kind: Kind
    }

    private var quickReplyActions: [QuickReplyAction] {
        guard let lastAssistantMessage = messages.last, lastAssistantMessage.role == .assistant else {
            return []
        }

        guard pendingDraft == nil,
              pendingDeepAnalysisOffer == nil,
              pendingDeepAnalysisPrompt == nil,
              pendingImportStatementOffer == nil,
              !isLoading else {
            return []
        }

        if !assistantMessageNeedsQuickReply(lastAssistantMessage.content) {
            return deepLinkQuickReplyActions(from: lastAssistantMessage.content)
        }

        var actions: [QuickReplyAction] = [
            QuickReplyAction(id: "reply-yes", title: t("common.yes"), kind: .sendText(t("common.yes"))),
            QuickReplyAction(id: "reply-no", title: t("common.no"), kind: .sendText(t("common.no")))
        ]
        actions.append(contentsOf: deepLinkQuickReplyActions(from: lastAssistantMessage.content))
        return Array(actions.prefix(4))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    WorkspaceBackground(isRegularLayout: isRegularLayout)
                        .ignoresSafeArea()

                    VStack(spacing: 0) {
                        chatHeaderCard(topInset: proxy.safeAreaInsets.top)
                            .ignoresSafeArea(edges: .top)

                        Group {
                            if !isConfigured {
                                notConfiguredView
                            } else if messages.isEmpty {
                                suggestionsView
                            } else {
                                chatScrollView
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .frame(maxWidth: isRegularLayout ? regularContentMaxWidth : .infinity)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded { dismissKeyboard() }
                        )

                        if isConfigured {
                            inputSection
                                .frame(maxWidth: isRegularLayout ? regularContentMaxWidth : .infinity)
                        }
                    }
                }
                .animation(.spring(duration: 0.3), value: pendingDraft != nil)
                .padding(.top, -50)
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if consumeSharedImportsIfNeeded() { return }

                // Fire initialPrompt (used when opened from an Insight card)
                guard let prompt = initialPrompt, !prompt.isEmpty else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    inputText = prompt
                    if isConfigured { sendMessage() }
                }
            }
            .onAppear {
                consumePendingChatNavigationIfNeeded()
            }
            .onChange(of: chatNavigationManager.pendingRequest) { _, request in
                guard request != nil else { return }
                consumePendingChatNavigationIfNeeded()
            }
            .onChange(of: importManager.pendingSharedImage) { _, _ in
                consumeSharedImportsIfNeeded()
            }
            .onChange(of: importManager.pendingSharedChatFile != nil) { _, _ in
                consumeSharedImportsIfNeeded()
            }
            .sheet(isPresented: $showSetup) {
                AISetupView()
            }
            .sheet(isPresented: $showAISettings) {
                NavigationStack {
                    AIProviderSettingsView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(t("common.ok")) { showAISettings = false }
                                    .fontWeight(.semibold)
                            }
                        }
                }
            }
            .sheet(item: $transactionToView) { transaction in
                TransactionEditView(transaction: transaction)
            }
            .sheet(item: $reviewState) { wrapper in
                NavigationStack {
                    Step4DetailsView(
                        state: wrapper.state,
                        onBack: { reviewState = nil },
                        onSave: { saveReviewedTransaction(wrapper.state) }
                    )
                    .navigationTitle(t("newTx.step4"))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button(t("common.cancel")) { reviewState = nil }
                        }
                    }
                }
            }
            .sheet(item: $deepAnalysisSharePayload) { payload in
                DeepAnalysisShareSheet(payload: payload)
            }
            // Câmera
            .sheet(isPresented: $showCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    attachedImage = image
                }
            }
            // Galeria
            .sheet(isPresented: $showPhotoLibrary) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    attachedImage = image
                }
            }
            // Arquivo CSV / texto
            .fileImporter(
                isPresented: $showCSVPicker,
                allowedContentTypes: ([
                    .commaSeparatedText,
                    .tabSeparatedText,
                    .plainText,
                    .text,
                    UTType("org.openxmlformats.spreadsheetml.sheet"),
                    UTType("com.microsoft.excel.xls"),
                    UTType(filenameExtension: "ofx"),
                    UTType("com.intuit.ofx"),
                ] as [UTType?]).compactMap { $0 },
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = handleStatementFileSelection(url)
                }
            }
        }
    }

    init(
        initialPrompt: String? = nil,
        deepAnalysisFocus: String? = nil,
        shouldOfferDeepAnalysis: Bool = false
    ) {
        self.initialPrompt = initialPrompt
        self.deepAnalysisFocus = deepAnalysisFocus
        self.shouldOfferDeepAnalysis = shouldOfferDeepAnalysis
        _activeDeepAnalysisFocus = State(initialValue: deepAnalysisFocus)
        _activeShouldOfferDeepAnalysis = State(initialValue: shouldOfferDeepAnalysis)
    }

    // MARK: - Input Section (attachment preview + input bar)

    private func dismissKeyboard() {
        isInputFocused = false
    }

    private func consumePendingChatNavigationIfNeeded() {
        guard let request = chatNavigationManager.pendingRequest else { return }

        if request.startNewChat {
            clearChat()
        }

        activeDeepAnalysisFocus = request.deepAnalysisFocus
        activeShouldOfferDeepAnalysis = request.shouldOfferDeepAnalysis
        chatNavigationManager.consume(request)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            inputText = request.prompt
            if isConfigured { sendMessage() }
        }
    }

    @discardableResult
    private func consumeSharedImportsIfNeeded() -> Bool {
        var consumedAttachment = false

        if let sharedImage = importManager.pendingSharedImage {
            attachedImage = sharedImage
            importManager.clearPendingSharedImage()
            consumedAttachment = true
        }

        if let sharedFile = importManager.pendingSharedChatFile {
            _ = handleStatementFileSelection(sharedFile.url)
            importManager.clearPendingSharedChatFile()
        }

        if consumedAttachment {
            sendSharedAttachmentIfPossible()
        }

        return consumedAttachment
    }

    private func sendSharedAttachmentIfPossible() {
        guard isConfigured else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard hasAttachment, !isLoading else { return }
            sendMessage()
        }
    }

    // MARK: - Header

    private func chatHeaderCard(topInset: CGFloat) -> some View {
        Group {
            if isRegularLayout {
                regularChatHeader(topInset: topInset)
            } else {
                compactChatHeader(topInset: topInset)
            }
        }
    }

    private func compactChatHeader(topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 14) {
            chatHeaderLeadingContent

            Spacer()

            chatHeaderTrailingAction
        }
        .padding(.horizontal, 20)
        .padding(.top, topInset + 16)
        .padding(.bottom, 18)
        .background(chatHeaderBackground)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)
            )
        )
        .shadow(color: regularHeaderBottomColor.opacity(colorScheme == .dark ? 0.28 : 0.20), radius: 14, x: 0, y: 8)
    }

    private func regularChatHeader(topInset: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 18) {
            chatHeaderLeadingContent

            Spacer(minLength: 16)

            chatHeaderTrailingAction
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 16)
        .padding(.bottom, 24)
        .frame(maxWidth: regularContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(chatHeaderBackground)
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28)
            )
        )
        .shadow(color: Color.accentColor.opacity(0.20), radius: 14, x: 0, y: 8)
    }

    private var chatHeaderLeadingContent: some View {
        HStack(alignment: .top, spacing: 14) {
            Image("Avatar")
                .resizable()
                .scaledToFill()
                .frame(width: isRegularLayout ? 56 : 52, height: isRegularLayout ? 56 : 52)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(chatGlassBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)

            VStack(alignment: .leading, spacing: 8) {
                (Text("fin")
                    .foregroundStyle(.white)
                + Text("AI")
                    .foregroundStyle(FinAInceColor.inverseText.opacity(0.92))
                + Text("nce")
                    .foregroundStyle(.white))
                .font(.system(size: 30, weight: .bold, design: .rounded))

                Text(t("ai.emptyTitle"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)

                if !isConfigured {
                    Text(t("ai.smartAssistant"))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.80))
                }
            }

        }
    }

    private var chatHeaderTrailingAction: some View {
        Group {
            if isConfigured {
                HStack(spacing: 10) {
                    if let s = activeSettings {
                        Button { showAISettings = true } label: {
                            HStack(spacing: 6) {
                                Image(systemName: s.provider.iconName)
                                    .font(.caption2.weight(.semibold))
                                Text(s.provider.modelDisplayName(s.model))
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(.white.opacity(0.95))
                            .padding(.horizontal, 10)
                            .frame(height: 42)
                            .background(chatGlassFill)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }

                    Button { clearChat() } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                            .frame(width: 42, height: 42)
                            .background(chatGlassStrongFill)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button { showSetup = true } label: {
                    Text(t("common.configure"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(FinAInceColor.primaryActionForeground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var chatHeaderBackground: some View {
        LinearGradient(
            colors: [
                regularHeaderTopColor,
                regularHeaderBottomColor
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var inputSection: some View {
        VStack(spacing: 0) {
            if hasAttachment {
                attachmentPreview
                    .padding(.horizontal, isRegularLayout ? 24 : 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            inputBar
        }
        .animation(.easeInOut(duration: 0.2), value: hasAttachment)
        .padding(.horizontal, isRegularLayout ? 24 : 16)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: - Attachment Preview

    @ViewBuilder
    private var attachmentPreview: some View {
        if let image = attachedImage {
            HStack(spacing: 10) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(t("ai.imageAttached"))
                        .font(.caption.weight(.medium))
                    Text(isProcessingAttachment ? t("ai.ocrProcessing") : t("ai.attachReady"))
                        .font(.caption2)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer()

                Button { attachedImage = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FinAInceColor.secondaryText)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        if let name = attachedCSVName {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Text(t("ai.csvReady"))
                        .font(.caption2)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer()

                Button {
                    attachedCSVName = nil
                    attachedCSVContent = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(FinAInceColor.secondaryText)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            Button { showAttachMenu = true } label: {
                Image(systemName: hasAttachment ? "paperclip.circle.fill" : "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(hasAttachment ? Color.accentColor : FinAInceColor.secondaryText)
                    .frame(width: 42, height: 42)
                    .background(FinAInceColor.secondarySurface)
                    .clipShape(Circle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .confirmationDialog(t("ai.attachMenu"), isPresented: $showAttachMenu, titleVisibility: .visible) {
                Button(t("ai.camera")) { showCamera = true }
                Button(t("ai.gallery")) { showPhotoLibrary = true }
                Button(t("common.cancel"), role: .cancel) {}
            }

            TextField(t("ai.placeholder"), text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .finInputFieldSurface(cornerRadius: 22)
                .focused($isInputFocused)

            Button { sendMessage() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(canSend ? Color.accentColor : Color.secondary.opacity(0.35))
                    .clipShape(Circle())
                    .shadow(color: canSend ? Color.accentColor.opacity(0.22) : .clear, radius: 10, x: 0, y: 6)
            }
            .disabled(!canSend)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial)
        .background(FinAInceColor.primarySurface.opacity(0.88))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(FinAInceColor.borderStrong, lineWidth: 1)
        }
        .shadow(color: FinAInceColor.borderSubtle, radius: 16, x: 0, y: 8)
    }

    // MARK: - Subviews

    private var notConfiguredView: some View {
        ScrollView {
            VStack(spacing: 22) {
                Spacer(minLength: 28)

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.12), .blue.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 92, height: 92)
                    Image(systemName: "link")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .top, endPoint: .bottom
                        ))
                }

                VStack(spacing: 12) {
                    Text(t("chat.notConfiguredTitle"))
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(FinAInceColor.primaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(t("chat.notConfiguredSubtitle"))
                        .font(.subheadline)
                        .foregroundStyle(FinAInceColor.secondaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 360, alignment: .center)
                .padding(.horizontal, 24)

                VStack(spacing: 9) {
                    notConfiguredBenefitRow(
                        icon: "checkmark.circle",
                        title: t("chat.notConfiguredWorksTitle"),
                        body: t("chat.notConfiguredWorksBody")
                    )
                    notConfiguredBenefitRow(
                        icon: "square.and.arrow.up",
                        title: t("chat.notConfiguredExportTitle"),
                        body: t("chat.notConfiguredExportBody")
                    )
                    notConfiguredBenefitRow(
                        icon: "brain.head.profile",
                        title: t("chat.notConfiguredPowerTitle"),
                        body: t("chat.notConfiguredPowerBody")
                    )
                }
                .frame(maxWidth: 380)
                .padding(.horizontal, 20)

                Button { showAISettings = true } label: {
                    Text(t("chat.notConfiguredCTA"))
                        .font(.headline)
                        .frame(maxWidth: isRegularLayout ? 420 : .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(FinAInceColor.primaryActionForeground)
                }
                .buttonStyle(FinPrimaryButtonStyle())
                .padding(.horizontal, 28)

                Text(t("chat.notConfiguredMicrocopy"))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 320)
                    .padding(.horizontal, 24)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 24)
        }
    }

    private func notConfiguredBenefitRow(icon: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(FinAInceColor.secondaryText)
                .frame(width: 24, height: 24)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(FinAInceColor.primaryText)
                Text(body)
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(FinAInceColor.secondarySurface.opacity(0.72), in: RoundedRectangle(cornerRadius: 14))
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 0)

                if isDailyInsightLoading {
                    dailyInsightSkeletonCard
                        .padding(.horizontal)
                } else if let dailyInsight {
                    dailyInsightCard(dailyInsight)
                        .padding(.horizontal)
                }

                if isSavingsOpportunitiesLoading || !savingsOpportunities.isEmpty || !transactions.isEmpty {
                    savingsOpportunitySection
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("ai.hub.sectionTitle"))
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(FinAInceColor.primaryText)

                        Text(t("ai.hub.sectionSubtitle"))
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(analysisHubItems) { item in
                                analysisHubCard(item)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal)

                // Chips de atalho para anexos
                HStack(spacing: 8) {
                    attachShortcut(icon: "camera.fill",    label: t("ai.shortcutReceipt")) { showCamera = true }
                    attachShortcut(icon: "photo.fill",     label: t("ai.shortcutImage")) { showPhotoLibrary = true }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 10) {
                    Text(t("ai.hub.quickQuestionsTitle"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FinAInceColor.primaryText)

                    VStack(spacing: 8) {
                        ForEach(suggestedQuestions, id: \.self) { question in
                            Button {
                                inputText = question
                                sendMessage()
                            } label: {
                                Text(question)
                                    .font(.subheadline)
                                    .multilineTextAlignment(.leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(12)
                                    .background(FinAInceColor.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            .foregroundStyle(FinAInceColor.primaryText)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .task(id: dailyInsightReloadKey) {
            scheduleDailyInsightLoad()
            scheduleSavingsOpportunitiesLoad()
        }
    }

    private var dailyInsightSkeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("ai.dailyInsightTitle"))
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Text(t("dashboard.insightsLoadingTitle"))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(FinAInceColor.primaryText)
                }
            }

            Text(t("dashboard.dailyInsightLoadingSubtitle"))
                .font(.subheadline)
                .foregroundStyle(FinAInceColor.secondaryText)

            Text(t("dashboard.dailyInsightLoadingAction"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.accentColor)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FinAInceColor.secondarySurface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(FinAInceColor.borderSubtle, lineWidth: 1)
        )
    }

    private func dailyInsightCard(_ dailyInsight: DailyInsight) -> some View {
        chatSignalCard(
            icon: dailyInsight.icon,
            color: dailyInsight.color,
            badgeTitle: t("ai.signal.insightBadge"),
            title: dailyInsight.title,
            body: dailyInsight.explanation,
            detail: dailyInsight.action,
            detailColor: dailyInsight.color,
            ctaTitle: t("ai.dailyInsightCTA")
        ) {
            triggerDailyInsightConversation(dailyInsight)
        }
    }

    private func savingsOpportunityCard(_ opportunity: SavingsOpportunity) -> some View {
        chatSignalCard(
            icon: opportunity.icon,
            color: opportunity.color,
            badgeTitle: t("ai.signal.opportunityBadge"),
            title: opportunity.title,
            body: nil,
            detail: opportunity.action,
            detailColor: FinAInceColor.secondaryText,
            ctaTitle: t("ai.opportunities.cta")
        ) {
            triggerSavingsOpportunityConversation(opportunity)
        }
    }

    private func chatSignalCard(
        icon: String,
        color: Color,
        badgeTitle: String,
        title: String,
        body: String?,
        detail: String,
        detailColor: Color,
        ctaTitle: String,
        onTap: @escaping () -> Void
    ) -> some View {
        Button {
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.12))
                            .frame(width: 40, height: 40)

                        Image(systemName: icon)
                            .font(.subheadline.bold())
                            .foregroundStyle(color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(badgeTitle)
                            .font(.caption2.bold())
                            .foregroundStyle(color)
                            .textCase(.uppercase)
                            .tracking(0.5)

                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(FinAInceColor.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(color)
                }

                if let body, !body.isEmpty {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(FinAInceColor.primaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(detailColor)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.caption.bold())
                    Text(ctaTitle)
                        .font(.caption.bold())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(color)
                .clipShape(Capsule())
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        color.opacity(0.16),
                        color.opacity(0.07),
                        FinAInceColor.secondarySurface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(color.opacity(0.24), lineWidth: 1)
            )
            .shadow(color: color.opacity(0.10), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(.plain)
    }

    private var savingsOpportunitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(t("ai.opportunities.sectionTitle"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(FinAInceColor.primaryText)

                Text(t("ai.opportunities.sectionSubtitle"))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isSavingsOpportunitiesLoading {
                savingsOpportunitySkeletonCard
            } else if savingsOpportunities.isEmpty {
                savingsOpportunityEmptyStateCard
            } else {
                VStack(spacing: 10) {
                    ForEach(savingsOpportunities) { opportunity in
                        savingsOpportunityCard(opportunity)
                    }
                }
            }
        }
    }

    private var savingsOpportunitySkeletonCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.12))
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(t("ai.opportunities.loadingTitle"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FinAInceColor.primaryText)
                    Text(t("ai.opportunities.loadingSubtitle"))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.green.opacity(0.10),
                    FinAInceColor.secondarySurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.16), lineWidth: 1)
        )
    }

    private var savingsOpportunityEmptyStateCard: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.green.opacity(0.10))
                    .frame(width: 42, height: 42)

                Image(systemName: "leaf.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(t("ai.opportunities.emptyTitle"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(FinAInceColor.primaryText)

                Text(t("ai.opportunities.emptySubtitle"))
                    .font(.caption)
                    .foregroundStyle(FinAInceColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.green.opacity(0.08),
                    FinAInceColor.secondarySurface
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.green.opacity(0.14), lineWidth: 1)
        )
    }

    private func analysisHubCard(_ item: AnalysisHubItem) -> some View {
        Button {
            triggerAnalysisHubConversation(item)
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(item.color.opacity(0.16))
                            .frame(width: 42, height: 42)

                        Image(systemName: item.icon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(item.color)
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(FinAInceColor.secondaryText)
                }

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(FinAInceColor.primaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: 40, alignment: .topLeading)
                        .layoutPriority(1)

                    Text(item.subtitle)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                        .lineLimit(1)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(width: isRegularLayout ? 168 : 150, height: isRegularLayout ? 168 : 150, alignment: .topLeading)
            .background(
                LinearGradient(
                    colors: [
                        item.color.opacity(0.14),
                        FinAInceColor.secondarySurface
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: 18)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(item.color.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }


    private var chatScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(messages) { message in
                        ChatBubbleView(
                            message: message,
                            attachmentImage: sessionImages[message.id]
                        )
                        .id(message.id)

                        if let transaction = createdTransactionByMessageId[message.id] {
                            TransactionCreatedBubble(
                                transaction: transaction,
                                currencyCode: currencyCode,
                                onView: { transactionToView = transaction }
                            )
                            .id(createdTransactionId(for: message.id))
                        }

                        if pendingDeepAnalysisOfferMessageId == message.id,
                           let offer = pendingDeepAnalysisOffer {
                            DeepAnalysisOfferBubble(
                                payload: offer,
                                isPreparing: isPreparingDeepAnalysis,
                                onConfirm: { prepareDeepAnalysisPrompt() },
                                onCancel: { dismissDeepAnalysisOffer() }
                            )
                            .id("pending-deep-analysis-offer")
                        }

                        if pendingDeepAnalysisPromptMessageId == message.id,
                           let payload = pendingDeepAnalysisPrompt {
                            DeepAnalysisPromptBubble(
                                payload: payload,
                                onShare: { deepAnalysisSharePayload = payload }
                            )
                            .id("pending-deep-analysis-prompt")
                        }

                        if pendingImportStatementOfferMessageId == message.id,
                           let payload = pendingImportStatementOffer {
                            ImportStatementOfferBubble(
                                payload: payload,
                                onImport: { startStatementImport(from: payload.fileURL) },
                                onCancel: { dismissStatementImportOffer() }
                            )
                            .id("pending-import-statement-offer")
                        }

                        if messages.last?.id == message.id, !quickReplyActions.isEmpty {
                            quickReplyChips
                        }
                    }

                    if let draft = pendingDraft {
                        TransactionDraftBubble(
                            draft: draft,
                            currencyCode: currencyCode,
                            onConfirm: { approvePendingDraft() },
                            onCancel: { cancelPendingDraft() },
                            onReview: { reviewPendingDraft() }
                        )
                        .id("pending-transaction-draft")
                    }

                    if isLoading {
                        TypingIndicatorView()
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                scrollToConversationBottom(using: proxy)
            }
            .onChange(of: pendingDraft != nil) { _, _ in
                scrollToConversationBottom(using: proxy)
            }
            .onChange(of: pendingDeepAnalysisOffer != nil) { _, _ in
                scrollToConversationBottom(using: proxy)
            }
            .onChange(of: pendingDeepAnalysisPrompt != nil) { _, _ in
                scrollToConversationBottom(using: proxy)
            }
            .onChange(of: lastCreatedMessageId) { _, _ in
                scrollToConversationBottom(using: proxy)
            }
        }
    }

    private func scrollToConversationBottom(using proxy: ScrollViewProxy) {
        withAnimation {
            if pendingDraft != nil {
                proxy.scrollTo("pending-transaction-draft", anchor: .bottom)
            } else if pendingDeepAnalysisOffer != nil {
                proxy.scrollTo("pending-deep-analysis-offer", anchor: .bottom)
            } else if pendingDeepAnalysisPrompt != nil {
                proxy.scrollTo("pending-deep-analysis-prompt", anchor: .bottom)
            } else if let createdMessageId = lastCreatedMessageId {
                proxy.scrollTo(createdTransactionId(for: createdMessageId), anchor: .bottom)
            } else if let last = messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func createdTransactionId(for messageId: UUID) -> String {
        "created-transaction-\(messageId.uuidString)"
    }

    private var quickReplyChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(quickReplyActions) { action in
                    Button {
                        performQuickReply(action)
                    } label: {
                        Text(action.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(FinAInceColor.accentText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(Color.accentColor.opacity(0.10))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(Color.accentColor.opacity(0.18), lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 40)
            .padding(.trailing, 4)
        }
        .id("quick-replies")
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: - Attach Shortcut Chip

    private func attachShortcut(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption.bold())
                Text(label)
                    .font(.caption.bold())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(FinAInceColor.secondarySurface)
            .foregroundStyle(FinAInceColor.secondaryText)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send Message

    private func performQuickReply(_ action: QuickReplyAction) {
        guard !isLoading else { return }

        switch action.kind {
        case .sendText(let suggestion):
            inputText = suggestion
            sendMessage()
        case .openDeepLink(let url):
            _ = deepLinkManager.handle(url)
        }
    }

    private func assistantMessageNeedsQuickReply(_ content: String) -> Bool {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("?") else { return false }

        if trimmed.hasSuffix("?") {
            return true
        }

        let lines = trimmed
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return lines.last?.hasSuffix("?") == true
    }

    private func deepLinkQuickReplyActions(from content: String) -> [QuickReplyAction] {
        let pattern = #"\[([^\]]+)\]\((finaince://[^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        let source = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: source.length))
        var actions: [QuickReplyAction] = []
        var seenDestinations = Set<String>()

        for match in matches {
            guard match.numberOfRanges == 3 else { continue }

            let title = source.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let destination = source.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !title.isEmpty,
                  !destination.isEmpty,
                  seenDestinations.insert(destination).inserted,
                  let url = URL(string: destination) else {
                continue
            }

            actions.append(
                QuickReplyAction(
                    id: "link-\(destination)",
                    title: title,
                    kind: .openDeepLink(url)
                )
            )
        }

        return Array(actions.prefix(3))
    }

    private func sendMessage(displayTextOverride: String? = nil, aiContentOverride: String? = nil) {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard canSend, let settings = activeSettings else { return }

        // ── Build the display text (shown in the bubble) ───────────────────
        var displayContent = displayTextOverride ?? text
        if attachedImage != nil {
            displayContent = text.isEmpty ? "📷 Imagem" : "📷  \(text)"
        } else if let name = attachedCSVName {
            displayContent = text.isEmpty ? "📄 \(name)" : "📄 \(name)\n\(text)"
        }

        let userMessage = ChatMessage(role: .user, content: displayContent)
        messages.append(userMessage)
        lastCreatedMessageId = nil

        if let deepAnalysisFocus = deepAnalysisFocusForDirectRequest(from: text) {
            activeDeepAnalysisFocus = deepAnalysisFocus
            inputText = ""
            attachedImage = nil
            attachedCSVName = nil
            attachedCSVContent = nil
            prepareDeepAnalysisPrompt()
            return
        }

        // Capture attachment references before clearing
        let capturedImage  = attachedImage
        let capturedCSVName    = attachedCSVName
        let capturedCSVContent = attachedCSVContent

        // Clear inputs
        inputText        = ""
        attachedImage    = nil
        attachedCSVName  = nil
        attachedCSVContent = nil
        isLoading        = true

        Task {
            // ── Build enriched content for the AI ──────────────────────────
            var aiContent = aiContentOverride ?? text
            var imageDataForAI: Data? = nil

            if let image = capturedImage {
                // Store for bubble rendering (session-only, never persisted)
                await MainActor.run { sessionImages[userMessage.id] = image }

                // Always try OCR receipt detection first — fast, local, free
                let ocrText = await ReceiptDraftExtractionService.recognizeText(in: image)
                print("🔍 [OCR · Vision/Apple] chars=\(ocrText.count) preview=\(ocrText.prefix(120).replacingOccurrences(of: "\n", with: "↵"))")

                if !ocrText.isEmpty, let draft = await extractReceiptDraft(
                    from: ocrText,
                    settings: settings,
                    fallbackText: text,
                    receiptImageData: image.jpegData(compressionQuality: 0.85)
                ) {
                    // Receipt confirmed — show draft card without calling AI
                    print("✅ [Receipt · \(settings.provider.label)] CONFIRMED → amount=\(draft.amount) store=\(draft.placeName ?? "-") category=\(draft.categoryName ?? "-") date=\(draft.date.map { "\($0)" } ?? "nil")")
                    await MainActor.run {
                        pendingDraft = draft
                        isLoading = false
                    }
                    return
                }

                print("⛔ [Receipt] Not detected — routing image to AI as regular message")

                if settings.provider.supportsVision {
                    // Provider has native vision — send the image directly
                    // Compress to JPEG (≈60% quality keeps size ~200-400 KB for most photos)
                    imageDataForAI = image.jpegData(compressionQuality: 0.6)
                    if aiContent.trimmingCharacters(in: .whitespaces).isEmpty {
                        aiContent = t("chat.imageAnalysisPrompt")
                    }
                } else {
                    // No vision — inject OCR text as context fallback
                    if ocrText.isEmpty {
                        aiContent += "\n\n[SISTEMA: O usuário enviou uma imagem, mas não foi " +
                                     "possível extrair texto via OCR. Peça uma foto mais nítida.]"
                    } else {
                        aiContent += "\n\n[SISTEMA: O usuário enviou uma imagem. " +
                                     "Texto extraído via OCR:\n---\n\(ocrText)\n---\n" +
                                     "Ajude o usuário a entender o conteúdo.]"
                    }
                }
            }

            if let name = capturedCSVName, let csvText = capturedCSVContent {
                aiContent += "\n\n" + t("chat.csvContext", name, csvText)
            }

            if aiContent.trimmingCharacters(in: .whitespaces).isEmpty {
                aiContent = displayContent
            }

            // ── Build messages array for AI (last msg has enriched content) ─
            let enrichedMsg = ChatMessage(role: .user, content: aiContent)
            let aiMessages  = Array(messages.dropLast()) + [enrichedMsg]

            do {
                let result = try await AIService.send(
                    messages:     aiMessages,
                    settings:     settings,
                    transactions: Array(transactions),
                    goals:        Array(goals),
                    accounts:     Array(accounts),
                    categories:   Array(categories),
                    projects:     Array(costCenters),
                    families:     Array(families),
                    userProfile:   .init(
                        name: userName,
                        adultsCount: adultsCount,
                        childrenCount: childrenCount
                    ),
                    currencyCode: currencyCode,
                    imageData:    imageDataForAI
                )
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: result.content))
                    if let draft = result.transactionDraft {
                        pendingDraft = normalizedDraft(draft)
                    }
                    maybeOfferDeepAnalysis()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: chatFallbackMessage(for: error)
                    ))
                    maybeOfferDeepAnalysis()
                    isLoading = false
                }
            }
        }
    }

    private func triggerDailyInsightConversation(_ dailyInsight: DailyInsight) {
        guard isConfigured else {
            showAISettings = true
            return
        }

        activeDeepAnalysisFocus = dailyInsight.title
        activeShouldOfferDeepAnalysis = true
        let userFacingText = t("ai.dailyInsightUserMessage", dailyInsight.title)
        inputText = userFacingText
        sendMessage(
            displayTextOverride: userFacingText,
            aiContentOverride: dailyInsight.chatPrompt
        )
    }

    private func triggerAnalysisHubConversation(_ item: AnalysisHubItem) {
        guard isConfigured else {
            showAISettings = true
            return
        }

        activeDeepAnalysisFocus = item.deepFocus
        activeShouldOfferDeepAnalysis = true
        inputText = item.prompt
        sendMessage()
    }

    private func triggerSavingsOpportunityConversation(_ opportunity: SavingsOpportunity) {
        guard isConfigured else {
            showAISettings = true
            return
        }

        activeDeepAnalysisFocus = opportunity.title
        activeShouldOfferDeepAnalysis = true
        let userFacingText = t("ai.opportunities.userMessage", opportunity.categoryName)
        inputText = userFacingText
        sendMessage(
            displayTextOverride: userFacingText,
            aiContentOverride: opportunity.chatPrompt
        )
    }

    @MainActor
    private func scheduleDailyInsightLoad() {
        let token = UUID()
        dailyInsightLoadToken = token
        isDailyInsightLoading = true
        dailyInsight = nil

        let scopedTransactions = Array(transactions)
        let scopedAccounts = Array(accounts)
        let scopedGoals = Array(goals)
        let scopedCurrencyCode = currencyCode

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            guard token == dailyInsightLoadToken else { return }

            let now = Date()
            let month = Calendar.current.component(.month, from: now)
            let year = Calendar.current.component(.year, from: now)
            let insight = InsightEngine.computeDailyInsight(
                transactions: scopedTransactions,
                accounts: scopedAccounts,
                goals: scopedGoals,
                month: month,
                year: year,
                currencyCode: scopedCurrencyCode
            )

            guard token == dailyInsightLoadToken else { return }
            dailyInsight = insight
            isDailyInsightLoading = false
        }
    }

    @MainActor
    private func scheduleSavingsOpportunitiesLoad() {
        let token = UUID()
        savingsOpportunityLoadToken = token
        isSavingsOpportunitiesLoading = true
        savingsOpportunities = []

        let scopedTransactions = Array(transactions)
        let scopedCurrencyCode = currencyCode

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            guard token == savingsOpportunityLoadToken else { return }

            let now = Date()
            let month = Calendar.current.component(.month, from: now)
            let year = Calendar.current.component(.year, from: now)
            let opportunities = SavingsOpportunityService.computeOpportunities(
                transactions: scopedTransactions,
                month: month,
                year: year,
                currencyCode: scopedCurrencyCode,
                maximumCount: 2,
                now: now
            )

            guard token == savingsOpportunityLoadToken else { return }
            savingsOpportunities = opportunities
            isSavingsOpportunitiesLoading = false
        }
    }

    private func chatFallbackMessage(for error: Error) -> String {
        if isAILimitError(error) {
            return "O seu provedor de IA informou que você atingiu o seu limite de uso da IA neste momento, por favor, tente mais tarde."
        }

        if isAIConnectionError(error) {
            return "O seu provedor de IA está fora do ar neste momento, por favor, tente mais tarde."
        }

        return "Desculpe, não consegui processar seu pedido. Por favor, tente novamente."
    }

    private func isAILimitError(_ error: Error) -> Bool {
        let message = normalizedErrorMessage(error)
        let limitIndicators = [
            "rate limit",
            "rate_limit",
            "quota",
            "insufficient_quota",
            "resource_exhausted",
            "too many requests",
            "tokens",
            "token limit",
            "context length",
            "context_length",
            "maximum context",
            "usage limit"
        ]

        return limitIndicators.contains { message.contains($0) }
    }

    private func isAIConnectionError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return connectionErrorCodes.contains(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            return connectionErrorCodes.contains(code)
        }

        let message = normalizedErrorMessage(error)
        let connectionIndicators = [
            "status 500",
            "status 502",
            "status 503",
            "status 504",
            "server error",
            "service unavailable",
            "temporarily unavailable",
            "overloaded",
            "timeout",
            "timed out",
            "network",
            "connection",
            "cannot connect",
            "could not connect",
            "dns"
        ]

        return connectionIndicators.contains { message.contains($0) }
    }

    private var connectionErrorCodes: Set<URLError.Code> {
        [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .networkConnectionLost,
            .dnsLookupFailed,
            .notConnectedToInternet,
            .secureConnectionFailed,
            .cannotLoadFromNetwork
        ]
    }

    private func normalizedErrorMessage(_ error: Error) -> String {
        let nsError = error as NSError
        return [
            error.localizedDescription,
            nsError.localizedFailureReason,
            nsError.localizedRecoverySuggestion
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .lowercased()
    }

    private func clearChat() {
        messages     = []
        inputText    = ""
        pendingDraft = nil
        pendingDeepAnalysisOffer = nil
        pendingDeepAnalysisPrompt = nil
        pendingImportStatementOffer = nil
        pendingDeepAnalysisOfferMessageId = nil
        pendingDeepAnalysisPromptMessageId = nil
        pendingImportStatementOfferMessageId = nil
        createdTransactionByMessageId = [:]
        lastCreatedMessageId = nil
        transactionToView = nil
        attachedImage    = nil
        attachedCSVName  = nil
        attachedCSVContent = nil
        sessionImages    = [:]
        deepAnalysisOfferShown = false
        deepAnalysisSharePayload = nil
    }

    private func maybeOfferDeepAnalysis() {
        guard activeShouldOfferDeepAnalysis,
              !deepAnalysisOfferShown,
              activeDeepAnalysisFocus != nil else { return }

        deepAnalysisOfferShown = true
        pendingDeepAnalysisOffer = DeepAnalysisOfferPayload(
            title: t("chat.deepAnalysis.offerTitle"),
            subtitle: t("chat.deepAnalysis.offerSubtitle")
        )
        pendingDeepAnalysisOfferMessageId = messages.last?.id
    }

    private func prepareDeepAnalysisPrompt() {
        guard let focus = activeDeepAnalysisFocus, !isPreparingDeepAnalysis else { return }

        isPreparingDeepAnalysis = true

        Task {
            let startTime = Date()
            let month = Calendar.current.component(.month, from: Date())
            let year = Calendar.current.component(.year, from: Date())
            let prompt = AnalysisPromptBuilder.buildDeepAnalysisPrompt(
                transactions: Array(transactions),
                accounts: Array(accounts),
                goals: Array(goals),
                month: month,
                year: year,
                currencyCode: currencyCode,
                focus: focus
            )

            let result: Result<URL, Error>
            do {
                let fileURL = try FinancialAnalysisExporter.writeAnalysisFile(
                    text: prompt,
                    selectedMonth: month,
                    selectedYear: year
                )
                result = .success(fileURL)
            } catch {
                result = .failure(error)
            }

            let elapsed = Date().timeIntervalSince(startTime)
            let remainingDelay = max(0, 2.0 - elapsed)
            if remainingDelay > 0 {
                try? await Task.sleep(for: .seconds(remainingDelay))
            }

            await MainActor.run {
                isPreparingDeepAnalysis = false

                switch result {
                case .success(let fileURL):
                    let shareButtonTitle = t("transaction.aiAnalysisButton")
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: t("chat.deepAnalysis.readyMessage", shareButtonTitle)
                    )
                    messages.append(assistantMessage)
                    pendingDeepAnalysisPrompt = DeepAnalysisSharePayload(
                        title: t("chat.deepAnalysis.readyTitle"),
                        subtitle: t("chat.deepAnalysis.readySubtitle"),
                        fileURL: fileURL
                    )
                    pendingDeepAnalysisPromptMessageId = assistantMessage.id
                    pendingDeepAnalysisOffer = nil
                    pendingDeepAnalysisOfferMessageId = nil
                case .failure:
                    pendingDeepAnalysisOffer = nil
                    pendingDeepAnalysisOfferMessageId = nil
                    messages.append(
                        ChatMessage(
                            role: .assistant,
                            content: t("chat.deepAnalysis.error")
                        )
                    )
                }
            }
        }
    }

    private func dismissDeepAnalysisOffer() {
        pendingDeepAnalysisOffer = nil
        pendingDeepAnalysisOfferMessageId = nil
        messages.append(
            ChatMessage(
                role: .assistant,
                content: t("chat.deepAnalysis.dismissed")
            )
        )
    }

    private func deepAnalysisFocusForDirectRequest(from text: String) -> String? {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        guard !normalized.isEmpty else { return nil }

        let directRequests = [
            "gerar relatorio",
            "gere relatorio",
            "gere um relatorio",
            "gera relatorio",
            "quero o relatorio",
            "fazer relatorio",
            "analise profunda",
            "analise detalhada",
            "quero a analise",
            "gerar analise",
            "gere uma analise",
            "ver com minha ia",
            "analisar com minha ia",
            "analise com minha ia",
            "para minha ia",
            "pra minha ia",
            "generate report",
            "generate a report",
            "create report",
            "create a report",
            "build report",
            "build a report",
            "deep analysis",
            "detailed analysis",
            "analyze with my ai",
            "analyse with my ai",
            "for my ai",
            "send to my ai",
            "report for my ai",
            "generate analysis",
            "generate an analysis",
            "generar informe",
            "generar un informe",
            "crear informe",
            "crear un informe",
            "analisis profundo",
            "analisis detallado",
            "analizar con mi ia",
            "analisis con mi ia",
            "para mi ia",
            "informe para mi ia",
            "generar analisis"
        ]

        guard directRequests.contains(where: { normalized.contains($0) }) else { return nil }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractReceiptDraft(
        from ocrText: String,
        settings: AISettings,
        fallbackText: String,
        receiptImageData: Data?
    ) async -> TransactionDraft? {
        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        return await ReceiptDraftExtractionService.extractDraft(
            from: ocrText,
            settings: settings,
            categories: Array(categories),
            accounts: allAccounts,
            fallbackText: fallbackText,
            receiptImageData: receiptImageData
        )
    }

    // MARK: - Review Draft (opens Step4DetailsView pre-filled)

    private func reviewPendingDraft() {
        guard let draft = pendingDraft else { return }
        reviewState = IdentifiableNewTransactionState(state: buildNewTransactionState(from: normalizedDraft(draft)))
    }

    private func buildNewTransactionState(from draft: TransactionDraft) -> NewTransactionState {
        let state = NewTransactionState()
        state.amount    = draft.amount
        state.type      = .expense
        state.placeName = draft.placeName
        state.notes     = draft.notes
        state.date      = draft.date ?? Date()

        // Resolve category
        state.category = resolvedCategory(for: draft)

        // Resolve account
        state.account = resolvedAccount(for: draft)

        // Attach receipt image if available
        if let data = draft.receiptImageData,
           let image = UIImage(data: data),
           let attachment = try? ReceiptAttachmentStore.createDraft(from: image) {
            state.receiptDrafts = [attachment]
        }

        return state
    }

    private func saveReviewedTransaction(_ state: NewTransactionState) {
        reviewState = nil
        pendingDraft = nil

        let tx = Transaction(
            type:      state.type,
            amount:    state.amount,
            date:      state.date,
            placeName: state.placeName.isEmpty ? nil : state.placeName,
            notes:     state.notes.isEmpty     ? nil : state.notes,
            isPaid:    state.isPaid
        )
        tx.category = state.category
        tx.account  = state.account
        modelContext.insert(tx)
        _ = try? ReceiptAttachmentStore.persistDrafts(state.receiptDrafts, to: tx, in: modelContext)

        let confirmationMessage = ChatMessage(role: .user, content: t("common.register"))
        messages.append(confirmationMessage)
        createdTransactionByMessageId[confirmationMessage.id] = tx
        lastCreatedMessageId = confirmationMessage.id
        print("✅ [Receipt · Review] CONFIRMED → \(tx.amount) @ \(tx.placeName ?? "-")")
    }

    // MARK: - Confirm Transaction

    private func approvePendingDraft() {
        guard let draft = pendingDraft else { return }
        pendingDraft = nil
        let confirmationMessage = ChatMessage(role: .user, content: "Registrar")
        messages.append(confirmationMessage)
        createdTransactionByMessageId[confirmationMessage.id] = confirmTransaction(draft)
        lastCreatedMessageId = confirmationMessage.id
    }

    private func cancelPendingDraft() {
        pendingDraft = nil
        lastCreatedMessageId = nil
        messages.append(ChatMessage(role: .user, content: "Cancelar"))
        messages.append(ChatMessage(
            role: .assistant,
            content: "Registro cancelado. Pode enviar outro recibo ou me dizer os dados da despesa."
        ))
    }

    private func confirmTransaction(_ draft: TransactionDraft) -> Transaction {
        let normalized = normalizedDraft(draft)

        // ── Resolve category ──────────────────────────────────────────────
        let category = resolvedCategory(for: normalized)

        // ── Resolve account (by name from draft, fallback to default) ─────
        let account = resolvedAccount(for: normalized)

        // ── Create transaction ────────────────────────────────────────────
        let tx = Transaction(
            type:      .expense,
            amount:    normalized.amount,
            date:      normalized.date ?? Date(),
            placeName: normalized.placeName.isEmpty ? nil : normalized.placeName,
            notes:     normalized.notes.isEmpty     ? nil : normalized.notes
        )
        tx.category = category
        tx.account  = account
        modelContext.insert(tx)
        if let data = normalized.receiptImageData,
           let image = UIImage(data: data) {
            _ = try? ReceiptAttachmentStore.addImage(image, to: tx, in: modelContext)
        }

        return tx
    }

    private func normalizedDraft(_ draft: TransactionDraft) -> TransactionDraft {
        let allCategories = Array(categories)
        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        return TransactionDraftResolutionService.normalizeDraft(
            draft,
            categories: allCategories,
            accounts: allAccounts
        )
    }

    private func resolvedCategory(for draft: TransactionDraft) -> Category? {
        TransactionDraftResolutionService.resolvedCategory(for: draft, in: Array(categories))
    }

    private func resolvedAccount(for draft: TransactionDraft) -> Account? {
        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        return TransactionDraftResolutionService.resolvedAccount(for: draft, in: allAccounts)
    }

    // MARK: - OCR Helper

    // MARK: - Statement Import Routing

    @discardableResult
    private func handleStatementFileSelection(_ url: URL) -> Bool {
        guard isStatementImportCandidate(url) else { return false }

        attachedCSVName = nil
        attachedCSVContent = nil

        let assistantMessage = ChatMessage(
            role: .assistant,
            content: t("chat.importStatement.receivedMessage", url.lastPathComponent)
        )
        messages.append(assistantMessage)
        pendingImportStatementOffer = ImportStatementOfferPayload(
            title: t("chat.importStatement.offerTitle"),
            subtitle: t("chat.importStatement.offerSubtitle", url.lastPathComponent),
            fileURL: url
        )
        pendingImportStatementOfferMessageId = assistantMessage.id
        return true
    }

    private func startStatementImport(from url: URL) {
        importManager.pendingFile = SharedImportFile(url: url)
        pendingImportStatementOffer = nil
        pendingImportStatementOfferMessageId = nil
    }

    private func dismissStatementImportOffer() {
        pendingImportStatementOffer = nil
        pendingImportStatementOfferMessageId = nil
    }

    private func isStatementImportCandidate(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        return ["csv", "tsv", "txt", "xlsx", "xls", "ofx"].contains(pathExtension)
    }
}

// MARK: - Identifiable wrapper for NewTransactionState (used by .sheet(item:))

final class IdentifiableNewTransactionState: Identifiable {
    let id = UUID()
    let state: NewTransactionState
    init(state: NewTransactionState) { self.state = state }
}

// MARK: - Transaction Draft Bubble

struct TransactionDraftBubble: View {
    let draft: TransactionDraft
    let currencyCode: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    let onReview: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("ai.draftFoundExpense"))
                            .font(.subheadline.weight(.semibold))
                        Text(t("ai.draftReview"))
                            .font(.caption)
                            .foregroundStyle(FinAInceColor.secondaryText)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        draftRow(icon: "banknote.fill", color: .green, label: t("transaction.amount"), value: draft.amount.asCurrency(currencyCode))
                        draftRow(icon: "mappin.circle.fill", color: .red, label: t("transaction.place"), value: draft.placeName.isEmpty ? t("transaction.noPlace") : draft.placeName)
                        draftRow(icon: "tag.fill", color: .blue, label: t("transaction.category"), value: draft.categoryName)
                        if let date = draft.date {
                            draftRow(icon: "calendar", color: .orange, label: t("transaction.date"), value: date.formatted(.dateTime.day().month(.abbreviated).year()))
                        }
                        draftRow(
                            icon: "creditcard.fill",
                            color: .purple,
                            label: t("transaction.account"),
                            value: draft.accountName.isEmpty ? "—" : draft.accountName
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .finInsetSurface(cornerRadius: 8)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .finSecondarySurface(cornerRadius: 14)

                HStack(spacing: 8) {
                    QuickReplyButton(title: t("common.register"), icon: "checkmark", style: .confirm, action: onConfirm)
                    QuickReplyButton(title: t("ai.draftReviewAction"), icon: "pencil", style: .primary, action: onReview)
                    QuickReplyButton(title: t("common.cancel"), icon: "xmark", style: .cancel, action: onCancel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func draftRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(label)
                .font(.caption)
                .foregroundStyle(FinAInceColor.secondaryText)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.subheadline.weight(.medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TransactionCreatedBubble: View {
    let transaction: Transaction
    let currencyCode: String
    let onView: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("ai.expenseRegistered"))
                        .font(.subheadline.weight(.semibold))
                    Text(t("ai.expenseRegisteredDetail", transaction.amount.asCurrency(currencyCode), transaction.placeName ?? transaction.category?.displayName ?? t("transaction.noPlace")))
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .finSecondarySurface(cornerRadius: 14)

                QuickReplyButton(
                    title: t("ai.viewTransaction"),
                    icon: "arrow.right.circle",
                    style: .primary,
                    action: onView
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct DeepAnalysisSharePayload: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let fileURL: URL
}

private struct DeepAnalysisOfferPayload: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
}

private struct ImportStatementOfferPayload: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let fileURL: URL
}

private struct DeepAnalysisOfferBubble: View {
    let payload: DeepAnalysisOfferPayload
    let isPreparing: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(payload.title)
                        .font(.subheadline.weight(.semibold))
                    Text(payload.subtitle)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .finSecondarySurface(cornerRadius: 14)

                HStack(spacing: 8) {
                    QuickReplyButton(
                        title: isPreparing ? t("chat.deepAnalysis.generating") : t("chat.deepAnalysis.generateButton"),
                        icon: "sparkles",
                        style: .primary,
                        isLoading: isPreparing,
                        action: onConfirm
                    )
                    QuickReplyButton(
                        title: t("chat.deepAnalysis.notNow"),
                        icon: "xmark",
                        style: .cancel,
                        isDisabled: isPreparing,
                        action: onCancel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct DeepAnalysisPromptBubble: View {
    let payload: DeepAnalysisSharePayload
    let onShare: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(payload.title)
                                .font(.subheadline.weight(.semibold))
                            Text(payload.fileURL.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(FinAInceColor.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Text(payload.subtitle)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(
                        colors: [
                            Color.accentColor.opacity(0.10),
                            Color.purple.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.accentColor.opacity(0.15), lineWidth: 1)
                )

                QuickReplyButton(
                    title: t("transaction.aiAnalysisButton"),
                    icon: "square.and.arrow.up",
                    style: .primary,
                    action: onShare
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct ImportStatementOfferBubble: View {
    let payload: ImportStatementOfferPayload
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.text.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.blue)
                            .clipShape(RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(payload.title)
                                .font(.subheadline.weight(.semibold))
                            Text(payload.fileURL.lastPathComponent)
                                .font(.caption2)
                                .foregroundStyle(FinAInceColor.secondaryText)
                                .lineLimit(1)
                        }
                    }

                    Text(payload.subtitle)
                        .font(.caption)
                        .foregroundStyle(FinAInceColor.secondaryText)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .finSecondarySurface(cornerRadius: 14)

                HStack(spacing: 8) {
                    QuickReplyButton(
                        title: t("chat.importStatement.importButton"),
                        icon: "square.and.arrow.down",
                        style: .primary,
                        action: onImport
                    )
                    QuickReplyButton(
                        title: t("chat.importStatement.notNow"),
                        icon: "xmark",
                        style: .cancel,
                        action: onCancel
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 32)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

private struct DeepAnalysisShareSheet: UIViewControllerRepresentable {
    let payload: DeepAnalysisSharePayload

    func makeUIViewController(context: Context) -> UIActivityViewController {

        return UIActivityViewController(
            activityItems: [payload.fileURL],
            applicationActivities: nil
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private final class ShareTextItemSource: NSObject, UIActivityItemSource {
    private let message: String

    init(message: String) {
        self.message = message
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        itemForActivityType activityType: UIActivity.ActivityType?
    ) -> Any? {
        message
    }

    func activityViewController(
        _ activityViewController: UIActivityViewController,
        subjectForActivityType activityType: UIActivity.ActivityType?
    ) -> String {
        message
    }

    func activityViewControllerLinkMetadata(_ activityViewController: UIActivityViewController) -> LPLinkMetadata? {
        let metadata = LPLinkMetadata()
        metadata.title = message
        return metadata
    }
}

private struct QuickReplyButton: View {
    let title: String
    let icon: String
    let style: QuickReplyStyle
    var isLoading: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(style.foregroundColor)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                }

                Text(title)
            }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(style.backgroundColor)
                .foregroundStyle(style.foregroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(color: style.backgroundColor.opacity(0.18), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(isLoading || isDisabled)
        .opacity((isLoading || isDisabled) ? 0.85 : 1)
    }
}

private enum QuickReplyStyle {
    case confirm
    case cancel
    case primary

    var backgroundColor: Color {
        switch self {
        case .confirm:
            return .green
        case .cancel:
            return .red
        case .primary:
            return .accentColor
        }
    }

    var foregroundColor: Color {
        .white
    }
}

// MARK: - Chat Bubble

struct ChatBubbleView: View {
    let message: ChatMessage
    var attachmentImage: UIImage? = nil

    var isUser: Bool { message.role == .user }

    /// True when the content is just an auto-generated placeholder for an image attachment
    private var isImagePlaceholder: Bool {
        message.content == "📷 Imagem" || message.content.hasPrefix("📷  ")
    }

    private var renderedContent: AttributedString {
        (try? AttributedString(
            markdown: message.content,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(message.content)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isUser { Spacer(minLength: 60) }

            if !isUser {
                Image(systemName: "sparkles.square.filled.on.square")
                    .font(.title3)
                    .foregroundStyle(.purple)
                    .frame(width: 32, height: 32)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                // Image thumbnail (session-only — not persisted)
                if let img = attachmentImage {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: 220)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color(.systemGray5), lineWidth: 1)
                        )
                }

                // Text bubble (hidden when image covers everything)
                if attachmentImage == nil || !isImagePlaceholder {
                    Text(renderedContent)
                        .font(.subheadline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.accentColor : FinAInceColor.secondarySurface)
                        .foregroundStyle(isUser ? FinAInceColor.inverseText : FinAInceColor.primaryText)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}

private struct PressedCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animate = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "sparkles.square.filled.on.square")
                .font(.title3)
                .foregroundStyle(.purple)
                .frame(width: 32, height: 32)

            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animate ? 1.2 : 0.8)
                        .animation(
                            .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                            value: animate
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(FinAInceColor.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
        .onAppear { animate = true }
    }
}
