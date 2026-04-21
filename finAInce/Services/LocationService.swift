import Foundation
import CoreLocation
import MapKit

// MARK: - Modelo de local próximo

struct NearbyPlace: Identifiable {
    let id = UUID()
    let name: String
    let address: String
    let distance: Double        // metros
    let category: MKPointOfInterestCategory?

    var distanceLabel: String {
        distance < 1000
            ? "\(Int(distance))m"
            : String(format: "%.1fkm", distance / 1000)
    }

    var icon: String {
        guard let cat = category else { return "mappin.circle.fill" }
        switch cat {
        case .restaurant:                      return "fork.knife"
        case .cafe, .bakery:                   return "cup.and.saucer.fill"
        case .gasStation:                      return "fuelpump.fill"
        case .pharmacy:                        return "cross.fill"
        case .bank, .atm:                      return "banknote.fill"
        case .hospital:                        return "cross.circle.fill"
        case .hotel:                           return "bed.double.fill"
        case .school, .university:             return "book.fill"
        case .fitnessCenter:                   return "dumbbell.fill"
        case .park:                            return "tree.fill"
        case .museum, .theater, .movieTheater: return "theatermasks.fill"
        case .airport:                         return "airplane"
        case .laundry:                         return "washer.fill"
        case .store:                           return "bag.fill"
        default:                               return "storefront.fill"
        }
    }

    var iconColor: String {
        guard let cat = category else { return "#8E8E93" }
        switch cat {
        case .restaurant, .cafe, .bakery:  return "#FF9500"
        case .gasStation:                  return "#FF3B30"
        case .pharmacy, .hospital:         return "#34C759"
        case .bank, .atm:                  return "#007AFF"
        case .park:                        return "#30D158"
        case .hotel:                       return "#5856D6"
        case .store:                       return "#FF6B35"
        default:                           return "#8E8E93"
        }
    }
}

// MARK: - LocationService

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()

    var authStatus: CLAuthorizationStatus = .notDetermined
    var currentLocation: CLLocation?      = nil
    var nearbyPlaces: [NearbyPlace]        = []
    var isLoading: Bool                    = false
    var locationError: String?             = nil

    override init() {
        super.init()
        manager.delegate        = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        authStatus = manager.authorizationStatus
    }

    // MARK: - Public

    func requestPermissionAndLocate() {
        locationError = nil
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startLocating()
        case .denied, .restricted:
            locationError = "Permissão de localização negada. Ative em Ajustes > finAInce."
        @unknown default:
            break
        }
    }

    private func startLocating() {
        // startUpdatingLocation() é muito mais confiável que requestLocation()
        // em dispositivos reais — especialmente em ambientes fechados.
        manager.startUpdatingLocation()
        isLoading = true
    }

    // MARK: - Nearby fetch

    func fetchNearby(from location: CLLocation, radius: CLLocationDistance = 800) async {
        await MainActor.run {
            isLoading    = true
            nearbyPlaces = []
        }

        // Tentativa 1: MKLocalPointsOfInterestRequest (estruturado, preciso)
        var places = await fetchViaPOIRequest(from: location, radius: radius)

        // Tentativa 2: MKLocalSearch (fallback — funciona melhor no Brasil)
        if places.isEmpty {
            places = await fetchViaLocalSearch(from: location, radius: radius)
        }

        let sorted = places
            .sorted { $0.distance < $1.distance }
            .prefix(15)
            .map { $0 }

        await MainActor.run {
            nearbyPlaces = sorted
            isLoading    = false
        }
    }

    // MARK: - POI Request (Apple Maps structured)

    private func fetchViaPOIRequest(
        from loc: CLLocation,
        radius: CLLocationDistance
    ) async -> [NearbyPlace] {
        let request = MKLocalPointsOfInterestRequest(center: loc.coordinate, radius: radius)
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.compactMap { item in
                guard let name = item.name else { return nil }
                let dist = item.placemark.location?.distance(from: loc) ?? 9999
                let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare]
                    .compactMap { $0 }.joined(separator: ", ")
                return NearbyPlace(name: name, address: address, distance: dist,
                                   category: item.pointOfInterestCategory)
            }
        } catch {
            return []
        }
    }

    // MARK: - Local Search (more reliable in Brazil)

    private func fetchViaLocalSearch(
        from loc: CLLocation,
        radius: CLLocationDistance
    ) async -> [NearbyPlace] {
        let queries = ["restaurante", "mercado supermercado", "farmácia", "banco caixa"]
        let region  = MKCoordinateRegion(
            center: loc.coordinate,
            latitudinalMeters:  radius * 2,
            longitudinalMeters: radius * 2
        )

        var results: [NearbyPlace] = []
        var seen = Set<String>()

        for query in queries {
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            req.region               = region

            guard let response = try? await MKLocalSearch(request: req).start() else { continue }

            for item in response.mapItems {
                guard let name = item.name, seen.insert(name).inserted else { continue }
                let dist = item.placemark.location?.distance(from: loc) ?? 9999
                guard dist <= radius else { continue }
                let address = [item.placemark.thoroughfare, item.placemark.subThoroughfare]
                    .compactMap { $0 }.joined(separator: ", ")
                results.append(NearbyPlace(name: name, address: address, distance: dist,
                                           category: item.pointOfInterestCategory))
            }
        }

        return results
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last,
              loc.horizontalAccuracy > 0,
              loc.horizontalAccuracy < 500        // rejeita leituras imprecisas
        else { return }

        manager.stopUpdatingLocation()            // para de gastar bateria
        currentLocation = loc
        Task { await fetchNearby(from: loc) }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authStatus = manager.authorizationStatus
        if authStatus == .authorizedWhenInUse || authStatus == .authorizedAlways {
            startLocating()
        } else if authStatus == .denied || authStatus == .restricted {
            locationError = "Permissão de localização negada. Ative em Ajustes > finAInce."
            isLoading = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard let err = error as? CLError else { return }
        switch err.code {
        case .locationUnknown:
            // Temporário — continua tentando automaticamente
            break
        case .denied:
            manager.stopUpdatingLocation()
            locationError = "Permissão de localização negada. Ative em Ajustes > finAInce."
            isLoading = false
        default:
            manager.stopUpdatingLocation()
            isLoading = false
        }
    }
}
