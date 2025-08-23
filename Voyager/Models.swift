import Foundation
import CoreLocation

// MARK: - Models

struct Place: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: Category
    let coordinate: CLLocationCoordinate2D
    let blurb: String
    let links: [URL]

    enum Category: String, CaseIterable, Hashable {
        case ghostTown = "Ghost Town"
        case cave = "Cave"
        case viewpoint = "Viewpoint"
    }

    // Manual Hashable/Equatable since CLLocationCoordinate2D isn’t Hashable
    static func == (lhs: Place, rhs: Place) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// Wrapper so we can use .sheet(item:) with a URL
struct IdentURL: Identifiable, Hashable {
    let id = UUID()
    let url: URL
}
