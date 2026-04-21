import SwiftUI
import UniformTypeIdentifiers

// MARK: - CSVImportInfoView

/// Tela de entrada do fluxo de importação.
/// Gerencia tudo em uma única sheet: mostra a info → quando o usuário escolhe
/// um arquivo, empurra o CSVImportReviewView dentro do mesmo NavigationStack.
/// Isso evita o problema de encadear duas sheets (a segunda aparecia em branco).
private struct IdentifiableURL: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let accountId: UUID?
}

struct CSVImportInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showPicker  = false
    @State private var pickedURL: IdentifiableURL? = nil
    @State private var lastImportedSummary: ImportedStatementSummary? = ImportStatementStore.currentSummary()

    // MARK: - Body

    var body: some View {
        
        NavigationStack {
            infoContent
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                    }
                }
                .navigationDestination(
                    isPresented: Binding(
                        get: { pickedURL != nil },
                        set: { if !$0 { pickedURL = nil } }
                    )
                ) {
                    if let url = pickedURL {
                        CSVImportReviewView(
                            csvURL: url.url,
                            initialAccountId: url.accountId,
                            onDismissSheet: {
                                dismiss()
                                SharedImportManager.shared.clearPendingFile()
                            }
                        )
                    }
                }
        }
        .onAppear {
            if let file = SharedImportManager.shared.pendingFile {
                if let savedURL = try? saveImportedStatement(from: file.url) {
                    lastImportedSummary = ImportStatementStore.currentSummary()
                    pickedURL = IdentifiableURL(url: savedURL, accountId: nil)
                }
                SharedImportManager.shared.clearPendingFile()
            } else {
                lastImportedSummary = ImportStatementStore.currentSummary()
            }
        }
        .fileImporter(
            isPresented: $showPicker,
            allowedContentTypes: ([
                .commaSeparatedText,
                .tabSeparatedText,
                .plainText,
                // XLSX (.xlsx) — ZIP+XML, suportado
                UTType("org.openxmlformats.spreadsheetml.sheet"),
                // XLS legado (.xls) — detectado e bloqueado com mensagem clara
                UTType("com.microsoft.excel.xls"),
            ] as [UTType?]).compactMap { $0 },
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                if let savedURL = try? saveImportedStatement(from: url) {
                    lastImportedSummary = ImportStatementStore.currentSummary()
                    pickedURL = IdentifiableURL(url: savedURL, accountId: nil)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }

    // MARK: - Info content

    private var infoContent: some View {
        ScrollView {
            VStack(spacing: 36) {
                heroSection

                if let summary = lastImportedSummary,
                   let storedURL = ImportStatementStore.currentFileURL() {
                    VStack(alignment: .center, spacing: 14) {
                        Text("Último arquivo enviado")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        latestImportSection(summary: summary, storedURL: storedURL)
                    }
                    importAnotherButton
                } else {
                    formatsSection
                    shareSection
                    ctaButton
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .navigationTitle(t("import.navTitle"))
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Hero

    private var heroSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 88, height: 88)
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 8) {
                Text(t("import.title"))
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(t("import.subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Accepted formats

    private var formatsSection: some View {
        VStack(alignment: .center, spacing: 14) {
            Text(t("import.formatsTitle"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing:12) {
                FormatBadge(label: "CSV",   ext: ".csv",   icon: "doc.text.fill",   color: .green)
                FormatBadge(label: "Excel", ext: ".xlsx",  icon: "tablecells.fill",  color: .blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bank hint

    private var bankHintSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "lightbulb.fill")
                .font(.subheadline)
                .foregroundStyle(.yellow)
                .padding(.top, 2)

            Text(t("import.bankHint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Share hint

    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "square.and.arrow.up.circle.fill")
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                Text(t("import.shareTitle"))
                    .font(.subheadline.bold())
            }

            Text(t("import.shareHint"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Step-by-step
            VStack(alignment: .leading, spacing: 10) {
                ShareStep(number: 1, icon: "building.columns",     label: t("import.shareStep1"))
                ShareStep(number: 2, icon: "square.and.arrow.up",  label: t("import.shareStep2"),
                          detail: "( ↑ )")
                ShareStep(number: 3, icon: "checkmark.circle",     label: t("import.shareStep3"))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accentColor.opacity(0.15), lineWidth: 1))
    }

    // MARK: - CTA

    private var ctaButton: some View {
        Button { showPicker = true } label: {
            Label(t("import.chooseFile"), systemImage: "folder.badge.plus")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private var importAnotherButton: some View {
        Button { showPicker = true } label: {
            Label("Importar outro extrato", systemImage: "arrow.clockwise.circle")
                .font(.body.bold())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    private func latestImportSection(summary: ImportedStatementSummary, storedURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "doc.text.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.fileName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(summary.storedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                importStatusPill(title: "Novos", value: summary.newCount, color: .blue)
                importStatusPill(title: "Conciliados", value: summary.reconciledCount, color: .green)
                importStatusPill(title: "Total", value: summary.totalCount, color: .secondary)
            }

            Button {
                pickedURL = IdentifiableURL(url: storedURL, accountId: summary.accountId)
            } label: {
                Label("Continuar importação", systemImage: "arrow.right.circle")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)

            Button(role: .destructive) {
                deleteSavedStatement()
            } label: {
                Label("Excluir extrato", systemImage: "trash")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func importStatusPill(title: String, value: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.headline.weight(.semibold))
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func saveImportedStatement(from url: URL) throws -> URL {
        _ = try ImportStatementStore.replaceCurrentFile(with: url)
        guard let storedURL = ImportStatementStore.currentFileURL() else {
            throw CocoaError(.fileNoSuchFile)
        }
        return storedURL
    }

    private func deleteSavedStatement() {
        ImportStatementStore.deleteCurrent()
        lastImportedSummary = nil
        pickedURL = nil
    }
}

// MARK: - Share Step

private struct ShareStep: View {
    let number: Int
    let icon:   String
    let label:  String
    var detail: String = ""

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 28, height: 28)
                Text("\(number)")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
            }

            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(.primary)

            if !detail.isEmpty {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Format Badge

private struct FormatBadge: View {
    let label: String
    let ext:   String
    let icon:  String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline.bold())
                Text(ext)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospaced()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }
}
