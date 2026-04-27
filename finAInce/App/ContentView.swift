import SwiftUI
import SwiftData

// MARK: - App Phase State Machine

private enum AppPhase: Equatable {
    case splash
    case onboarding
    case main
}

// MARK: - Root

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage("app.colorScheme")         private var colorSchemePreference  = "light"
    @State private var phase: AppPhase = .splash
    @State private var splashMode: SplashMode = .brand
    @State private var sharedImportManager = SharedImportManager.shared
    @State private var deepLinkManager = DeepLinkManager.shared

    /// Keeps a reference so SwiftUI re-renders when language changes
    private var lm: LanguageManager { LanguageManager.shared }
    private let cloudSyncWaitSeconds = 180
    private let stableCloudDataChecks = 2

    private var preferredScheme: ColorScheme? {
        switch colorSchemePreference {
        case "light": return .light
        case "dark":  return .dark
        default:      return .light
        }
    }

    var body: some View {
        Group {
            switch phase {
            case .splash:
                SplashView(mode: splashMode)
                    .ignoresSafeArea()
                    .onAppear { scheduleSplashDismiss() }
                    .transition(.opacity)

            case .onboarding:
                OnboardingView()
                    .transition(.opacity)

            case .main:
                mainRoot
                    .transition(.opacity)
                    .task { scheduleNotifications() }
                    .onReceive(NotificationCenter.default.publisher(
                        for: UIApplication.willEnterForegroundNotification
                    )) { _ in scheduleNotifications() }
            }
        }
        // Force full re-render when language changes so all t("key") calls refresh
        .id(lm.language)
        .environment(lm)
        .dynamicTypeSize(.large ... .accessibility5)
        .preferredColorScheme(preferredScheme)
        .animation(.easeInOut(duration: 0.4), value: phase)
        .onOpenURL { url in
            // finaince://shared-image → image from Share Extension
            if url.scheme == "finaince" && url.host == "shared-image" {
                sharedImportManager.handleSharedImage()
            } else if deepLinkManager.handle(url) {
                if !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                }
                phase = .main
            } else {
                sharedImportManager.handleSharedFile(url)
            }
        }

        .alert(
            "Importação não disponível",
            isPresented: Binding(
                get: { sharedImportManager.errorMessage != nil },
                set: { if !$0 { sharedImportManager.errorMessage = nil } }
            )
        ) {
            Button(t("common.ok"), role: .cancel) { sharedImportManager.errorMessage = nil }
        } message: {
            if let message = sharedImportManager.errorMessage {
                Text(message)
            }
        }
        // Quando o onboarding termina (AppStorage muda → true), avança para main
        .onChange(of: hasCompletedOnboarding) { _, completed in
            if completed {
                withAnimation(.easeInOut(duration: 0.4)) {
                    phase = .main
                }
            }
        }
    }

    // MARK: - Helpers

    private var mainRoot: some View {
        Group {
            if UIDevice.current.userInterfaceIdiom == .pad {
                iPadRootView()
            } else {
                iPhoneRootView()
            }
        }
    }

    private func scheduleSplashDismiss() {
        Task { @MainActor in
            // 2.8s → dá tempo para: logo spring (0.55s) + glow pulse (0.8s) +
            // slogan revelar em 3 fases (1.0s→1.95s) + hold de ~0.8s para leitura.
            try? await Task.sleep(for: .seconds(2.8))

            let shouldForceInitialSyncRecovery = EntitlementManager.shared.shouldForceInitialSyncRecovery
            let isReturningCloudUserAwaitingData = EntitlementManager.shared.isCloudEnabled &&
                hasCompletedOnboarding &&
                !hasExistingUserData()
            let shouldWaitForCloudSync = EntitlementManager.shared.isCloudEnabled && (
                !hasCompletedOnboarding || shouldForceInitialSyncRecovery || isReturningCloudUserAwaitingData
            )
            var shouldSkipOnboarding = shouldWaitForCloudSync
                ? false
                : (hasCompletedOnboarding || hasExistingUserData())
            splashMode = .brand

            DebugLaunchLog.log("☁️ [Launch] splashDismiss start cloudEnabled=\(EntitlementManager.shared.isCloudEnabled) hasCompletedOnboarding=\(hasCompletedOnboarding) awaitingInitialSync=\(EntitlementManager.shared.isAwaitingInitialSync) shouldForceInitialSyncRecovery=\(shouldForceInitialSyncRecovery) isReturningCloudUserAwaitingData=\(isReturningCloudUserAwaitingData) shouldWaitForCloudSync=\(shouldWaitForCloudSync) hasExistingUserData=\(hasExistingUserData())")

            if shouldWaitForCloudSync {
                splashMode = .syncing
                var consecutiveSuccessfulChecks = 0
                var iteration = 0

                while true {
                    iteration += 1
                    lm.syncFromCloud()

                    let ready = hasCloudSyncReadyData()
                    let existing = hasExistingUserData()
                    let transactionCount = (try? modelContext.fetchCount(FetchDescriptor<Transaction>())) ?? 0
                    let goalCount = (try? modelContext.fetchCount(FetchDescriptor<Goal>())) ?? 0
                    let conversationCount = (try? modelContext.fetchCount(FetchDescriptor<ChatConversation>())) ?? 0
                    let analysisCount = (try? modelContext.fetchCount(FetchDescriptor<AIAnalysis>())) ?? 0
                    let accountCount = (try? modelContext.fetchCount(FetchDescriptor<Account>())) ?? 0
                    let familyCount = (try? modelContext.fetchCount(FetchDescriptor<Family>())) ?? 0

                    DebugLaunchLog.log("☁️ [Launch] recoverySync tick=\(iteration) ready=\(ready) existing=\(existing) transactions=\(transactionCount) goals=\(goalCount) chats=\(conversationCount) analyses=\(analysisCount) accounts=\(accountCount) families=\(familyCount) language=\(lm.language.rawValue)")

                    if ready {
                        consecutiveSuccessfulChecks += 1
                    } else {
                        consecutiveSuccessfulChecks = 0
                    }

                    if consecutiveSuccessfulChecks >= stableCloudDataChecks {
                        shouldSkipOnboarding = true
                        EntitlementManager.shared.markInitialSyncCompleted()
                        DebugLaunchLog.log("☁️ [Launch] recoverySync complete after \(iteration) ticks")
                        break
                    }

                    try? await Task.sleep(for: .seconds(1))
                }
            } else if !shouldSkipOnboarding && EntitlementManager.shared.isCloudEnabled {
                splashMode = .syncing
                for iteration in 0..<cloudSyncWaitSeconds {
                    lm.syncFromCloud()
                    let existing = hasExistingUserData()
                    DebugLaunchLog.log("☁️ [Launch] cloudSync tick=\(iteration + 1) existing=\(existing) language=\(lm.language.rawValue)")
                    try? await Task.sleep(for: .seconds(1))
                    if existing {
                        shouldSkipOnboarding = true
                        EntitlementManager.shared.markInitialSyncCompleted()
                        DebugLaunchLog.log("☁️ [Launch] cloudSync complete at tick \(iteration + 1)")
                        break
                    }
                }
            }

            if shouldSkipOnboarding && !hasCompletedOnboarding {
                hasCompletedOnboarding = true
                DebugLaunchLog.log("☁️ [Launch] marking onboarding as completed from launch recovery")
            }

            splashMode = .brand
            DebugLaunchLog.log("☁️ [Launch] final destination=\(shouldSkipOnboarding ? "main" : "onboarding") language=\(lm.language.rawValue)")
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = shouldSkipOnboarding ? .main : .onboarding
            }
        }
    }

    private func scheduleNotifications() {
        NotificationService.shared.scheduleAll(context: modelContext)
    }

    private func hasExistingUserData() -> Bool {
        let accountCount = (try? modelContext.fetchCount(FetchDescriptor<Account>())) ?? 0
        if accountCount > 0 { return true }

        let transactionCount = (try? modelContext.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        if transactionCount > 0 { return true }

        let goalCount = (try? modelContext.fetchCount(FetchDescriptor<Goal>())) ?? 0
        if goalCount > 0 { return true }

        let conversationCount = (try? modelContext.fetchCount(FetchDescriptor<ChatConversation>())) ?? 0
        if conversationCount > 0 { return true }

        let analysisCount = (try? modelContext.fetchCount(FetchDescriptor<AIAnalysis>())) ?? 0
        if analysisCount > 0 { return true }

        return false
    }

    private func hasCloudSyncReadyData() -> Bool {
        let transactionCount = (try? modelContext.fetchCount(FetchDescriptor<Transaction>())) ?? 0
        if transactionCount > 0 { return true }

        let goalCount = (try? modelContext.fetchCount(FetchDescriptor<Goal>())) ?? 0
        if goalCount > 0 { return true }

        let conversationCount = (try? modelContext.fetchCount(FetchDescriptor<ChatConversation>())) ?? 0
        if conversationCount > 0 { return true }

        let analysisCount = (try? modelContext.fetchCount(FetchDescriptor<AIAnalysis>())) ?? 0
        if analysisCount > 0 { return true }

        return false
    }
}

