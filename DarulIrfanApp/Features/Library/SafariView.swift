import SwiftUI
import SafariServices
import UIKit

/// SFSafariViewController wrapper for showing source pages on
/// naqshbandiaowaisiah.org without leaving the app. Present as a sheet and
/// apply `.ignoresSafeArea()`. Only pass http/https URLs — callers validate
/// (see `ContentItemDetailViewModel.sourceURL`).
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(DIColor.primary)
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // The URL is fixed for the lifetime of the presentation.
    }
}
