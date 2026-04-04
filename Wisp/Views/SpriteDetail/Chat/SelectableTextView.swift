import SwiftUI
import UIKit

/// A non-editable UITextView that immediately selects all its text on appearance.
/// Used for the "Select" context menu action on chat message bubbles.
struct SelectableTextView: UIViewRepresentable {
    let text: String
    let textColor: UIColor
    let font: UIFont
    var onDeselect: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(onDeselect: onDeselect)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.font = font
        textView.textColor = textColor
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.delegate = context.coordinator
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        if textView.text != text {
            textView.text = text
        }
        guard !context.coordinator.hasInitiallySelected else { return }
        DispatchQueue.main.async {
            textView.selectAll(nil)
            context.coordinator.hasInitiallySelected = true
        }
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var onDeselect: (() -> Void)?
        var hasInitiallySelected = false

        init(onDeselect: (() -> Void)?) {
            self.onDeselect = onDeselect
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard hasInitiallySelected, textView.selectedRange.length == 0 else { return }
            onDeselect?()
        }
    }
}

#Preview {
    SelectableTextView(
        text: "Can you add a README to this project?",
        textColor: .white,
        font: .preferredFont(forTextStyle: .body)
    )
    .padding(.horizontal, 14)
    .padding(.vertical, 10)
    .background(.blue, in: RoundedRectangle(cornerRadius: 16))
    .padding()
}
