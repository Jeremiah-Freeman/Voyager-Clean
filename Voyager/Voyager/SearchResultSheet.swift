import SwiftUI
import MapKit

struct IdentMapItem: Identifiable, Hashable {
    let item: MKMapItem
    var id: String {
        let c = item.placemark.coordinate
        return "\(item.name ?? "item")-\(c.latitude)-\(c.longitude)"
    }
}

struct SearchResultSheet: View {
    let ident: IdentMapItem
    let onLookAround: ((CLLocationCoordinate2D) -> Void)?

    var body: some View {
        let item = ident.item
        VStack(alignment: .leading, spacing: 12) {
            Text(item.name ?? "Place")
                .font(.title2.weight(.semibold))

            if let locality = item.placemark.locality,
               let admin = item.placemark.administrativeArea {
                Text("\(locality), \(admin)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button {
                    Navigator.shared.open(to: item.placemark.coordinate, name: item.name)
                } label: {
                    Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    onLookAround?(item.placemark.coordinate)
                } label: {
                    Label("Look Around", systemImage: "camera.viewfinder")
                }
                .buttonStyle(.bordered)
            }

            if let url = item.url {
                Divider().padding(.vertical, 6)
                Text("Website").font(.headline)
                Link(url.absoluteString, destination: url)
                    .lineLimit(1).truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding()
    }
}//
//  SearchResultSheet.swift
//  Voyager
//
//  Created by Jeremiah freeman on 8/9/25.
//

