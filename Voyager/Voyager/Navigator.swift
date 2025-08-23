import Foundation
import MapKit
import UIKit

enum NavApp: String, CaseIterable, Identifiable {
    case apple, google, waze
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .apple: return "Apple Maps"
        case .google: return "Google Maps"
        case .waze: return "Waze"
        }
    }
}

final class Navigator {
    static let shared = Navigator()
    private init() {}

    // MARK: - Preference
    private let prefKey = "voyager.nav.pref"

    func preferredApp() -> NavApp {
        if let raw = UserDefaults.standard.string(forKey: prefKey),
           let app = NavApp(rawValue: raw) { return app }
        return .apple
    }

    func setPreferredApp(_ app: NavApp) {
        UserDefaults.standard.set(app.rawValue, forKey: prefKey)
    }

    // MARK: - Capability
    private func isInstalled(_ app: NavApp) -> Bool {
        switch app {
        case .apple:
            return true
        case .google:
            return UIApplication.shared.canOpenURL(URL(string: "comgooglemaps://")!)
        case .waze:
            return UIApplication.shared.canOpenURL(URL(string: "waze://")!)
        }
    }

    // MARK: - Open directions (driving)
    @MainActor
    func open(to coordinate: CLLocationCoordinate2D, name: String? = nil, preferred: NavApp? = nil) {
        let choice = preferred ?? preferredApp()

        if openIn(choice, to: coordinate, name: name) { return }
        if choice != .google, openIn(.google, to: coordinate, name: name) { return }
        if choice != .waze, openIn(.waze, to: coordinate, name: name) { return }

        // Last resort: Apple Maps (always available)
        _ = openIn(.apple, to: coordinate, name: name)
    }

    // MARK: - Internal router
    @discardableResult
    private func openIn(_ app: NavApp, to c: CLLocationCoordinate2D, name: String?) -> Bool {
        guard isInstalled(app) else { return false }

        let lat = c.latitude
        let lon = c.longitude

        switch app {
        case .apple:
            let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
            if let name { item.name = name }
            item.openInMaps(launchOptions: [
                MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
            ])
            return true

        case .google:
            // https://developers.google.com/maps/documentation/urls/ios-urlscheme
            var comps = URLComponents(string: "comgooglemaps://")!
            comps.queryItems = [
                URLQueryItem(name: "daddr", value: "\(lat),\(lon)"),
                URLQueryItem(name: "directionsmode", value: "driving")
            ]
            if let name { comps.queryItems?.append(URLQueryItem(name: "q", value: name)) }
            if let url = comps.url { UIApplication.shared.open(url) }
            return true

        case .waze:
            // https://developers.google.com/waze/deeplinks
            let urlStr = "waze://?ll=\(lat),\(lon)&navigate=yes"
            if let url = URL(string: urlStr) { UIApplication.shared.open(url) }
            return true
        }
    }
}
