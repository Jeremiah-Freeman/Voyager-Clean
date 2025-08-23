import SwiftUI

struct HomeView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Welcome to Voyager")
                    .font(.largeTitle.bold())

                Text("Ask me anything, or tell me where you want to go.")
                    .foregroundStyle(.secondary)

                Button("Start Chat") {
                    // Later: navigate to chat/agent screen
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }
}

#Preview {
    HomeView()
        .environmentObject(AppState())
}
