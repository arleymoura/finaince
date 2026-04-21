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
    @State private var sharedImportManager = SharedImportManager.shared
    @State private var deepLinkManager = DeepLinkManager.shared

    /// Keeps a reference so SwiftUI re-renders when language changes
    private var lm: LanguageManager { LanguageManager.shared }

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
                SplashView()
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
        // 2.8s → dá tempo para: logo spring (0.55s) + glow pulse (0.8s) +
        // slogan revelar em 3 fases (1.0s→1.95s) + hold de ~0.8s para leitura.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.8) {
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = hasCompletedOnboarding ? .main : .onboarding
            }
        }
    }

    private func scheduleNotifications() {
        NotificationService.shared.scheduleAll(context: modelContext)
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

// MARK: - iPad Layout (NavigationSplitView)

private struct iPadRootView: View {
    @State private var showNewTransaction = false
    @State private var showImportSheet = false
    @State private var deepLinkManager = DeepLinkManager.shared
    @State private var importManager = SharedImportManager.shared
    @State private var chatNavigationManager = ChatNavigationManager.shared

    enum Destination: Hashable {
        case dashboard, transactions, chat, profile, analysis, settings
    }

    @State private var selectedDestination: Destination? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                Section(t("navigation.main")) {
                    Label(t("tab.dashboard"), systemImage: "chart.pie.fill")
                        .tag(Destination.dashboard)
                    Label(t("tab.transactions"), systemImage: "list.bullet.rectangle")
                        .tag(Destination.transactions)
                    Label(t("tab.profile"), systemImage: "person.crop.circle.fill")
                        .tag(Destination.profile)
                }
                Section(t("navigation.intelligence")) {
                    Label(t("tab.chat"), systemImage: "bubble.left.and.bubble.right.fill")
                        .tag(Destination.chat)
                    Label(t("ai.analysisTitle"), systemImage: "chart.line.uptrend.xyaxis")
                        .tag(Destination.analysis)
                }
                Section(t("navigation.account")) {
                    Label(t("settings.title"), systemImage: "gearshape.fill")
                        .tag(Destination.settings)
                }
            }
            .navigationTitle("FamilyFinance")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showNewTransaction = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
        } detail: {
            switch selectedDestination {
            case .dashboard, nil: DashboardView()
           case .transactions:    TransactionListView()
            case .chat:           ChatView()
            case .profile:        ProfileView()
            case .analysis:       AnalysisView()
            case .settings:       SettingsView()
            }
        }
        .sheet(isPresented: $showNewTransaction) {
            NewTransactionFlowView()
        }
        .sheet(isPresented: $showImportSheet) {
            CSVImportInfoView()
        }
        .onAppear {
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
        .onChange(of: chatNavigationManager.pendingRequest) { _, request in
            if request != nil {
                selectedDestination = .chat
            }
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
