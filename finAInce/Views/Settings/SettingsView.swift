import SwiftUI
import SwiftData
import LocalAuthentication

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var currentColorScheme
    @Query private var aiSettingsList: [AISettings]

    @AppStorage("notif.pendingExpense") private var paymentAlert = false
    @AppStorage("notif.creditCardCycle") private var creditCardAlert = false
    @AppStorage("notif.goalAlert")      private var goalAlert   = false
    @AppStorage("app.currencyCode")     private var currencyCode = CurrencyOption.defaultCode
    @AppStorage("app.colorScheme")      private var colorScheme  = "light"
    @AppStorage("app.lockEnabled")      private var lockEnabled  = false
    @State private var showSavedAlert = false
    @State private var lockManager = AppLockManager.shared
    private var lm: LanguageManager { LanguageManager.shared }
    private var isRegularLayout: Bool { horizontalSizeClass == .regular }
    private let regularContentMaxWidth: CGFloat = 1100
    private var regularHeaderTopColor: Color {
        currentColorScheme == .dark ? Color(red: 0.34, green: 0.25, blue: 0.72) : Color.accentColor.opacity(0.96)
    }
    private var regularHeaderBottomColor: Color {
        currentColorScheme == .dark ? Color(red: 0.18, green: 0.14, blue: 0.36) : Color.accentColor.opacity(0.72)
    }

    var aiSettings: AISettings? {
        aiSettingsList.first(where: { $0.isConfigured }) ?? aiSettingsList.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if isRegularLayout {
                    regularSettingsView
                } else {
                    settingsForm
                        .navigationTitle(t("settings.title"))
                }
            }
            .alert(t("settings.saved"), isPresented: $showSavedAlert) {
                Button(t("common.ok")) { }
            }
            .onAppear(perform: normalizeColorScheme)
        }
    }

    private var settingsForm: some View {
        Form {
            familySection
            aiSection
            languageSection
            privacySection
            notificationsSection
            preferencesSection
        }
    }

    private var regularSettingsView: some View {
        GeometryReader { proxy in
            ZStack {
                WorkspaceBackground(isRegularLayout: isRegularLayout)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    regularSettingsHeader(topInset: proxy.safeAreaInsets.top)
                        .ignoresSafeArea(edges: .top)

                    settingsForm
                        .frame(maxWidth: regularContentMaxWidth)
                        .frame(maxWidth: .infinity)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .padding(.top, 12)
                }.padding(.top, -50)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func regularSettingsHeader(topInset: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("settings.title"))
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text(t("settings.preferences"))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 24)
        .padding(.top, topInset + 18)
        .padding(.bottom, 22)
        .frame(maxWidth: regularContentMaxWidth, alignment: .leading)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [
                    regularHeaderTopColor,
                    regularHeaderBottomColor
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(
            UnevenRoundedRectangle(
                cornerRadii: .init(bottomLeading: 28, bottomTrailing: 28)
            )
        )
        .shadow(color: regularHeaderBottomColor.opacity(currentColorScheme == .dark ? 0.28 : 0.18), radius: 14, x: 0, y: 8)
    }

    // MARK: - Sections

    private var familySection: some View {
        Section(t("settings.family")) {
            NavigationLink {
                FamilyMembersView()
            } label: {
                Label(t("settings.familyMembers"), systemImage: "person.2.fill")
            }
        }
    }

    private var aiSection: some View {
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
    }

    // MARK: - Language Section

    private var languageSection: some View {
        Section(t("settings.language")) {
            ForEach(AppLanguage.allCases) { lang in
                Button {
                    LanguageManager.shared.language = lang
                } label: {
                    HStack(spacing: 14) {
                        Text(lang.flag)
                            .font(.title3)
                            .frame(width: 36)
                        Text(lang.displayName)
                            .foregroundStyle(.primary)
                        Spacer()
                        if lm.language == lang {
                            Image(systemName: "checkmark")
                                .foregroundStyle(Color.accentColor)
                                .fontWeight(.semibold)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Privacy Section

    private var privacySection: some View {
        Section {
            Toggle(isOn: $lockEnabled) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 32, height: 32)
                        Image(systemName: biometryIcon)
                            .font(.subheadline)
                            .foregroundStyle(Color.accentColor)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("settings.lock"))
                            .font(.subheadline)
                        Text(biometryDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onChange(of: lockEnabled) { _, enabled in
                lockManager.isEnabled = enabled
                // If disabling, make sure app is unlocked
                if !enabled {
                    // nothing extra needed — next foreground won't call lockIfEnabled
                }
            }
        } header: {
            Text(t("settings.privacy"))
        } footer: {
            Text(t("settings.lockFooter"))
        }
    }

    private var biometryIcon: String {
        switch lockManager.biometryType {
        case .faceID:   return "faceid"
        case .touchID:  return "touchid"
        default:        return "lock.fill"
        }
    }

    private var biometryDescription: String {
        switch lockManager.biometryType {
        case .faceID:   return t("settings.lockDescFaceID")
        case .touchID:  return t("settings.lockDescTouchID")
        default:        return t("settings.lockDescPasscode")
            
        }
    }

    // MARK: - Notifications Section

    private var notificationsSection: some View {
        Section {
            Toggle(isOn: $paymentAlert) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("profile.notifPayment"))
                        .font(.subheadline)
                    Text(t("profile.notifPaymentDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: paymentAlert) { _, enabled in
                Task {
                    if enabled { await NotificationService.shared.requestPermission() }
                    NotificationService.shared.schedulePaymentNotifications(context: modelContext)
                }
            }

            Toggle(isOn: $creditCardAlert) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("profile.notifCardCycle"))
                        .font(.subheadline)
                    Text(t("profile.notifCardCycleDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: creditCardAlert) { _, enabled in
                Task {
                    if enabled { await NotificationService.shared.requestPermission() }
                    NotificationService.shared.scheduleCreditCardNotifications(context: modelContext)
                }
            }

            Toggle(isOn: $goalAlert) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("profile.notifGoal"))
                        .font(.subheadline)
                    Text(t("profile.notifGoalDesc"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: goalAlert) { _, enabled in
                if enabled {
                    Task {
                        await NotificationService.shared.requestPermission()
                        NotificationService.shared.checkGoalAlerts(context: modelContext)
                    }
                }
            }
        } header: {
            Text(t("profile.notifications"))
        } footer: {
            Text(t("profile.notifFooter"))
        }
    }

    // MARK: - Preferences Section

    private var preferencesSection: some View {
        Section(t("settings.preferences")) {
            Picker(t("settings.currency"), selection: $currencyCode) {
                ForEach(OnboardingCurrency.all) { c in
                    Text("\(c.flag)  \(c.code) (\(c.symbol)) · \(c.name)")
                        .tag(c.code)
                }
            }

            Picker(t("settings.theme"), selection: $colorScheme) {
                Text(t("settings.themeLight")).tag("light")
                Text(t("settings.themeDark")).tag("dark")
            }
        }
    }

    private func normalizeColorScheme() {
        if colorScheme == "system" {
            colorScheme = "light"
        }
    }

    private var aboutSection: some View {
        Section(t("settings.about")) {
            LabeledContent(t("settings.version"), value: "1.0.0 (Sprint 1)")
            LabeledContent(t("settings.design"),  value: t("settings.designValue"))
        }
    }
}
