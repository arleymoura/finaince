import SwiftUI
import SwiftData
import Vision
import UIKit

// MARK: - Receipt Scanner

struct ReceiptScannerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var aiSettingsArr: [AISettings]
    @Query private var categories: [Category]
    @Bindable var state: NewTransactionState

    private enum ScanPhase {
        case idle
        case processing
        case result(amount: Double, storeName: String, categoryName: String, notes: String)
        case error(String)
    }

    @State private var phase: ScanPhase = .idle
    @State private var showCamera       = false
    @State private var showLibrary      = false
    @State private var scannedImage: UIImage? = nil

    private var aiSettings: AISettings? { aiSettingsArr.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    // Instrução
                    VStack(spacing: 8) {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 48))
                            .foregroundStyle(Color.accentColor)
                        Text(t("receipt.instruction"))
                            .font(.title3.bold())
                        Text(t("receipt.desc"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 8)

                    // Botões de origem da imagem
                    HStack(spacing: 12) {
                        sourceButton(
                            title: "Câmera",
                            icon: "camera.fill",
                            color: Color.accentColor
                        ) { showCamera = true }

                        sourceButton(
                            title: "Galeria",
                            icon: "photo.on.rectangle",
                            color: Color(hex: "#34C759")
                        ) { showLibrary = true }
                    }
                    .disabled(isProcessing)

                    // Estado atual
                    switch phase {
                    case .idle:
                        EmptyView()

                    case .processing:
                        VStack(spacing: 16) {
                            ProgressView()
                                .scaleEffect(1.3)
                            Text(t("receipt.analyzing"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))

                    case .result(let amount, let storeName, let categoryName, let notes):
                        resultCard(amount: amount, storeName: storeName,
                                   categoryName: categoryName, notes: notes)

                    case .error(let msg):
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.title)
                                .foregroundStyle(.orange)
                            Text(msg)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }

                    // Aviso sem IA configurada
                    if aiSettings == nil {
                        Label(
                            t("receipt.noAI"),
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(16)
                        .background(Color(.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(20)
            }
            .navigationTitle(t("receipt.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("common.cancel")) { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePickerView(sourceType: .camera) { image in
                scannedImage = image
                Task { await process(image: image) }
            }
        }
        .sheet(isPresented: $showLibrary) {
            ImagePickerView(sourceType: .photoLibrary) { image in
                scannedImage = image
                Task { await process(image: image) }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Subviews

    private func sourceButton(
        title: String, icon: String, color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func resultCard(amount: Double, storeName: String,
                            categoryName: String, notes: String) -> some View {
        // Resolve Category object (case-insensitive match)
        let resolvedCategory = categories.first {
            $0.name.localizedCaseInsensitiveCompare(categoryName) == .orderedSame
        } ?? categories.first {
            !categoryName.isEmpty && $0.name.localizedCaseInsensitiveContains(categoryName)
        }

        return VStack(spacing: 20) {
            VStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title2)
                    Text(t("receipt.found"))
                        .font(.headline)
                    Spacer()
                }

                Divider()

                // Valor
                resultRow(label: t("transaction.amount"),
                          value: amount.asCurrency(),
                          valueBold: true)

                // Estabelecimento
                if !storeName.isEmpty {
                    resultRow(label: t("transaction.establishment"), value: storeName)
                }

                // Categoria sugerida
                if let cat = resolvedCategory {
                    HStack {
                        Text(t("transaction.category"))
                            .foregroundStyle(.secondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: cat.icon)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(cat.name)
                                .font(.subheadline.bold())
                        }
                    }
                } else if !categoryName.isEmpty {
                    resultRow(label: t("transaction.category"), value: categoryName)
                }

                // Observação
                if !notes.isEmpty {
                    resultRow(label: t("receipt.obs"), value: notes)
                }
            }
            .padding(16)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))

            // CTA — preenche state e vai direto para a tela de confirmação
            Button {
                state.amount = amount
                if !storeName.isEmpty { state.placeName = storeName }
                if let cat = resolvedCategory  { state.category = cat }
                if !notes.isEmpty              { state.notes    = notes }
                if let scannedImage,
                   let draft = try? ReceiptAttachmentStore.createDraft(from: scannedImage) {
                    state.receiptDrafts.append(draft)
                }
                state.jumpToReview = true   // pula para step 4
                dismiss()
            } label: {
                Label(t("receipt.confirm"), systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)

            Button { phase = .idle } label: {
                Text(t("common.retry"))
                    .font(.subheadline)
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    private func resultRow(label: String, value: String, valueBold: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(valueBold ? .title3.bold() : .subheadline.bold())
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - Processing

    private var isProcessing: Bool {
        if case .processing = phase { return true }
        return false
    }

    @MainActor
    private func process(image: UIImage) async {
        guard let settings = aiSettings else {
            phase = .error(t("receipt.noAIError"))
            return
        }

        phase = .processing

        // 1. OCR via Vision
        let ocrText = await recognizeText(in: image)
        guard !ocrText.isEmpty else {
            phase = .error(t("receipt.noText"))
            return
        }

        // 2. AI analysis — passa categorias para inferência
        let catNames = categories
            .filter { $0.parent == nil }
            .map { $0.name }

        do {
            let result = try await AIService.analyzeReceipt(
                ocrText: ocrText,
                settings: settings,
                categoryNames: catNames
            )
            phase = .result(
                amount:       result.amount,
                storeName:    result.storeName,
                categoryName: result.suggestedCategoryName,
                notes:        result.notes
            )
        } catch {
            phase = .error(error.localizedDescription)
        }
    }

    private func recognizeText(in image: UIImage) async -> String {
        await withCheckedContinuation { continuation in
            guard let cgImage = image.cgImage else {
                continuation.resume(returning: "")
                return
            }

            let request = VNRecognizeTextRequest { req, _ in
                let observations = req.results as? [VNRecognizedTextObservation] ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel       = .accurate
            request.recognitionLanguages   = LanguageManager.shared.effective.visionRecognitionLanguages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try? handler.perform([request])
        }
    }
}

// MARK: - UIImagePickerController Wrapper

struct ImagePickerView: UIViewControllerRepresentable {
    let sourceType: UIImagePickerController.SourceType
    let onImage: (UIImage) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType  = UIImagePickerController.isSourceTypeAvailable(sourceType)
            ? sourceType : .photoLibrary
        picker.delegate    = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        init(onImage: @escaping (UIImage) -> Void) { self.onImage = onImage }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            picker.dismiss(animated: true)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
