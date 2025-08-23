import Foundation
import CoreLocation

/// All actions the LLM can ask the app to perform.
enum LLMAction: String, Codable {
    case showSeedCategory   // e.g. ghostTown / cave / viewpoint
    case localSearch        // e.g. "seattle starbucks"
    case openMap            // just open the map UI
    case navigateTo         // open external nav app to a named place or coordinates
    case noop               // nothing to do
}

/// Seed categories we already support visually.
enum SeedCategory: String, Codable {
    case ghostTown, cave, viewpoint
}

struct LLMCommand: Codable {
    let action: LLMAction

    // For showSeedCategory
    let category: SeedCategory?
    let radiusMiles: Double?

    // For localSearch / navigateTo
    let query: String?
    let centerLat: Double?
    let centerLon: Double?

    // Optional “confidence” / notes from the LLM (not required)
    let meta: String?

    // Convenience
    var centerCoordinate: CLLocationCoordinate2D? {
        if let lat = centerLat, let lon = centerLon {
            return .init(latitude: lat, longitude: lon)
        }
        return nil
    }
    
}