// MARK: - iPhone Layout (TabView)

private struct iPhoneRootView: View {
    @State private var showNewTransaction = false
    @State private var showImportSheet = false
    @State private var selectedTab        = 0
    @State private var previousTab        = 0
    @State private var isKeyboardVisible  = false
    @State private var deepLinkManager = DeepLinkManager.shared
    @State private var chatNavigationManager = ChatNavigationManager.shared

    /// @State so SwiftUI's @Observable tracking works correctly on the singleton
    @State private var importManager = SharedImportManager.shared

    private var tabSelection: Binding<Int> {
        Binding(
            get: { selectedTab },
            set: { newValue in
                if newValue == 2 {
                    selectedTab = previousTab
                    showNewTransaction = true
                } else {
                    selectedTab = newValue
                    previousTab = newValue
                }
            }
        )
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: tabSelection) {
                DashboardView()
                    .tabItem { Label(t("tab.dashboard"), systemImage: "chart.pie.fill") }
                    .tag(0)

                TransactionListView()
                    .tabItem { Label(t("tab.transactions"), systemImage: "list.bullet.rectangle") }
                    .tag(1)

                Color.clear
                    .tabItem { Label("", systemImage: "") }
                    .tag(2)

                ChatView()
                    .tabItem { Label(t("tab.chat"), systemImage: "sparkles") }
                    .tag(3)

                ProfileView()
                    .tabItem { Label(t("tab.profile"), systemImage: "person.crop.circle.fill") }
                    .tag(4)
            }
            .sheet(isPresented: $showNewTransaction) {
                NewTransactionFlowView()
            }
            .sheet(isPresented: $showImportSheet) {
                CSVImportInfoView()
            }

