import SwiftUI
import SwiftData

@main
struct FamilyFinanceApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(
                for: Family.self,
                     Account.self,
                     Category.self,
                     Transaction.self,
                     AISettings.self,
                     AIAnalysis.self,
                     ChatConversation.self,
                     ChatMessage.self
            )
        } catch {
            fatalError("Falha ao criar ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .task { seedIfNeeded() }
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func seedIfNeeded() {
        let key = "hasSeededDefaultData"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        DefaultCategories.seed(in: modelContainer.mainContext)
        SampleData.seed(in: modelContainer.mainContext)
        UserDefaults.standard.set(true, forKey: key)
    }
}
