import SwiftUI

@main
struct VoyagerApp: App {
    @StateObject private var placeStore = PlaceStore()
    @StateObject private var searchStore = SearchStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(placeStore)
                .environmentObject(searchStore)
        }
    }
}
