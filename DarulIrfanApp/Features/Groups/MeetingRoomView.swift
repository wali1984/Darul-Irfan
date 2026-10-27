import AVFoundation
import SwiftUI
import WebKit

/// A group meeting or joined zikr, inside the app.
///
/// The room page is Darul Irfan's own (served by its backend), loaded in a web
/// view with the participant pass in the URL fragment - which is never sent to
/// any server, so it stays out of every log. Camera and microphone are asked
/// for only here, and only when the person joins.
@MainActor
struct MeetingRoomView: View {
    let pass: GroupRoomPass
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MeetingWebView(url: roomURL) { dismiss() }
                .ignoresSafeArea(edges: .bottom)
                .background(Color(red: 0.04, green: 0.17, blue: 0.13))
                .navigationTitle("Darul Irfan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Leave") { dismiss() }
                    }
                }
        }
    }

    /// The room page on the same backend the app already talks to - not the
    /// address the server reports, which may be a domain not yet live.
    private var roomURL: URL {
        let page = OfficialPlatformConfiguration.baseURL.appendingPathComponent("v1/meet")
        var components = URLComponents(url: page, resolvingAgainstBaseURL: false)
        components?.fragment = "token=\(pass.authToken)"
        return components?.url ?? page
    }
}

private struct MeetingWebView: UIViewRepresentable {
    let url: URL
    let onLeave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLeave: onLeave) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "darulirfan")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.accessibilityLabel = String(localized: "Meeting room")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "darulirfan")
        webView.loadHTMLString("", baseURL: nil)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
        let onLeave: () -> Void
        init(onLeave: @escaping () -> Void) { self.onLeave = onLeave }

        /// Camera and microphone for the room page only; the system still asks
        /// the person the first time.
        func webView(
            _ webView: WKWebView,
            requestMediaCapturePermissionFor origin: WKSecurityOrigin,
            initiatedByFrame frame: WKFrameInfo,
            type: WKMediaCaptureType,
            decisionHandler: @escaping (WKPermissionDecision) -> Void
        ) {
            let ours = OfficialPlatformConfiguration.baseURL.host == origin.host
            decisionHandler(ours ? .grant : .deny)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.body as? String == "left" {
                DispatchQueue.main.async { self.onLeave() }
            }
        }
    }
}
