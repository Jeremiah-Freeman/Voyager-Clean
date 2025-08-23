import SwiftUI

struct RootView: View {
    @State private var showMain = false

    var body: some View {
        Group {
            if showMain {
                HomeView()
            } else {
                SplashView()
                    .task {
                        try? await Task.sleep(nanoseconds: 2_400_000_000)
                        withAnimation { showMain = true }
                    }
            }
        }
        // pass your environment objects here if you create them at the top level
        .environmentObject(PlaceStore())
        .environmentObject(SearchStore())
    }
}
