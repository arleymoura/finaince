import Foundation
import UserNotifications
import SwiftData

// MARK: - Notification Service

final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    private let center = UNUserNotificationCenter.current()

    // MARK: - Permission

    /// Solicita permissão ao usuário. Retorna true se autorizado.
    @discardableResult
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    /// Verifica se as notificações estão autorizadas pelo sistema.
    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule All

    /// Ponto de entrada único: agenda pagamentos e verifica metas.
    /// Deve ser chamado no launch e ao entrar em foreground.
    func scheduleAll(context: ModelContext) {
        schedulePaymentNotifications(context: context)
        scheduleCreditCardNotifications(context: context)
        checkGoalAlerts(context: context)
    }

    // MARK: - 1. Alerta de Dia de Pagamento

    /// Agenda uma notificação às 9h no dia de cada despesa não paga futura.
    func schedulePaymentNotifications(context: ModelContext) {
        // Remove todas as notificações de pagamento pendentes
        removeAll(prefix: "payment-")

        guard UserDefaults.standard.bool(forKey: "notif.pendingExpense") else { return }

        guard let transactions = try? context.fetch(FetchDescriptor<Transaction>()) else { return }

        let now   = Calendar.current.startOfDay(for: Date())
        let limit = Calendar.current.date(byAdding: .day, value: 60, to: now)! // janela de 60 dias

        let upcoming = transactions.filter {
            $0.type == .expense &&
            !$0.isPaid         &&
            $0.date >= now     &&
            $0.date <= limit
        }

        for tx in upcoming {
            let content           = UNMutableNotificationContent()
            content.title         = t("notif.pendingExpenseTitle")
            content.body          = "\(tx.placeName ?? t("notif.pendingExpenseFallback")) · \(tx.amount.asCurrency())"
            content.sound         = .default
            content.interruptionLevel = .timeSensitive

            var comps      = Calendar.current.dateComponents([.year, .month, .day], from: tx.date)
            comps.hour     = 9
            comps.minute   = 0
            comps.second   = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(
                identifier: "payment-\(tx.id.uuidString)",
                content:    content,
                trigger:    trigger
            )
            center.add(request)
        }
    }

    // MARK: - 2. Alertas de Cartão de Crédito

    /// Agenda lembretes da véspera de fechamento e do vencimento da fatura.
    func scheduleCreditCardNotifications(context: ModelContext) {
        removeAll(prefix: "card-closing-")
        removeAll(prefix: "card-due-")

        guard UserDefaults.standard.bool(forKey: "notif.creditCardCycle") else { return }
        guard let accounts = try? context.fetch(FetchDescriptor<Account>()) else { return }

        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let limit = calendar.date(byAdding: .day, value: 60, to: now) ?? now
        let creditCards = accounts.filter { $0.type == .creditCard }

        for account in creditCards {
            scheduleClosingReminder(for: account, calendar: calendar, now: now, limit: limit)
            scheduleDueReminder(for: account, calendar: calendar, now: now, limit: limit)
        }
    }

    // MARK: - 3. Alerta de Meta Próxima

    /// Dispara notificação imediata quando os gastos atingem ≥80% de uma meta ativa.
    /// Cada meta só notifica uma vez por mês (rastreado via UserDefaults).
    func checkGoalAlerts(context: ModelContext) {
        guard UserDefaults.standard.bool(forKey: "notif.goalAlert") else { return }

        guard
            let goals        = try? context.fetch(FetchDescriptor<Goal>()),
            let transactions = try? context.fetch(FetchDescriptor<Transaction>())
        else { return }

        let cal      = Calendar.current
        let now      = Date()
        let month    = cal.component(.month, from: now)
        let year     = cal.component(.year,  from: now)
        let monthKey = "\(year)-\(month)"

        let monthExpenses = transactions.filter {
            let c = cal.dateComponents([.month, .year], from: $0.date)
            return c.month == month && c.year == year && $0.type == .expense && $0.isPaid
        }

        var notifiedKeys = Set(UserDefaults.standard.stringArray(forKey: "notif.notifiedGoals") ?? [])

        for goal in goals where goal.isActive {
            let fireKey = "\(goal.id.uuidString)-\(monthKey)"
            guard !notifiedKeys.contains(fireKey) else { continue }

            let spent = monthExpenses
                .filter { matchesGoal($0, goal: goal) }
                .reduce(0) { $0 + $1.amount }

            let pct = goal.targetAmount > 0 ? spent / goal.targetAmount : 0
            guard pct >= 0.8 else { continue }

            let content           = UNMutableNotificationContent()
            content.title         = t("notif.goalLimitTitle")
            content.body          = String(
                format: t("notif.goalLimitBody"),
                goal.title,
                Int(pct * 100),
                goal.targetAmount.asCurrency()
            )
            content.sound         = .default

            // Dispara após 1 segundo (notificação imediata)
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            let request = UNNotificationRequest(
                identifier: "goal-\(fireKey)",
                content:    content,
                trigger:    trigger
            )
            center.add(request)
            notifiedKeys.insert(fireKey)
        }

        UserDefaults.standard.set(Array(notifiedKeys), forKey: "notif.notifiedGoals")
    }

    // MARK: - Helpers

    private func removeAll(prefix: String) {
        center.getPendingNotificationRequests { requests in
            let ids = requests
                .filter { $0.identifier.hasPrefix(prefix) }
                .map    { $0.identifier }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
        }
    }

    private func scheduleClosingReminder(for account: Account, calendar: Calendar, now: Date, limit: Date) {
        guard let closingDay = account.ccBillingEndDay else { return }

        for monthStart in upcomingMonthStarts(from: now, calendar: calendar) {
            guard
                let closingDate = clippedDate(for: closingDay, in: monthStart, calendar: calendar),
                let reminderDateRaw = calendar.date(byAdding: .day, value: -1, to: closingDate)
            else { continue }

            let reminderDate = calendar.startOfDay(for: reminderDateRaw)
            guard reminderDate >= now, reminderDate <= limit else { continue }

            let content = UNMutableNotificationContent()
            content.title = t("notif.cardClosingSoonTitle")
            content.body = String(format: t("notif.cardClosingSoonBody"), account.name)
            content.sound = .default
            content.interruptionLevel = .active

            var comps = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            comps.hour = 9
            comps.minute = 0
            comps.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifierDate = isoDayString(reminderDate, calendar: calendar)
            let request = UNNotificationRequest(
                identifier: "card-closing-\(account.id.uuidString)-\(identifierDate)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func scheduleDueReminder(for account: Account, calendar: Calendar, now: Date, limit: Date) {
        guard let dueDay = account.ccPaymentDueDay else { return }

        for monthStart in upcomingMonthStarts(from: now, calendar: calendar) {
            guard let dueDate = clippedDate(for: dueDay, in: monthStart, calendar: calendar) else { continue }
            let reminderDate = calendar.startOfDay(for: dueDate)
            guard reminderDate >= now, reminderDate <= limit else { continue }

            let content = UNMutableNotificationContent()
            content.title = t("notif.cardDueTodayTitle")
            content.body = String(format: t("notif.cardDueTodayBody"), account.name)
            content.sound = .default
            content.interruptionLevel = .timeSensitive

            var comps = calendar.dateComponents([.year, .month, .day], from: reminderDate)
            comps.hour = 9
            comps.minute = 0
            comps.second = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let identifierDate = isoDayString(reminderDate, calendar: calendar)
            let request = UNNotificationRequest(
                identifier: "card-due-\(account.id.uuidString)-\(identifierDate)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }

    private func upcomingMonthStarts(from date: Date, calendar: Calendar) -> [Date] {
        guard let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: date)) else {
            return []
        }

        return (0...2).compactMap { offset in
            calendar.date(byAdding: .month, value: offset, to: currentMonthStart)
        }
    }

    private func clippedDate(for day: Int, in monthStart: Date, calendar: Calendar) -> Date? {
        guard let maxDay = calendar.range(of: .day, in: .month, for: monthStart)?.count else { return nil }
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        return calendar.date(from: DateComponents(
            year: components.year,
            month: components.month,
            day: min(day, maxDay)
        ))
    }

    private func isoDayString(_ date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private func matchesGoal(_ tx: Transaction, goal: Goal) -> Bool {
        guard tx.type == .expense else { return false }
        return goal.matches(tx)
    }
}