            // Botão oculto enquanto o teclado estiver aberto
            if !isKeyboardVisible {
                Button {
                    showNewTransaction = true
                } label: {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 56, height: 56)
                        .shadow(color: Color.accentColor.opacity(0.45), radius: 10, y: 4)
                        .overlay(
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                        )
                }
                .frame(width: 56, height: 56)
                .contentShape(Circle())
                .buttonStyle(.plain)
                .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.easeInOut(duration: 0.2), value: isKeyboardVisible)
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )) { _ in isKeyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )) { _ in isKeyboardVisible = false }
        // Navigate to Chat tab when a shared image arrives from the Share Extension
        .onChange(of: importManager.pendingSharedImage) { _, image in
            if image != nil {
                withAnimation { selectedTab = 3 }
            }
        }
        .onChange(of: importManager.pendingSharedChatFile != nil) { _, hasPendingFile in
            if hasPendingFile {
                withAnimation {
                    selectedTab = 3
                    previousTab = 3
                }
            }
        }
        .onChange(of: importManager.pendingFile != nil) { _, hasPendingFile in
            if hasPendingFile {
                showImportSheet = true
            }
        }
        .onChange(of: chatNavigationManager.pendingRequest) { _, request in
            if request != nil {
                withAnimation {
                    selectedTab = 3
                    previousTab = 3
                }
            }
        }
        // Fallback: app was already running when extension saved the image
        // (onOpenURL won't fire if app is already in foreground)
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            importManager.handleSharedImage()
        }
        .onAppear {
            importManager.handleSharedImage()
            if importManager.pendingSharedImage != nil || importManager.pendingSharedChatFile != nil {
                selectedTab = 3
                previousTab = 3
            }
            if importManager.pendingFile != nil {
                showImportSheet = true
            }
            handleDeepLink(deepLinkManager.pendingDeepLink)
        }
        .onChange(of: deepLinkManager.pendingDeepLink) { _, deepLink in
            handleDeepLink(deepLink)
        }
    }

    private func handleDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        switch deepLink {
        case .home:
            selectedTab = 0
            previousTab = 0
            deepLinkManager.consume(deepLink)
        case .transaction:
            selectedTab = 1
            previousTab = 1
        case .category:
            selectedTab = 0
            previousTab = 0
        case .goal:
            selectedTab = 4
            previousTab = 4
        }
    }
}

