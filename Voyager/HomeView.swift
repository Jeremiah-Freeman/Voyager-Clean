import SwiftUI

struct HomeView: View {
    @EnvironmentObject var searchStore: SearchStore
    @EnvironmentObject var placeStore: PlaceStore

    @StateObject private var speech = SpeechService()   // uses your existing service

    var body: some View {
        ZStack {
            // Outdoorsy, soft background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.88), // sand
                    Color(red: 0.98, green: 0.98, blue: 0.97)  // warm white
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                // Title
                VStack(spacing: 6) {
                    Text("Voyager")
                        .font(.largeTitle.bold())
                    Text("I’m listening—ask me anything ✨")
                        .foregroundStyle(.secondary)
                }

                // Waveform
                ChatWaveformView()
                    .frame(height: 120)
                    .padding(.horizontal, 32)

                // Live transcript line
                if !speech.transcript.isEmpty {
                    Text(speech.transcript)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                Spacer(minLength: 12)
            }
            .padding(.top, 40)
        }
        .task {
            // auto-start mic on entry
            do { try await speech.start() } catch {
                print("[Speech] start() error: \(error)")
            }
        }
        .onDisappear {
            Task { try? await speech.stop() }
        }
    }
}
