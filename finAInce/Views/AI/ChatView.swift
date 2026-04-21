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
    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query private var goals: [Goal]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var aiSettings: [AISettings]
    @AppStorage("app.currencyCode") private var currencyCode = "BRL"
    @State private var chatNavigationManager = ChatNavigationManager.shared

    // ── Chat state ──────────────────────────────────────────────────────────
    @State private var inputText         = ""
    @State private var messages: [ChatMessage] = []
    @State private var isLoading         = false
    @State private var conversation: ChatConversation?
    @State private var showSetup         = false
    @State private var showAISettings    = false
    @State private var pendingDraft: TransactionDraft? = nil
    @State private var pendingDeepAnalysisOffer: DeepAnalysisOfferPayload? = nil
    @State private var pendingDeepAnalysisPrompt: DeepAnalysisSharePayload? = nil
    @State private var pendingDeepAnalysisOfferMessageId: UUID? = nil
    @State private var pendingDeepAnalysisPromptMessageId: UUID? = nil
    @State private var createdTransactionByMessageId: [UUID: Transaction] = [:]
    @State private var lastCreatedMessageId: UUID? = nil
    @State private var transactionToView: Transaction? = nil
    @FocusState private var isInputFocused: Bool
    @State private var deepAnalysisOfferShown = false
    @State private var deepAnalysisSharePayload: DeepAnalysisSharePayload? = nil
    @State private var isPreparingDeepAnalysis = false

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
    private var isConfigured: Bool { aiSettings.first?.isConfigured == true }
    private var activeSettings: AISettings? { aiSettings.first }
    private var hasAttachment: Bool { attachedImage != nil || attachedCSVName != nil }
    private var canSend: Bool {
        (!inputText.trimmingCharacters(in: .whitespaces).isEmpty || hasAttachment) && !isLoading
    }

    private var suggestedQuestions: [String] {
        [
            t("ai.suggest1"),
            t("ai.suggest2"),
            t("ai.suggest3"),
            t("ai.suggest4"),
            t("ai.suggest5")
        ]
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { dismissKeyboard() }
                )

                if isConfigured { inputSection }
            }
            .animation(.spring(duration: 0.3), value: pendingDraft != nil)
            .safeAreaInset(edge: .top, spacing: 0) {
                chatHeaderCard
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                let manager = SharedImportManager.shared

                // Image shared via the Share Extension → attach and auto-send
                if let sharedImage = manager.pendingSharedImage {
                    attachedImage = sharedImage
                    manager.clearPendingSharedImage()
                    // Give the view a moment to settle, then send automatically
                    if isConfigured {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            sendMessage()
                        }
                    }
                    return  // skip initialPrompt when handling shared image
                }

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
                allowedContentTypes: [.commaSeparatedText, .text, .plainText],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    loadCSV(from: url)
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

    // MARK: - Header Card (Profile-style)

    private var chatHeaderCard: some View {
        HStack(alignment: .center, spacing: 14) {

            // ── AI icon ───────────────────────────────────────────────────
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.55, green: 0.20, blue: 0.95),
                                Color(red: 0.40, green: 0.10, blue: 0.80)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 52, height: 52)
                Image(systemName: "sparkles")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(red: 0.45, green: 0.10, blue: 0.85).opacity(0.35),
                    radius: 8, x: 0, y: 4)

            // ── Title + provider ──────────────────────────────────────────
            VStack(alignment: .leading, spacing: 3) {
                (Text("fin")
                    .foregroundStyle(.primary)
                + Text("AI")
                    .foregroundStyle(Color(red: 0.55, green: 0.20, blue: 0.95))
                + Text("nce")
                    .foregroundStyle(.primary))
                .font(.largeTitle.weight(.bold))

                if isConfigured, let s = activeSettings {
                    Button { showAISettings = true } label: {
                        HStack(spacing: 5) {
                            Image(systemName: s.provider.iconName)
                                .font(.caption2.weight(.semibold))
                            Text(s.provider.modelDisplayName(s.model))
                                .font(.caption)
                        }
                        .foregroundStyle(s.provider.accentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(s.provider.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(t("ai.smartAssistant"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // ── Actions ───────────────────────────────────────────────────
            if isConfigured {
                Button { clearChat() } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color(red: 0.50, green: 0.15, blue: 0.90))
                        .frame(width: 38, height: 38)
                        .background(Color(red: 0.50, green: 0.15, blue: 0.90).opacity(0.10))
                        .clipShape(Circle())
                }
            } else {
                Button { showSetup = true } label: {
                    Text(t("common.configure"))
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.55, green: 0.20, blue: 0.95),
                                    Color(red: 0.40, green: 0.10, blue: 0.80)
                                ],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .background {
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24)
            )
            .fill(Color(.systemBackground))
            .ignoresSafeArea(edges: .top)
        }
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }

    private var inputSection: some View {
        VStack(spacing: 0) {
            // Preview do anexo (mostrado acima da barra de texto)
            if hasAttachment {
                attachmentPreview
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            inputBar
        }
        .animation(.easeInOut(duration: 0.2), value: hasAttachment)
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
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button { attachedImage = nil } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
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
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    attachedCSVName = nil
                    attachedCSVContent = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding(10)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 10) {
            // Botão de anexo
            Button { showAttachMenu = true } label: {
                Image(systemName: hasAttachment ? "paperclip.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(hasAttachment ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .confirmationDialog(t("ai.attachMenu"), isPresented: $showAttachMenu, titleVisibility: .visible) {
                Button(t("ai.camera")) { showCamera = true }
                Button(t("ai.gallery")) { showPhotoLibrary = true }
                Button(t("ai.csv")) { showCSVPicker = true }
                Button(t("common.cancel"), role: .cancel) {}
            }

            // Campo de texto
            TextField(t("ai.placeholder"), text: $inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .focused($isInputFocused)

            // Botão enviar
            Button { sendMessage() } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title2)
            }
            .disabled(!canSend)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(.bar)
    }

    // MARK: - Subviews

    private var notConfiguredView: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 48)

                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.purple.opacity(0.12), .blue.opacity(0.12)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ))
                        .frame(width: 100, height: 100)
                    Image(systemName: "brain")
                        .font(.system(size: 44))
                        .foregroundStyle(LinearGradient(
                            colors: [.purple, .blue],
                            startPoint: .top, endPoint: .bottom
                        ))
                }

                VStack(spacing: 8) {
                    Text(t("ai.setupTitle"))
                        .font(.title2.bold())
                        .multilineTextAlignment(.center)
                    Text(t("ai.setupDesc"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: 340, alignment: .center)
                .padding(.horizontal, 28)

                Button { showSetup = true } label: {
                    Label(t("ai.configureButton"), systemImage: "key.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var suggestionsView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                VStack(spacing: 6) {
                    Text(t("ai.emptyTitle"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.center)
                    Text(t("ai.emptyDesc"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal)

                // Chips de atalho para anexos
                HStack(spacing: 8) {
                    attachShortcut(icon: "camera.fill",    label: t("ai.shortcutReceipt")) { showCamera = true }
                    attachShortcut(icon: "doc.text.fill",  label: t("ai.shortcutCSV")) { showCSVPicker = true }
                    attachShortcut(icon: "photo.fill",     label: t("ai.shortcutImage")) { showPhotoLibrary = true }
                }
                .padding(.horizontal)

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
                                .background(Color(.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal)
            }
        }
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
                    }

                    if let draft = pendingDraft {
                        TransactionDraftBubble(
                            draft: draft,
                            currencyCode: currencyCode,
                            onConfirm: { approvePendingDraft() },
                            onCancel: { cancelPendingDraft() }
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
            .background(Color(.secondarySystemBackground))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Send Message

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard canSend, let settings = aiSettings.first else { return }

        // ── Build the display text (shown in the bubble) ───────────────────
        var displayContent = text
        if attachedImage != nil {
            displayContent = text.isEmpty ? "📷 Imagem" : "📷  \(text)"
        } else if let name = attachedCSVName {
            displayContent = text.isEmpty ? "📄 \(name)" : "📄 \(name)\n\(text)"
        }

        let userMessage = ChatMessage(role: .user, content: displayContent)
        messages.append(userMessage)
        lastCreatedMessageId = nil

        if shouldGenerateDeepAnalysisDirectly(from: text) {
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
            var aiContent = text
            var imageDataForAI: Data? = nil

            if let image = capturedImage {
                // Store for bubble rendering (session-only, never persisted)
                await MainActor.run { sessionImages[userMessage.id] = image }

                // Always try OCR receipt detection first — fast, local, free
                let ocrText = await recognizeText(in: image)
                if !ocrText.isEmpty, let draft = await extractReceiptDraft(
                    from: ocrText,
                    settings: settings,
                    fallbackText: text,
                    receiptImageData: image.jpegData(compressionQuality: 0.85)
                ) {
                    // Receipt confirmed — show draft card without calling AI
                    await MainActor.run { pendingDraft = draft; isLoading = false }
                    return
                }

                if settings.provider.supportsVision {
                    // Provider has native vision — send the image directly
                    // Compress to JPEG (≈60% quality keeps size ~200-400 KB for most photos)
                    imageDataForAI = image.jpegData(compressionQuality: 0.6)
                    if aiContent.trimmingCharacters(in: .whitespaces).isEmpty {
                        aiContent = "Analise esta imagem. Se for um recibo ou comprovante, " +
                                    "descreva o estabelecimento, valor total, data e itens principais."
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
                aiContent += "\n\n[Contexto: o usuário enviou o arquivo CSV \"\(name)\". " +
                             "Dados (até 50 linhas):\n---\n\(csvText)\n---\n" +
                             "Analise as colunas disponíveis e ajude o usuário a entender " +
                             "ou importar as transações.]"
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
                    currencyCode: currencyCode,
                    imageData:    imageDataForAI
                )
                await MainActor.run {
                    messages.append(ChatMessage(role: .assistant, content: result.content))
                    if let draft = result.transactionDraft {
                        pendingDraft = draft
                    }
                    maybeOfferDeepAnalysis()
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(ChatMessage(
                        role: .assistant,
                        content: "⚠️ \(error.localizedDescription)"
                    ))
                    maybeOfferDeepAnalysis()
                    isLoading = false
                }
            }
        }
    }

    private func clearChat() {
        messages     = []
        inputText    = ""
        pendingDraft = nil
        pendingDeepAnalysisOffer = nil
        pendingDeepAnalysisPrompt = nil
        pendingDeepAnalysisOfferMessageId = nil
        pendingDeepAnalysisPromptMessageId = nil
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

    private func shouldGenerateDeepAnalysisDirectly(from text: String) -> Bool {
        guard activeShouldOfferDeepAnalysis, activeDeepAnalysisFocus != nil else { return false }

        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        guard !normalized.isEmpty else { return false }

        let directRequests = [
            "gerar relatorio",
            "gera relatorio",
            "quero o relatorio",
            "fazer relatorio",
            "analise profunda",
            "analise detalhada",
            "quero a analise",
            "gerar analise",
            "minha ia",
            "ver com minha ia"
        ]

        return directRequests.contains { normalized.contains($0) }
    }

    private func extractReceiptDraft(
        from ocrText: String,
        settings: AISettings,
        fallbackText: String,
        receiptImageData: Data?
    ) async -> TransactionDraft? {
        let categoryNames = categories.map(\.name)
        guard let receipt = try? await AIService.analyzeReceipt(
            ocrText: ocrText,
            settings: settings,
            categoryNames: categoryNames
        ), receipt.amount > 0 else {
            return nil
        }

        let categoryName = receipt.suggestedCategoryName.isEmpty
            ? "Comércio"
            : receipt.suggestedCategoryName
        let notes = receipt.notes.isEmpty ? fallbackText : receipt.notes

        return TransactionDraft(
            amount: receipt.amount,
            typeRaw: TransactionType.expense.rawValue,
            categoryName: categoryName,
            placeName: receipt.storeName,
            notes: notes,
            date: receipt.date,
            accountName: "",
            receiptImageData: receiptImageData
        )
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
        // ── Resolve category ──────────────────────────────────────────────
        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
        let category = allCategories.first {
            $0.name.localizedCaseInsensitiveCompare(draft.categoryName) == .orderedSame
        } ?? allCategories.first {
            $0.name.localizedCaseInsensitiveContains(draft.categoryName)
        }

        // ── Resolve account (by name from draft, fallback to default) ─────
        let allAccounts = (try? modelContext.fetch(FetchDescriptor<Account>())) ?? []
        let account: Account?
        if draft.accountName.isEmpty {
            account = allAccounts.first(where: \.isDefault) ?? allAccounts.first
        } else {
            account = allAccounts.first {
                $0.name.localizedCaseInsensitiveCompare(draft.accountName) == .orderedSame
            } ?? allAccounts.first {
                $0.name.localizedCaseInsensitiveContains(draft.accountName)
            } ?? allAccounts.first(where: \.isDefault) ?? allAccounts.first
        }

        // ── Create transaction ────────────────────────────────────────────
        let tx = Transaction(
            type:      .expense,
            amount:    draft.amount,
            date:      draft.date ?? Date(),
            placeName: draft.placeName.isEmpty ? nil : draft.placeName,
            notes:     draft.notes.isEmpty     ? nil : draft.notes
        )
        tx.category = category
        tx.account  = account
        modelContext.insert(tx)
        if let data = draft.receiptImageData,
           let image = UIImage(data: data) {
            _ = try? ReceiptAttachmentStore.addImage(image, to: tx, in: modelContext)
        }

        return tx
    }

    // MARK: - OCR Helper

    private func recognizeText(in image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }
            let request = VNRecognizeTextRequest { req, _ in
                let text = (req.results as? [VNRecognizedTextObservation] ?? [])
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel       = .accurate
            request.recognitionLanguages   = LanguageManager.shared.effective.visionRecognitionLanguages
            request.usesLanguageCorrection = true
            try? VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        }
    }

    // MARK: - CSV Loader

    private func loadCSV(from url: URL) {
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        let raw: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            raw = utf8
        } else if let latin1 = try? String(contentsOf: url, encoding: .isoLatin1) {
            raw = latin1
        } else {
            return
        }

        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Keep header + up to 50 data rows so the prompt stays manageable
        let preview = lines.prefix(51)
        var content = preview.joined(separator: "\n")
        if lines.count > 51 {
            content += "\n… e mais \(lines.count - 51) linhas omitidas."
        }

        attachedCSVName    = url.lastPathComponent
        attachedCSVContent = content
    }
}

// MARK: - Transaction Draft Bubble

struct TransactionDraftBubble: View {
    let draft: TransactionDraft
    let currencyCode: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

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
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        draftRow(icon: "banknote.fill", color: .green, label: t("transaction.amount"), value: draft.amount.asCurrency(currencyCode))
                        draftRow(icon: "mappin.circle.fill", color: .red, label: t("transaction.place"), value: draft.placeName.isEmpty ? t("transaction.noPlace") : draft.placeName)
                        draftRow(icon: "tag.fill", color: .blue, label: t("transaction.category"), value: draft.categoryName)
                        if let date = draft.date {
                            draftRow(icon: "calendar", color: .orange, label: t("transaction.date"), value: date.formatted(.dateTime.day().month(.abbreviated).year()))
                        }
                        if !draft.accountName.isEmpty {
                            draftRow(icon: "creditcard.fill", color: .purple, label: t("transaction.account"), value: draft.accountName)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color(.tertiarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 8) {
                    QuickReplyButton(title: t("common.register"), icon: "checkmark", style: .confirm, action: onConfirm)
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
                .foregroundStyle(.secondary)
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
                    Text(t("ai.expenseRegisteredDetail", transaction.amount.asCurrency(currencyCode), transaction.placeName ?? transaction.category?.name ?? t("transaction.noPlace")))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

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
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))

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
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Text(payload.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                        .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(isUser ? Color.white : Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
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
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 18))

            Spacer(minLength: 60)
        }
        .onAppear { animate = true }
    }
}
