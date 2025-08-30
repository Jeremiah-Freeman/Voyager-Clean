import SwiftUI

struct RootView: View {
    @State private var showMain = false

    // create the stores here once
    @StateObject private var placeStore  = PlaceStore()
    @StateObject private var searchStore = SearchStore()

    var body: some View {
        Group {
            if showMain {
                HomeView()               // <-- use the already-wired screen
                    .environmentObject(placeStore)
                    .environmentObject(searchStore)
            } else {
                SplashView {
                    withAnimation { showMain = true }
                }
            }
        }
    }
}
