import SwiftUI
import CoreLocation
import Speech
import AVFoundation
import MapKit

// MARK: - Helpers
@inline(__always)
func isPreview() -> Bool {
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
}

// MARK: - UI
struct ContentView: View {
    // Debug UI
    @State private var lastParsed: String = ""
    @State private var lastCommandJSON: String = ""
    @State private var isRouting = false

    // Services
    @StateObject private var loc = LocationService()
    @StateObject private var speech = SpeechService()
    @EnvironmentObject var placeStore: PlaceStore
    @EnvironmentObject var searchStore: SearchStore

    // Map state
    @State private var showMap = false
    @State private var filter: Set<Place.Category> = [.ghostTown, .cave, .viewpoint]
    @State private var radiusMiles: Double? = 50
    @State private var centerOverride: CLLocationCoordinate2D? = nil

    // Debounce / duplicate guard for voice routing
    @State private var _lastQuerySent: String = ""
    @State private var _lastSendAt: Date = .distantPast

    var body: some View {
        VStack(spacing: 16) {
            Text("Voyager").font(.largeTitle.bold())

            // Location status
            Group {
                Text("Location: \(statusString(loc.status))")
                if let l = loc.lastLocation {
                    Text(String(format: "Lat: %.5f  Lon: %.5f", l.coordinate.latitude, l.coordinate.longitude))
                        .font(.caption.monospaced())
                } else {
                    Text("No location yet").font(.caption)
                }
            }

            // Speech controls
            VStack(spacing: 8) {
                Text("Speech: \(speechStatus(speech.authStatus))").font(.caption)

                Button(speech.isListening ? "Stop Listening" : "Start Listening") {
                    if speech.isListening { speech.stop() }
                    else {
                        do { try speech.start() } catch { print("Speech start error:", error.localizedDescription) }
                    }
                }
                .buttonStyle(.borderedProminent)

                Text(speech.transcript.isEmpty
                     ? "Try: “show starbucks near me”, “navigate to Powell’s Books”, or “show ghost towns within 150 miles”."
                     : speech.transcript)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            }

            // Manual route trigger + spinner
            HStack {
                Button("Route Now") { Task { await routeViaLLM(speech.transcript) } }
                    .buttonStyle(.bordered)
                if isRouting { ProgressView().padding(.leading, 4) }
                Spacer()
            }
            .padding(.horizontal)

            // Optional quick buttons
            HStack {
                Button("Open Map") { showMap = true }
                Button("Ghost Towns") {
                    filter = [.ghostTown]
                    radiusMiles = 150
                    centerOverride = loc.lastLocation?.coordinate
                    showMap = true
                }
            }
            .buttonStyle(.bordered)

            // Tiny debug panel
            if !lastParsed.isEmpty || !lastCommandJSON.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if !lastParsed.isEmpty {
                        Text("Parsed: \(lastParsed)")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if !lastCommandJSON.isEmpty {
                        Text("LLM: \(lastCommandJSON)")
                            .font(.caption2).foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .padding(.horizontal)
            }

            Spacer()
        }
        .padding()
        .onAppear { if !isPreview() { loc.requestWhenInUse() } }

        // Voice → route via LLM (with gating + debounce inside)
        .onChange(of: speech.transcript, initial: false) { oldValue, newValue in
            Task { await routeViaLLM(newValue) }
        }

        // Map sheet
        .sheet(isPresented: $showMap) {
            ExplorerMapView(
                isPresented: $showMap,
                filter: $filter,
                radiusMiles: $radiusMiles,
                centerOverride: $centerOverride,    // <— was: centerOverride: centerOverride
                markerIcon: "mappin.circle.fill"
            )
            .environmentObject(placeStore)
            .environmentObject(searchStore)
        }
    }

    // MARK: - Status helpers

    private func statusString(_ s: CLAuthorizationStatus?) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedWhenInUse: return "whenInUse"
        case .authorizedAlways: return "always"
        case .none: return "unknown"
        @unknown default: return "unknown"
        }
    }

    private func speechStatus(_ s: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch s {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    // MARK: - LLM routing + fallbacks

    /// Main entry used by `.onChange(of: speech.transcript)` and "Route Now"
    @MainActor
    func routeViaLLM(_ raw: String) async {
        // Normalize once
        let t = raw
            .lowercased()
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !t.isEmpty else { return }
        print("[Voice] heard:", t)

        // Gate: require a wake word like “show/find/search/go/navigate/open”
        guard let stripped = stripWakeWord(t) else { return }

        // Ignore trivial / partial tokens that come mid-utterance
        let throwaways: Set<String> = ["near", "near me", "me", "please"]
        if stripped.isEmpty || throwaways.contains(stripped) || stripped.count < 3 {
            return
        }

        // Debounce identical commands for 1.5s (avoid spamming on partials)
        let now = Date()
        if stripped == _lastQuerySent, now.timeIntervalSince(_lastSendAt) < 1.5 {
            return
        }
        _lastQuerySent = stripped
        _lastSendAt = now

        lastParsed = stripped
        isRouting = true
        defer { isRouting = false }

        // Instant seed categories (no network)
        if stripped.contains("ghost") {
            filter = [.ghostTown]; radiusMiles = 150
            centerOverride = loc.lastLocation?.coordinate
            showMap = true
            return
        } else if stripped.contains("viewpoint") || stripped.contains("view point") || stripped.contains("scenic") {
            filter = [.viewpoint]; radiusMiles = 50
            centerOverride = loc.lastLocation?.coordinate
            showMap = true
            return
        } else if stripped.contains("cave") {
            filter = [.cave]; radiusMiles = 50
            centerOverride = loc.lastLocation?.coordinate
            showMap = true
            return
        }

        // LLM normalize → else fallback to direct local search
        do {
            let llm = try LLMClient()
            let normalized = try await llm.interpret(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return }
            lastCommandJSON = "normalized: \(normalized)"

            switch normalized {
            case "ghost":
                filter = [.ghostTown]; radiusMiles = 150
                centerOverride = loc.lastLocation?.coordinate
                showMap = true
                return
            case "viewpoint":
                filter = [.viewpoint]; radiusMiles = 50
                centerOverride = loc.lastLocation?.coordinate
                showMap = true
                return
            case "cave":
                filter = [.cave]; radiusMiles = 50
                centerOverride = loc.lastLocation?.coordinate
                showMap = true
                return
            default:
                break
            }

            await searchStore.run(
                query: normalized,
                near: centerOverride ?? loc.lastLocation?.coordinate
            )
            // NEW: auto-center to the first search hit so the user sees pins even if they’re
            // outside the current viewport.
            if let first = searchStore.results.first {
                centerOverride = first.coordinate
                radiusMiles = 25
            }
            showMap = true

        } catch {
            print("[LLM Fallback]", error.localizedDescription)
            lastCommandJSON = "fallback: \(error.localizedDescription)"

            await searchStore.run(
                query: stripped,
                near: centerOverride ?? loc.lastLocation?.coordinate
            )
            if let first = searchStore.results.first {
                centerOverride = first.coordinate
                radiusMiles = 25
            }
            showMap = true
        }
    }

    /// Wake‑word stripper. Returns text after the trigger, or nil if no command.
    /// Accepts:
    ///  - "show starbucks", "search for ghost towns", "navigate to crater lake"
    ///  - Tolerates fillers: "show me please starbucks"
    func stripWakeWord(_ t: String) -> String? {
        let input = t.trimmingCharacters(in: .whitespacesAndNewlines)

        // Specific (multi-word) triggers first
        let multi = [
            "navigate to", "go to", "take me to", "search for",
            "find me", "show me", "find nearest", "show nearest"
        ]
        for w in multi {
            if input.hasPrefix(w + " ") {
                var rest = String(input.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
                let fillers = ["me", "please", "uh", "um", "the"]
                for f in fillers where rest.hasPrefix(f + " ") {
                    rest = String(rest.dropFirst(f.count)).trimmingCharacters(in: .whitespaces)
                }
                return rest.isEmpty ? nil : rest
            }
        }

        // Single-word triggers
        let single = ["show", "find", "search", "go", "navigate", "open"]
        for w in single {
            if input == w { return nil } // verb alone (too short)
            if input.hasPrefix(w + " ") {
                var rest = String(input.dropFirst(w.count)).trimmingCharacters(in: .whitespaces)
                let fillers = ["me", "please", "uh", "um", "the"]
                for f in fillers where rest.hasPrefix(f + " ") {
                    rest = String(rest.dropFirst(f.count)).trimmingCharacters(in: .whitespaces)
                }
                return rest.isEmpty ? nil : rest
            }
        }
        return nil
    }
}
