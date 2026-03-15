import UIKit
import SwiftUI

/// Root view controller for the Wisp share extension.
/// Hosts the SwiftUI ShareView inside a UIHostingController.
final class ShareExtensionViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()

        guard let context = extensionContext else { return }

        let viewModel = ShareViewModel(extensionContext: context)
        let shareView = ShareView(viewModel: viewModel)
        let host = UIHostingController(rootView: shareView)

        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
    }
}
