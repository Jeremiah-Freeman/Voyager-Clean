import SwiftUI

/// Simple splash that shows the `SplashImage` asset, fades out, and then
/// calls an optional completion handler. No AppState dependency.
struct SplashView: View {
    /// Called after the splash fades out. Default does nothing so callers can
    /// ignore it if they just overlay this view.
    var onFinished: () -> Void = {}

    @State private var isVisible = true

    private var splash: Image {
        // Use the single asset name you created in Assets.xcassets
        if UIImage(named: "SplashImage") != nil {
            return Image("SplashImage")
        } else {
            print("[Splash] ⚠️ Splash image not found in Assets.xcassets. Using placeholder.")
            return Image(systemName: "photo")
        }
    }

    var body: some View {
        ZStack {
            // Soft fallback bg so there is no harsh white while loading
            LinearGradient(
                gradient: Gradient(colors: [Color(.systemGray6), Color(.systemBackground)]),
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            splash
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        }
        // Fade the WHOLE splash view out so it doesn't leave an empty bg behind
        .opacity(isVisible ? 1 : 0)
        .animation(.easeOut(duration: 0.4), value: isVisible)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // ~2s hold
            withAnimation { isVisible = false }
            try? await Task.sleep(nanoseconds: 400_000_000)   // allow fade to finish
            onFinished()
        }
    }
}
