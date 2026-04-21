import SwiftUI
import SwiftData

struct Step2LocationView: View {
    var state: NewTransactionState

    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]

    @State private var locationService = LocationService()
    @FocusState private var isFocused: Bool
    @State private var inputText = ""

    // MARK: - Computed suggestions (histórico)

    private var recentPlaces: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for tx in allTransactions {
            guard let name = tx.placeName, !name.isEmpty else { continue }
            if seen.insert(name).inserted {
                result.append(name)
                if result.count == 4 { break }
            }
        }
        return result
    }

    private var filteredSuggestions: [String] {
        guard !inputText.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        let q = inputText.lowercased()
        var seen = Set<String>()
        return allTransactions.compactMap { tx -> String? in
            guard let name = tx.placeName, !name.isEmpty,
                  name.lowercased().contains(q),
                  seen.insert(name).inserted else { return nil }
            return name
        }.prefix(8).map { $0 }
    }

    private var isTyping: Bool {
        !inputText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            inputField
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 16)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if isTyping {
                        // Sugestões filtradas do histórico enquanto digita
                        if filteredSuggestions.isEmpty {
                            noMatchHint
                        } else {
                            historyBlock(
                                title: t("step2.suggestions"),
                                icon: "magnifyingglass",
                                items: filteredSuggestions.map { ($0, nil) }
                            )
                        }
                    } else {
                        // Blocos padrão: histórico + locais próximos
                        if !recentPlaces.isEmpty {
                            historyBlock(
                                title: t("step2.recent"),
                                icon: "clock.arrow.circlepath",
                                items: recentPlaces.map { ($0, nil) }
                            )
                        }

                        // Locais próximos via MapKit
                        nearbySection

                        if recentPlaces.isEmpty
                            && locationService.nearbyPlaces.isEmpty
                            && !locationService.isLoading {
                            firstTimeHint
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .onAppear {
            inputText = state.placeName
            locationService.requestPermissionAndLocate()
        }
        // Se a localização já estava disponível (ex: re-abriu o step), busca imediatamente
        .onChange(of: locationService.currentLocation) { _, loc in
            guard let loc, locationService.nearbyPlaces.isEmpty else { return }
            Task { await locationService.fetchNearby(from: loc) }
        }
    }

    // MARK: - Input Field

    private var inputField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t("step2.prompt"))
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            HStack(spacing: 10) {
                Image(systemName: "storefront.fill")
                    .foregroundStyle(Color.accentColor)
                    .font(.title3)

                TextField(t("step2.placeholder"), text: $inputText)
                    .font(.body)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onChange(of: inputText) { _, val in
                        state.placeName = val.trimmingCharacters(in: .whitespaces)
                    }

                if !inputText.isEmpty {
                    Button {
                        inputText = ""
                        state.placeName = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(14)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Nearby Section

    @ViewBuilder
    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cabeçalho
            HStack(spacing: 6) {
                Image(systemName: "location.fill")
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                Text(t("step2.nearby"))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
                Spacer()
                if locationService.isLoading {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)

            if let error = locationService.locationError {
                // Permissão negada ou erro
                HStack(spacing: 8) {
                    Image(systemName: "location.slash")
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            } else if locationService.nearbyPlaces.isEmpty && !locationService.isLoading {
                HStack(spacing: 8) {
                    Image(systemName: "location.circle")
                        .foregroundStyle(.secondary)
                    Text(t("step2.loadingNearby"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            } else {
                // Lista de locais próximos
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(locationService.nearbyPlaces.enumerated()), id: \.element.id) { idx, place in
                        Button {
                            selectPlace(place.name)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: place.icon)
                                    .foregroundStyle(Color(hex: place.iconColor))
                                    .font(.body)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    if !place.address.isEmpty {
                                        Text(place.address)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Text(place.distanceLabel)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)

                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(Color(.tertiaryLabel))
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 11)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if idx < locationService.nearbyPlaces.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - History Block (recentes / frequentes / sugestões)

    private func historyBlock(
        title: String,
        icon: String,
        items: [(name: String, badge: String?)]
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.4)
            }
            .padding(.horizontal)
            .padding(.top, 16)
            .padding(.bottom, 6)

            ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                Button {
                    selectPlace(item.name)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.up.left.circle.fill")
                            .foregroundStyle(Color.accentColor.opacity(0.75))
                            .font(.body)

                        Text(item.name)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        Spacer()

                        if let badge = item.badge {
                            Text(badge)
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12))
                                .foregroundStyle(Color.accentColor)
                                .clipShape(Capsule())
                        }

                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(Color(.tertiaryLabel))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if idx < items.count - 1 {
                    Divider().padding(.leading, 52)
                }
            }
        }
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Empty States

    private var noMatchHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "storefront")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(t("step2.emptyHistory", inputText))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(t("step2.tapNext"))
                .font(.caption)
                .foregroundStyle(Color(.tertiaryLabel))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    private var firstTimeHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.secondary.opacity(0.5))
            Text(t("step2.noHistory"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Helper

    private func selectPlace(_ name: String) {
        inputText = name
        state.placeName = name
        isFocused = false
    }
}