// MARK: - iPad Layout

private struct iPadRootView: View {
    @State private var showNewTransaction = false
    @State private var showImportSheet    = false
    @State private var deepLinkManager   = DeepLinkManager.shared
    @State private var importManager     = SharedImportManager.shared
    @State private var chatNavigationManager = ChatNavigationManager.shared

    enum Destination: Hashable {
        case dashboard, transactions, chat, profile, settings
    }

    @State private var selectedDestination: Destination? = .dashboard

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // ── Custom split layout — plain HStack, no NavigationSplitView chrome ──
            HStack(spacing: 0) {
                // Sidebar column (fixed 240pt)
                iPadSidebar(selected: $selectedDestination)
                .frame(width: 240)
                .ignoresSafeArea()

                // Hairline divider
                Rectangle()
                    .fill(Color(.separator).opacity(0.5))
                    .frame(width: 0.5)
                    .ignoresSafeArea()

                // Detail column
                ZStack {
                    switch selectedDestination {
                    case .dashboard, nil: DashboardView()
                    case .transactions:   TransactionListView()
                    case .chat:           ChatView()
                    case .profile:        ProfileView()
                    case .settings:       SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .ignoresSafeArea()

            // ── Floating Action Button ───────────────────────────────────
            Button {
                showNewTransaction = true
            } label: {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.80)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 60, height: 60)
                    .shadow(color: Color.accentColor.opacity(0.40), radius: 12, y: 5)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    )
            }
            .buttonStyle(.plain)
            .padding(.trailing, 28)
            .padding(.bottom, 28)
        }
        .ignoresSafeArea()
        .sheet(isPresented: $showNewTransaction) {
            NewTransactionFlowView()
        }
        .sheet(isPresented: $showImportSheet) {
            CSVImportInfoView()
        }
        .onAppear {
            importManager.handleSharedImage()
            if importManager.pendingSharedImage != nil || importManager.pendingSharedChatFile != nil {
                selectedDestination = .chat
            }
            if importManager.pendingFile != nil {
                showImportSheet = true
            }
            handleDeepLink(deepLinkManager.pendingDeepLink)
        }
        .onChange(of: deepLinkManager.pendingDeepLink) { _, deepLink in
            handleDeepLink(deepLink)
        }
        .onChange(of: importManager.pendingFile != nil) { _, hasPendingFile in
            if hasPendingFile {
                showImportSheet = true
            }
        }
        .onChange(of: importManager.pendingSharedImage) { _, image in
            if image != nil {
                selectedDestination = .chat
            }
        }
        .onChange(of: importManager.pendingSharedChatFile != nil) { _, hasPendingFile in
            if hasPendingFile {
                selectedDestination = .chat
            }
        }
        .onChange(of: chatNavigationManager.pendingRequest) { _, request in
            if request != nil {
                selectedDestination = .chat
            }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification
        )) { _ in
            importManager.handleSharedImage()
        }
    }

    private func handleDeepLink(_ deepLink: DeepLink?) {
        guard let deepLink else { return }

        switch deepLink {
        case .home:
            selectedDestination = .dashboard
            deepLinkManager.consume(deepLink)
        case .transaction:
            selectedDestination = .transactions
        case .category:
            selectedDestination = .dashboard
        case .goal:
            selectedDestination = .profile
        }
    }
}

// MARK: - iPad Sidebar

private struct iPadSidebar: View {
    @Binding var selected: iPadRootView.Destination?

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("user.name") private var userName = "Meu Perfil"
    @AppStorage("user.photo") private var photoData: Data = Data()
    @State private var profileImage: Image? = nil
    @State private var showCloudInfoSheet = false

    private struct NavItem {
        let destination: iPadRootView.Destination
        let icon: String
        let labelKey: String
    }

    private let primaryItems: [NavItem] = [
        NavItem(destination: .dashboard,    icon: "chart.pie.fill",              labelKey: "tab.dashboard"),
        NavItem(destination: .transactions, icon: "list.bullet.rectangle",       labelKey: "tab.transactions"),
        NavItem(destination: .chat,         icon: "sparkles",                    labelKey: "tab.chat"),
    ]

    private let accountItems: [NavItem] = [
        NavItem(destination: .profile,      icon: "person.crop.circle.fill",     labelKey: "tab.profile"),
        NavItem(destination: .settings,     icon: "gearshape.fill",              labelKey: "tab.settings"),
    ]

