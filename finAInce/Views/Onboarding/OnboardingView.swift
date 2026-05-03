import SwiftUI
import SwiftData

// MARK: - FixedExpenseItem

struct FixedExpenseItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    let iconColor: Color
    let description: String
    let categorySystemKey: String
    let subcategorySystemKey: String?
}

extension FixedExpenseItem {
    static let all: [FixedExpenseItem] = [
        .init(id: "aluguel",    name: "Aluguel",
              icon: "house.fill",           iconColor: Color(hex: "#5E5CE6"),
              description: "Pagamento mensal de aluguel",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.rent"),
        .init(id: "condominio", name: "Condomínio",
              icon: "building.2.fill",      iconColor: Color(hex: "#8E8E93"),
              description: "Taxa condominial",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.condo"),
        .init(id: "agua",       name: "Água",
              icon: "drop.fill",            iconColor: Color(hex: "#32ADE6"),
              description: "Conta de água",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.water"),
        .init(id: "luz",        name: "Luz",
              icon: "bolt.fill",            iconColor: Color(hex: "#FF9F0A"),
              description: "Conta de energia elétrica",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.energy"),
        .init(id: "internet",   name: "Internet",
              icon: "wifi",                 iconColor: Color(hex: "#30B0C7"),
              description: "Internet fixa",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.internet"),
        .init(id: "telefone",   name: "Telefone",
              icon: "iphone",              iconColor: Color(hex: "#636366"),
              description: "Plano de celular",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.phone"),
        .init(id: "tv",         name: "TV / Streaming",
              icon: "tv.fill",             iconColor: Color(hex: "#BF5AF2"),
              description: "TV a cabo ou streaming",
              categorySystemKey: "housing",   subcategorySystemKey: "housing.tvStreaming"),
        .init(id: "combo",      name: "Combo",
              icon: "shippingbox.fill",    iconColor: Color(hex: "#FF6B35"),
              description: "Pacote Telefone + Internet + TV",
              categorySystemKey: "housing",   subcategorySystemKey: nil),
        .init(id: "escola",     name: "Escola",
              icon: "book.fill",           iconColor: Color(hex: "#34C759"),
              description: "Mensalidade escolar",
              categorySystemKey: "education",  subcategorySystemKey: "education.school"),
        .init(id: "saude",      name: "Plano de Saúde",
              icon: "cross.fill",          iconColor: Color(hex: "#FF3B30"),
              description: "Mensalidade do plano de saúde",
              categorySystemKey: "health",     subcategorySystemKey: "health.insurance"),
    ]
    
    /// Expenses pre-selected based on family structure
    static func defaults(adults: Int, children: Int) -> Set<String> {
        var ids: Set<String> = ["agua", "luz", "internet", "telefone"]
        if children > 0 { ids.insert("escola") }
        if adults >= 2 || children > 0 { ids.insert("saude") }
        return ids
    }

    /// Localized display name (looks up ob.exp.<id>.name, falls back to PT)
    var displayName: String { t("ob.exp.\(id).name") }
    /// Localized display description
    var displayDesc: String { t("ob.exp.\(id).desc") }
}

// MARK: - BudgetGoalItem

struct BudgetGoalItem: Identifiable {
    let id: String
    let categorySystemKey: String?
    let categoryName: String
    let icon: String
    let color: Color
    let emoji: String
    let percentage: Double    // display percentage (0-100), already normalized
    var amount: Double
    var isEnabled: Bool

    /// Compute suggested monthly budget split based on family structure and income.
    static func compute(adults: Int, children: Int, budget: Double) -> [BudgetGoalItem] {
        let ch = Double(min(children, 4))

        // Raw allocations — will be normalized
        let raw: [(id: String, systemKey: String?, name: String, pct: Double, emoji: String, icon: String, hex: String)] = [
            ("moradia",      "housing",      "Moradia",      adults >= 2 ? 0.28 : 0.33, "🏠", "house.fill",              "#5E5CE6"),
            ("supermercado", "groceries",    "Supermercado", 0.12 + 0.018 * ch,         "🛒", "cart.fill",               "#FF9500"),
            ("restaurantes", "restaurants",  "Restaurantes", 0.06 + 0.007 * ch,         "🍽", "fork.knife",              "#FF6B35"),
            ("transporte",   "transport",    "Transporte",   max(0.07, 0.10 - 0.01 * ch), "🚗", "car.fill",             "#636366"),
            ("saude",        "health",       "Saúde",        0.07 + 0.012 * ch,         "❤️", "heart.fill",              "#FF3B30"),
            ("educacao",     "education",    "Educação",     0.03 + 0.09 * ch,          "📚", "book.fill",               "#34C759"),
            ("lazer",        "leisure",      "Lazer",        max(0.05, 0.12 - 0.025 * ch), "🎮", "gamecontroller.fill",  "#BF5AF2"),
            ("poupanca",     nil,            "Poupança",     0.12,                       "💰", "banknote.fill",           "#32ADE6"),
        ]

        let total = raw.reduce(0.0) { $0 + $1.pct }

        return raw.map { item in
            let normalized = item.pct / total
            return BudgetGoalItem(
                id:           item.id,
                categorySystemKey: item.systemKey,
                categoryName: item.name,
                icon:         item.icon,
                color:        Color(hex: item.hex),
                emoji:        item.emoji,
                percentage:   normalized * 100,
                amount:       normalized * budget,
                isEnabled:    item.id != "poupanca"   // savings shown for context only
            )
        }
    }

    /// Localized display name
    var displayName: String { t("ob.goal.\(id)") }
}

// MARK: - OnboardingView (main container)

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage("user.name")              private var storedName  = "Meu Perfil"
    @AppStorage("user.adultsCount")       private var storedAdults = 0
    @AppStorage("user.childrenCount")     private var storedChildren = 0
    @AppStorage("hasCompletedOnboarding") private var completed   = false
    @AppStorage("hasSeededDefaultData")   private var hasSeeded   = false

    // ── Shared state ────────────────────────────────────────────────────────
    @State private var step             = 0
    @State private var userName         = ""
    @State private var adultsCount      = 1
    @State private var childrenCount    = 0
    @State private var selectedExpenses = Set<String>()
    @State private var monthlyBudget: Double = 5000
    @State private var budgetGoals: [BudgetGoalItem] = []
    @State private var hasCreditCard     = false
    @State private var cardClosingDay    = 5
    @State private var cardPaymentDueDay = 12
    @State private var cardLimitText     = ""
    @State private var cardName          = t("ob.step5.cardDefault")
    @State private var hasSetupAI        = false
    @State private var isFinishing       = false
    @State private var navigationDirection = 1

    private let totalFormSteps = 7   // steps 0-6 are form; step 7 is success

    var body: some View {
        ZStack {
            OnboardingAmbientBackground()

            switch step {
            case 0:
                OnboardingNameStep(
                    userName: $userName,
                    progress: progress(for: 0),
                    onNext: { advance() }
                )
                .transition(slide)

            case 1:
                OnboardingFamilyStep(
                    adults: $adultsCount,
                    children: $childrenCount,
                    progress: progress(for: 1),
                    onBack: { back() },
                    onNext: {
                        // Pre-select expenses the first time based on family structure
                        if selectedExpenses.isEmpty {
                            selectedExpenses = FixedExpenseItem.defaults(adults: adultsCount, children: childrenCount)
                        }
                        advance()
                    }
                )
                .transition(slide)

            case 2:
                OnboardingExpensesStep(
                    selected: $selectedExpenses,
                    progress: progress(for: 2),
                    onBack: { back() },
                    onNext: { advance() }
                )
                .transition(slide)

            case 3:
                OnboardingBudgetStep(
                    budget: $monthlyBudget,
                    adultsCount: adultsCount,
                    childrenCount: childrenCount,
                    progress: progress(for: 3),
                    onBack: { back() },
                    onNext: {
                        budgetGoals = BudgetGoalItem.compute(
                            adults: adultsCount, children: childrenCount, budget: monthlyBudget
                        )
                        advance()
                    }
                )
                .transition(slide)

            case 4:
                OnboardingGoalsStep(
                    goals: $budgetGoals,
                    budget: monthlyBudget,
                    adults: adultsCount,
                    children: childrenCount,
                    progress: progress(for: 4),
                    onBack: { back() },
                    onNext: { advance() }
                )
                .transition(slide)

            case 5:
                OnboardingAccountStep(
                    hasCreditCard:  $hasCreditCard,
                    cardClosingDay: $cardClosingDay,
                    cardPaymentDueDay: $cardPaymentDueDay,
                    cardLimitText: $cardLimitText,
                    cardName:       $cardName,
                    progress: progress(for: 5),
                    onBack: { back() },
                    onNext: { advance() }
                )
                .transition(slide)

            case 6:
                OnboardingAIStep(
                    progress: progress(for: 6),
                    onBack: { back() },
                    onNext: { aiConfigured in
                        hasSetupAI = aiConfigured
                        advance()
                    }
                )
                .transition(slide)

            case 7:
                OnboardingSuccessStep(userName: userName, aiConfigured: hasSetupAI, onFinish: { finishOnboarding() })
                    .transition(slide)

            default:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }

    // MARK: - Navigation helpers

    private var slide: AnyTransition {
        let insertionEdge: Edge = navigationDirection >= 0 ? .trailing : .leading
        let removalEdge: Edge = navigationDirection >= 0 ? .leading : .trailing
        return .asymmetric(insertion: .move(edge: insertionEdge), removal: .move(edge: removalEdge))
    }

    private func advance() {
        withAnimation(.easeInOut) {
            navigationDirection = 1
            step = min(step + 1, totalFormSteps)
        }
    }

    private func back() {
        withAnimation(.easeInOut) {
            navigationDirection = -1
            step = max(step - 1, 0)
        }
    }

    private func progress(for s: Int) -> Double {
        Double(s + 1) / Double(totalFormSteps)
    }

    // MARK: - Finish

    private func finishOnboarding() {
        isFinishing = true

        // 1. Seed default categories if needed
        if !hasSeeded {
            DefaultCategories.seed(in: modelContext)
            hasSeeded = true
        }

        // 2. Save profile
        storedName = userName.trimmingCharacters(in: .whitespaces).isEmpty ? t("ob.step0.defaultName") : userName
        storedAdults = adultsCount
        storedChildren = childrenCount

        let family = Family(name: storedName)
        modelContext.insert(family)

        // 3. Create default checking account
        let checking = Account(
            name: t("ob.step5.checkingName"),
            type: .checking,
            icon: "building.columns.fill",
            color: "#5E5CE6",
            isDefault: true
        )
        checking.family = family
        modelContext.insert(checking)

        let wallet = Account(
            name: t("account.walletDefault"),
            type: .cash,
            icon: "wallet.bifold.fill",
            color: "#34C759",
            isDefault: false
        )
        wallet.family = family
        modelContext.insert(wallet)

        // 4. Create credit card if selected
        if hasCreditCard {
            let closingDay = cardClosingDay
            let dueDay     = cardPaymentDueDay
            let cc = Account(
                name: cardName.trimmingCharacters(in: .whitespaces).isEmpty ? t("ob.step5.cardFallback") : cardName,
                type: .creditCard,
                icon: "creditcard.fill",
                color: "#FF9500",
                ccBillingStartDay: closingDay < 28 ? closingDay + 1 : 1,
                ccBillingEndDay: closingDay,
                ccPaymentDueDay: dueDay,
                ccCreditLimit: parsedOnboardingCardLimit
            )
            cc.family = family
            modelContext.insert(cc)
        }

        // 5. Fetch categories for lookup
        let allCategories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []

        func findCategory(systemKey: String?) -> Category? {
            guard let systemKey else { return nil }
            return allCategories.first { $0.systemKey == systemKey }
        }

        // 6. Create recurring transactions for selected fixed expenses
        for itemId in selectedExpenses {
            guard let item = FixedExpenseItem.all.first(where: { $0.id == itemId }) else { continue }
            let category    = findCategory(systemKey: item.categorySystemKey)
            let subcategory = findCategory(systemKey: item.subcategorySystemKey)
            let base = Transaction(
                type: .expense, amount: 0,
                date: firstDayOfCurrentMonth(),
                placeName: item.name,
                recurrenceType: .monthly,
                isPaid: false
            )
            base.account     = checking
            base.family      = family
            base.category    = category
            base.subcategory = subcategory
            modelContext.insert(base)
            Transaction.generateMonthlyRecurrences(from: base, in: modelContext)
        }

        // 7. Create spending goals from the approved budget plan
        for goalItem in budgetGoals where goalItem.isEnabled && goalItem.id != "poupanca" {
            let category = findCategory(systemKey: goalItem.categorySystemKey)
            guard category != nil else { continue }   // skip if category not seeded yet
            let goal = Goal(
                title: goalItem.displayName,
                targetAmount: goalItem.amount.rounded(),
                emoji: goalItem.icon,
                category: category
            )
            goal.family = family
            modelContext.insert(goal)
        }

        // 8. Mark onboarding done
        completed = true
    }

    private func firstDayOfCurrentMonth() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month], from: Date())
        comps.day = 1
        return Calendar.current.date(from: comps) ?? Date()
    }

    private var parsedOnboardingCardLimit: Double? {
        let sanitized = cardLimitText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !sanitized.isEmpty else { return nil }
        return Double(sanitized)
    }
}

// MARK: - Shared: Progress Bar + Hero Shell

private struct OnboardingAmbientBackground: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isRegularLayout {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.85),
                            Color.accentColor.opacity(0.70)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()

                    Circle()
                        .fill(.white.opacity(0.12))
                        .frame(width: 320, height: 320)
                        .blur(radius: 80)
                        .offset(x: -120, y: -220)
                        .allowsHitTesting(false)

                    Circle()
                        .fill(.white.opacity(0.08))
                        .frame(width: 280, height: 280)
                        .blur(radius: 70)
                        .offset(x: 140, y: 260)
                        .allowsHitTesting(false)
                }
            } else {
                Color.white
                    .ignoresSafeArea()
            }
        }
    }
}

