import SwiftUI
import MapKit

struct PlaceSheet: View {
    let place: Place
    let onLookAround: ((CLLocationCoordinate2D) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(place.name)
                .font(.title2.weight(.semibold))
            Text(place.category.rawValue)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text(place.blurb)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Button {
                    Navigator.shared.open(to: place.coordinate, name: place.name)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onLookAround?(place.coordinate)
                } label: {
                    Label("Look Around", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)
            }

            if !place.links.isEmpty {
                Divider().padding(.vertical, 6)
                Text("Links").font(.headline)
                ForEach(place.links, id: \.self) { url in
                    Link(url.absoluteString, destination: url)
                        .lineLimit(1).truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}
