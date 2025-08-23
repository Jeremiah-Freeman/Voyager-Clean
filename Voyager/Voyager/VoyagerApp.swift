import SwiftUI

@main
struct VoyagerApp: App {
    // One instance of each store for the whole app
    @StateObject private var placeStore  = PlaceStore()
    @StateObject private var searchStore = SearchStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(placeStore)
                .environmentObject(searchStore)
        }
    }
}
