import SwiftUI

struct Step2LocationView: View {
    var state: NewTransactionState

    @State private var searchText = ""
    // Sprint 4: substituir por resultados reais do Google Places API
    @State private var suggestions: [PlaceSuggestion] = PlaceSuggestion.mockData

    var body: some View {
        VStack(spacing: 0) {
            // Campo de busca
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar local...", text: $searchText)
                    .autocorrectionDisabled()
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding()

            if state.placeName.isEmpty {
                // Lista de sugestões
                List {
                    Section("Próximos de você") {
                        ForEach(filteredSuggestions) { place in
                            PlaceRowView(place: place) {
                                state.placeName = place.name
                                state.placeGoogleId = place.googleId
                                searchText = place.name
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                // Local selecionado
                VStack(spacing: 16) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text(state.placeName)
                        .font(.headline)
                    Button("Alterar local") {
                        state.placeName = ""
                        state.placeGoogleId = nil
                        searchText = ""
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.top, 40)
                Spacer()
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                state.placeName = ""
                state.placeGoogleId = nil
            }
        }
    }

    private var filteredSuggestions: [PlaceSuggestion] {
        if searchText.isEmpty { return suggestions }
        return suggestions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - Place Model (substituído pela Google Places API no Sprint 4)

struct PlaceSuggestion: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let distance: String
    let googleId: String

    static let mockData: [PlaceSuggestion] = [
        .init(name: "Supermercado Extra",  address: "Rua das Flores, 123",   distance: "320m", googleId: "mock_1"),
        .init(name: "Padaria São João",    address: "Av. Central, 45",       distance: "150m", googleId: "mock_2"),
        .init(name: "Farmácia Drogasil",   address: "Rua Principal, 200",    distance: "500m", googleId: "mock_3"),
        .init(name: "Posto Shell",         address: "Av. Brasil, 1000",      distance: "800m", googleId: "mock_4"),
        .init(name: "McDonald's",          address: "Shopping Center, L2",   distance: "1,2km", googleId: "mock_5"),
    ]
}

struct PlaceRowView: View {
    let place: PlaceSuggestion
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(.red)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(place.address)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(place.distance)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
