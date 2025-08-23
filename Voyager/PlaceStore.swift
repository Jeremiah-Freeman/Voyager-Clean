import Foundation
import CoreLocation

final class PlaceStore: ObservableObject {
    @Published var places: [Place] = [
        Place(name: "Garnet Ghost Town",
              category: .ghostTown,
              coordinate: .init(latitude: 46.8347, longitude: -113.3575),
              blurb: "Well‑preserved Montana gold‑rush town from the 1890s.",
              links: [URL(string:"https://en.wikipedia.org/wiki/Garnet,_Montana")!]),
        Place(name: "Zigzag Overlook",
              category: .viewpoint,
              coordinate: .init(latitude: 45.3342, longitude: -121.9562),
              blurb: "Roadside viewpoint for Mt. Hood and Zigzag River canyon.",
              links: []),
        Place(name: "Lava Tube (Mock)",
              category: .cave,
              coordinate: .init(latitude: 44.1000, longitude: -121.3000),
              blurb: "Lava tube cave system—helmet and lights recommended.",
              links: [URL(string:"https://www.fs.usda.gov")!])
    ]

    func by(categories: Set<Place.Category>) -> [Place] {
        places.filter { categories.contains($0.category) }
    }

    func within(_ radiusMiles: Double,
                of coordinate: CLLocationCoordinate2D,
                categories: Set<Place.Category>) -> [Place] {
        let center = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        return places.filter { p in
            let d = CLLocation(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude)
                .distance(from: center) / 1609.344
            return d <= radiusMiles && categories.contains(p.category)
        }
    }
}
