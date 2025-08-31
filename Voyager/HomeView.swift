import Speech
import SwiftUI

import CoreLocation

struct HomeView: View {
    @StateObject private var speech = SpeechService()
    @StateObject private var loc = LocationService()
    @EnvironmentObject var placeStore: PlaceStore
    @EnvironmentObject var searchStore: SearchStore
    @State private var isRouting = false
    @State private var showMap = false
    @State private var filter: Set<Place.Category> = [.ghostTown, .cave, .viewpoint]
    @State private var radiusMiles: Double? = 50
    @State private var centerOverride: CLLocationCoordinate2D? = nil
    @State private var _lastQuerySent: String = ""
    @State private var _lastSendAt: Date = .distantPast

    var body: some View {
        ZStack {
            // Warm, outdoorsy background
            LinearGradient(
                colors: [
                    Color(red: 0.96, green: 0.93, blue: 0.88), // light sand
                    Color(red: 0.99, green: 0.98, blue: 0.97)  // off-white
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer(minLength: 40)

                // Centered waveform
                ChatWaveformView()
                    .frame(height: 120)
                    .padding(.horizontal, 28)
                    .opacity(speech.isListening ? 1.0 : 0.35)
                    .accessibilityHidden(true)

                // Transcript or prompt
                Text(speech.transcript.isEmpty
                     ? "Say anything… e.g. “show Starbucks near me”"
                     : speech.transcript)
                    .multilineTextAlignment(.center)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)

                Spacer()
            }
            .padding(.bottom, 24)
        }
        .onAppear {
            if !isPreview() {
                loc.requestWhenInUse()
            }
            SFSpeechRecognizer.requestAuthorization { authStatus in
                DispatchQueue.main.async {
                    if authStatus == .authorized {
                        do {
                            try speech.start()
                            print("[DEBUG] Speech started after authorization")
                        } catch {
                            print("[DEBUG] Speech failed after auth: \(error.localizedDescription)")
                        }
                    } else {
                        print("[DEBUG] Speech authorization denied or restricted: \(authStatus.rawValue)")
                    }
                }
            }
        }
        .onChange(of: speech.transcript) { oldValue, newValue in
            print("[DEBUG] Transcript changed to: \(newValue)")
            Task {
                await routeViaLLM(newValue)
            }
        }
        .sheet(isPresented: $showMap) {
            ExplorerMapView(
                isPresented: $showMap,
                filter: $filter,
                radiusMiles: $radiusMiles,
                centerOverride: $centerOverride,
                markerIcon: "mappin.circle.fill"
            )
            .environmentObject(placeStore)
            .environmentObject(searchStore)
        }
    }

    // MARK: - Routing helpers

    func routeViaLLM(_ transcript: String) async {
        print("[DEBUG] routeViaLLM called with transcript: \(transcript)")
        // Normalize and strip wake word
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = stripWakeWord(trimmed)
        print("[DEBUG] Processed query: \(query)")
        let lower = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        // Ignore trivial partial tokens
        if lower.isEmpty || lower == "..." || lower == "." { return }
        // Debounce identical commands within 1.5s
        let now = Date()
        if lower == _lastQuerySent && now.timeIntervalSince(_lastSendAt) < 1.5 { return }
        _lastQuerySent = lower
        _lastSendAt = now
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Use LLMClient to normalize query
        do {
            let llm = try LLMClient()
            let normalizedQuery = try await llm.interpret(query).trimmingCharacters(in: .whitespacesAndNewlines)
            print("[DEBUG] Normalized query from LLM: \(normalizedQuery)")

            // Quick routes for ghost, viewpoint, cave
            if normalizedQuery.lowercased().contains("ghost") {
                filter = [.ghostTown]
                radiusMiles = 50
                await searchStore.run(query: "ghost town", near: centerOverride ?? loc.lastLocation?.coordinate)
                print("[DEBUG] Map will be shown")
                showMap = true
                return
            } else if normalizedQuery.lowercased().contains("viewpoint") {
                filter = [.viewpoint]
                radiusMiles = 50
                await searchStore.run(query: "viewpoint", near: centerOverride ?? loc.lastLocation?.coordinate)
                print("[DEBUG] Map will be shown")
                showMap = true
                return
            } else if normalizedQuery.lowercased().contains("cave") {
                filter = [.cave]
                radiusMiles = 50
                await searchStore.run(query: "cave", near: centerOverride ?? loc.lastLocation?.coordinate)
                print("[DEBUG] Map will be shown")
                showMap = true
                return
            }

            // Attempt to split normalizedQuery into search term and location
            let lowerNormalized = normalizedQuery.lowercased()
            var searchTerm = normalizedQuery
            var locationPart: String? = nil

            // Check for " in " to split query and location
            if let range = lowerNormalized.range(of: " in ") {
                let before = normalizedQuery[..<range.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                let after = normalizedQuery[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !before.isEmpty && !after.isEmpty {
                    searchTerm = String(before)
                    locationPart = String(after)
                }
            } else {
                // Otherwise, try to parse last word(s) as location if query has multiple words
                let components = normalizedQuery.components(separatedBy: .whitespaces)
                if components.count > 1 {
                    // Assume last one or two words might be location
                    let lastTwo = components.suffix(2).joined(separator: " ")
                    locationPart = lastTwo
                    searchTerm = components.dropLast(2).joined(separator: " ")
                    if searchTerm.isEmpty {
                        // fallback to entire query if dropping last two leaves empty
                        searchTerm = normalizedQuery
                        locationPart = nil
                    }
                }
            }

            if let location = locationPart {
                print("[DEBUG] Attempting geocode for location: \(location)")
                let geocoder = CLGeocoder()
                do {
                    let placemarks = try await geocoder.geocodeAddressString(location)
                    if let placemark = placemarks.first, let coord = placemark.location?.coordinate {
                        centerOverride = coord
                        print("[DEBUG] Geocoded location coordinate: \(coord)")
                        await searchStore.run(query: searchTerm, near: coord)
                        if let first = searchStore.results.first {
                            centerOverride = first.coordinate
                            radiusMiles = 25
                        }
                        print("[DEBUG] Map will be shown")
                        showMap = true
                        return
                    } else {
                        print("[DEBUG] Geocoding returned no results")
                    }
                } catch {
                    print("[DEBUG] Geocoding failed with error: \(error.localizedDescription)")
                }
            }

            // Default search with normalized query near current centerOverride or location
            await searchStore.run(query: normalizedQuery, near: centerOverride ?? loc.lastLocation?.coordinate)

            // After search, set center/radius from first result if available
            if let first = searchStore.results.first {
                centerOverride = first.coordinate
                radiusMiles = 25
            }
            print("[DEBUG] Map will be shown")
            showMap = true
        } catch {
            print("[DEBUG] LLM normalization failed: \(error.localizedDescription)")
            // Fallback search
            await searchStore.run(query: query, near: centerOverride ?? loc.lastLocation?.coordinate)
            if let first = searchStore.results.first {
                centerOverride = first.coordinate
                radiusMiles = 25
            }
            print("[DEBUG] Map will be shown (fallback)")
            showMap = true
        }
    }

    func stripWakeWord(_ text: String) -> String {
        let triggers = [
            "hey voyager", "ok voyager", "show me", "navigate to", "find", "search for", "show", "go to", "take me to", "open", "voyager"
        ]
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for trigger in triggers {
            if result.hasPrefix(trigger) {
                result = result.dropFirst(trigger.count).trimmingCharacters(in: .whitespaces)
                break
            }
        }
        return result
    }
}

#Preview {
    HomeView()
}
