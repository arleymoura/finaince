import SwiftUI
import SwiftData
import PhotosUI

struct ProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var goals: [Goal]
    @Query private var aiSettingsList: [AISettings]
    @Query private var accounts: [Account]
    @Query private var categories: [Category]
    @Query private var transactions: [Transaction]
    @Query private var families: [Family]
    @Query private var conversations: [ChatConversation]
    @Query private var analyses: [AIAnalysis]
    @Query private var costCenters: [CostCenter]

    @AppStorage("user.name")  private var userName  = "Meu Perfil"
    @AppStorage("user.photo") private var photoData: Data = Data()
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var showNameEdit   = false
    @State private var photoPicker: PhotosPickerItem? = nil
    @State private var profileImage: Image? = nil
    @State private var deepLinkedGoal: Goal? = nil
    @State private var deepLinkManager = DeepLinkManager.shared
    @State private var selectedAccount: Account?
    @State private var showCreateAccount = false
    @State private var showCloudPaywall = false
    #if DEBUG
    @State private var showDebugPaywall = false
    #endif
    @State private var entitlements = EntitlementManager.shared
    @State private var profileCloudSync = ProfileCloudSyncStore.shared
    private let regularContentMaxWidth: CGFloat = 1100
    
    var aiSettings: AISettings? { aiSettingsList.first }
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }
    
    var body: some View {
        NavigationStack {
            profileList
                .scrollContentBackground(.hidden)
                .background(WorkspaceBackground(isRegularLayout: isRegularLayout))
                .frame(maxWidth: isRegularLayout ? regularContentMaxWidth : .infinity)
                .frame(maxWidth: .infinity)
                .safeAreaInset(edge: .top, spacing: 0) {
                    profileHeaderCard
                }
                .toolbar(.hidden, for: .navigationBar)
            .onChange(of: photoPicker) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        photoData = data
                        if let ui = UIImage(data: data) {
                            profileImage = Image(uiImage: ui)
                        }
                        publishProfileIfNeeded()
                    }
                }
            }
            .onAppear {
                syncProfileFromCloudIfNeeded()
                loadPhoto()
                handleDeepLink(deepLinkManager.pendingDeepLink)
            }
            .onChange(of: userName) { _, _ in
                publishProfileIfNeeded()
            }
            .onChange(of: photoData) { _, _ in
                loadPhoto()
                publishProfileIfNeeded()
            }
            .onChange(of: deepLinkManager.pendingDeepLink) { _, deepLink in
                handleDeepLink(deepLink)
            }
            .sheet(item: $deepLinkedGoal) { goal in
                GoalFormView(goal: goal)
            }
            .sheet(item: $selectedAccount) { account in
                AccountFormView(account: account)
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCreateAccount) {
                AccountFormView()
                    .presentationDetents([.medium, .large])
            }
            .sheet(isPresented: $showCloudPaywall) {
                FinAInceCloudView()
            }
            #if DEBUG
            .sheet(isPresented: $showDebugPaywall) {
                FinAInceCloudView(debugForceShowPaywall: true)
            }
            #endif
        }
    }

    // MARK: - Deep Links

    private func handleDeepLink(_ deepLink: DeepLink?) {
        guard case let .goal(id) = deepLink else { return }

        guard let goal = goals.first(where: { matchesDeepLinkID(id, uuid: $0.id) }) else {
            deepLinkManager.routeToHome()
            return
        }

        deepLinkedGoal = goal
        deepLinkManager.consume(.goal(id: id))
    }

    private func matchesDeepLinkID(_ id: String, uuid: UUID) -> Bool {
        uuid.uuidString.caseInsensitiveCompare(id) == .orderedSame
    }

    private var profileList: some View {
        List {
            // ── finAInce Cloud banner ─────────────────────────────────────
            Section {
                Button {
                    showCloudPaywall = true
                } label: {
                    FinAInceCloudBanner(state: entitlements.purchaseState)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                NavigationLink {
                    GoalsListView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "target")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(t("profile.goals"))
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(t("profile.goalsConfigured", goals.count))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text(t("profile.goals"))
            }
            
            Section {
                NavigationLink {
                    ProjectsListView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                            .frame(width: 32, height: 32)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text(t("profile.projects"))
                            .font(.subheadline)
                            .foregroundStyle(.primary)

                        Spacer()

                        let activeCount = costCenters.filter(\.isActive).count
                        if activeCount > 0 {
                            Text(t("profile.projectsActive", activeCount))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(t("profile.projects"))
            }

            AccountsProfileSection(
                selectedAccount: $selectedAccount,
                showCreateAccount: $showCreateAccount
            )


            
            Section {
                NavigationLink(destination: AIProviderSettingsView()) {
                    HStack(spacing: 12) {
                        if let settings = aiSettings {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(settings.provider.accentColor.opacity(0.15))
                                    .frame(width: 32, height: 32)
                                Image(systemName: settings.provider.iconName)
                                    .font(.subheadline)
                                    .foregroundStyle(settings.provider.accentColor)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(settings.provider.label)
                                    .font(.subheadline)
                                Text(settings.provider.modelDisplayName(settings.model))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if settings.isConfigured {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.subheadline)
                            }
                        } else {
                            Image(systemName: "brain")
                                .foregroundStyle(.secondary)
                            Text(t("settings.aiNotConfigured"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } header: {
                Text(t("settings.ai"))
            } footer: {
                Text(t("settings.aiFooter"))
            }
            

            // App
            Section(t("profile.app")) {
                NavigationLink {
                    CategoryManagerView()
                } label: {
                    Label(t("profile.manageCategories"), systemImage: "tag.fill")
                }
                NavigationLink {
                    SettingsView()
                } label: {
                    Label(t("profile.settings"), systemImage: "gearshape.fill")
                }
                NavigationLink {
                    HelpView()
                } label: {
                    Label(t("profile.help"), systemImage: "questionmark.circle.fill")
                }
            }

            // Debug tools — visível apenas em builds de desenvolvimento
            #if DEBUG
            Section {
                debugCloudDiagnostics

                Divider()

                Button {
                    showDebugPaywall = true
                } label: {
                    Label("Ver tela de compra (Paywall)", systemImage: "creditcard.fill")
                        .foregroundStyle(.purple)
                }

                Button {
                    SampleData.seed(in: modelContext)
                } label: {
                    Label(t("profile.seedData"), systemImage: "wand.and.stars")
                        .foregroundStyle(.orange)
                }

                Button {
                    UserDefaults.standard.removeObject(forKey: "ftu.dashboard.v1")
                } label: {
                    Label(t("profile.resetDashboardTutorial"), systemImage: "arrow.counterclockwise")
                        .foregroundStyle(.blue)
                }

                Button(role: .destructive) {
                    resetAllData()
                } label: {
                    Label(t("profile.resetAll"), systemImage: "trash.fill")
                }
            } header: {
                Text(t("profile.dev"))
            } footer: {
                Text(t("profile.devFooter"))
            }
            #endif
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 16, for: .scrollContent)
        .environment(\.defaultMinListHeaderHeight, 0)
        .listSectionSpacing(12)
    }

    // MARK: - Profile Header

    private var profileHeaderCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // ── Title ────────────────────────────────────────────────────
            Text(t("profile.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            // ── Avatar + Name ─────────────────────────────────────────────
            HStack(spacing: 16) {
                PhotosPicker(selection: $photoPicker, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        Group {
                            if let profileImage {
                                profileImage
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [.accentColor.opacity(0.75), .accentColor],
                                        startPoint: .topLeading, endPoint: .bottomTrailing
                                    ))
                                    .overlay(
                                        Text(initials)
                                            .font(.system(size: 30, weight: .bold))
                                            .foregroundStyle(.white)
                                    )
                            }
                        }
                        .frame(width: 74, height: 74)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.12), radius: 6, x: 0, y: 3)

                        Circle()
                            .fill(Color(.systemBackground))
                            .frame(width: 26, height: 26)
                            .overlay(
                                Image(systemName: "camera.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            )
                            .shadow(color: Color.black.opacity(0.10), radius: 3, y: 1)
                    }
                }
                .buttonStyle(.plain)

                Button {
                    showNameEdit = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)
                        Text(t("profile.tapToEdit"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .alert(t("profile.yourName"), isPresented: $showNameEdit) {
                    TextField(t("profile.yourName"), text: $userName)
                    Button(t("common.ok")) {}
                }

                Spacer()
            }
        }
        .frame(maxWidth: isRegularLayout ? regularContentMaxWidth : .infinity, alignment: .leading)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isRegularLayout ? 24 : 20)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .background {
            // As shapes com ignoresSafeArea(edges: .top) cobrem a status bar.
            // O clipShape NÃO é usado no view externo — as bordas arredondadas
            // são definidas pelas próprias shapes aqui dentro, que se estendem
            // para cima sem serem cortadas.
            ZStack {
                UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24))
                    .fill(
                        LinearGradient(
                            colors: [Color(.systemGray6), Color(.systemBackground)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .ignoresSafeArea(edges: .top)

                UnevenRoundedRectangle(cornerRadii: .init(bottomLeading: 24, bottomTrailing: 24))
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.06), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .ignoresSafeArea(edges: .top)
            }
        }
        .shadow(color: Color.black.opacity(0.10), radius: 14, x: 0, y: 8)
    }

    private var emptyGoals: some View {
        VStack(spacing: 8) {
            Text("🎯")
                .font(.system(size: 32))
            Text(t("profile.noGoals"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var initials: String {
        let parts = userName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first }
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    private func loadPhoto() {
        guard !photoData.isEmpty, let ui = UIImage(data: photoData) else { return }
        profileImage = Image(uiImage: ui)
    }

    private func syncProfileFromCloudIfNeeded() {
        let synced = profileCloudSync.syncFromCloud(
            localName: userName,
            localPhotoData: photoData,
            isConfiguredDevice: hasCompletedOnboarding
        )

        if synced.name != userName {
            userName = synced.name
        }

        if synced.photoData != photoData {
            photoData = synced.photoData
        }
    }

    private func publishProfileIfNeeded() {
        profileCloudSync.publish(
            name: userName,
            photoData: photoData,
            isConfiguredDevice: hasCompletedOnboarding
        )
    }

    #if DEBUG
    private var debugCloudDiagnostics: some View {
        let status = FamilyFinanceApp.debugCloudStatus()
        let launchLogs = DebugLaunchLog.entries()

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: status.cloudEntitlementEnabled ? "checkmark.icloud.fill" : "icloud.slash")
                    .foregroundStyle(status.cloudEntitlementEnabled ? .green : .secondary)
                Text("Cloud Debug")
                    .font(.subheadline.bold())
                Spacer()
                Text(status.cloudEntitlementEnabled ? "Enabled" : "Disabled")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background((status.cloudEntitlementEnabled ? Color.green : Color.secondary).opacity(0.12))
                    .foregroundStyle(status.cloudEntitlementEnabled ? .green : .secondary)
                    .clipShape(Capsule())
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                debugStatCard(title: "Store", value: status.cloudEntitlementEnabled ? "Cloud" : "Local")
                debugStatCard(title: "Transactions", value: "\(transactions.count)")
                debugStatCard(title: "Accounts", value: "\(accounts.count)")
                debugStatCard(title: "Categories", value: "\(categories.count)")
                debugStatCard(title: "Families", value: "\(families.count)")
                debugStatCard(title: "Goals", value: "\(goals.count)")
                debugStatCard(title: "Chats", value: "\(conversations.count)")
                debugStatCard(title: "Analyses", value: "\(analyses.count)")
            }

            VStack(alignment: .leading, spacing: 8) {
                debugFlagRow(label: "Prepared cloud migration", value: status.preparedCloudMigration)
                debugFlagRow(label: "Needs cloud import", value: status.needsCloudImport)
                debugFlagRow(label: "Needs deduplication", value: status.needsCloudDeduplication)
                debugFlagRow(label: "Local store exists", value: status.localStoreExists)
                debugFlagRow(label: "Cloud store exists", value: status.cloudStoreExists)
            }

            Divider()

            HStack {
                Text("Launch Logs")
                    .font(.subheadline.bold())
                Spacer()
                Button("Clear") {
                    DebugLaunchLog.clear()
                }
                .font(.caption.bold())
            }

            if launchLogs.isEmpty {
                Text("No persisted logs yet.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(launchLogs.enumerated()), id: \.offset) { _, entry in
                            Text(entry)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 240)
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.vertical, 4)
    }

    private func debugStatCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline.monospacedDigit())
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func debugFlagRow(label: String, value: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: value ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(value ? .green : .secondary)
            Text(label)
                .font(.footnote)
            Spacer()
            Text(value ? "YES" : "NO")
                .font(.caption.bold())
                .foregroundStyle(value ? .green : .secondary)
        }
    }

    private func resetAllData() {
        try? modelContext.delete(model: Transaction.self)
        try? modelContext.delete(model: Account.self)
        try? modelContext.delete(model: Category.self)
        try? modelContext.delete(model: Goal.self)
        try? modelContext.delete(model: ChatConversation.self)
        try? modelContext.delete(model: ChatMessage.self)
        try? modelContext.delete(model: AIAnalysis.self)
        try? modelContext.delete(model: AISettings.self)
        try? modelContext.delete(model: Family.self)
        UserDefaults.standard.removeObject(forKey: "hasSeededDefaultData")
        UserDefaults.standard.removeObject(forKey: "hasCompletedOnboarding")
        UserDefaults.standard.removeObject(forKey: "user.name")
        FamilyFinanceApp.debugResetPersistentStores()
    }
    #endif
}

// MARK: - Goals List

struct GoalsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var goals: [Goal]

    @State private var showGoalForm = false
    @State private var goalToEdit: Goal? = nil

    var body: some View {
       
        
       
        
        List {
            Section {
                if goals.isEmpty {
                    emptyGoals
                } else {
                   
                    ForEach(goals) { goal in
                        GoalRowView(goal: goal)
                            .contentShape(Rectangle())
                            .onTapGesture { goalToEdit = goal }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    modelContext.delete(goal)
                                } label: {
                                    Label(t("common.delete"), systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        let currentGoals = goals
                        for index in offsets where currentGoals.indices.contains(index) {
                            modelContext.delete(currentGoals[index])
                        }
                    }
                }
            }header: {
                Text(t("profile.goals.subtitle"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t("profile.goals"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showGoalForm = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(t("profile.newGoal"))
            }
        }
        .sheet(isPresented: $showGoalForm) {
            GoalFormView()
        }
        .sheet(item: $goalToEdit) { goal in
            GoalFormView(goal: goal)
        }
    }

    private var emptyGoals: some View {
        VStack(spacing: 8) {
            Image(systemName: "target")
                .font(.system(size: 32, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(t("profile.noGoals"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                showGoalForm = true
            } label: {
                Label(t("profile.newGoal"), systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Goal Row

struct GoalRowView: View {
    let goal: Goal
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: goal.iconName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(goal.title)
                    .font(.subheadline.weight(.medium))
                if let cat = goal.category {
                    Text(cat.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(t("goal.allExpenses"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Text(goal.targetAmount.asCurrency(currencyCode))
                .font(.subheadline.bold())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
