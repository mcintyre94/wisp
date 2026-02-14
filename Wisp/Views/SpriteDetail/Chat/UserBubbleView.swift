import SwiftUI

struct UserBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing) {
                ForEach(message.content) { content in
                    if case .text(let text) = content {
                        Text(text)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 16))
                            .foregroundStyle(.white)
                    }
                }
            }
        }
    }
}