private let onboardingRegularMaxWidth: CGFloat = 1100
private let onboardingSuccessMaxWidth: CGFloat = 900
private let onboardingRegularSurfaceFill = Color.white.opacity(0.97)
private let onboardingCompactContentFill = Color.white
private let onboardingCompactCardFill = Color(.systemGray6)
private let onboardingSurfaceStroke = Color.black.opacity(0.08)

private struct OnboardingContentShellModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let cornerRadius: CGFloat

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var fillColor: Color {
        isRegularLayout ? onboardingRegularSurfaceFill : onboardingCompactContentFill
    }

    func body(content: Content) -> some View {
        if isRegularLayout {
            content
                .background(fillColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(onboardingSurfaceStroke, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.16), radius: 24, x: 0, y: 14)
        } else {
            content
                .background(fillColor)
        }
    }
}

private struct OnboardingSurfaceCardModifier: ViewModifier {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let cornerRadius: CGFloat

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    private var fillColor: Color {
        isRegularLayout ? onboardingRegularSurfaceFill : onboardingCompactCardFill
    }

    func body(content: Content) -> some View {
        content
            .background(fillColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(onboardingSurfaceStroke, lineWidth: 1)
            }
    }
}

private extension View {
    func onboardingRegularWidth(_ enabled: Bool, alignment: Alignment = .leading) -> some View {
        self
            .frame(maxWidth: enabled ? onboardingRegularMaxWidth : .infinity, alignment: alignment)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    func onboardingContentShell(cornerRadius: CGFloat = 28) -> some View {
        self
            .modifier(OnboardingContentShellModifier(cornerRadius: cornerRadius))
    }

    func onboardingSurfaceCard(cornerRadius: CGFloat = 14) -> some View {
        self
            .modifier(OnboardingSurfaceCardModifier(cornerRadius: cornerRadius))
    }

    func onboardingTitleFont() -> some View {
        self.font(.system(size: 30, weight: .bold, design: .rounded))
    }

    func onboardingHeroTitleFont() -> some View {
        self.font(.system(size: 28, weight: .bold, design: .rounded))
    }
}

struct OnboardingHero: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let title: String
    let subtitle: String
    let progress: Double
    let icon: String
    var privacyNote: String? = nil

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Icon badge
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.white.opacity(0.22))
                    .frame(width: 50, height: 50)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 2)

            Text(title)
                .onboardingHeroTitleFont()
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if let note = privacyNote {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.caption2.bold())
                    Text(note)
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.22))
                .clipShape(Capsule())
                .padding(.top, 4)
            }
        }
        .padding(24)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !isRegularLayout {
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.86),
                        Color.accentColor.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(
                    RoundedRectangle(cornerRadius: 0, style: .continuous)
                )
                .ignoresSafeArea(edges: .top)
            }
        }
        // Progress bar overlaid at top of hero (below safe area, above content)
        .overlay(alignment: .top) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Color.white.opacity(0.18)
                        .frame(maxWidth: .infinity)
                        .frame(height: 3)
                    Color.white
                        .frame(width: geo.size.width * progress, height: 3)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
            .frame(height: 3)
        }
        .overlay(alignment: .bottom) {
            if !isRegularLayout {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white)
                    .frame(height: 24)
                    .offset(y: 12)
            }
        }
        .onboardingRegularWidth(isRegularLayout)
    }
}

