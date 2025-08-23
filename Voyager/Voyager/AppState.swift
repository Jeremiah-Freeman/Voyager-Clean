import SwiftUI

final class AppState: ObservableObject {
    enum Route { case splash, main }          // ← only these
    @Published var route: Route = .splash

    func goToMain() { route = .main }
}
