import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var aiSettingsList: [AISettings]

    @AppStorage("notif.pendingExpense") private var paymentAlert = false
    @AppStorage("notif.goalAlert")      private var goalAlert   = false
    @AppStorage("app.currencyCode")     private var currencyCode = "BRL"
    @AppStorage("app.colorScheme")      private var colorScheme  = "light"

    @State private var showSavedAlert = false
    private var lm: LanguageManager { LanguageManager.shared }

    var aiSettings: AISettings? { aiSettingsList.first }

    var body: some View {
        NavigationStack {
            Form {
                familySection
                aiSection
                languageSection
                notificationsSection
                preferencesSection
                aboutSection
            }
            .navigationTitle(t("settings.title"))
            .alert(t("settings.saved"), isPresented: $showSavedAlert) {
                Button(t("common.ok")) { }
            }
            .onAppear(perform: normalizeColorScheme)
        }
    }

    // MARK: - Sections

    private var familySection: some View {
        Section(t("settings.family")) {
            NavigationLink {
                Text(t("settings.familyComing"))
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