private struct OnboardingNavButtons: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let backLabel: String
    let nextLabel: String
    let canAdvance: Bool
    let isLoading: Bool
    let onBack: () -> Void
    let onNext: () -> Void

    init(backLabel: String? = nil,
         nextLabel: String? = nil,
         canAdvance: Bool = true,
         isLoading: Bool = false,
         onBack: @escaping () -> Void,
         onNext: @escaping () -> Void) {
        self.backLabel  = backLabel ?? t("ob.nav.back")
        self.nextLabel  = nextLabel ?? t("ob.nav.next")
        self.canAdvance = canAdvance
        self.isLoading  = isLoading
        self.onBack     = onBack
        self.onNext     = onNext
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Text(backLabel)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .onboardingSurfaceCard(cornerRadius: 14)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)

            Button(action: onNext) {
                Group {
                    if isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text(nextLabel).font(.headline)
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    canAdvance
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                            startPoint: .leading,
                            endPoint: .trailing
                        ))
                        : AnyShapeStyle(Color.white.opacity(0.22))
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(.white.opacity(canAdvance ? 0 : 0.18), lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
                .disabled(!canAdvance || isLoading)
        }
        .padding(20)
        .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .onboardingRegularWidth(isRegularLayout)
    }
}

// MARK: - Supported currencies (onboarding picker)

