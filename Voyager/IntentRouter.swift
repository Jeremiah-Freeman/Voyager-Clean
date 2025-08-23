import Foundation
import MapKit

struct IntentResult {
    var categories: Set<Place.Category> = [.ghostTown, .cave, .viewpoint]
    var radiusMiles: Double? = 50
    var center: CLLocationCoordinate2D? = nil
}

@MainActor
final class IntentRouter: ObservableObject {
    func parse(_ text: String) -> IntentResult {
        var r = IntentResult()

        let lower = text.lowercased()

        // categories
        var cats = Set<Place.Category>()
        if lower.contains("ghost") { cats.insert(.ghostTown) }
        if lower.contains("cave") { cats.insert(.cave) }
        if lower.contains("view") || lower.contains("scenic") { cats.insert(.viewpoint) }
        if cats.isEmpty { cats = r.categories }
        r.categories = cats

        // radius
        if let m = lower.capture(regex: #"(\d+)\s*(mi|mile|miles)"#) {
            if let v = Double(m) { r.radiusMiles = v }
        }

        return r
    }

    /// Resolve place names like “Portland Airport” or “Applebees” using Apple’s geocoder.
    func resolve(_ text: String) async -> IntentResult {
        var r = parse(text)

        // naive: remove generic words so local search has a chance
        let cleaned = text
            .replacingOccurrences(of: "show", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "within", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: "miles", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard cleaned.count > 2 else { return r }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = cleaned
        let search = MKLocalSearch(request: request)

        do {
            let resp = try await search.start()
            if let item = resp.mapItems.first {
                r.center = item.placemark.coordinate
            }
        } catch {
            // leave r.center nil → UI falls back gracefully
        }
        return r
    }
}

private extension String {
    func capture(regex pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = self as NSString
        guard let m = re.firstMatch(in: self, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.numberOfRanges >= 2 {
            return ns.substring(with: m.range(at: 1))
        }
        return nil
    }
}
