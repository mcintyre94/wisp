import SwiftUI

struct StreamingIndicator: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let phase = (1 + sin((t - Double(index) * 0.2) * .pi / 0.6)) / 2
                    let scale = 0.5 + 0.5 * phase
                    let opacity = 0.3 + 0.7 * phase

                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 6, height: 6)
                        .scaleEffect(scale, anchor: .center)
                        .opacity(opacity)
                }
            }
        }
        .frame(height: 6)
        .padding(.leading, 14)
        .padding(.vertical, 4)
    }
}
