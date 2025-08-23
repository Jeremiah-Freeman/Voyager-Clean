import SwiftUI

struct ChatWaveformView: View {
    @State private var level: CGFloat = 0.5

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 4) {
                ForEach(0..<20, id: \.self) { bar in
                    Capsule()
                        .fill(Color.green.gradient)
                        .frame(width: 4,
                               height: CGFloat.random(in: 10...geo.size.height) * level)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            // fake animation for now
            withAnimation(.easeInOut(duration: 0.3).repeatForever()) {
                level = .random(in: 0.2...1.0)
            }
        }
    }
}

#Preview {
    ChatWaveformView()
        .frame(height: 100)
        .padding()
}
