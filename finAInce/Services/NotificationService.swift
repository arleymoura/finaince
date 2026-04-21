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
            content.title         = "Pagamento pendente"
            content.body          = "\(tx.placeName ?? "Despesa") · \(tx.amount.asCurrency())"
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

    // MARK: - 2. Alerta de Meta Próxima

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
            content.title         = "Meta próxima do limite ⚠️"
            content.body          = "'\(goal.title)' está em \(Int(pct * 100))% — limite \(goal.targetAmount.asCurrency())"
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

    private func matchesGoal(_ tx: Transaction, goal: Goal) -> Bool {
        guard tx.type == .expense else { return false }
        guard let goalCategory = goal.category else { return true } // meta global
        let root = tx.category?.parent ?? tx.category
        return root?.id == goalCategory.id
    }
}