struct OnboardingCurrency: Identifiable, Hashable {
    let code: String
    let symbol: String
    let name: String
    let flag: String
    var id: String { code }

    static let all: [OnboardingCurrency] = [
        .init(code: "BRL", symbol: "R$", name: "Real",     flag: "🇧🇷"),
        .init(code: "USD", symbol: "$",  name: "Dollar",   flag: "🇺🇸"),
        .init(code: "EUR", symbol: "€",  name: "Euro",     flag: "🇪🇺"),
    ]
}

// MARK: - Step 0: Nome + Idioma + Moeda

private struct OnboardingNameStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var userName: String
    let progress: Double
    let onNext: () -> Void
    @State private var lm = LanguageManager.shared
    @State private var entitlements = EntitlementManager.shared
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    private var canAdvance: Bool {
        !userName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            // Hero (full-bleed welcome)
            VStack(alignment: .leading, spacing: 14) {
                Text("👋")
                    .font(.system(size: 48))
                Text(t("ob.step0.heroTitle"))
                    .onboardingTitleFont()
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(t("ob.step0.heroSubtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.86))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
                    .frame(maxWidth: 760, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if !isRegularLayout {
                    LinearGradient(
                        colors: [
                            Color.accentColor,
                            Color.accentColor.opacity(0.86),
                            Color.accentColor.opacity(0.72)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea(edges: .top)
                }
            }
            .overlay(alignment: .top) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Color.white.opacity(0.18).frame(maxWidth: .infinity).frame(height: 3)
                        Color.white
                            .frame(width: geo.size.width * progress, height: 3)
                            .animation(.easeInOut(duration: 0.4), value: progress)
                    }
                }
                .frame(height: 3)
            }
            .overlay(alignment: .bottom) {
                if !isRegularLayout {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.white)
                        .frame(height: 24)
                        .offset(y: 12)
                }
            }
            .onboardingRegularWidth(isRegularLayout)

            // Content
            ScrollView {
                VStack(spacing: 30) {
                    // Language + Currency selectors
                    HStack(spacing: 12) {
                        // Language
                        Menu {
                            ForEach(AppLanguage.allCases) { lang in
                                Button {
                                    lm.language = lang
                                } label: {
                                    if lm.language == lang {
                                        Label(lang.displayName, systemImage: "checkmark")
                                    } else {
                                        Text(lang.flag + "  " + lang.displayName)
                                    }
                                }
                            }
                        } label: {
                            pickerLabel(
                                caption: t("ob.step0.language"),
                                leading: lm.language.flag,
                                text: languageShortName(lm.language)
                            )
                        }

                        // Currency
                        Menu {
                            ForEach(OnboardingCurrency.all) { cur in
                                Button {
                                    currencyCode = cur.code
                                } label: {
                                    if currencyCode == cur.code {
                                        Label("\(cur.flag)  \(cur.code) — \(cur.name)", systemImage: "checkmark")
                                    } else {
                                        Text("\(cur.flag)  \(cur.code) — \(cur.name)")
                                    }
                                }
                            }
                        } label: {
                            pickerLabel(
                                caption: t("ob.step0.currency"),
                                leading: currentCurrency.flag,
                                text: "\(currentCurrency.code) \(currentCurrency.symbol)"
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("ob.step0.nameQuestion"))
                            .onboardingHeroTitleFont()
                            .foregroundStyle(.primary)
                        Text(t("ob.step0.nameDesc"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField(t("ob.step0.namePlaceholder"), text: $userName)
                        .font(.title3)
                        .padding(16)
                        .onboardingSurfaceCard(cornerRadius: 14)
                        .submitLabel(.next)
                        .onSubmit { if canAdvance { onNext() } }

                    VStack(alignment: .leading, spacing: 12) {
                        Divider()
                            .overlay(Color.black.opacity(0.06))

                        if entitlements.purchaseState == .purchasedPendingRestart {
                            Label(t("onboarding.cloudRestoredRestart"), systemImage: "checkmark.icloud.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        } else if entitlements.purchaseState == .active {
                            Label(t("onboarding.cloudAlreadyActive"), systemImage: "icloud.fill")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(t("onboarding.cloudOwnershipQuestion"))
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.secondary)

                                HStack(spacing: 10) {
                                    Button {
                                        Task { await entitlements.restorePurchases() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if entitlements.isRestoring {
                                                ProgressView()
                                                    .controlSize(.small)
                                                    .tint(Color.accentColor)
                                            }
                                            Text(t("cloud.restorePurchase"))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(entitlements.isRestoring || entitlements.isPurchasing)

                                    Text("|")
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.tertiary)

                                    Button {
                                        Task { await entitlements.purchase() }
                                    } label: {
                                        HStack(spacing: 6) {
                                            if entitlements.isPurchasing {
                                                ProgressView()
                                                    .controlSize(.small)
                                                    .tint(Color.accentColor)
                                            }
                                            Text(t("onboarding.cloudBuyNew"))
                                                .font(.subheadline.weight(.semibold))
                                        }
                                        .foregroundStyle(Color.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(entitlements.isRestoring || entitlements.isPurchasing || entitlements.product == nil)

                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                    }
                    .padding(.top, 2)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color.accentColor.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Spacer(minLength: 8)

                    if !isRegularLayout {
                        Button(action: onNext) {
                            Text(t("ob.nav.letsStart"))
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    canAdvance && entitlements.purchaseState != .purchasedPendingRestart
                                        ? AnyShapeStyle(LinearGradient(
                                            colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ))
                                        : AnyShapeStyle(Color.white.opacity(0.22))
                                )
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(.white.opacity(canAdvance && entitlements.purchaseState != .purchasedPendingRestart ? 0 : 0.18), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAdvance || entitlements.purchaseState == .purchasedPendingRestart)
                        .shadow(color: canAdvance && entitlements.purchaseState != .purchasedPendingRestart ? Color.black.opacity(0.16) : .clear, radius: 14, x: 0, y: 8)
                    }
                }
                .padding(28)
                .onboardingContentShell()
                .onboardingRegularWidth(isRegularLayout)
            }

            if isRegularLayout {
                Button(action: onNext) {
                    Text(t("ob.nav.letsStart"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            canAdvance && entitlements.purchaseState != .purchasedPendingRestart
                                ? AnyShapeStyle(LinearGradient(
                                    colors: [Color.accentColor, Color.accentColor.opacity(0.82)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ))
                                : AnyShapeStyle(Color.white.opacity(0.22))
                        )
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(.white.opacity(canAdvance && entitlements.purchaseState != .purchasedPendingRestart ? 0 : 0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(!canAdvance || entitlements.purchaseState == .purchasedPendingRestart)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .onboardingRegularWidth(isRegularLayout)
                .shadow(color: canAdvance && entitlements.purchaseState != .purchasedPendingRestart ? Color.black.opacity(0.16) : .clear, radius: 14, x: 0, y: 8)
            }
        }
        .overlay {
            if entitlements.purchaseState == .purchasedPendingRestart {
                ZStack {
                    Color.white
                        .opacity(0.98)
                        .ignoresSafeArea()

                    VStack(spacing: 24) {
                        FinAInceCloudRestartPrompt(
                            cloudColors: [
                                Color(red: 0.20, green: 0.45, blue: 0.90),
                                Color(red: 0.42, green: 0.25, blue: 0.85)
                            ],
                            allowsDismissLater: false
                        ) { }
                    }
                    .padding(24)
                }
                .transition(.opacity)
            }
        }
        .alert(t("common.error"), isPresented: Binding(
            get: { entitlements.purchaseError != nil },
            set: { if !$0 { entitlements.clearError() } }
        )) {
            Button(t("common.ok"), role: .cancel) {
                entitlements.clearError()
            }
        } message: {
            if let message = entitlements.purchaseError {
                Text(message)
            }
        }
    }

    // MARK: Helpers

    private var currentCurrency: OnboardingCurrency {
        OnboardingCurrency.all.first { $0.code == currencyCode }
            ?? OnboardingCurrency.all[0]
    }

    private func languageShortName(_ l: AppLanguage) -> String {
        switch l {
        case .ptBR:   return "PT-BR"
        case .en:     return "EN"
        case .es:     return "ES"
        case .system: return "EN"
        }
    }

    @ViewBuilder
    private func pickerLabel(caption: String, leading: String, text: String) -> some View {
        HStack(spacing: 8) {
            Text(leading).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(text)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .onboardingSurfaceCard(cornerRadius: 12)
    }
}

// MARK: - Step 1: Estrutura Familiar

private struct OnboardingFamilyStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var adults: Int
    @Binding var children: Int
    let progress: Double
    let onBack: () -> Void
    let onNext: () -> Void

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step1.heroTitle"),
                subtitle: t("ob.step1.heroSubtitle"),
                progress: progress,
                icon: "person.3.fill"
            )

            ScrollView {
                VStack(spacing: 20) {
                    HouseholdCompositionEditor(
                        adults: $adults,
                        children: $children
                    )

                    if !isRegularLayout {
                        OnboardingNavButtons(onBack: onBack, onNext: onNext)
                    }
                }
                .padding(20)
                .onboardingContentShell()
                .onboardingRegularWidth(isRegularLayout)
            }

            if isRegularLayout {
                OnboardingNavButtons(onBack: onBack, onNext: onNext)
            }
        }
    }
}

// MARK: - Step 2: Despesas Fixas

private struct OnboardingExpensesStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var selected: Set<String>
    let progress: Double
    let onBack: () -> Void
    let onNext: () -> Void

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step2.heroTitle"),
                subtitle: t("ob.step2.heroSubtitle"),
                progress: progress,
                icon: "arrow.clockwise.circle.fill"
            )

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(FixedExpenseItem.all.enumerated()), id: \.element.id) { idx, item in
                        expenseRow(item: item)
                        if idx < FixedExpenseItem.all.count - 1 {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .onboardingSurfaceCard(cornerRadius: 16)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)

                if !selected.isEmpty {
                    Text(selected.count == 1
                         ? t("ob.step2.selected", selected.count)
                         : t("ob.step2.selectedPlural", selected.count))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 12)
                }

                if !isRegularLayout {
                    OnboardingNavButtons(onBack: onBack, onNext: onNext)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 20)
            .onboardingContentShell()
            .onboardingRegularWidth(isRegularLayout)

            if isRegularLayout {
                OnboardingNavButtons(onBack: onBack, onNext: onNext)
            }
        }
    }

    private func expenseRow(item: FixedExpenseItem) -> some View {
        let isSelected = selected.contains(item.id)
        return Button {
            if isSelected { selected.remove(item.id) }
            else          { selected.insert(item.id) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(isSelected ? item.iconColor : item.iconColor.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .animation(.easeInOut(duration: 0.15), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.displayName).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                    Text(item.displayDesc).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? item.iconColor : Color(.systemGray4))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? item.iconColor.opacity(0.07) : Color.clear)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

// MARK: - Step 3: Orçamento

private struct OnboardingBudgetStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var budget: Double
    let adultsCount: Int
    let childrenCount: Int
    let progress: Double
    let onBack: () -> Void
    let onNext: () -> Void
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step3.heroTitle"),
                subtitle: t("ob.step3.heroSubtitle"),
                progress: progress,
                icon: "chart.pie.fill",
                privacyNote: t("ob.step3.privacy")
            )

            VStack(spacing: 32) {
                Spacer()

                // Big amount display
                VStack(spacing: 6) {
                    Text(t("ob.step3.monthlyIncome"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(budget.asCurrency(currencyCode))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.accentColor)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.1), value: budget)
                    Text(budgetLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                }

                // Slider
                VStack(spacing: 8) {
                    Slider(value: $budget, in: 1000...50000, step: 500)
                        .tint(Color.accentColor)
                    HStack {
                        Text(Double(1000).asCurrency(currencyCode)).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                        Text(Double(50000).asCurrency(currencyCode) + "+").font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)

                // Context card
                VStack(spacing: 10) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(t("ob.step3.privacyCard"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
                .padding(14)
                .onboardingSurfaceCard(cornerRadius: 12)
                .padding(.horizontal, 20)

                Spacer()

                if !isRegularLayout {
                    OnboardingNavButtons(onBack: onBack, onNext: onNext)
                }
            }
            .padding(20)
            .onboardingContentShell()
            .onboardingRegularWidth(isRegularLayout)

            if isRegularLayout {
                OnboardingNavButtons(onBack: onBack, onNext: onNext)
            }
        }
    }

    private var budgetLabel: String {
        let total = adultsCount + childrenCount
        switch budget {
        case ..<2000:  return t("ob.step3.labelLean")
        case ..<4000:  return total <= 2 ? t("ob.step3.labelIndividual") : t("ob.step3.labelBelow")
        case ..<8000:  return t("ob.step3.labelAverage")
        case ..<15000: return t("ob.step3.labelComfortable")
        default:       return t("ob.step3.labelAmple")
        }
    }
}

// MARK: - Step 4: Metas de Gastos

private struct OnboardingGoalsStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding var goals: [BudgetGoalItem]
    let budget: Double
    let adults: Int
    let children: Int
    let progress: Double
    let onBack: () -> Void
    let onNext: () -> Void
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step4.heroTitle"),
                subtitle: t("ob.step4.heroSubtitle"),
                progress: progress,
                icon: "sparkles"
            )

            ScrollView {
                VStack(spacing: 14) {
                    // Context badge
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.caption.bold())
                            .foregroundStyle(.purple)
                        Text((adults + children) == 1
                             ? t("ob.step4.badgeSingular", adults + children, budget.asCurrency(currencyCode))
                             : t("ob.step4.badgePlural", adults + children, budget.asCurrency(currencyCode)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.purple.opacity(0.08))
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Goal rows
                    VStack(spacing: 0) {
                        ForEach(Array(goals.enumerated()), id: \.element.id) { idx, goal in
                            goalRow(goal: goal, index: idx)
                            if idx < goals.count - 1 {
                                Divider().padding(.leading, 58)
                            }
                        }
                    }
                    .onboardingSurfaceCard(cornerRadius: 16)

                    Text(t("ob.step4.footer"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 8)
                .onboardingContentShell()
                .onboardingRegularWidth(isRegularLayout)

                if !isRegularLayout {
                    OnboardingNavButtons(onBack: onBack, onNext: onNext)
                        .padding(.top, 20)
                }
            }

            if isRegularLayout {
                OnboardingNavButtons(onBack: onBack, onNext: onNext)
            }
        }
    }

    private func goalRow(goal: BudgetGoalItem, index: Int) -> some View {
        let isPoupanca = goal.id == "poupanca"
        return HStack(spacing: 14) {
            // Icon
            Image(systemName: goal.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(goal.isEnabled ? goal.color : Color(.systemGray4))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            // Label + amount
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(goal.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(goal.isEnabled ? .primary : .secondary)
                    if isPoupanca {
                        Text(t("ob.step4.savingsTarget"))
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.purple.opacity(0.10))
                            .clipShape(Capsule())
                    }
                }
                Text(t("ob.step4.perMonth", goal.amount.asCurrency(currencyCode), Int(goal.percentage.rounded())))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Toggle (disabled for poupanca — informational only)
            if isPoupanca {
                Image(systemName: "info.circle")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("", isOn: Binding(
                    get: { goals[index].isEnabled },
                    set: { goals[index].isEnabled = $0 }
                ))
                .labelsHidden()
                .tint(goal.color)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .opacity(goal.isEnabled ? 1 : 0.5)
    }
}

// MARK: - Step 5: Contas

private struct OnboardingAccountStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @AppStorage("app.currencyCode") private var currencyCode = CurrencyOption.defaultCode
    @Binding var hasCreditCard: Bool
    @Binding var cardClosingDay: Int
    @Binding var cardPaymentDueDay: Int
    @Binding var cardLimitText: String
    @Binding var cardName: String
    let progress: Double
    let onBack: () -> Void
    let onNext: () -> Void

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step5.heroTitle"),
                subtitle: t("ob.step5.heroSubtitle"),
                progress: progress,
                icon: "building.columns.fill"
            )

            ScrollView {
                VStack(spacing: 16) {
                    // Conta corrente (always created)
                    HStack(spacing: 14) {
                        Image(systemName: "building.columns.fill")
                            .font(.title2)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(t("ob.step5.checkingName"))
                                .font(.subheadline.bold())
                            Text(t("ob.step5.checkingDesc"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .padding(16)
                    .onboardingSurfaceCard(cornerRadius: 14)

                    // Cartão de crédito
                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            Image(systemName: "creditcard.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(hasCreditCard ? Color.orange : Color(.systemGray4))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .animation(.easeInOut(duration: 0.2), value: hasCreditCard)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("ob.step5.creditTitle"))
                                    .font(.subheadline.bold())
                                Text(t("ob.step5.creditToggle"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $hasCreditCard).labelsHidden().tint(.orange)
                        }
                        .padding(16)

                        if hasCreditCard {
                            Divider().padding(.leading, 78)

                            HStack {
                                Text(t("ob.step5.nameLabel"))
                                    .font(.subheadline).foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                TextField(t("ob.step5.cardPlaceholder"), text: $cardName)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            Divider().padding(.leading, 78)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("ob.step5.closingDay"))
                                        .font(.subheadline)
                                    Text(t("ob.step5.closingDayDesc"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Stepper(t("ob.step5.dayPrefix", cardClosingDay), value: $cardClosingDay, in: 1...28)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            Divider().padding(.leading, 78)

                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("ob.step5.paymentDueDay"))
                                        .font(.subheadline)
                                    Text(t("ob.step5.paymentDueDayDesc"))
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Stepper(t("ob.step5.dayPrefix", cardPaymentDueDay), value: $cardPaymentDueDay, in: 1...31)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            Divider().padding(.leading, 78)

                            HStack(spacing: 10) {
                                Text(t("account.creditLimit"))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(width: 118, alignment: .leading)

                                Spacer()

                                Text((CurrencyOption(rawValue: currencyCode)
                                      ?? CurrencyOption(rawValue: CurrencyOption.defaultCode)
                                      ?? .usd).symbol)
                                    .font(.body.bold())
                                    .foregroundStyle(.secondary)

                                TextField("0.00", text: $cardLimitText)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 96)
                            }
                            .padding(.horizontal, 16).padding(.vertical, 12)

                            Text(t("ob.step5.closingHint"))
                                .font(.caption2).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16).padding(.bottom, 12)
                        }
                    }
                    .onboardingSurfaceCard(cornerRadius: 14)
                    .animation(.easeInOut(duration: 0.25), value: hasCreditCard)
                }
                .padding(20)
                .onboardingContentShell()
                .onboardingRegularWidth(isRegularLayout)

                if !isRegularLayout {
                    OnboardingNavButtons(
                        nextLabel: t("ob.nav.continue"),
                        onBack: onBack,
                        onNext: onNext
                    )
                        .padding(.top, 20)
                }
            }

            if isRegularLayout {
                OnboardingNavButtons(
                    nextLabel: t("ob.nav.continue"),
                    onBack: onBack,
                    onNext: onNext
                )
            }
        }
    }
}

// MARK: - Step 6: Configurar IA

private struct OnboardingAIStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let progress: Double
    let onBack: () -> Void
    let onNext: (Bool) -> Void   // Bool = whether AI was configured

    @Environment(\.modelContext) private var modelContext
    @Query private var aiSettingsList: [AISettings]
    @State private var showProviderSheet = false
    @State private var localConfigured: AIProvider? = nil

    private var isConfigured: Bool {
        localConfigured != nil || !aiSettingsList.isEmpty
    }

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingHero(
                title: t("ob.step6ai.heroTitle"),
                subtitle: t("ob.step6ai.heroSubtitle"),
                progress: progress,
                icon: "sparkles"
            )

            ScrollView {
                VStack(spacing: 10) {
                    // Option 1: Apple Intelligence
                    aiOptionCard(
                        icon: "applelogo",
                        iconColor: Color.primary,
                        title: t("ob.step6ai.optionAppleTitle"),
                        desc: t("ob.step6ai.optionAppleDesc"),
                        badge: t("ob.step6ai.badgeFree"),
                        isSelected: localConfigured == .local
                    ) {
                        configureAppleIntelligence()
                    }

                    // Option 2: Connect external AI
                    aiOptionCard(
                        icon: "link.circle.fill",
                        iconColor: Color.blue,
                        title: t("ob.step6ai.optionConnectTitle"),
                        desc: t("ob.step6ai.optionConnectDesc"),
                        badge: nil,
                        isSelected: localConfigured != nil && localConfigured != .local
                    ) {
                        showProviderSheet = true
                    }

                    // Option 3: Skip
                    Button { onNext(false) } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("ob.step6ai.optionSkipTitle"))
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Text(t("ob.step6ai.optionSkipDesc"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(16)
                        .onboardingSurfaceCard(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
                .onboardingContentShell()
                .onboardingRegularWidth(isRegularLayout)

                if !isRegularLayout {
                    OnboardingNavButtons(
                        nextLabel: isConfigured
                            ? t("ob.step6ai.continueConfigured")
                            : t("ob.nav.next"),
                        canAdvance: true,
                        onBack: onBack,
                        onNext: { onNext(isConfigured) }
                    )
                        .padding(.top, 20)
                }
            }

            if isRegularLayout {
                OnboardingNavButtons(
                    nextLabel: isConfigured
                        ? t("ob.step6ai.continueConfigured")
                        : t("ob.nav.next"),
                    canAdvance: true,
                    onBack: onBack,
                    onNext: { onNext(isConfigured) }
                )
            }
        }
        .sheet(isPresented: $showProviderSheet) {
            NavigationStack {
                AIProviderSettingsView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(t("common.done")) { showProviderSheet = false }
                                .fontWeight(.semibold)
                        }
                    }
            }
            .onDisappear {
                if let settings = aiSettingsList.first {
                    localConfigured = settings.provider
                }
            }
        }
    }

    // MARK: - Option card

    private func aiOptionCard(
        icon: String,
        iconColor: Color,
        title: String,
        desc: String,
        badge: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isSelected ? .white : iconColor)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.accentColor : iconColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let badge {
                            Text(badge)
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color(.systemGray4))
            }
            .padding(16)
            .background(
                isSelected
                    ? Color.accentColor.opacity(0.08)
                    : (isRegularLayout ? onboardingRegularSurfaceFill : onboardingCompactCardFill)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(
                        isSelected ? Color.accentColor.opacity(0.35) : Color.clear,
                        lineWidth: 1.5
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - Actions

    private func configureAppleIntelligence() {
        // Reutiliza settings existente se houver, senão cria um novo
        if let existing = aiSettingsList.first {
            existing.provider = .local
            existing.model = AIProvider.local.defaultModel
            existing.isConfigured = true
        } else {
            let settings = AISettings(provider: .local)
            settings.isConfigured = true
            modelContext.insert(settings)
        }
        localConfigured = .local
    }
}

// MARK: - Step 7: Sucesso + Descoberta

private struct OnboardingSuccessStep: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let userName: String
    let aiConfigured: Bool
    let onFinish: () -> Void

    private var isRegularLayout: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        ZStack {
            if isRegularLayout {
                OnboardingAmbientBackground()
            } else {
                LinearGradient(
                    colors: [
                        Color.accentColor,
                        Color.accentColor.opacity(0.86),
                        Color.accentColor.opacity(0.72)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                Spacer(minLength: 20)

                // Hero — celebration emoji + title + subtitle
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(.white.opacity(0.18))
                            .frame(width: 104, height: 104)
                        Circle()
                            .fill(.white.opacity(0.12))
                            .frame(width: 128, height: 128)
                            .blur(radius: 6)
                        Text("🎉")
                            .font(.system(size: 56))
                    }

                    Text(t("ob.step6.title", firstName.isEmpty ? "" : ", \(firstName)"))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(t("ob.step6.subtitle"))
                        .font(.body)
                        .foregroundStyle(.white.opacity(0.88))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 28)

                // "Next steps" reading block — informational, not card-like
                VStack(alignment: .leading, spacing: 22) {
                    Text(t("ob.step6.tryNow"))
                        .font(.footnote.weight(.semibold))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.75))
                        .textCase(.uppercase)

                    nextStepLine(
                        index: 1,
                        icon:     "doc.text.fill",
                        title:    t("ob.step6.f1Title"),
                        subtitle: t("ob.step6.f1Desc")
                    )

                    dividerLine

                    nextStepLine(
                        index: 2,
                        icon:     "plus.circle.fill",
                        title:    t("ob.step6.f2Title"),
                        subtitle: t("ob.step6.f2Desc")
                    )

                    dividerLine

                    nextStepLine(
                        index: 3,
                        icon:     aiConfigured ? "checkmark.seal.fill" : "sparkles",
                        title:    t("ob.step6.f3Title"),
                        subtitle: t("ob.step6.f3Desc")
                    )
                }
                .padding(.horizontal, 28)
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: 28)

                // CTA — inverted button on the colored bg
                Button(action: onFinish) {
                    Text(t("ob.nav.finish"))
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 18)
                        .background(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }
            .frame(maxWidth: isRegularLayout ? onboardingSuccessMaxWidth : .infinity)
            .frame(maxWidth: .infinity)
        }
    }

    private var firstName: String {
        userName.trimmingCharacters(in: .whitespaces).components(separatedBy: " ").first ?? ""
    }

    private var dividerLine: some View {
        Rectangle()
            .fill(.white.opacity(0.18))
            .frame(height: 1)
            .padding(.leading, 44)
    }

    private func nextStepLine(index: Int, icon: String,
                              title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Numbered step marker — understated, reads as a guidepost, not a button
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.55), lineWidth: 1)
                    .frame(width: 28, height: 28)
                Text("\(index)")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
    }
}
