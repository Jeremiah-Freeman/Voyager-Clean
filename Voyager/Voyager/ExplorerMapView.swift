import SwiftUI
import MapKit
import CoreLocation
import MapKit

enum MapTheme: String, CaseIterable, Identifiable {
    case standard, muted, hybrid, satellite
    var id: String { rawValue }
}

private func style(for theme: MapTheme) -> MapStyle {
    switch theme {
    case .standard:
        return .standard
    case .muted:
        return .standard(emphasis: .muted)
    case .hybrid:
        return .hybrid
    case .satellite:
        return .imagery
    }
}

// Split into small subviews so the compiler can type‑check quickly.
struct ExplorerMapView: View {
    @Binding var isPresented: Bool
    @Binding var filter: Set<Place.Category>
    @Binding var radiusMiles: Double?
    @Binding var centerOverride: CLLocationCoordinate2D?   // <— was: let/var centerOverride: CLLocationCoordinate2D?
    var markerIcon: String

    @EnvironmentObject var placeStore: PlaceStore
    @EnvironmentObject var searchStore: SearchStore

    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var selection: Place?                 // seed tap
    @State private var selectionSearch: SelectedSearch?  // search tap
    @State private var theme: MapTheme = .muted

    // Lightweight selection type for search pins
    struct SelectedSearch: Identifiable {
        let id = UUID()
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
        }
        // Sheets kept tiny (extracted views) so type‑checking stays fast
        .sheet(item: $selection) { place in
            PlaceSheetView(place: place)
        }
        .sheet(item: $selectionSearch) { ident in
            SearchResultSheetView(ident: ident)
        }
    }
}

// MARK: - Subviews
private extension ExplorerMapView {
    var mapView: some View {
        Map(position: $position) {
            seedLayer
            searchLayer
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapPitchToggle()
        }
        .mapStyle(style(for: theme))
        .onAppear { centerIfNeeded() }
        // Observe doubles (not optionals) so the equatable requirement is satisfied
        .onChange(of: centerOverride?.latitude ?? 0) { _ in centerIfNeeded() }
        .onChange(of: centerOverride?.longitude ?? 0) { _ in centerIfNeeded() }
    }

    // Built‑in Places (ghost/cave/viewpoint)
    var seedLayer: some MapContent {
        ForEach(currentPlaces) { place in
            Annotation(place.name, coordinate: place.coordinate) {
                Button { selection = place } label: {
                    ZStack {
                        Circle().fill(.ultraThickMaterial).frame(width: 28, height: 28)
                        Image(systemName: markerIcon)
                            .foregroundColor(.yellow) // or your color
                    }
                }
                .accessibilityLabel(place.name)
            }
            .tag(place.id)
        }
    }

    // Transient search results (from SearchStore)
    var searchLayer: some MapContent {
        ForEach(searchStore.results) { r in
            Annotation(r.name, coordinate: r.coordinate) {
                Button {
                    selectionSearch = SelectedSearch(name: r.name, coordinate: r.coordinate)
                } label: {
                    Image(systemName: "mappin.and.ellipse")
                        .padding(6)
                        .background(.thinMaterial, in: Circle())
                }
                .accessibilityLabel(r.name)
            }
            .tag(r.id)
        }
    }

    var debugHUD: some View {
        Text("seed: \(currentPlaces.count) | search: \(searchStore.results.count)")
            .font(.caption2.monospaced())
            .padding(6)
            .background(.ultraThinMaterial, in: Capsule())
            .padding(.bottom, 80)
    }

    var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("Ghost Town", on: filter.contains(.ghostTown)) { toggle(.ghostTown) }
                chip("Cave", on: filter.contains(.cave)) { toggle(.cave) }
                chip("Viewpoint", on: filter.contains(.viewpoint)) { toggle(.viewpoint) }
                if let r = radiusMiles {
                    Text("≤ \(Int(r)) mi")
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.purple.opacity(0.9), in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 24)
        }
    }
}

// MARK: - Helpers
private extension ExplorerMapView {
    var currentPlaces: [Place] {
        if let r = radiusMiles, let center = centerOverride {
            return placeStore.within(r, of: center, categories: filter)
        }
        return placeStore.by(categories: filter)
    }

    func icon(for cat: Place.Category) -> String {
        switch cat {
        case .ghostTown: return "house.fill"
        case .cave: return "mountain.2.fill"
        case .viewpoint: return "binoculars.fill"
        }
    }

    func centerIfNeeded() {
        if let c = centerOverride {
            position = .region(.init(center: c, span: .init(latitudeDelta: 0.5, longitudeDelta: 0.5)))
        } else if let first = currentPlaces.first {
            position = .region(.init(center: first.coordinate, span: .init(latitudeDelta: 0.6, longitudeDelta: 0.6)))
        }
    }

    func toggle(_ cat: Place.Category) {
        if filter.contains(cat) { filter.remove(cat) } else { filter.insert(cat) }
    }

    func chip(_ label: String, on: Bool, tap: @escaping () -> Void) -> some View {
        Button(label, action: tap)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(on ? .blue.opacity(0.95) : .gray.opacity(0.35), in: Capsule())
            .foregroundStyle(.white)
    }
}

// MARK: - Sheet tiny views
private struct PlaceSheetView: View {
    let place: Place
    var body: some View {
        VStack(spacing: 12) {
            Text(place.name).font(.title2.bold())
            Text(place.category.rawValue).foregroundStyle(.secondary)
            Button("Directions in Apple Maps") {
                let item = MKMapItem(placemark: .init(coordinate: place.coordinate))
                item.name = place.name
                item.openInMaps(launchOptions: [
                    MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
                ])
            }
        }
        .padding()
        .presentationDetents([.medium, .large])
    }
}

private struct SearchResultSheetView: View {
    let ident: ExplorerMapView.SelectedSearch
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Text(ident.name)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    openInAppleMaps()
                } label: {
                    Label("Directions in Apple Maps", systemImage: "map")
                }

                if canOpen(scheme: "comgooglemaps://") {
                    Button {
                        openInGoogleMaps()
                    } label: {
                        Label("Directions in Google Maps", systemImage: "globe")
                    }
                }

                if canOpen(scheme: "waze://") {
                    Button {
                        openInWaze()
                    } label: {
                        Label("Directions in Waze", systemImage: "location.circle")
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            Spacer(minLength: 12)
        }
        .padding()
        .presentationDetents([.medium, .large])
    }

    // MARK: helpers
    private func openInAppleMaps() {
        let item = MKMapItem(placemark: .init(coordinate: ident.coordinate))
        item.name = ident.name
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func openInGoogleMaps() {
        let q = "comgooglemaps://?daddr=\(ident.coordinate.latitude),\(ident.coordinate.longitude)&directionsmode=driving"
        if let url = URL(string: q) { openURL(url) }
    }

    private func openInWaze() {
        let q = "waze://?ll=\(ident.coordinate.latitude),\(ident.coordinate.longitude)&navigate=yes"
        if let url = URL(string: q) { openURL(url) }
    }

    private func canOpen(scheme: String) -> Bool {
        guard let url = URL(string: scheme) else { return false }
        return UIApplication.shared.canOpenURL(url)
    }
}