    private var windowTopInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first(where: { $0.activationState == .foregroundActive })?.keyWindow?
            .safeAreaInsets.top ?? 24
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Full-height sidebar background, bleeds under status bar
            sidebarBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                profileHeader

                Divider()
                    .opacity(0.10)
                    .padding(.horizontal, 16)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 22) {
                        navSection(title: "Principal", items: primaryItems)
                        navSection(title: "Conta", items: accountItems)
                    }
                    .padding(.top, 18)
                    .padding(.horizontal, 12)
                }

                Spacer(minLength: 0)
            }
        }
        .onAppear(perform: loadProfilePhoto)
        .sheet(isPresented: $showCloudInfoSheet) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.98, green: 0.94, blue: 0.80),
                                        Color.white
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 78, height: 78)

                        Image(systemName: "checkmark.icloud.fill")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.12))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("FinAInce Cloud Premium")
                            .font(.title2.bold())

                        Text("Seu backup no iCloud e a sincronizacao entre aparelhos estao ativos neste dispositivo.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        cloudInfoRow(
                            icon: "icloud.fill",
                            title: "Backup automatico",
                            subtitle: "Seus dados ficam protegidos no seu iCloud privado."
                        )
                        cloudInfoRow(
                            icon: "arrow.triangle.2.circlepath.icloud.fill",
                            title: "Sync entre aparelhos",
                            subtitle: "As informacoes acompanham voce no iPhone e no iPad."
                        )
                    }

                    Spacer()
                }
                .padding(24)
                .navigationTitle("Cloud Premium")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(t("common.done")) {
                            showCloudInfoSheet = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
    }

    // MARK: - Profile Header

    private var profileHeader: some View {
        VStack(spacing: 16) {
            Group {
                if let profileImage {
                    profileImage
                        .resizable()
                        .scaledToFill()
                } else {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.86), Color.accentColor.opacity(0.64)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            Text(initials)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                        )
                }
            }
            .frame(width: 92, height: 92)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.45), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)

            VStack(spacing: 6) {
                Text(userName)
                    .font(.system(size: 21, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text("Seu espaco financeiro")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Button {
                    showCloudInfoSheet = true
                } label: {
                    premiumCloudBadge
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, windowTopInset + 28)
        .padding(.bottom, 22)
    }

    private func navSection(title: String, items: [NavItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 12)

            VStack(spacing: 6) {
                ForEach(items, id: \.destination) { item in
                    navRow(item)
                }
            }
        }
    }

    // MARK: - Nav Row

    @ViewBuilder
    private func navRow(_ item: NavItem) -> some View {
        let isSelected = selected == item.destination
        let isChat = item.destination == .chat

        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selected = item.destination
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: isSelected ? .semibold : .regular))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? .white : (isChat ? Color.accentColor : .secondary))

                Text(t(item.labelKey))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : (isChat ? .primary : .secondary))

                Spacer(minLength: 0)

                if isChat && !isSelected {
                    Text("AI")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isSelected
                        ? LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.78)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: isChat
                                ? [Color.accentColor.opacity(0.10), Color.accentColor.opacity(0.04)]
                                : [Color.clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        isSelected
                        ? Color.white.opacity(0.14)
                        : (isChat
                            ? Color.accentColor.opacity(0.16)
                            : Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.04)),
                        lineWidth: 1
                    )
            )
            .shadow(color: isSelected ? Color.accentColor.opacity(0.18) : .clear, radius: 10, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Background

    private var sidebarBackground: some View {
        Rectangle()
            .fill(colorScheme == .dark
                  ? Color(red: 0.12, green: 0.12, blue: 0.14)
                  : .white)
    }

    private var initials: String {
        let parts = userName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func loadProfilePhoto() {
        guard !photoData.isEmpty, let ui = UIImage(data: photoData) else { return }
        profileImage = Image(uiImage: ui)
    }

    private var premiumCloudBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "crown.fill")
                .font(.caption.bold())
                .foregroundStyle(Color(red: 0.83, green: 0.63, blue: 0.12))

            Text("FinAInce Cloud Premium")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.98, green: 0.94, blue: 0.80),
                            Color.white.opacity(0.92)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
        )
        .overlay(
            Capsule()
                .strokeBorder(Color(red: 0.83, green: 0.63, blue: 0.12).opacity(0.28), lineWidth: 1)
        )
    }

    private func cloudInfoRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }
}
