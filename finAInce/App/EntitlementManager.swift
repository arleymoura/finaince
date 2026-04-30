import Foundation
import StoreKit
import SwiftUI

// MARK: - EntitlementManager
//
// Gerencia a feature paga "finAInce Cloud" (Backup + Multi devices).
// Produto: Non-Consumable — "finaince.cloud.lifetime"
// Implementado com StoreKit 2 (async/await, iOS 15+).

@Observable final class EntitlementManager {
    static let shared = EntitlementManager()

    // MARK: - Product ID
    static let productID = "finaince.cloud.lifetime"

    // MARK: - State
    private(set) var purchaseState: PurchaseState = .notPurchased
    private(set) var isPurchasing  = false
    private(set) var isRestoring   = false
    private(set) var product: Product?
    private(set) var purchaseError: String?
    private(set) var isLoadingProduct = false
    private(set) var productLoadError: String?

    enum PurchaseState {
        /// Nunca comprou
        case notPurchased
        /// Comprou nesta sessão — aguarda reinício para ativar CloudKit
        case purchasedPendingRestart
        /// Comprou em sessão anterior — CloudKit já ativo desde o launch
        case active
    }

    // MARK: - Persistence
    private let enabledKey = "finaince.cloud.enabled"
    private let awaitingInitialSyncKey = "finaince.cloud.awaitingInitialSync"
    private let activationDateKey = "finaince.cloud.activationDate"

    // MARK: - Background listener
    private var updateListenerTask: Task<Void, Never>?

    // MARK: - Init
    private init() {
        if UserDefaults.standard.bool(forKey: enabledKey) {
            purchaseState = .active
        }
        DebugLaunchLog.log("☁️ [Cloud] init enabled=\(UserDefaults.standard.bool(forKey: enabledKey)) awaitingInitialSync=\(UserDefaults.standard.bool(forKey: awaitingInitialSyncKey)) state=\(String(describing: purchaseState))")
        updateListenerTask = listenForTransactions()
        Task { await loadProduct() }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Computed
    var isCloudEnabled: Bool   { purchaseState == .active }
    var isNotPurchased: Bool   { purchaseState == .notPurchased }
    var isPendingRestart: Bool { purchaseState == .purchasedPendingRestart }
    var isAwaitingInitialSync: Bool { UserDefaults.standard.bool(forKey: awaitingInitialSyncKey) }
    var shouldForceInitialSyncRecovery: Bool {
        if isAwaitingInitialSync { return true }
        guard
            let activatedAt = UserDefaults.standard.object(forKey: activationDateKey) as? Date,
            UserDefaults.standard.bool(forKey: enabledKey)
        else {
            return false
        }

        return Date().timeIntervalSince(activatedAt) < 600
    }

    // MARK: - Load product

    @MainActor
    func loadProduct() async {
        isLoadingProduct = true
        productLoadError = nil
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
            if let product {
                DebugLaunchLog.log("☁️ [Cloud] Product loaded id=\(product.id) price=\(product.displayPrice)")
            } else {
                productLoadError = "Produto indisponível no momento."
                DebugLaunchLog.log("☁️ [Cloud] Product list returned empty for id=\(Self.productID)")
            }
        } catch {
            product = nil
            productLoadError = "Não foi possível carregar o produto agora."
            print("☁️ [Cloud] Erro ao carregar produto: \(error)")
            DebugLaunchLog.log("☁️ [Cloud] Product load failed id=\(Self.productID) error=\(error.localizedDescription)")
        }
        isLoadingProduct = false
    }

    // MARK: - Purchase

    @MainActor
    func clearError() {
        purchaseError = nil
    }

    @MainActor
    func purchase() async {
        guard let product else {
            purchaseError = "Produto não disponível. Verifique sua conexão."
            return
        }
        isPurchasing  = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await transaction.finish()
                activate()
                print("☁️ [Cloud] ✅ Compra confirmada — transactionID=\(transaction.id)")

            case .userCancelled:
                print("☁️ [Cloud] Compra cancelada pelo usuário")

            case .pending:
                print("☁️ [Cloud] Compra pendente (aguarda aprovação parental ou Ask to Buy)")

            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            print("☁️ [Cloud] ❌ Erro na compra: \(error)")
        }

        isPurchasing = false
    }

    // MARK: - Restore

    @MainActor
    func restorePurchases() async {
        isRestoring   = true
        purchaseError = nil

        do {
            // AppStore.sync() reconcilia o estado local com o servidor da Apple
            try await AppStore.sync()

            var found = false
            for await result in StoreKit.Transaction.currentEntitlements {
                if case .verified(let transaction) = result,
                   transaction.productID == Self.productID {
                    await transaction.finish()
                    activate()
                    found = true
                    print("☁️ [Cloud] ✅ Compra restaurada — transactionID=\(transaction.id)")
                    break
                }
            }

            if !found {
                purchaseError = "Nenhuma compra encontrada para restaurar."
                print("☁️ [Cloud] Nenhuma entitlement encontrada para \(Self.productID)")
            }
        } catch {
            purchaseError = error.localizedDescription
            print("☁️ [Cloud] ❌ Erro ao restaurar: \(error)")
        }

        isRestoring = false
    }

    // MARK: - Background transaction listener
    //
    // Captura compras finalizadas fora do app (ex: App Store, outro dispositivo,
    // Ask to Buy aprovado) e atualiza o estado sem precisar de interação do usuário.

    private func listenForTransactions() -> Task<Void, Never> {
        Task.detached(priority: .background) { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { break }
                do {
                    let transaction = try self.checkVerified(result)
                    if transaction.productID == Self.productID {
                        await transaction.finish()
                        await MainActor.run { self.activate() }
                        print("☁️ [Cloud] ✅ Transação recebida em background — id=\(transaction.id)")
                    }
                } catch {
                    print("☁️ [Cloud] ❌ Transação inválida ignorada: \(error)")
                }
            }
        }
    }

    // MARK: - Helpers

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let value):
            return value
        }
    }

    @MainActor
    private func activate() {
        UserDefaults.standard.set(true, forKey: enabledKey)
        UserDefaults.standard.set(true, forKey: awaitingInitialSyncKey)
        UserDefaults.standard.set(Date(), forKey: activationDateKey)
        UserDefaults.standard.synchronize()
        purchaseState = .purchasedPendingRestart
        DebugLaunchLog.log("☁️ [Cloud] activate enabled=true awaitingInitialSync=true state=purchasedPendingRestart")
    }

    @MainActor
    func markInitialSyncCompleted() {
        UserDefaults.standard.set(false, forKey: awaitingInitialSyncKey)
        UserDefaults.standard.removeObject(forKey: activationDateKey)
        if UserDefaults.standard.bool(forKey: enabledKey) {
            purchaseState = .active
        }
        DebugLaunchLog.log("☁️ [Cloud] Initial sync marked as completed")
    }

    #if DEBUG
    @MainActor
    func debugDisableCloudEntitlement() {
        UserDefaults.standard.set(false, forKey: enabledKey)
        UserDefaults.standard.set(false, forKey: awaitingInitialSyncKey)
        UserDefaults.standard.removeObject(forKey: activationDateKey)
        UserDefaults.standard.synchronize()
        purchaseError = nil
        purchaseState = .notPurchased
        DebugLaunchLog.log("☁️ [Cloud][DEBUG] Local entitlement reset to notPurchased")
    }
    #endif
}
