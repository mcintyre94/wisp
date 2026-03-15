import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - UITextView subclass

final class PasteTextView: UITextView {
    var onPasteNonText: (() -> Void)?

    private let placeholderLabel: UILabel = {
        let label = UILabel()
        label.textColor = .tertiaryLabel
        label.font = UIFont.preferredFont(forTextStyle: .body)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: topAnchor),
            placeholderLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var placeholder: String = "" {
        didSet {
            placeholderLabel.text = placeholder
        }
    }

    func updatePlaceholderVisibility() {
        placeholderLabel.isHidden = !text.isEmpty
    }

    private func pasteboardHasNonTextContent() -> Bool {
        let pb = UIPasteboard.general
        if pb.hasImages { return true }
        // Check item providers for any non-text data (e.g. files from Files app are
        // stored as raw data under their content UTI, not as public.file-url)
        for provider in pb.itemProviders {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) { return true }
            if provider.registeredTypeIdentifiers.contains(where: { id in
                guard let type = UTType(id) else { return false }
                return type.conforms(to: .data) && !type.conforms(to: .text)
            }) { return true }
        }
        return false
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) {
            // Always show Paste — canPerformAction is called without a user gesture so there's
            // no privacy-safe way to detect arbitrary file types on the pasteboard. The paste(_:)
            // override handles routing to onPasteNonText or super as appropriate.
            return true
        }
        return super.canPerformAction(action, withSender: sender)
    }

    override func paste(_ sender: Any?) {
        let hasNonText = pasteboardHasNonTextContent()
        let hasPlainText = UIPasteboard.general.hasStrings

        if hasNonText && !hasPlainText {
            onPasteNonText?()
            return
        }
        super.paste(sender)
    }

}

// MARK: - UIViewRepresentable

struct PasteInterceptingTextInput: UIViewRepresentable {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var isDisabled: Bool
    var placeholder: String
    var onPasteNonText: (() -> Void)?

    private static let maxHeight: CGFloat = 120
    private static let minHeight: CGFloat = 36

    func makeUIView(context: Context) -> PasteTextView {
        let textView = PasteTextView()
        textView.backgroundColor = .clear
        textView.isScrollEnabled = false
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.delegate = context.coordinator
        textView.placeholder = placeholder
        textView.updatePlaceholderVisibility()
        return textView
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: PasteTextView, context: Context) -> CGSize? {
        let width = proposal.width ?? uiView.frame.width
        guard width > 0 else { return nil }
        let fits = uiView.sizeThatFits(CGSize(width: width, height: .infinity))
        let height = max(min(fits.height, Self.maxHeight), Self.minHeight)
        uiView.isScrollEnabled = fits.height > Self.maxHeight
        return CGSize(width: width, height: height)
    }

    func updateUIView(_ textView: PasteTextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            textView.text = text
            textView.updatePlaceholderVisibility()
            // Invalidate so SwiftUI calls sizeThatFits again with the updated text
            textView.invalidateIntrinsicContentSize()
        }
        textView.isUserInteractionEnabled = !isDisabled
        textView.placeholder = placeholder
        textView.onPasteNonText = onPasteNonText

        // Only manage first responder when the user isn't actively editing,
        // to avoid resignFirstResponder being called mid-typing due to SwiftUI
        // re-renders before FocusState has propagated.
        guard !context.coordinator.isEditing else { return }
        let shouldFocus = isFocused.wrappedValue
        if shouldFocus && !textView.isFirstResponder {
            textView.becomeFirstResponder()
        } else if !shouldFocus && textView.isFirstResponder {
            textView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: PasteInterceptingTextInput
        var isEditing = false

        init(_ parent: PasteInterceptingTextInput) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            (textView as? PasteTextView)?.updatePlaceholderVisibility()
            // Signal SwiftUI to re-query sizeThatFits with the new content
            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            isEditing = true
            parent.isFocused.wrappedValue = true
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            isEditing = false
            parent.isFocused.wrappedValue = false
        }
    }
}

#Preview {
    @Previewable @State var text = ""
    @Previewable @FocusState var focused: Bool
    PasteInterceptingTextInput(
        text: $text,
        isFocused: $focused,
        isDisabled: false,
        placeholder: "Message..."
    )
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    .glassEffect(in: .rect(cornerRadius: 20))
    .padding()
}
