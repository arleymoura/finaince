import SwiftUI

struct ContentView: View {
    var body: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            iPadRootView()
        } else {
            iPhoneRootView()
        }
    }
}

// MARK: - iPhone Layout (TabView)

private struct iPhoneRootView: View {
    @State private var showNewTransaction = false
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                DashboardView()
                    .tabItem { Label("Dashboard", systemImage: "chart.pie.fill") }
                    .tag(0)

                TransactionListView()
                    .tabItem { Label("Extrato", systemImage: "list.bullet.rectangle") }
                    .tag(1)

                Color.clear
                    .tabItem { Label("", systemImage: "") }
                    .tag(2)

                AccountsView()
                    .tabItem { Label("Contas", systemImage: "creditcard.fill") }
                    .tag(3)

                ChatView()
                    .tabItem { Label("IA", systemImage: "sparkles") }
                    .tag(4)
            }
            .sheet(isPresented: $showNewTransaction) {
                NewTransactionFlowView()
            }

            Button {
                showNewTransaction = true
            } label: {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                    )
            }
            .offset(y: -28)
        }
    }
}

// MARK: - iPad Layout (NavigationSplitView)

private struct iPadRootView: View {
    @State private var showNewTransaction = false

    enum Destination: Hashable {
        case dashboard, transactions, accounts, chat, analysis, settings
    }

    @State private var selectedDestination: Destination? = .dashboard

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedDestination) {
                Section("Principal") {
                    Label("Dashboard",   systemImage: "chart.pie.fill")
                        .tag(Destination.dashboard)
                    Label("Extrato",     systemImage: "list.bullet.rectangle")
                        .tag(Destination.transactions)
                    Label("Contas",      systemImage: "creditcard.fill")
                        .tag(Destination.accounts)
                }
                Section("Inteligência") {
                    Label("Chat IA",     systemImage: "bubble.left.and.bubble.right.fill")
                        .tag(Destination.chat)
                    Label("Análise IA",  systemImage: "chart.line.uptrend.xyaxis")
                        .tag(Destination.analysis)
                }
                Section("Conta") {
                    Label("Configurações", systemImage: "gearshape.fill")
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
            case .transactions:   TransactionListView()
            case .accounts:       AccountsView()
            case .chat:           ChatView()
            case .analysis:       AnalysisView()
            case .settings:       SettingsView()
            }
        }
        .sheet(isPresented: $showNewTransaction) {
            NewTransactionFlowView()
        }
    }
}
