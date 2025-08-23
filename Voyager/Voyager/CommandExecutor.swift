import Foundation
import CoreLocation
import MapKit

/// This holds references the executor needs (stores & state setters)
struct CommandContext {
    // Stores
    let placeStore: PlaceStore
    let searchStore: SearchStore

    // State writers (bridged from ContentView)
    let setShowMap: (Bool) -> Void
    let setFilter: (Set<Place.Category>) -> Void
    let setRadius: (Double?) -> Void
    let setCenterOverride: (CLLocationCoordinate2D?) -> Void
}

struct CommandExecutor {

    func execute(_ cmd: LLMCommand, ctx: CommandContext, userCoord: CLLocationCoordinate2D?) async {
        switch cmd.action {

        case .openMap:
            ctx.setShowMap(true)

        case .showSeedCategory:
            guard let cat = cmd.category else { return }
            let mapped: Place.Category
            switch cat {
            case .ghostTown: mapped = .ghostTown
            case .cave:      mapped = .cave
            case .viewpoint: mapped = .viewpoint
            }
            ctx.setFilter([mapped])
            ctx.setRadius(cmd.radiusMiles ?? 50)
            ctx.setCenterOverride(cmd.centerCoordinate ?? userCoord)
            ctx.setShowMap(true)

        case .localSearch:
            guard let q = cmd.query?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else { return }
            await ctx.searchStore.run(query: q, near: cmd.centerCoordinate ?? userCoord)
            ctx.setShowMap(true)

        case .navigateTo:
            // Try local search to pick a destination, then open Apple Maps/Waze/Google according to availability.
            guard let q = cmd.query, !q.isEmpty else { return }
            // Resolve one item with MKLocalSearch
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = q
            let search = MKLocalSearch(request: request)
            if let item = try? await search.start().mapItems.first {
                // Prefer Apple Maps; you can add Waze/Google switches later
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
            }

        case .noop:
            break
        }
    }
}
