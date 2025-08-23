import Foundation
import MapKit

// One search hit (identifiable & hashable without relying on CLLocationCoordinate2D conformance)
struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let mapItem: MKMapItem?

    static func == (lhs: SearchResult, rhs: SearchResult) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Runs MKLocalSearch queries and publishes results
final class SearchStore: ObservableObject {
    @Published var results: [SearchResult] = []

    /// Run a search for `query`, optionally biased near `center` or a given `region`.
    @MainActor
    func run(query: String,
             near center: CLLocationCoordinate2D? = nil,
             region: MKCoordinateRegion? = nil,
             span: MKCoordinateSpan = .init(latitudeDelta: 0.35, longitudeDelta: 0.35)) async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query

        if let c = center {
            req.region = MKCoordinateRegion(center: c, span: span)
        } else if let r = region {
            req.region = r
        }

        let search = MKLocalSearch(request: req)
        do {
            let resp = try await search.start()
            let mapped: [SearchResult] = resp.mapItems.map { item in
                SearchResult(
                    name: item.name ?? item.placemark.name ?? "Result",
                    coordinate: item.placemark.coordinate,
                    mapItem: item
                )
            }
            self.results = mapped
        } catch {
            self.results = []
            print("Search error:", error.localizedDescription)
        }
    }

    /// Convenience: run a search near a center with an approximate radius in miles.
    @MainActor
    func run(query: String,
             near center: CLLocationCoordinate2D,
             radiusMiles: Double) async {
        let span = Self.span(forMiles: radiusMiles, atLatitude: center.latitude)
        await run(query: query, near: center, region: nil, span: span)
    }

    /// Open Apple Maps driving directions to a given search result.
    @MainActor
    func openDirections(to result: SearchResult) {
        let item: MKMapItem
        if let existing = result.mapItem {
            item = existing
        } else {
            let placemark = MKPlacemark(coordinate: result.coordinate)
            item = MKMapItem(placemark: placemark)
            item.name = result.name
        }
        item.name = item.name ?? result.name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    /// Compute a reasonable span for a given radius in miles at a latitude.
    static func span(forMiles miles: Double, atLatitude lat: Double) -> MKCoordinateSpan {
        // 1 degree latitude ~ 69 miles; longitude scales by cos(latitude)
        let latDelta = max(miles / 69.0, 0.01)
        let lonScale = max(cos(lat * .pi / 180), 0.01)
        let lonDelta = max(miles / (69.0 * lonScale), 0.01)
        return MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lonDelta)
    }
    

    @MainActor
    func clear() { results.removeAll() }
}
